#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../build'

class TestParseFrontMatter < Minitest::Test
  def test_parses_quoted_values
    raw = "---\ntitle: \"Hello World\"\ndate: \"2024-01-01\"\n---\n\nBody text."
    data, body = parse_front_matter(raw)
    assert_equal 'Hello World', data['title']
    assert_equal '2024-01-01', data['date']
    assert_equal 'Body text.', body
  end

  def test_parses_single_quoted_values
    raw = "---\ntitle: 'My Post'\n---\n\ncontent"
    data, body = parse_front_matter(raw)
    assert_equal 'My Post', data['title']
    assert_equal 'content', body
  end

  def test_returns_empty_data_when_no_front_matter
    raw = "Just plain text."
    data, body = parse_front_matter(raw)
    assert_equal({}, data)
    assert_equal 'Just plain text.', body
  end

  def test_parses_comma_separated_tags_field
    raw = "---\ntags: \"ruby, rails, refactoring\"\n---\n\nbody"
    data, _body = parse_front_matter(raw)
    tags = data['tags'].to_s.split(',').map(&:strip).reject(&:empty?)
    assert_equal %w[ruby rails refactoring], tags
  end

  def test_handles_empty_tags
    raw = "---\ntags: \"\"\n---\n\nbody"
    data, _body = parse_front_matter(raw)
    tags = data['tags'].to_s.split(',').map(&:strip).reject(&:empty?)
    assert_empty tags
  end

  def test_handles_windows_line_endings
    raw = "---\r\ntitle: \"Win\"\r\n---\r\n\r\nbody"
    data, body = parse_front_matter(raw)
    assert_equal 'Win', data['title']
    assert_equal 'body', body
  end
end

class TestFormatDate < Minitest::Test
  def test_formats_iso_date
    assert_equal '1 January 2024', format_date('2024-01-01')
  end

  def test_formats_date_without_leading_zero
    assert_equal '5 June 2015', format_date('2015-06-05')
  end

  def test_returns_original_on_invalid_date
    assert_equal 'not-a-date', format_date('not-a-date')
  end

  def test_returns_empty_string_on_nil
    assert_equal '', format_date(nil)
  end
end

class TestMakeExcerpt < Minitest::Test
  def test_strips_html_tags
    html = '<p>Hello <strong>world</strong>.</p>'
    assert_equal 'Hello world .', make_excerpt(html)
  end

  def test_returns_full_text_when_short
    html = '<p>Short text.</p>'
    result = make_excerpt(html)
    assert_equal 'Short text.', result
  end

  def test_truncates_at_word_boundary
    html = '<p>' + ('word ' * 60) + '</p>'
    result = make_excerpt(html, 30)
    assert result.end_with?('…')
    assert result.length <= 35
    # cut should be at a word boundary — no partial words
    assert_match(/\A(word ?)+ *…\z/, result)
  end

  def test_custom_max_length
    html = '<p>one two three four five</p>'
    result = make_excerpt(html, 10)
    assert result.end_with?('…')
    assert result.length <= 15
  end
end

class TestHtmlEscape < Minitest::Test
  def test_escapes_ampersand
    assert_equal 'a &amp; b', h('a & b')
  end

  def test_escapes_angle_brackets
    assert_equal '&lt;tag&gt;', h('<tag>')
  end

  def test_escapes_double_quotes
    assert_equal '&quot;hi&quot;', h('"hi"')
  end

  def test_leaves_plain_text_alone
    assert_equal 'hello world', h('hello world')
  end
end

class TestTagsHtml < Minitest::Test
  def test_returns_empty_string_for_no_tags
    assert_equal '', tags_html([])
  end

  def test_renders_single_tag
    result = tags_html(['ruby'])
    assert_includes result, '<span class="post-tag">ruby</span>'
    assert_includes result, '<div class="post-tags">'
  end

  def test_renders_multiple_tags
    result = tags_html(%w[ruby rails])
    assert_includes result, 'ruby'
    assert_includes result, 'rails'
  end

  def test_escapes_tags_with_special_chars
    result = tags_html(['a & b'])
    assert_includes result, 'a &amp; b'
    refute_includes result, 'a & b'
  end
end

class TestBuildBlog < Minitest::Test
  def setup
    @tmpdir   = Dir.mktmpdir
    @posts_src = File.join(@tmpdir, '_posts')
    FileUtils.mkdir_p(@posts_src)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write_post(filename, content)
    File.write(File.join(@posts_src, filename), content)
  end

  def test_builds_single_markdown_post
    write_post('hello-world.md', <<~MD)
      ---
      title: "Hello World"
      date: "2024-06-01"
      slug: "hello-world"
      tags: "ruby, testing"
      ---

      Hello **world**.
    MD

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    assert_equal 1, posts.length
    assert_equal 'Hello World', posts[0]['title']
    assert_equal '2024-06-01', posts[0]['date']
    assert_equal 'hello-world', posts[0]['slug']
    assert_equal %w[ruby testing], posts[0]['tags']
  end

  def test_generates_index_html
    write_post('test-post.md', <<~MD)
      ---
      title: "Test Post"
      date: "2024-01-01"
      slug: "test-post"
      ---

      Content here.
    MD

    build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    out = File.join(@tmpdir, 'test-post', 'index.html')
    assert File.exist?(out), "Expected #{out} to exist"

    html = File.read(out)
    assert_includes html, 'Test Post'
    assert_includes html, '<p>Content here.</p>'
    assert_includes html, '1 January 2024'
  end

  def test_generates_posts_yaml
    write_post('post-a.md', "---\ntitle: \"A\"\ndate: \"2024-02-01\"\nslug: \"post-a\"\n---\n\nBody A.")
    write_post('post-b.md', "---\ntitle: \"B\"\ndate: \"2024-01-01\"\nslug: \"post-b\"\n---\n\nBody B.")

    build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    yaml_path = File.join(@tmpdir, 'posts.yaml')
    assert File.exist?(yaml_path)

    content = File.read(yaml_path)
    assert_includes content, 'title: "A"'
    assert_includes content, 'title: "B"'
    # A is newer (2024-02-01) so it should appear first
    assert content.index('title: "A"') < content.index('title: "B"')
  end

  def test_sorts_posts_newest_first
    write_post('old.md', "---\ntitle: \"Old\"\ndate: \"2020-01-01\"\nslug: \"old\"\n---\n\nOld.")
    write_post('new.md', "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nNew.")

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    assert_equal 'new', posts[0]['slug']
    assert_equal 'old', posts[1]['slug']
  end

  def test_auto_generates_excerpt_when_missing
    write_post('no-excerpt.md', <<~MD)
      ---
      title: "No Excerpt"
      date: "2024-01-01"
      slug: "no-excerpt"
      ---

      This is the post body with enough text to generate an excerpt automatically.
    MD

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    refute_empty posts[0]['excerpt']
    assert_includes posts[0]['excerpt'], 'This is the post body'
  end

  def test_uses_explicit_excerpt_when_provided
    write_post('with-excerpt.md', <<~MD)
      ---
      title: "With Excerpt"
      date: "2024-01-01"
      slug: "with-excerpt"
      excerpt: "Custom excerpt."
      ---

      Long body that would generate a different auto-excerpt.
    MD

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    assert_equal 'Custom excerpt.', posts[0]['excerpt']
  end

  def test_tags_rendered_in_html
    write_post('tagged.md', <<~MD)
      ---
      title: "Tagged"
      date: "2024-01-01"
      slug: "tagged"
      tags: "ruby, rails"
      ---

      Content.
    MD

    build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    html = File.read(File.join(@tmpdir, 'tagged', 'index.html'))
    assert_includes html, '<span class="post-tag">ruby</span>'
    assert_includes html, '<span class="post-tag">rails</span>'
  end

  def test_returns_empty_array_when_no_posts
    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)
    assert_equal [], posts
  end

  def test_slug_falls_back_to_filename
    write_post('my-post.md', "---\ntitle: \"My Post\"\ndate: \"2024-01-01\"\n---\n\nBody.")

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    assert_equal 'my-post', posts[0]['slug']
  end

  def test_ignores_html_files_in_posts_src
    write_post('old-migrated.html', "---\ntitle: \"Old\"\ndate: \"2020-01-01\"\nslug: \"old\"\n---\n\n<p>old</p>")
    write_post('new-post.md', "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nNew.")

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    slugs = posts.map { |p| p['slug'] }
    assert_includes slugs, 'new'
    refute_includes slugs, 'old'
  end

  def test_preserves_migrated_posts_from_existing_yaml
    # Seed a posts.yaml that simulates 60 previously-migrated posts
    File.write(File.join(@tmpdir, 'posts.yaml'), <<~YAML)
      - title: "Migrated Post"
        date: "2015-01-01"
        slug: "migrated-post"
        tags: ["ruby"]
        excerpt: "Old post from the migration."
    YAML

    # Now add a new .md post and rebuild
    write_post('new-post.md', "---\ntitle: \"New Post\"\ndate: \"2024-01-01\"\nslug: \"new-post\"\n---\n\nNew content.")

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    slugs = posts.map { |p| p['slug'] }
    assert_includes slugs, 'new-post',      'new .md post should appear'
    assert_includes slugs, 'migrated-post', 'migrated post from existing yaml should be preserved'
    assert_equal 2, posts.length
  end

  def test_md_post_updates_overwrite_existing_yaml_entry
    File.write(File.join(@tmpdir, 'posts.yaml'), <<~YAML)
      - title: "Old Title"
        date: "2024-01-01"
        slug: "my-post"
        tags: ""
        excerpt: "Old excerpt."
    YAML

    write_post('my-post.md', "---\ntitle: \"New Title\"\ndate: \"2024-01-01\"\nslug: \"my-post\"\n---\n\nUpdated content.")

    posts = build_blog(blog_dir: @tmpdir, posts_src: @posts_src)

    assert_equal 1, posts.length
    assert_equal 'New Title', posts[0]['title']
  end
end
