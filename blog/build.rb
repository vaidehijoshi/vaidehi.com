#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts blog/_posts/*.md → blog/[slug]/index.html
# and regenerates blog/posts.yaml (the post listing index).
#
# Usage:
#   ruby blog/build.rb

require 'date'
require 'fileutils'
require 'json'
require 'kramdown'
require 'kramdown-parser-gfm'
require 'yaml'

BLOG_DIR  = File.expand_path('..', __FILE__)
POSTS_SRC = File.join(BLOG_DIR, '_posts')

# ---------------------------------------------------------------------------
# Front matter parser — handles simple key: "value" lines
# ---------------------------------------------------------------------------
def parse_front_matter(raw)
  m = raw.match(/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/m)
  return [{}, raw] unless m

  data = {}
  m[1].each_line do |line|
    idx = line.index(':')
    next unless idx

    key = line[0, idx].strip
    val = line[idx + 1..].strip.gsub(/\A["']|["']\z/, '')
    data[key] = val
  end

  [data, m[2].strip]
end

# ---------------------------------------------------------------------------
# Date formatting
# ---------------------------------------------------------------------------
def format_date(iso)
  Date.parse(iso).strftime('%-d %B %Y')
rescue ArgumentError, TypeError
  iso.to_s
end

# ---------------------------------------------------------------------------
# Plain-text excerpt (strips HTML tags)
# ---------------------------------------------------------------------------
def make_excerpt(html, max_len = 220)
  text = html.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  return text if text.length <= max_len

  trimmed = text[0, max_len]
  last_space = trimmed.rindex(' ')
  (last_space ? trimmed[0, last_space] : trimmed) + '…'
end

# ---------------------------------------------------------------------------
# HTML-escape a title for use in attributes
# ---------------------------------------------------------------------------
def h(str)
  str.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

# ---------------------------------------------------------------------------
# Render the tags HTML snippet (empty string when no tags)
# ---------------------------------------------------------------------------
def tags_html(tags)
  return '' if tags.empty?

  links = tags.map { |t| "<span class=\"post-tag\">#{h(t)}</span>" }.join
  "<div class=\"post-tags\">#{links}</div>"
end

# ---------------------------------------------------------------------------
# HTML page template
# ---------------------------------------------------------------------------
def page_template(title:, date_display:, tags:, content:)
  safe = h(title)
  <<~HTML
    <!DOCTYPE html>

    <html>
      <head>
        <title>#{safe} - Vaidehi Joshi</title>

        <link rel="stylesheet" type="text/css" href="/style.css" />
        <link rel="stylesheet" type="text/css" href="/blog/blog.css" />
        <script>
          (function() {
            var stored = localStorage.getItem('theme');
            var prefersDark = stored ? stored === 'dark' : window.matchMedia('(prefers-color-scheme: dark)').matches;
            document.documentElement.setAttribute('data-theme', prefersDark ? 'dark' : '');
          })();
        </script>

        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width" />

        <meta property="og:type" content="article" />
        <meta property="og:title" content="#{safe} - Vaidehi Joshi" />

        <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🌻</text></svg>">

        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css" />
        <link rel="stylesheet" id="hljs-light" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" />
        <link rel="stylesheet" id="hljs-dark"  href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" disabled />
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
      </head>

      <body>
        <label class="theme-toggle" aria-label="Toggle light/dark mode">
          <input type="checkbox" id="theme-checkbox" />
          <span class="toggle-track"><span class="toggle-thumb"></span></span>
        </label>

        <div id="heading-content">
          <a href="/"><img src="/vaidehi-white.png" class="vaidehi-logo-image" /></a>
        </div>

        <main class="blog-post-container">
          <nav class="blog-nav">
            <a href="/blog" class="back-link">&larr; all posts</a>
          </nav>

          <article class="blog-post">
            <h1 class="post-title">#{safe}</h1>
            <time class="post-date">#{date_display}</time>
            #{tags_html(tags)}
            <div class="post-content">
              #{content}
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
          var checkbox = document.getElementById('theme-checkbox');
          var dark = document.documentElement.getAttribute('data-theme') === 'dark';
          var lightSheet = document.getElementById('hljs-light');
          var darkSheet  = document.getElementById('hljs-dark');

          function syncHighlightTheme(isDark) {
            lightSheet.disabled = isDark;
            darkSheet.disabled  = !isDark;
          }

          checkbox.checked = dark;
          syncHighlightTheme(dark);

          checkbox.addEventListener('change', function() {
            dark = checkbox.checked;
            document.documentElement.setAttribute('data-theme', dark ? 'dark' : '');
            localStorage.setItem('theme', dark ? 'dark' : 'light');
            syncHighlightTheme(dark);
          });

          document.getElementById('copyright-year').textContent = new Date().getFullYear();
          hljs.highlightAll();
        </script>
      </body>
    </html>
  HTML
end

# ---------------------------------------------------------------------------
# Main build — accepts custom dirs for testing
# ---------------------------------------------------------------------------
def build_blog(blog_dir: BLOG_DIR, posts_src: POSTS_SRC)
  source_files = Dir[File.join(posts_src, '*.md')].sort

  # Load existing posts.yaml so migrated posts (which have no .md source)
  # keep their entries in the listing when new posts are added.
  yaml_path = File.join(blog_dir, 'posts.yaml')
  existing_posts = File.exist?(yaml_path) ? (YAML.load_file(yaml_path) || []) : []
  existing_by_slug = existing_posts.each_with_object({}) { |p, h| h[p['slug']] = p }

  md_slugs = []
  posts    = []

  source_files.each do |src|
    raw          = File.read(src, encoding: 'utf-8')
    data, body   = parse_front_matter(raw)
    slug         = data['slug'] || File.basename(src, '.md')
    title        = data['title'] || 'Untitled'
    date         = data['date'] || ''
    excerpt      = data['excerpt'] || ''
    tags         = data['tags'].to_s.split(',').map(&:strip).reject(&:empty?)

    content_html = Kramdown::Document.new(body, input: 'GFM', syntax_highlighter: nil).to_html

    excerpt = make_excerpt(content_html) if excerpt.empty?
    date_display = date.empty? ? '' : format_date(date)

    out_dir = File.join(blog_dir, slug)
    FileUtils.mkdir_p(out_dir)
    File.write(File.join(out_dir, 'index.html'),
               page_template(title: title, date_display: date_display, tags: tags, content: content_html),
               encoding: 'utf-8')

    md_slugs << slug
    posts << { 'title' => title, 'date' => date, 'slug' => slug, 'tags' => tags, 'excerpt' => excerpt }
  end

  # Preserve migrated posts that have no .md source
  existing_by_slug.each do |slug, entry|
    posts << entry unless md_slugs.include?(slug)
  end

  posts.sort_by! { |p| p['date'].to_s }.reverse!

  yaml_lines = posts.flat_map do |p|
    tags_val = (p['tags'] || []).empty? ? '""' : p['tags'].to_json
    [
      "- title: #{p['title'].to_json}",
      "  date: #{p['date'].to_json}",
      "  slug: #{p['slug'].to_json}",
      "  tags: #{tags_val}",
      "  excerpt: #{p['excerpt'].to_json}",
    ]
  end

  File.write(File.join(blog_dir, 'posts.yaml'), yaml_lines.join("\n") + "\n", encoding: 'utf-8')

  posts
end

if $PROGRAM_NAME == __FILE__
  posts = build_blog
  puts "Built #{posts.length} posts → blog/posts.yaml updated"
end
