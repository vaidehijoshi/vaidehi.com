# Writing a new blog post

Posts live in `blog/_posts/` as Markdown files. The build script converts them to static HTML.

## Quickstart

```bash
# 1. Create the post file
touch blog/_posts/your-post-slug.md

# 2. Add front matter + content (see format below)

# 3. Build
ruby blog/build.rb

# 4. Preview locally
ruby -run -e httpd . -p 8080
# → open http://localhost:8080/blog/your-post-slug
```

## Front matter

Every post starts with a `---` block:

```markdown
---
title: "Your Post Title"
date: "2026-06-24"
slug: "your-post-slug"
tags: "ruby, rails, refactoring"
---

Your content starts here.
```

| Field | Required | Notes |
|-------|----------|-------|
| `title` | yes | Displayed as the `<h1>` and page `<title>` |
| `date` | yes | ISO format `YYYY-MM-DD`, used for sorting |
| `slug` | yes | Must match the filename (without `.md`); becomes the URL path `/blog/your-post-slug` |
| `tags` | no | Comma-separated list of tags |
| `excerpt` | no | If omitted, auto-generated from the first ~220 characters of the post |

## Content

Write normal Markdown. Fenced code blocks with a language identifier get syntax-highlighted via highlight.js in the browser:

````markdown
```ruby
def hello
  puts "hello, world"
end
```
````

## What the build script does

`ruby blog/build.rb` reads every file in `blog/_posts/` and:

- Converts `.md` files to HTML via [Kramdown](https://kramdown.gettalong.org/)
- Wraps content in the page template (same header, footer, dark-mode toggle as the main site)
- Writes the page to `blog/[slug]/index.html`
- Regenerates `blog/posts.yaml` (the listing index read by `blog/index.html`)

## Committing a new post

After building, commit the source file, the generated HTML, and the updated index:

```bash
git add blog/_posts/your-post-slug.md \
        blog/your-post-slug/index.html \
        blog/posts.yaml
git commit -m "Add post: Your Post Title"
```

## Editing an existing post

Edit `blog/_posts/[slug].md`, then re-run `ruby blog/build.rb` and commit.

Migrated posts don't have a `.md` source — edit `blog/[slug]/index.html` directly and skip the build step.
