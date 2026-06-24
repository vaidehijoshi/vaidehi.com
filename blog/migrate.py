#!/usr/bin/env python3
"""
One-time migration: pulls compiled HTML from vaidehijoshi.github.io (via GitHub API)
and writes cleaned HTML source files to blog/_posts/[slug].html.

Run once with:
    python3 blog/migrate.py
"""

import re
import json
import base64
import pathlib
import subprocess
import sys

BLOG_DIR = pathlib.Path(__file__).parent
POSTS_SRC = BLOG_DIR / '_posts'
POSTS_SRC.mkdir(exist_ok=True)

REPO = 'vaidehijoshi/vaidehijoshi.github.io'


# ---------------------------------------------------------------------------
# GitHub API via gh CLI
# ---------------------------------------------------------------------------
def gh_api(endpoint: str):
    result = subprocess.run(
        ['gh', 'api', endpoint],
        capture_output=True, text=True, check=True
    )
    return json.loads(result.stdout)


def decode_content(b64: str) -> str:
    return base64.b64decode(b64.replace('\n', '')).decode('utf-8', errors='replace')


# ---------------------------------------------------------------------------
# HTML entity decoding (for code blocks where we need plain text)
# ---------------------------------------------------------------------------
ENTITY_MAP = {
    '&lt;': '<', '&gt;': '>', '&amp;': '&', '&quot;': '"', '&apos;': "'",
    '&rsquo;': '’', '&lsquo;': '‘',
    '&rdquo;': '”', '&ldquo;': '“',
    '&ndash;': '–', '&mdash;': '—',
    '&hellip;': '…', '&nbsp;': ' ',
}

def decode_entities(s: str) -> str:
    for entity, char in ENTITY_MAP.items():
        s = s.replace(entity, char)
    # Numeric entities
    s = re.sub(r'&#(\d+);', lambda m: chr(int(m.group(1))), s)
    return s

def encode_for_html(s: str) -> str:
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


# ---------------------------------------------------------------------------
# Convert Octopress <figure class='code'> blocks → <pre><code class="language-X">
# The compiled HTML has syntax-highlighted code in nested span.line elements.
# ---------------------------------------------------------------------------
def convert_code_blocks(html: str) -> str:
    def replace_block(m: re.Match) -> str:
        block = m.group(0)

        # Language from <code class='ruby'> etc. (Octopress uses single quotes)
        lang_m = re.search(r"<code class=['\"](\w+)['\"]>", block)
        lang = lang_m.group(1) if lang_m else ''

        # Extract the code cell (td.code), stripping line-number gutter
        cell_m = re.search(r"<td class=['\"]code['\"]>(.*?)</td>", block, re.DOTALL)
        if not cell_m:
            return block

        # Strip ALL HTML tags — leaves only the raw code text with its newlines
        raw = re.sub(r'<[^>]+>', '', cell_m.group(1))
        raw = decode_entities(raw)

        lines = raw.split('\n')
        # Trim leading/trailing blank lines
        while lines and not lines[0].strip():
            lines.pop(0)
        while lines and not lines[-1].strip():
            lines.pop()

        code = encode_for_html('\n'.join(lines))
        cls = f' class="language-{lang}"' if lang else ''
        return f'<pre><code{cls}>{code}</code></pre>'

    return re.sub(r"<figure class='code'>.*?</figure>", replace_block, html, flags=re.DOTALL)


# ---------------------------------------------------------------------------
# Extract the content div using depth-counting (handles nested divs safely)
# ---------------------------------------------------------------------------
def extract_div_content(html: str, class_attr: str) -> str:
    marker = f'<div class="{class_attr}">'
    start = html.find(marker)
    if start == -1:
        return ''
    content_start = start + len(marker)
    depth = 1
    i = content_start
    while i < len(html) and depth > 0:
        next_open = html.find('<div', i)
        next_close = html.find('</div>', i)
        if next_close == -1:
            break
        if next_open != -1 and next_open < next_close:
            depth += 1
            i = next_open + 4
        else:
            depth -= 1
            if depth == 0:
                return html[content_start:next_close]
            i = next_close + 6
    return ''


# ---------------------------------------------------------------------------
# Clean content: convert code blocks, strip HTML comments
# ---------------------------------------------------------------------------
def clean_content(html: str) -> str:
    html = re.sub(r'<!--.*?-->', '', html, flags=re.DOTALL)
    html = convert_code_blocks(html)
    html = re.sub(r'\n{3,}', '\n\n', html)
    return html.strip()


# ---------------------------------------------------------------------------
# Extract all needed fields from a compiled post HTML page
# ---------------------------------------------------------------------------
def extract_post(html: str, post_path: str) -> dict:
    # Title
    title_m = re.search(r'<h1 class="entry-title">(.*?)</h1>', html, re.DOTALL)
    title = decode_entities(re.sub(r'<[^>]+>', '', title_m.group(1))).strip() if title_m else ''

    # Date (prefer the machine-readable datetime attribute)
    date_m = re.search(r"datetime='(\d{4}-\d{2}-\d{2})", html)
    date = date_m.group(1) if date_m else ''

    # Slug = second-to-last path segment (blog/YYYY/MM/DD/SLUG/index.html)
    slug = post_path.split('/')[-2]

    # Content
    raw_content = extract_div_content(html, 'entry-content')
    content = clean_content(raw_content)

    # Excerpt (plain text, first ~200 chars)
    text = re.sub(r'<[^>]+>', ' ', content)
    text = re.sub(r'\s+', ' ', text).strip()
    excerpt = text[:220].rsplit(' ', 1)[0] + '…' if len(text) > 220 else text

    return {'slug': slug, 'title': title, 'date': date, 'content': content, 'excerpt': excerpt}


# ---------------------------------------------------------------------------
# Write source file with front matter header
# ---------------------------------------------------------------------------
def write_post_source(post: dict):
    out = POSTS_SRC / f'{post["slug"]}.html'
    if out.exists():
        return  # Already migrated; skip

    safe = lambda s: s.replace('\\', '\\\\').replace('"', '\\"')
    fm = (
        f'---\n'
        f'title: "{safe(post["title"])}"\n'
        f'date: "{post["date"]}"\n'
        f'slug: "{post["slug"]}"\n'
        f'excerpt: "{safe(post["excerpt"])}"\n'
        f'---\n\n'
    )
    out.write_text(fm + post['content'] + '\n', encoding='utf-8')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print('Fetching repository tree…')
    tree_data = gh_api(f'repos/{REPO}/git/trees/master?recursive=1')
    post_paths = [
        item['path']
        for item in tree_data['tree']
        if (item['type'] == 'blob'
            and re.match(r'^blog/\d{4}/\d{2}/\d{2}/[^/]+/index\.html$', item['path']))
    ]

    print(f'Found {len(post_paths)} posts. Migrating…')

    done = 0
    failed = []
    for post_path in post_paths:
        try:
            res = gh_api(f'repos/{REPO}/contents/{post_path}')
            html = decode_content(res['content'])
            post = extract_post(html, post_path)
            write_post_source(post)
            done += 1
            print(f'\r{done}/{len(post_paths)}', end='', flush=True)
        except Exception as e:
            failed.append((post_path, str(e)))
            print(f'\n  Failed: {post_path} — {e}')

    print(f'\n\nDone. {done} posts written to blog/_posts/')
    if failed:
        print(f'{len(failed)} failed:')
        for path, err in failed:
            print(f'  {path}: {err}')


if __name__ == '__main__':
    main()
