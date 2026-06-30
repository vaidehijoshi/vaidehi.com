#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts blog/_posts/*.md → blog/[slug]/index.html
# and regenerates blog/posts.yaml (the post listing index).
#
# Usage:
#   ruby blog/build.rb

require 'cgi'
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
  Date.parse(iso).strftime('%B %-d, %Y')
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
# Shared nav partial
# ---------------------------------------------------------------------------
def back_link_html
  '<a href="/blog" class="back-link">&larr; All Posts</a>'
end

# ---------------------------------------------------------------------------
# Render the tags HTML snippet (empty string when no tags)
# ---------------------------------------------------------------------------
def tags_html(tags)
  return '' if tags.empty?

  links = tags.map { |t| "<a href=\"/blog/tags/#{CGI.escapeHTML(t)}\" class=\"post-tag\">#{CGI.escapeHTML(t)}</a>" }.join(', ')
  "<div class=\"post-tags\">#{links}</div>"
end

# ---------------------------------------------------------------------------
# HTML template for a tag index page
# ---------------------------------------------------------------------------
def tag_page_template(tag:, posts:)
  safe_tag = CGI.escapeHTML(tag)
  items = posts.sort_by { |p| p['date'].to_s }.reverse.map do |p|
    date_html = p['date'].to_s.empty? ? '' : "<span class=\"post-list-date\">#{format_date(p['date'])}</span>"
    slug  = CGI.escapeHTML(p['slug'])
    title = CGI.escapeHTML(p['title'])
    "<li class=\"post-list-item\"><a href=\"/blog/#{slug}\">#{title}</a>#{date_html}</li>"
  end.join("\n          ")

  <<~HTML
    <!DOCTYPE html>

    <html>
      <head>
        <title>##{safe_tag} - Vaidehi Joshi</title>

        <link rel="stylesheet" type="text/css" href="/style.css" />
        <link rel="stylesheet" type="text/css" href="/blog/blog.css" />
        <script src="/theme.js"></script>

        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width" />

        <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🌻</text></svg>">

        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css" />
      </head>

      <body>
        <label class="theme-toggle" aria-label="Toggle light/dark mode">
          <input type="checkbox" id="theme-checkbox" />
          <span class="toggle-track"><span class="toggle-thumb"></span></span>
        </label>

        <div id="heading-content">
          <a href="/"><img src="/vaidehi-white.png" class="vaidehi-logo-image" /></a>
        </div>

        <nav id="site-nav">
          <a href="/">home</a><span class="nav-sep"> · </span><a href="/blog">blog</a><span class="nav-sep"> · </span><a href="https://www.linkedin.com/in/vaidehisj/" target="_blank" rel="noopener">linkedin</a><span class="nav-sep"> · </span><a href="https://github.com/vaidehijoshi" target="_blank" rel="noopener">github</a><span class="nav-sep"> · </span><a href="https://medium.com/@vaidehijoshi" target="_blank" rel="noopener">medium</a><span class="nav-sep"> · </span><a href="https://bsky.app/profile/vaidehi.com" target="_blank" rel="noopener">bluesky</a><span class="nav-sep"> · </span><a href="https://www.twitter.com/vaidehijoshi" target="_blank" rel="noopener">twitter</a>
        </nav>

        <div class="container">
          <section class="section">
            <nav class="blog-nav">
              #{back_link_html}
            </nav>
            <div class="section-heading">##{safe_tag}</div>
            <ul class="post-list">
              #{items}
            </ul>
          </section>
        </div>

        <footer>
          <div class="social-links">
            <a href="https://www.linkedin.com/in/vaidehisj/" target="_blank" aria-label="LinkedIn"><i class="fa-brands fa-linkedin"></i></a>
            <a href="https://github.com/vaidehijoshi" target="_blank" aria-label="GitHub"><i class="fa-brands fa-github"></i></a>
            <a href="https://bsky.app/profile/vaidehi.com" target="_blank" aria-label="Bluesky"><i class="fa-brands fa-bluesky"></i></a>
            <a href="https://www.twitter.com/vaidehijoshi" target="_blank" aria-label="Twitter"><i class="fa-brands fa-x-twitter"></i></a>
          </div>
          <p>&copy; Vaidehi Joshi | <span id="copyright-year"></span></p>
        </footer>
      </body>
    </html>
  HTML
end

# ---------------------------------------------------------------------------
# Generate blog/tags/[tag]/index.html for every tag across all posts
# ---------------------------------------------------------------------------
def build_tag_pages(posts, blog_dir: BLOG_DIR)
  by_tag = Hash.new { |h, k| h[k] = [] }
  posts.each { |p| (p['tags'] || []).each { |t| by_tag[t] << p } }

  by_tag.each do |tag, tagged_posts|
    out_dir = File.join(blog_dir, 'tags', tag)
    FileUtils.mkdir_p(out_dir)
    File.write(File.join(out_dir, 'index.html'),
               tag_page_template(tag: tag, posts: tagged_posts),
               encoding: 'utf-8')
  end

  by_tag.keys.sort
end

# ---------------------------------------------------------------------------
# HTML page template
# ---------------------------------------------------------------------------
def page_template(title:, date_display:, tags:, content:)
  safe = CGI.escapeHTML(title)
  <<~HTML
    <!DOCTYPE html>

    <html>
      <head>
        <title>#{safe} - Vaidehi Joshi</title>

        <link rel="stylesheet" type="text/css" href="/style.css" />
        <link rel="stylesheet" type="text/css" href="/blog/blog.css" />
        <script src="/theme.js"></script>

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
        <header id="site-header"></header>
        <script src="/header.js"></script>

        <main class="blog-post-container">
          <nav class="blog-nav">
            #{back_link_html}
          </nav>

          <article class="blog-post">
            <h1 class="post-title">#{safe}</h1>
            <time class="post-date">#{CGI.escapeHTML(date_display)}</time>
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
          var lightSheet = document.getElementById('hljs-light');
          var darkSheet  = document.getElementById('hljs-dark');

          function syncHighlightTheme(isDark) {
            lightSheet.disabled = isDark;
            darkSheet.disabled  = !isDark;
          }

          syncHighlightTheme(document.documentElement.getAttribute('data-theme') === 'dark');

          document.addEventListener('themechange', function(e) {
            syncHighlightTheme(e.detail.dark);
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

  posts = []

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

    existing_by_slug.delete(slug)
    posts << { 'title' => title, 'date' => date, 'slug' => slug, 'tags' => tags, 'excerpt' => excerpt }
  end

  # Preserve migrated posts that have no .md source
  posts.concat(existing_by_slug.values)

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

  build_tag_pages(posts, blog_dir: blog_dir)

  posts
end

if $PROGRAM_NAME == __FILE__
  posts = build_blog
  puts "Built #{posts.length} posts → blog/posts.yaml updated"
end
