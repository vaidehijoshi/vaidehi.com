#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../migrate'

class TestDecodeEntities < Minitest::Test
  def test_decodes_lt_gt
    assert_equal '<tag>', decode_entities('&lt;tag&gt;')
  end

  def test_decodes_amp
    assert_equal 'a & b', decode_entities('a &amp; b')
  end

  def test_decodes_curly_quotes
    assert_equal 'don’t', decode_entities('don&rsquo;t')
  end

  def test_decodes_numeric_entity
    assert_equal 'A', decode_entities('&#65;')
  end

  def test_leaves_plain_text_alone
    assert_equal 'hello world', decode_entities('hello world')
  end

  def test_leaves_unknown_entity_alone
    assert_equal '&unknown;', decode_entities('&unknown;')
  end

  def test_decodes_nbsp
    assert_equal 'a b', decode_entities('a&nbsp;b')
  end
end

class TestEncodeForHtml < Minitest::Test
  def test_encodes_less_than
    assert_equal '&lt;', encode_for_html('<')
  end

  def test_encodes_greater_than
    assert_equal '&gt;', encode_for_html('>')
  end

  def test_encodes_ampersand_first
    assert_equal '&amp;lt;', encode_for_html('&lt;')
  end

  def test_leaves_plain_text_alone
    assert_equal 'hello', encode_for_html('hello')
  end
end

class TestNormaliseTags < Minitest::Test
  def test_maps_category_to_normalised_form
    assert_equal ['technical-tuesdays'], normalise_tags(['number-technicaltuesdays'])
  end

  def test_leaves_unknown_tags_as_is
    result = normalise_tags(['ruby', 'rails'])
    assert_includes result, 'ruby'
    assert_includes result, 'rails'
    assert_equal 2, result.length
  end

  def test_removes_duplicates
    result = normalise_tags(['ruby', 'ruby'])
    assert_equal ['ruby'], result
  end

  def test_sorts_tags
    result = normalise_tags(['zzz', 'aaa', 'mmm'])
    assert_equal ['aaa', 'mmm', 'zzz'], result
  end

  def test_handles_empty_array
    assert_equal [], normalise_tags([])
  end

  def test_mixed_known_and_unknown
    result = normalise_tags(['number-technicaltuesdays', 'ruby'])
    assert_includes result, 'technical-tuesdays'
    assert_includes result, 'ruby'
    refute_includes result, 'number-technicaltuesdays'
  end
end

class TestConvertCodeBlocks < Minitest::Test
  OCTOPRESS_FIGURE = <<~HTML
    <figure class='code'>
      <div class="highlight"><table><tr>
        <td class="gutter"><pre class="line-numbers"><span class='line-number'>1</span></pre></td>
        <td class='code'><pre><code class='ruby'><span class='line'><span class="k">puts</span> <span class="s2">&quot;hello&quot;</span>
    </span></code></pre></td>
      </tr></table></div>
    </figure>
  HTML

  def test_converts_to_pre_code
    result = convert_code_blocks(OCTOPRESS_FIGURE)
    assert_includes result, '<pre><code'
    assert_includes result, '</code></pre>'
    refute_includes result, '<figure'
    refute_includes result, '<table'
  end

  def test_extracts_language
    result = convert_code_blocks(OCTOPRESS_FIGURE)
    assert_includes result, 'class="language-ruby"'
  end

  def test_decodes_entities_in_code
    result = convert_code_blocks(OCTOPRESS_FIGURE)
    assert_includes result, '"hello"'
    refute_includes result, '&quot;'
  end

  def test_re_encodes_for_html
    figure = <<~HTML
      <figure class='code'>
        <div class="highlight"><table><tr>
          <td class="gutter"><pre></pre></td>
          <td class='code'><pre><code class='ruby'><span class='line'>x &lt; y</span></code></pre></td>
        </tr></table></div>
      </figure>
    HTML
    result = convert_code_blocks(figure)
    assert_includes result, '&lt;'
  end

  def test_handles_no_language
    figure = <<~HTML
      <figure class='code'>
        <div class="highlight"><table><tr>
          <td class="gutter"><pre></pre></td>
          <td class='code'><pre><code><span class='line'>plain code</span></code></pre></td>
        </tr></table></div>
      </figure>
    HTML
    result = convert_code_blocks(figure)
    assert_includes result, '<pre><code>'
  end

  def test_leaves_non_figure_html_alone
    html = '<p>regular paragraph</p>'
    assert_equal html, convert_code_blocks(html)
  end

  def test_handles_multiple_code_blocks
    html = OCTOPRESS_FIGURE + "\n<p>between</p>\n" + OCTOPRESS_FIGURE
    result = convert_code_blocks(html)
    assert_equal 2, result.scan('<pre><code').length
  end
end

class TestExtractDivContent < Minitest::Test
  def test_extracts_simple_div
    html = '<div class="entry-content"><p>Hello</p></div>'
    assert_equal '<p>Hello</p>', extract_div_content(html, 'entry-content')
  end

  def test_handles_nested_divs
    html = '<div class="entry-content"><div class="inner"><p>deep</p></div></div>'
    assert_equal '<div class="inner"><p>deep</p></div>', extract_div_content(html, 'entry-content')
  end

  def test_returns_empty_string_when_not_found
    html = '<p>no div here</p>'
    assert_equal '', extract_div_content(html, 'entry-content')
  end

  def test_extracts_correct_div_among_siblings
    html = '<div class="other">skip</div><div class="entry-content">target</div><div class="other">skip</div>'
    assert_equal 'target', extract_div_content(html, 'entry-content')
  end
end

class TestCleanContent < Minitest::Test
  def test_strips_html_comments
    html = '<p>before</p><!-- this is a comment --><p>after</p>'
    result = clean_content(html)
    refute_includes result, '<!--'
    assert_includes result, '<p>before</p>'
    assert_includes result, '<p>after</p>'
  end

  def test_collapses_extra_blank_lines
    html = "<p>a</p>\n\n\n\n<p>b</p>"
    result = clean_content(html)
    refute_includes result, "\n\n\n"
  end

  def test_converts_code_blocks
    html = <<~HTML
      <p>intro</p>
      <figure class='code'>
        <div class="highlight"><table><tr>
          <td class="gutter"><pre></pre></td>
          <td class='code'><pre><code class='ruby'><span class='line'>puts "hi"</span></code></pre></td>
        </tr></table></div>
      </figure>
    HTML
    result = clean_content(html)
    assert_includes result, '<pre><code'
    refute_includes result, '<figure'
  end
end

class TestExtractPost < Minitest::Test
  SAMPLE_HTML = <<~HTML
    <!DOCTYPE html>
    <html>
      <head><title>Test</title></head>
      <body>
        <article>
          <header>
            <h1 class="entry-title">Class Inheritance</h1>
            <p class="meta">
              <time class='entry-date' datetime='2014-10-16T18:00:34-07:00'>Oct 16th, 2014</time>
            </p>
            <div class="categories">
              <span class="categories">
                Filed under: <span class='category'><a href='/blog/categories/ruby/'>ruby</a></span>
              </span>
            </div>
          </header>
          <div class="entry-content">
            <p>Hello world. This is a test post about Ruby inheritance.</p>
          </div>
        </article>
      </body>
    </html>
  HTML

  def test_extracts_title
    post = extract_post(SAMPLE_HTML, 'blog/2014/10/16/class-inheritance/index.html')
    assert_equal 'Class Inheritance', post[:title]
  end

  def test_extracts_date
    post = extract_post(SAMPLE_HTML, 'blog/2014/10/16/class-inheritance/index.html')
    assert_equal '2014-10-16', post[:date]
  end

  def test_extracts_slug_from_path
    post = extract_post(SAMPLE_HTML, 'blog/2014/10/16/class-inheritance/index.html')
    assert_equal 'class-inheritance', post[:slug]
  end

  def test_extracts_content
    post = extract_post(SAMPLE_HTML, 'blog/2014/10/16/class-inheritance/index.html')
    assert_includes post[:content], 'Hello world'
  end

  def test_generates_excerpt
    post = extract_post(SAMPLE_HTML, 'blog/2014/10/16/class-inheritance/index.html')
    refute_empty post[:excerpt]
    assert_includes post[:excerpt], 'Hello world'
  end

  def test_extracts_categories_as_tags
    html = SAMPLE_HTML.sub('</div>', '').sub(
      '<div class="categories">',
      '<div class="categories"><a href=\'/blog/categories/ruby/\'>ruby</a></div><div class="x">'
    )
    post = extract_post(html, 'blog/2014/10/16/class-inheritance/index.html')
    assert_includes post[:tags], 'ruby'
  end

  def test_handles_missing_title
    html = SAMPLE_HTML.sub(/<h1 class="entry-title">.*?<\/h1>/m, '')
    post = extract_post(html, 'blog/2014/10/16/class-inheritance/index.html')
    assert_equal '', post[:title]
  end

  def test_handles_entities_in_title
    html = SAMPLE_HTML.sub('Class Inheritance', 'Don&rsquo;t Stop')
    post = extract_post(html, 'blog/2014/10/16/class-inheritance/index.html')
    assert_equal "Don’t Stop", post[:title]
  end
end
