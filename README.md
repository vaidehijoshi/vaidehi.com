# vaidehi.com

Personal website for [Vaidehi Joshi](https://vaidehi.com).

## Stack

Plain HTML, CSS, and vanilla JavaScript — no framework, no build step. Content is stored in `data.yaml` and loaded at runtime via [`js-yaml`](https://github.com/nodeca/js-yaml). Icons via [Font Awesome](https://fontawesome.com/).

The blog (`/blog`) is a set of static HTML files generated from Markdown sources in `blog/_posts/` using a small Ruby build script. See [WRITING.md](WRITING.md) for how to add a post.

## Running locally

The site uses `fetch()` to load `data.yaml`, so it must be served over HTTP rather than opened as a `file://` URL.

```bash
ruby -run -e httpd . -p 8080
```

Then open `http://localhost:8080`.

## Project structure

```
index.html          # Page shell — layout and JS
style.css           # All styles, including light/dark theme variables
data.yaml           # All content: talks, writing links, recommendations
vaidehi-white.png   # Logo (white, transparent background)
og-image.png        # Social card image (1200×630) for og:image / Twitter previews

blog/
  index.html        # Blog listing page
  blog.css          # Blog-specific styles
  build.rb          # Build script: _posts/ → [slug]/index.html + posts.yaml
  migrate.rb        # One-time migration script (Octopress → _posts/)
  Gemfile           # Ruby gem dependencies (kramdown, kramdown-parser-gfm)
  Gemfile.lock
  posts.yaml        # Generated post index (title, date, slug, tags, excerpt)
  _posts/           # Source files for new posts (.md only; migrated posts have no source)
  test/             # Minitest suite for build.rb and migrate.rb
  [slug]/           # Generated post directories (one per post)
```

## Updating content

All content lives in `data.yaml`. No HTML changes needed.

**Add a talk:**
```yaml
talks:
  keynote_and_leadership:
    - title: "Talk Title"
      year: 2025
      url: "https://youtube.com/..."
```

**Add a writing link:**
```yaml
writing:
  - title: "Publication Name"
    url: "https://..."
```

**Add a recommendation:**
```yaml
recommendations:
  - author: "Name"
    text: >-
      Recommendation text here.
```

## Theming

The site defaults to the user's system preference (`prefers-color-scheme`) and supports a manual light/dark toggle. Colors are defined as CSS custom properties in `:root` (light) and `[data-theme="dark"]` in `style.css`.
