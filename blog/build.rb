#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts blog/_posts/*.md and blog/_posts/*.html → blog/[slug]/index.html
# and regenerates blog/posts.yaml (the post listing index).
#
# Usage:
#   ruby blog/build.rb

require 'date'
require 'fileutils'
require 'json'
require 'kramdown'

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
# HTML page template
# ---------------------------------------------------------------------------
def page_template(title:, date_display:, content:)
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
            var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
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
        <button id="theme-toggle" aria-label="Toggle light/dark mode">☀️</button>

        <div id="heading-content">
          <a href="/"><img src="/vaidehi-white.png" class="vaidehi-logo-image" /></a>
        </div>

        <main class="blog-post-container">
          <nav class="blog-nav">
            <a href="/blog" class="back-link">&larr; all posts</a>
          </nav>

          <article class="blog-post">
            <h1 class="post-title">#{title}</h1>
            <time class="post-date">#{date_display}</time>
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
          var toggle = document.getElementById('theme-toggle');
          var dark = document.documentElement.getAttribute('data-theme') === 'dark';
          var lightSheet = document.getElementById('hljs-light');
          var darkSheet  = document.getElementById('hljs-dark');

          function syncHighlightTheme(isDark) {
            lightSheet.disabled = isDark;
            darkSheet.disabled  = !isDark;
          }

          toggle.textContent = dark ? '☀️' : '🌙';
          syncHighlightTheme(dark);

          toggle.addEventListener('click', function() {
            dark = !dark;
            document.documentElement.setAttribute('data-theme', dark ? 'dark' : '');
            toggle.textContent = dark ? '☀️' : '🌙';
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
# Main build
# ---------------------------------------------------------------------------
source_files = Dir[File.join(POSTS_SRC, '*.md'), File.join(POSTS_SRC, '*.html')].sort

if source_files.empty?
  warn 'No source files found in blog/_posts/. Run migrate.rb first.'
  exit 1
end

posts = []

source_files.each do |src|
  raw          = File.read(src, encoding: 'utf-8')
  data, body   = parse_front_matter(raw)
  ext          = File.extname(src)
  slug         = data['slug'] || File.basename(src, ext)
  title        = data['title'] || 'Untitled'
  date         = data['date'] || ''
  excerpt      = data['excerpt'] || ''

  content_html = if ext == '.md'
                   Kramdown::Document.new(body, input: 'GFM', syntax_highlighter: nil).to_html
                 else
                   body
                 end

  excerpt = make_excerpt(content_html) if excerpt.empty?
  date_display = date.empty? ? '' : format_date(date)

  out_dir = File.join(BLOG_DIR, slug)
  FileUtils.mkdir_p(out_dir)
  File.write(File.join(out_dir, 'index.html'),
             page_template(title: title, date_display: date_display, content: content_html),
             encoding: 'utf-8')

  posts << { 'title' => title, 'date' => date, 'slug' => slug, 'excerpt' => excerpt }
end

posts.sort_by! { |p| p['date'] }.reverse!

yaml_lines = posts.flat_map do |p|
  [
    "- title: #{p['title'].to_json}",
    "  date: \"#{p['date']}\"",
    "  slug: \"#{p['slug']}\"",
    "  excerpt: #{p['excerpt'].to_json}",
  ]
end

File.write(File.join(BLOG_DIR, 'posts.yaml'), yaml_lines.join("\n") + "\n", encoding: 'utf-8')

puts "Built #{posts.length} posts → blog/posts.yaml updated"
