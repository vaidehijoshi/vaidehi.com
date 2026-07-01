# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../build'

RSpec.describe '#parse_front_matter' do
  it 'parses double-quoted values' do
    raw = "---\ntitle: \"Hello World\"\ndate: \"2024-01-01\"\n---\n\nBody text."
    data, body = parse_front_matter(raw)
    expect(data['title']).to eq('Hello World')
    expect(data['date']).to eq('2024-01-01')
    expect(body).to eq('Body text.')
  end

  it 'parses single-quoted values' do
    raw = "---\ntitle: 'My Post'\n---\n\ncontent"
    data, body = parse_front_matter(raw)
    expect(data['title']).to eq('My Post')
    expect(body).to eq('content')
  end

  it 'returns empty data when there is no front matter' do
    raw = 'Just plain text.'
    data, body = parse_front_matter(raw)
    expect(data).to eq({})
    expect(body).to eq('Just plain text.')
  end

  it 'parses comma-separated tags' do
    raw = "---\ntags: \"ruby, rails, refactoring\"\n---\n\nbody"
    data, _body = parse_front_matter(raw)
    tags = data['tags'].to_s.split(',').map(&:strip).reject(&:empty?)
    expect(tags).to eq(%w[ruby rails refactoring])
  end

  it 'handles empty tags' do
    raw = "---\ntags: \"\"\n---\n\nbody"
    data, _body = parse_front_matter(raw)
    tags = data['tags'].to_s.split(',').map(&:strip).reject(&:empty?)
    expect(tags).to be_empty
  end

  it 'falls back gracefully when closing --- has no trailing newline' do
    raw = "---\ntitle: \"No Newline\"\ndate: \"2024-01-01\"\n---"
    data, body = parse_front_matter(raw)
    expect(data).to eq({})
    expect(body).to eq(raw)
  end
end

RSpec.describe '#format_date' do
  it 'formats an ISO date' do
    expect(format_date('2024-01-01')).to eq('January 1, 2024')
  end

  it 'omits the leading zero from the day' do
    expect(format_date('2015-06-05')).to eq('June 5, 2015')
  end

  it 'returns the original string for an invalid date' do
    expect(format_date('not-a-date')).to eq('not-a-date')
  end

  it 'returns an empty string for nil' do
    expect(format_date(nil)).to eq('')
  end
end

RSpec.describe '#make_excerpt' do
  it 'strips HTML tags' do
    expect(make_excerpt('<p>Hello <strong>world</strong>.</p>')).to eq('Hello world .')
  end

  it 'returns the full text when it fits within the limit' do
    expect(make_excerpt('<p>Short text.</p>')).to eq('Short text.')
  end

  it 'truncates at a word boundary and appends an ellipsis' do
    html = '<p>' + ('word ' * 60) + '</p>'
    result = make_excerpt(html, 30)
    expect(result).to end_with('…')
    expect(result.length).to be <= 35
    expect(result).to match(/\A(word ?)+ *…\z/)
  end

  it 'respects a custom max length' do
    result = make_excerpt('<p>one two three four five</p>', 10)
    expect(result).to end_with('…')
    expect(result.length).to be <= 15
  end
end

RSpec.describe '#tags_html' do
  it 'returns an empty string when there are no tags' do
    expect(tags_html([])).to eq('')
  end

  it 'wraps tags in a post-tags div' do
    result = tags_html(['ruby'])
    expect(result).to include('<div class="post-tags">')
    expect(result).to include('<a href="/blog/tags/ruby" class="post-tag">ruby</a>')
  end

  it 'renders multiple tags' do
    result = tags_html(%w[ruby rails])
    expect(result).to include('ruby')
    expect(result).to include('rails')
  end

  it 'escapes special characters in tag names' do
    result = tags_html(['a & b'])
    expect(result).to include('a &amp; b')
    expect(result).not_to include('a & b')
  end

  it 'percent-encodes the href and HTML-escapes the display text independently' do
    result = tags_html(['a & b'])
    expect(result).to include('href="/blog/tags/a+%26+b"')
    expect(result).to include('>a &amp; b<')
  end
end

RSpec.describe '#build_blog' do
  let(:tmpdir)    { Dir.mktmpdir }
  let(:posts_src) { File.join(tmpdir, '_posts').tap { |d| FileUtils.mkdir_p(d) } }

  after { FileUtils.rm_rf(tmpdir) }

  def write_post(filename, content)
    File.write(File.join(posts_src, filename), content)
  end

  it 'builds a single Markdown post' do
    write_post('hello-world.md', <<~MD)
      ---
      title: "Hello World"
      date: "2024-06-01"
      slug: "hello-world"
      tags: "ruby, testing"
      ---

      Hello **world**.
    MD

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts.length).to eq(1)
    expect(posts[0]['title']).to eq('Hello World')
    expect(posts[0]['date']).to eq('2024-06-01')
    expect(posts[0]['slug']).to eq('hello-world')
    expect(posts[0]['tags']).to eq(%w[ruby testing])
  end

  it 'generates [slug]/index.html for each post' do
    write_post('test-post.md', <<~MD)
      ---
      title: "Test Post"
      date: "2024-01-01"
      slug: "test-post"
      ---

      Content here.
    MD

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    out  = File.join(tmpdir, 'test-post', 'index.html')
    html = File.read(out)
    expect(File.exist?(out)).to be true
    expect(html).to include('Test Post')
    expect(html).to include('<p>Content here.</p>')
    expect(html).to include('January 1, 2024')
    expect(html).to include('<header id="site-header">')
    expect(html).to include('<script src="/header.js">')
  end

  it 'generates posts.yaml with newest post first' do
    write_post('post-a.md', "---\ntitle: \"A\"\ndate: \"2024-02-01\"\nslug: \"post-a\"\n---\n\nBody A.")
    write_post('post-b.md', "---\ntitle: \"B\"\ndate: \"2024-01-01\"\nslug: \"post-b\"\n---\n\nBody B.")

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    content = File.read(File.join(tmpdir, 'posts.yaml'))
    expect(content).to include('title: "A"')
    expect(content).to include('title: "B"')
    expect(content.index('title: "A"')).to be < content.index('title: "B"')
  end

  it 'sorts posts newest first in the returned array' do
    write_post('old.md', "---\ntitle: \"Old\"\ndate: \"2020-01-01\"\nslug: \"old\"\n---\n\nOld.")
    write_post('new.md', "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nNew.")

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts[0]['slug']).to eq('new')
    expect(posts[1]['slug']).to eq('old')
  end

  it 'auto-generates an excerpt from the post body' do
    write_post('no-excerpt.md', <<~MD)
      ---
      title: "No Excerpt"
      date: "2024-01-01"
      slug: "no-excerpt"
      ---

      This is the post body with enough text to generate an excerpt automatically.
    MD

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts[0]['excerpt']).not_to be_empty
    expect(posts[0]['excerpt']).to include('This is the post body')
  end

  it 'uses an explicit excerpt over the auto-generated one' do
    write_post('with-excerpt.md', <<~MD)
      ---
      title: "With Excerpt"
      date: "2024-01-01"
      slug: "with-excerpt"
      excerpt: "Custom excerpt."
      ---

      Long body that would generate a different auto-excerpt.
    MD

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts[0]['excerpt']).to eq('Custom excerpt.')
  end

  it 'renders tags as links in the generated HTML' do
    write_post('tagged.md', <<~MD)
      ---
      title: "Tagged"
      date: "2024-01-01"
      slug: "tagged"
      tags: "ruby, rails"
      ---

      Content.
    MD

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    html = File.read(File.join(tmpdir, 'tagged', 'index.html'))
    expect(html).to include('<a href="/blog/tags/ruby" class="post-tag">ruby</a>')
    expect(html).to include('<a href="/blog/tags/rails" class="post-tag">rails</a>')
  end

  it 'generates tag index pages' do
    write_post('tagged.md', <<~MD)
      ---
      title: "Tagged"
      date: "2024-01-01"
      slug: "tagged"
      tags: "ruby"
      ---

      Content.
    MD

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    tag_index = File.join(tmpdir, 'tags', 'ruby', 'index.html')
    expect(File.exist?(tag_index)).to be true
    html = File.read(tag_index)
    expect(html).to include('#ruby')
    expect(html).to include('/blog/tagged')
    expect(html).to include('Tagged')
  end

  it 'returns an empty array when there are no posts' do
    expect(build_blog(blog_dir: tmpdir, posts_src: posts_src)).to eq([])
  end

  it 'falls back to the filename as the slug' do
    write_post('my-post.md', "---\ntitle: \"My Post\"\ndate: \"2024-01-01\"\n---\n\nBody.")

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts[0]['slug']).to eq('my-post')
  end

  it 'ignores .html files in _posts' do
    write_post('old.html', "---\ntitle: \"Old\"\ndate: \"2020-01-01\"\nslug: \"old\"\n---\n\n<p>old</p>")
    write_post('new.md',   "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nNew.")

    slugs = build_blog(blog_dir: tmpdir, posts_src: posts_src).map { |p| p['slug'] }

    expect(slugs).to include('new')
    expect(slugs).not_to include('old')
  end

  it 'preserves migrated posts from an existing posts.yaml' do
    File.write(File.join(tmpdir, 'posts.yaml'), <<~YAML)
      - title: "Migrated Post"
        date: "2015-01-01"
        slug: "migrated-post"
        tags: ["ruby"]
        excerpt: "Old post from the migration."
    YAML

    write_post('new-post.md', "---\ntitle: \"New Post\"\ndate: \"2024-01-01\"\nslug: \"new-post\"\n---\n\nNew content.")

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)
    slugs = posts.map { |p| p['slug'] }

    expect(slugs).to include('new-post')
    expect(slugs).to include('migrated-post')
    expect(posts.length).to eq(2)
  end

  it 'overwrites an existing yaml entry when a .md source exists for that slug' do
    File.write(File.join(tmpdir, 'posts.yaml'), <<~YAML)
      - title: "Old Title"
        date: "2024-01-01"
        slug: "my-post"
        tags: ""
        excerpt: "Old excerpt."
    YAML

    write_post('my-post.md', "---\ntitle: \"New Title\"\ndate: \"2024-01-01\"\nslug: \"my-post\"\n---\n\nUpdated content.")

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts.length).to eq(1)
    expect(posts[0]['title']).to eq('New Title')
  end

  it 'HTML-escapes a malformed date that falls back to raw iso string' do
    write_post('bad-date.md', <<~MD)
      ---
      title: "Bad Date"
      date: "not-a-<date>"
      slug: "bad-date"
      ---

      Body.
    MD

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    html = File.read(File.join(tmpdir, 'bad-date', 'index.html'))
    expect(html).to include('not-a-&lt;date&gt;')
    expect(html).not_to include('not-a-<date>')
  end

  it 'HTML-escapes special characters in the <h1> title' do
    write_post('special.md', <<~MD)
      ---
      title: "Hello <World> & \"Friends\""
      date: "2024-01-01"
      slug: "special"
      ---

      Body.
    MD

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    html = File.read(File.join(tmpdir, 'special', 'index.html'))
    expect(html).to include('<h1 class="post-title">Hello &lt;World&gt; &amp; &quot;Friends&quot;</h1>')
    expect(html).not_to include('<h1 class="post-title">Hello <World>')
  end

  it 'does not crash when a migrated post has nil tags' do
    File.write(File.join(tmpdir, 'posts.yaml'), <<~YAML)
      - title: "No Tags Post"
        date: "2015-06-01"
        slug: "no-tags"
        excerpt: "A post with no tags field at all."
    YAML

    write_post('new.md', "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nContent.")

    slugs = build_blog(blog_dir: tmpdir, posts_src: posts_src).map { |p| p['slug'] }

    expect(slugs).to include('no-tags')
    expect(slugs).to include('new')
  end

  it 'does not crash when a migrated post has nil date' do
    File.write(File.join(tmpdir, 'posts.yaml'), <<~YAML)
      - title: "No Date Post"
        slug: "no-date"
        tags: []
        excerpt: "A post with no date field."
    YAML

    write_post('new.md', "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nContent.")

    posts = build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect(posts.length).to eq(2)
    expect(posts[0]['slug']).to eq('new')
  end

  it 'safely serializes a title containing double quotes into posts.yaml' do
    write_post('quoted.md', <<~MD)
      ---
      title: 'She said "hello"'
      date: "2024-01-01"
      slug: "quoted"
      ---

      Body.
    MD

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    reloaded = YAML.safe_load(File.read(File.join(tmpdir, 'posts.yaml')))
    expect(reloaded[0]['title']).to eq('She said "hello"')
  end

  it 'serializes empty tags as [] in posts.yaml' do
    write_post('no-tags.md', "---\ntitle: \"No Tags\"\ndate: \"2024-01-01\"\nslug: \"no-tags\"\n---\n\nBody.")

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    content = File.read(File.join(tmpdir, 'posts.yaml'))
    expect(content).to include('tags: []')
    expect(content).not_to include('tags: ""')
  end

  it 'does not crash on a second build when a post has empty tags' do
    write_post('no-tags.md', "---\ntitle: \"No Tags\"\ndate: \"2024-01-01\"\nslug: \"no-tags\"\n---\n\nBody.")

    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    expect { build_blog(blog_dir: tmpdir, posts_src: posts_src) }.not_to raise_error
  end

  it 'generates tag pages for tags from migrated posts in posts.yaml' do
    File.write(File.join(tmpdir, 'posts.yaml'), <<~YAML)
      - title: "Migrated"
        date: "2015-01-01"
        slug: "migrated"
        tags: ["ruby"]
        excerpt: "Old post."
    YAML

    write_post('new.md', "---\ntitle: \"New\"\ndate: \"2024-01-01\"\nslug: \"new\"\n---\n\nContent.")
    build_blog(blog_dir: tmpdir, posts_src: posts_src)

    tag_index = File.join(tmpdir, 'tags', 'ruby', 'index.html')
    expect(File.exist?(tag_index)).to be true
    expect(File.read(tag_index)).to include('Migrated')
  end
end

RSpec.describe 'build_tag_pages' do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  let(:posts) do
    [
      { 'title' => 'Ruby Post',  'date' => '2024-06-01', 'slug' => 'ruby-post',  'tags' => %w[ruby] },
      { 'title' => 'Rails Post', 'date' => '2024-05-01', 'slug' => 'rails-post', 'tags' => %w[ruby rails] },
      { 'title' => 'No Tags',    'date' => '2024-04-01', 'slug' => 'no-tags',    'tags' => [] },
    ]
  end

  it 'creates a directory and index.html for each tag' do
    build_tag_pages(posts, blog_dir: tmpdir)

    expect(File.exist?(File.join(tmpdir, 'tags', 'ruby',  'index.html'))).to be true
    expect(File.exist?(File.join(tmpdir, 'tags', 'rails', 'index.html'))).to be true
  end

  it 'does not create a tag page for posts with no tags' do
    build_tag_pages(posts, blog_dir: tmpdir)

    expect(Dir.exist?(File.join(tmpdir, 'tags', 'no-tags'))).to be false
  end

  it 'includes the tag name as a heading' do
    build_tag_pages(posts, blog_dir: tmpdir)

    html = File.read(File.join(tmpdir, 'tags', 'ruby', 'index.html'))
    expect(html).to include('#ruby')
  end

  it 'lists only posts that have that tag' do
    build_tag_pages(posts, blog_dir: tmpdir)

    ruby_html  = File.read(File.join(tmpdir, 'tags', 'ruby',  'index.html'))
    rails_html = File.read(File.join(tmpdir, 'tags', 'rails', 'index.html'))

    expect(ruby_html).to include('Ruby Post')
    expect(ruby_html).to include('Rails Post')
    expect(rails_html).to include('Rails Post')
    expect(rails_html).not_to include('Ruby Post')
  end

  it 'sorts posts newest first' do
    build_tag_pages(posts, blog_dir: tmpdir)

    html = File.read(File.join(tmpdir, 'tags', 'ruby', 'index.html'))
    expect(html.index('Ruby Post')).to be < html.index('Rails Post')
  end

  it 'includes a link back to /blog' do
    build_tag_pages(posts, blog_dir: tmpdir)

    html = File.read(File.join(tmpdir, 'tags', 'ruby', 'index.html'))
    expect(html).to include('href="/blog"')
  end

  it 'returns the sorted list of generated tag names' do
    result = build_tag_pages(posts, blog_dir: tmpdir)
    expect(result).to eq(%w[rails ruby])
  end

  it 'omits the date span for posts without a date' do
    build_tag_pages(
      [{ 'title' => 'No Date', 'date' => nil, 'slug' => 'no-date', 'tags' => %w[ruby] }],
      blog_dir: tmpdir
    )
    html = File.read(File.join(tmpdir, 'tags', 'ruby', 'index.html'))
    expect(html).not_to include('post-list-date')
    expect(html).to include('No Date')
  end

  it 'HTML-escapes post titles in tag page list items' do
    build_tag_pages(
      [{ 'title' => '<b>Bold</b>', 'date' => '2024-01-01', 'slug' => 'safe-slug', 'tags' => %w[ruby] }],
      blog_dir: tmpdir
    )
    html = File.read(File.join(tmpdir, 'tags', 'ruby', 'index.html'))
    expect(html).to include('&lt;b&gt;Bold&lt;/b&gt;')
    expect(html).not_to include('<b>Bold</b>')
  end
end
