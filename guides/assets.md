# Assets

Fractal's asset pipeline has **no Node, no bundler, and no build step**
beyond `mix compile`. Agents write content — plain modern CSS and
files — not build configuration.

## CSS: page-scoped styles in the page module

A page optionally implements `style/0`, returning plain CSS for that
page only:

```elixir
defmodule Fractal.Pages.Pricing do
  use Fractal.Page, path: "/pricing", title: "Pricing"

  @impl Fractal.Page
  def style do
    """
    .plans { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; }
    .plan h2 { color: var(--accent); }
    """
  end

  def render(assigns), do: # ...
end
```

The rules:

- Styles are collected automatically (like routes) and **scoped
  automatically**: each block is wrapped in `[data-page="pricing"]`
  using native CSS nesting, and the document puts that attribute on
  `<main>`. Selectors in `style/0` are therefore relative to the page —
  and physically cannot affect any other page.
- **Shared design goes in `assets/app.css`** — tokens (`--accent`,
  `--muted`, `--surface`, ...) and app-wide element styles. Prefer
  tokens over hard-coded colors in page styles. Twenty pages each
  styling their own buttons is the failure mode; if a style is needed
  twice, move it to `app.css`.
- Everything is served as one fingerprinted stylesheet; in development,
  editing `style/0` or `app.css` reloads the browser automatically.
- **Never render a `<style>` tag** — verification fails pages that do.
  Inline `style=` attributes remain fine for genuinely dynamic values
  (e.g. a progress bar width).
- Plain CSS only: variables and nesting are native now; there is no
  Sass/PostCSS/Tailwind and no reason to ask for one.

Scaffold a page with a style block via
`mix fractal.gen.page Name --style`.

## Images, fonts, and other static files

Files live in `assets/static/` and are referenced **only** through
`asset_path/1` (imported in every page):

```elixir
tag(:img, src: asset_path("logo.svg"), alt: "Fractal logo")
```

- URLs are fingerprinted (`/assets/logo.svg?vsn=<hash>`) and served
  with long-lived cache headers.
- `asset_path/1` **raises for missing files**, and verification
  smoke-renders every page — so a typo'd filename fails
  `mix fractal.verify` naming the page, instead of 404ing in
  production. The error lists the files that do exist.
- `mix fractal.verify` also reports (informationally) files in
  `assets/static/` that no page references.

## JavaScript: there is no user JS pipeline — deliberately

Interactivity is a framework primitive (`guides/interactivity.md`);
pages never ship their own scripts. Two rules verification enforces:

- No `<script>` tags in rendered output (long-standing rule).
- **No external `script`/`link` references** (CDNs). Third-party client
  code is a supply-chain risk and breaks "the framework owns the
  client." If a file is truly needed, vendor it into `assets/static/` —
  but for behavior, the answer is framework primitives, not scripts.

## Testing styles

`style/0` is data — test it like data when it matters:

```elixir
test "declares its scoped styles" do
  assert Fractal.Pages.Pricing.style() =~ ".plans"
end
```

Verification already checks every `style/0` for balanced braces and
every page render for the rules above; the CSS bundle itself can be
asserted through `Fractal.Assets.css_bundle/0`.
