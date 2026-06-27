# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../migrate'

RSpec.describe 'decode_entities' do
  it 'decodes &lt; and &gt;' do
    expect(decode_entities('&lt;tag&gt;')).to eq('<tag>')
  end

  it 'decodes &amp;' do
    expect(decode_entities('a &amp; b')).to eq('a & b')
  end

  it 'decodes curly quotes' do
    expect(decode_entities('don&rsquo;t')).to eq('don’t')
  end

  it 'decodes numeric character references' do
    expect(decode_entities('&#65;')).to eq('A')
  end

  it 'leaves plain text unchanged' do
    expect(decode_entities('hello world')).to eq('hello world')
  end

  it 'leaves unknown entities unchanged' do
    expect(decode_entities('&unknown;')).to eq('&unknown;')
  end

  it 'decodes &nbsp; to a regular space' do
    expect(decode_entities('a&nbsp;b')).to eq('a b')
  end
end

RSpec.describe 'encode_for_html' do
  it 'encodes < as &lt;' do
    expect(encode_for_html('<')).to eq('&lt;')
  end

  it 'encodes > as &gt;' do
    expect(encode_for_html('>')).to eq('&gt;')
  end

  it 'encodes & before encoding < or >' do
    expect(encode_for_html('&lt;')).to eq('&amp;lt;')
  end

  it 'leaves plain text unchanged' do
    expect(encode_for_html('hello')).to eq('hello')
  end
end

RSpec.describe 'normalise_tags' do
  it 'maps known category slugs to their normalised form' do
    expect(normalise_tags(['number-technicaltuesdays'])).to eq(['technical-tuesdays'])
  end

  it 'passes through unknown tags unchanged' do
    result = normalise_tags(%w[ruby rails])
    expect(result).to include('ruby')
    expect(result).to include('rails')
    expect(result.length).to eq(2)
  end

  it 'removes duplicates' do
    expect(normalise_tags(%w[ruby ruby])).to eq(['ruby'])
  end

  it 'sorts the resulting tags' do
    expect(normalise_tags(%w[zzz aaa mmm])).to eq(%w[aaa mmm zzz])
  end

  it 'returns an empty array for empty input' do
    expect(normalise_tags([])).to eq([])
  end

  it 'handles a mix of known and unknown tags' do
    result = normalise_tags(%w[number-technicaltuesdays ruby])
    expect(result).to include('technical-tuesdays')
    expect(result).to include('ruby')
    expect(result).not_to include('number-technicaltuesdays')
  end
end

RSpec.describe 'convert_code_blocks' do
  let(:octopress_figure) do
    <<~HTML
      <figure class='code'>
        <div class="highlight"><table><tr>
          <td class="gutter"><pre class="line-numbers"><span class='line-number'>1</span></pre></td>
          <td class='code'><pre><code class='ruby'><span class='line'><span class="k">puts</span> <span class="s2">&quot;hello&quot;</span>
      </span></code></pre></td>
        </tr></table></div>
      </figure>
    HTML
  end

  it 'converts Octopress figure blocks to <pre><code>' do
    result = convert_code_blocks(octopress_figure)
    expect(result).to include('<pre><code')
    expect(result).to include('</code></pre>')
    expect(result).not_to include('<figure')
    expect(result).not_to include('<table')
  end

  it 'extracts the language class' do
    expect(convert_code_blocks(octopress_figure)).to include('class="language-ruby"')
  end

  it 'decodes HTML entities inside the code block' do
    result = convert_code_blocks(octopress_figure)
    expect(result).to include('"hello"')
    expect(result).not_to include('&quot;')
  end

  it 're-encodes < and > for display in HTML' do
    figure = <<~HTML
      <figure class='code'>
        <div class="highlight"><table><tr>
          <td class="gutter"><pre></pre></td>
          <td class='code'><pre><code class='ruby'><span class='line'>x &lt; y</span></code></pre></td>
        </tr></table></div>
      </figure>
    HTML
    expect(convert_code_blocks(figure)).to include('&lt;')
  end

  it 'omits the language class when none is specified' do
    figure = <<~HTML
      <figure class='code'>
        <div class="highlight"><table><tr>
          <td class="gutter"><pre></pre></td>
          <td class='code'><pre><code><span class='line'>plain code</span></code></pre></td>
        </tr></table></div>
      </figure>
    HTML
    expect(convert_code_blocks(figure)).to include('<pre><code>')
  end

  it 'leaves non-figure HTML unchanged' do
    html = '<p>regular paragraph</p>'
    expect(convert_code_blocks(html)).to eq(html)
  end

  it 'converts multiple code blocks in one pass' do
    html = octopress_figure + "\n<p>between</p>\n" + octopress_figure
    expect(convert_code_blocks(html).scan('<pre><code').length).to eq(2)
  end
end

RSpec.describe 'extract_div_content' do
  it 'extracts the content of a simple div' do
    html = '<div class="entry-content"><p>Hello</p></div>'
    expect(extract_div_content(html, 'entry-content')).to eq('<p>Hello</p>')
  end

  it 'handles nested divs correctly' do
    html = '<div class="entry-content"><div class="inner"><p>deep</p></div></div>'
    expect(extract_div_content(html, 'entry-content')).to eq('<div class="inner"><p>deep</p></div>')
  end

  it 'returns an empty string when the div is not found' do
    expect(extract_div_content('<p>no div here</p>', 'entry-content')).to eq('')
  end

  it 'extracts the correct div among siblings' do
    html = '<div class="other">skip</div><div class="entry-content">target</div><div class="other">skip</div>'
    expect(extract_div_content(html, 'entry-content')).to eq('target')
  end
end

RSpec.describe 'clean_content' do
  it 'strips HTML comments' do
    html   = '<p>before</p><!-- this is a comment --><p>after</p>'
    result = clean_content(html)
    expect(result).not_to include('<!--')
    expect(result).to include('<p>before</p>')
    expect(result).to include('<p>after</p>')
  end

  it 'collapses runs of blank lines' do
    result = clean_content("<p>a</p>\n\n\n\n<p>b</p>")
    expect(result).not_to include("\n\n\n")
  end

  it 'converts Octopress code blocks' do
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
    expect(result).to include('<pre><code')
    expect(result).not_to include('<figure')
  end
end

RSpec.describe 'extract_post' do
  let(:sample_html) do
    <<~HTML
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
  end

  let(:path) { 'blog/2014/10/16/class-inheritance/index.html' }

  it 'extracts the title' do
    expect(extract_post(sample_html, path)[:title]).to eq('Class Inheritance')
  end

  it 'extracts the date from the datetime attribute' do
    expect(extract_post(sample_html, path)[:date]).to eq('2014-10-16')
  end

  it 'extracts the slug from the file path' do
    expect(extract_post(sample_html, path)[:slug]).to eq('class-inheritance')
  end

  it 'extracts the post body content' do
    expect(extract_post(sample_html, path)[:content]).to include('Hello world')
  end

  it 'generates an excerpt from the content' do
    post = extract_post(sample_html, path)
    expect(post[:excerpt]).not_to be_empty
    expect(post[:excerpt]).to include('Hello world')
  end

  it 'extracts categories as tags' do
    html = sample_html.sub('</div>', '').sub(
      '<div class="categories">',
      '<div class="categories"><a href=\'/blog/categories/ruby/\'>ruby</a></div><div class="x">'
    )
    expect(extract_post(html, path)[:tags]).to include('ruby')
  end

  it 'returns an empty title when the h1 is missing' do
    html = sample_html.sub(/<h1 class="entry-title">.*?<\/h1>/m, '')
    expect(extract_post(html, path)[:title]).to eq('')
  end

  it 'decodes HTML entities in the title' do
    html = sample_html.sub('Class Inheritance', 'Don&rsquo;t Stop')
    expect(extract_post(html, path)[:title]).to eq("Don’t Stop")
  end
end
