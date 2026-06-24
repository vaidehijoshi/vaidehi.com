#!/usr/bin/env python3
"""
Converts blog/_posts/*.md and blog/_posts/*.html → blog/[slug]/index.html
and regenerates blog/posts.yaml (the post listing index).

Usage:
    python3 blog/build.py
"""

import re
import sys
import json
import pathlib
import datetime
import markdown

BLOG_DIR = pathlib.Path(__file__).parent
POSTS_SRC = BLOG_DIR / '_posts'


# ---------------------------------------------------------------------------
# Front matter (YAML-ish) parser — handles simple key: "value" lines only
# ---------------------------------------------------------------------------
def parse_front_matter(raw: str):
    m = re.match(r'^---\r?\n(.*?)\r?\n---\r?\n(.*)', raw, re.DOTALL)
    if not m:
        return {}, raw
    data = {}
    for line in m.group(1).split('\n'):
        if ':' not in line:
            continue
        idx = line.index(':')
        key = line[:idx].strip()
        val = line[idx + 1:].strip().strip('"\'')
        data[key] = val
    return data, m.group(2).strip()


# ---------------------------------------------------------------------------
# Date formatting
# ---------------------------------------------------------------------------
def format_date(iso: str) -> str:
    try:
        d = datetime.date.fromisoformat(iso)
        return d.strftime('%B %-d, %Y')
    except ValueError:
        return iso


# ---------------------------------------------------------------------------
# Plain-text excerpt (strips HTML tags)
# ---------------------------------------------------------------------------
def make_excerpt(html: str, max_len: int = 220) -> str:
    text = re.sub(r'<[^>]+>', ' ', html)
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text) <= max_len:
        return text
    trimmed = text[:max_len]
    # Back up to last word boundary
    last_space = trimmed.rfind(' ')
    return (trimmed[:last_space] if last_space != -1 else trimmed) + '…'


# ---------------------------------------------------------------------------
# HTML page template
# ---------------------------------------------------------------------------
def page_template(title: str, date_display: str, content: str) -> str:
    safe_title = (title
                  .replace('&', '&amp;')
                  .replace('<', '&lt;')
                  .replace('>', '&gt;')
                  .replace('"', '&quot;'))
    return f"""<!DOCTYPE html>

<html>
  <head>
    <title>{safe_title} - Vaidehi Joshi</title>

    <link rel="stylesheet" type="text/css" href="/style.css" />
    <link rel="stylesheet" type="text/css" href="/blog/blog.css" />
    <script>
      (function() {{
        var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        document.documentElement.setAttribute('data-theme', prefersDark ? 'dark' : '');
      }})();
    </script>

    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width" />

    <meta property="og:type" content="article" />
    <meta property="og:title" content="{safe_title} - Vaidehi Joshi" />

    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🌻</text></svg>">

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css" />
    <link rel="stylesheet" id="hljs-light" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" />
    <link rel="stylesheet" id="hljs-dark"  href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" disabled />
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  </head>

  <body>
    <button id="theme-toggle" aria-label="Toggle light/dark mode">☀️</button>

    <div id="heading-content">
      <a href="/"><img src="/vaidehi-white.png" class="vaidehi-logo-image" /></a>
    </div>

    <main class="blog-post-container">
      <nav class="blog-nav">
        <a href="/blog" class="back-link">&larr; all posts</a>
      </nav>

      <article class="blog-post">
        <h1 class="post-title">{title}</h1>
        <time class="post-date">{date_display}</time>
        <div class="post-content">
          {content}
        </div>
      </article>
    </main>

    <footer>
      <div class="social-links">
        <a href="https://www.linkedin.com/in/vaidehisj/" target="_blank" aria-label="LinkedIn"><i class="fa-brands fa-linkedin"></i></a>
        <a href="https://github.com/vaidehijoshi" target="_blank" aria-label="GitHub"><i class="fa-brands fa-github"></i></a>
        <a href="https://bsky.app/profile/vaidehi.com" target="_blank" aria-label="Bluesky"><i class="fa-brands fa-bluesky"></i></a>
        <a href="https://www.twitter.com/vaidehijoshi" target="_blank" aria-label="Twitter"><i class="fa-brands fa-x-twitter"></i></a>
      </div>
      <p>&copy; Vaidehi Joshi | <span id="copyright-year"></span></p>
    </footer>

    <script>
      var toggle = document.getElementById('theme-toggle');
      var dark = document.documentElement.getAttribute('data-theme') === 'dark';
      var lightSheet = document.getElementById('hljs-light');
      var darkSheet  = document.getElementById('hljs-dark');

      function syncHighlightTheme(isDark) {{
        lightSheet.disabled = isDark;
        darkSheet.disabled  = !isDark;
      }}

      toggle.textContent = dark ? '☀️' : '🌙';
      syncHighlightTheme(dark);

      toggle.addEventListener('click', function() {{
        dark = !dark;
        document.documentElement.setAttribute('data-theme', dark ? 'dark' : '');
        toggle.textContent = dark ? '☀️' : '🌙';
        syncHighlightTheme(dark);
      }});

      document.getElementById('copyright-year').textContent = new Date().getFullYear();
      hljs.highlightAll();
    </script>
  </body>
</html>
"""


# ---------------------------------------------------------------------------
# Markdown extensions
# ---------------------------------------------------------------------------
MD_EXTENSIONS = ['fenced_code', 'tables', 'attr_list', 'nl2br']


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------
def main():
    source_files = sorted(POSTS_SRC.iterdir())
    source_files = [f for f in source_files if f.suffix in ('.md', '.html')]

    if not source_files:
        print('No source files found in blog/_posts/. Run migrate.py first.')
        sys.exit(1)

    posts = []

    for src in source_files:
        raw = src.read_text(encoding='utf-8')
        data, body = parse_front_matter(raw)

        slug = data.get('slug') or src.stem
        title = data.get('title') or 'Untitled'
        date = data.get('date') or ''
        excerpt = data.get('excerpt') or ''

        if src.suffix == '.md':
            content_html = markdown.markdown(body, extensions=MD_EXTENSIONS)
        else:
            content_html = body

        if not excerpt:
            excerpt = make_excerpt(content_html)

        date_display = format_date(date) if date else ''

        out_dir = BLOG_DIR / slug
        out_dir.mkdir(exist_ok=True)
        (out_dir / 'index.html').write_text(
            page_template(title, date_display, content_html),
            encoding='utf-8'
        )

        posts.append({'title': title, 'date': date, 'slug': slug, 'excerpt': excerpt})

    # Newest first
    posts.sort(key=lambda p: p['date'], reverse=True)

    # Write posts.yaml (hand-rolled to avoid a PyYAML dependency)
    lines = []
    for p in posts:
        lines.append(f'- title: {json.dumps(p["title"])}')
        lines.append(f'  date: "{p["date"]}"')
        lines.append(f'  slug: "{p["slug"]}"')
        lines.append(f'  excerpt: {json.dumps(p["excerpt"])}')
    (BLOG_DIR / 'posts.yaml').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    print(f'Built {len(posts)} posts → blog/posts.yaml updated')


if __name__ == '__main__':
    main()
