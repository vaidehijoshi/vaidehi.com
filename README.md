# vaidehi.com

Personal website for [Vaidehi Joshi](https://vaidehi.com).

## Stack

Plain HTML, CSS, and vanilla JavaScript — no framework, no build step. Content is stored in `data.yaml` and loaded at runtime via [`js-yaml`](https://github.com/nodeca/js-yaml). Icons via [Font Awesome](https://fontawesome.com/).

## Running locally

The site uses `fetch()` to load `data.yaml`, so it must be served over HTTP rather than opened as a `file://` URL.

```bash
ruby -run -e httpd . -p 8080
```

Then open `http://localhost:8080`.

## Project structure

```
index.html        # Page shell — layout and JS
style.css         # All styles, including light/dark theme variables
data.yaml         # All content: talks, writing links, recommendations
vaidehi-white.png # Logo image
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
