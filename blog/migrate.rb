#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time migration: pulls compiled HTML from vaidehijoshi.github.io (via GitHub API)
# and writes cleaned HTML source files to blog/_posts/[slug].html.
#
# Usage:
#   ruby blog/migrate.rb

require 'json'
require 'base64'
require 'fileutils'
require 'open3'

BLOG_DIR  = File.expand_path('..', __FILE__)
POSTS_SRC = File.join(BLOG_DIR, '_posts')
REPO      = 'vaidehijoshi/vaidehijoshi.github.io'

# ---------------------------------------------------------------------------
# GitHub API via gh CLI
# ---------------------------------------------------------------------------
def gh_api(endpoint)
  out, status = Open3.capture2('gh', 'api', endpoint)
  raise "gh api failed for #{endpoint}" unless status.success?
  JSON.parse(out)
end

def decode_content(b64)
  Base64.decode64(b64.gsub("\n", '')).force_encoding('UTF-8').scrub
end

# ---------------------------------------------------------------------------
# HTML entity decoding (used when extracting plain text from code blocks)
# ---------------------------------------------------------------------------
ENTITIES = {
  '&lt;'    => '<',  '&gt;'    => '>',  '&amp;'   => '&',
  '&quot;'  => '"',  '&apos;'  => "'",
  '&rsquo;' => "’", '&lsquo;' => "‘",
  '&rdquo;' => "”", '&ldquo;' => "“",
  '&ndash;' => "–", '&mdash;' => "—",
  '&hellip;'=> "…", '&nbsp;'  => ' ',
}.freeze

def decode_entities(str)
  s = str.gsub(/&[a-z]+;/) { |e| ENTITIES.fetch(e, e) }
  s.gsub(/&#(\d+);/) { $1.to_i.chr(Encoding::UTF_8) }
end

def encode_for_html(str)
  str.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
end

# ---------------------------------------------------------------------------
# Convert Octopress <figure class='code'> blocks → <pre><code class="language-X">
# ---------------------------------------------------------------------------
def convert_code_blocks(html)
  html.gsub(/<figure class='code'>.*?<\/figure>/m) do |block|
    lang = block[/<code class=['"](\w+)['"]>/, 1] || ''

    cell = block[/<td class=['"]code['"]>(.*?)<\/td>/m, 1]
    next block unless cell

    # Strip all HTML tags — leaves raw code text with its newlines intact
    raw   = cell.gsub(/<[^>]+>/, '')
    raw   = decode_entities(raw)
    lines = raw.split("\n").drop_while(&:empty?)
    lines.pop while lines.last&.strip&.empty?

    code  = encode_for_html(lines.join("\n"))
    cls   = lang.empty? ? '' : " class=\"language-#{lang}\""
    "<pre><code#{cls}>#{code}</code></pre>"
  end
end

# ---------------------------------------------------------------------------
# Extract a div's inner HTML using depth-counting (handles nested divs)
# ---------------------------------------------------------------------------
def extract_div_content(html, class_attr)
  marker = "<div class=\"#{class_attr}\">"
  start  = html.index(marker)
  return '' unless start

  i     = start + marker.length
  depth = 1

  while i < html.length && depth > 0
    next_open  = html.index('<div', i)
    next_close = html.index('</div>', i)
    break unless next_close

    if next_open && next_open < next_close
      depth += 1
      i = next_open + 4
    else
      depth -= 1
      return html[start + marker.length, next_close - (start + marker.length)] if depth == 0
      i = next_close + 6
    end
  end
  ''
end

# ---------------------------------------------------------------------------
# Clean content: strip HTML comments, convert code blocks
# ---------------------------------------------------------------------------
def clean_content(html)
  html = html.gsub(/<!--.*?-->/m, '')
  html = convert_code_blocks(html)
  html = html.gsub(/\n{3,}/, "\n\n")
  html.strip
end

# ---------------------------------------------------------------------------
# Category slug normalisation
# "number-technicaltuesdays" is how Octopress encoded #TechnicalTuesdays
# ---------------------------------------------------------------------------
CATEGORY_MAP = {
  'number-technicaltuesdays' => 'technical-tuesdays',
}.freeze

def normalise_tags(raw_tags)
  raw_tags.map { |t| CATEGORY_MAP.fetch(t, t) }.uniq.sort
end

# ---------------------------------------------------------------------------
# Extract all fields from a compiled Octopress post page
# ---------------------------------------------------------------------------
def extract_post(html, post_path)
  title_raw = html[/<h1 class="entry-title">(.*?)<\/h1>/m, 1] || ''
  title     = decode_entities(title_raw.gsub(/<[^>]+>/, '')).strip

  date = html[/datetime='(\d{4}-\d{2}-\d{2})/, 1] || ''

  # Slug = second-to-last path segment: blog/YYYY/MM/DD/SLUG/index.html
  slug = post_path.split('/')[-2]

  # Categories from Octopress <span class="categories"> section
  raw_tags = html.scan(%r{href='/blog/categories/([^/]+)/'}).flatten
  tags     = normalise_tags(raw_tags)

  raw_content = extract_div_content(html, 'entry-content')
  content     = clean_content(raw_content)

  text    = content.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  excerpt = text.length > 220 ? text[0, 220].gsub(/\s\S*$/, '') + '…' : text

  { slug: slug, title: title, date: date, tags: tags, content: content, excerpt: excerpt }
end

# ---------------------------------------------------------------------------
# Write source file with YAML front matter
# ---------------------------------------------------------------------------
def write_post_source(post)
  out = File.join(POSTS_SRC, "#{post[:slug]}.html")
  return if File.exist?(out)  # skip if already migrated

  safe = ->(s) { s.gsub('\\', '\\\\\\\\').gsub('"', '\\"') }
  tags_str = post[:tags].join(', ')
  fm = <<~FM
    ---
    title: "#{safe.(post[:title])}"
    date: "#{post[:date]}"
    slug: "#{post[:slug]}"
    tags: "#{tags_str}"
    excerpt: "#{safe.(post[:excerpt])}"
    ---

  FM

  File.write(out, fm + post[:content] + "\n", encoding: 'utf-8')
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if $PROGRAM_NAME == __FILE__
  FileUtils.mkdir_p(POSTS_SRC)

  print 'Fetching repository tree… '
  tree_data  = gh_api("repos/#{REPO}/git/trees/master?recursive=1")
  post_paths = tree_data['tree']
    .select { |n| n['type'] == 'blob' && n['path'].match?(%r{^blog/\d{4}/\d{2}/\d{2}/[^/]+/index\.html$}) }
    .map    { |n| n['path'] }

  puts "#{post_paths.length} posts found. Migrating…"

  done   = 0
  failed = []

  post_paths.each do |post_path|
    res  = gh_api("repos/#{REPO}/contents/#{post_path}")
    html = decode_content(res['content'])
    post = extract_post(html, post_path)
    write_post_source(post)
    done += 1
    print "\r#{done}/#{post_paths.length}"
    $stdout.flush
  rescue => e
    failed << [post_path, e.message]
    puts "\n  Failed: #{post_path} — #{e.message}"
  end

  puts "\n\nDone. #{done} posts written to blog/_posts/"
  if failed.any?
    puts "#{failed.length} failed:"
    failed.each { |path, err| puts "  #{path}: #{err}" }
  end
end
