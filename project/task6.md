# Task 6: asset pipeline (CSS, images, static files — no Node)

## Goal

Fractal is a new web framework written in Elixir that is AI-first.

In practice that means at least the following:

- It provides primitives for building web-pages in a way that AI agents can
easily consume and extend.

- It focuses on the developer experience using AI to build the web application.
Developers can dive in and write code, but the fundamental pattern is to prompt
the AI.

- It has built-in verification checks to ensure that the code AI produces is
correct.

- It has built-in documentation that the AI uses when a developer prompts it to
create a new page or feature.

Established principles that shape this task: the server stays stateless; we
don't reimplement battle-tested plumbing (Plug.Static here); zero-API where
the framework owns both ends (the CSRF precedent); options that exist get
pasted into the wrong file, so escape hatches are not added preemptively.

## Framing

Agents write content, not build config. A traditional pipeline
(npm + esbuild/webpack) solves human problems — repetition, transpiling — and
hands agents a second ecosystem of lockfiles, network installs, and config to
fiddle with. Meanwhile agents are excellent at plain modern CSS (native
variables and nesting cover the old preprocessor arguments). The bet:
**no Node, no bundler, no build step beyond `mix compile`** — which the
reloader already drives.

## Scope

### 1. CSS: page-scoped styles in the page module

Extend one-file-per-page to styling. A page optionally implements `style/0`:

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

- **Auto-collected** like routes are auto-discovered; new optional callback
  `style/0` (defaults to none).
- **Scoped without a CSS parser**: the layout wraps page content in
  `data-page="<slug>"`, and the collector emits
  `[data-page="pricing"] { ...page css... }`, relying on native CSS nesting.
  A page's styles physically cannot leak into another page — blast-radius
  containment as a framework property, same move as escaped-by-default HTML.
- **App-wide design tokens** (the current layout stylesheet, `--accent`,
  fonts) move to one shared `assets/app.css`, concatenated first.
- Served as a single `/fractal/assets/app-<hash>.css` with immutable cache
  headers. Dev: rebuilt per request (style edits hot-reload via the existing
  watcher + reload token — add `assets/` to watched dirs). Prod: cached in
  `:persistent_term`.

### 2. Static files: served, fingerprinted, reference-checked

Images/fonts are content, not code:

- Live in `assets/static/`, served via `Plug.Static` (do not hand-roll file
  serving) under `/assets/`, fingerprinted by a small manifest builder
  (~50 lines of our own is fine — it's not crypto).
- Pages reference them only through `asset_path/1`:

      tag(:img, src: asset_path("logo.png"), alt: "Fractal")

- **`asset_path/1` fails loudly on a missing file.** Verify already
  smoke-renders every page, so a typo'd filename becomes a red ✗ naming the
  page at `mix fractal.verify` time, not a 404 in production. Broken asset
  references become a mechanically-caught class of bug.
- Verify *warns* (not fails) on orphaned assets nothing references.

### 3. JavaScript: deliberately, there is no user JS pipeline

Interactivity is a framework primitive; AGENTS.md already bans `<script>`
tags. A JS bundling pipeline would be an engraved invitation to break that
invariant.

- The fx runtime and live-reload script stay framework-owned. Optionally move
  them from inline to a served, fingerprinted `/fractal/assets/fractal-<hash>.js`
  purely for caching — a nicety, not a principle.
- Future escape valve (NOT this task): named client **behaviors** shipped by
  the framework and attached declaratively (a curated vocabulary like `fx/2`,
  e.g. `behavior(:copy_to_clipboard)`). This design must not foreclose it,
  and it doesn't.

### Verification additions

- Balanced braces per `style/0` (cheap check, names the module).
- Rendered output containing a `<style>` tag fails — there is now a proper
  place for styles, so inline style blocks are a flagged bypass, like
  hand-rolled forms. (Inline `style=` *attributes* stay legal — dynamic
  values like progress widths are legitimate.)
- Missing `asset_path/1` references fail (via smoke-render).
- **No external origins in `script`/`link` tags** in rendered output —
  agents love pasting CDN lines; that's a supply-chain hole and a violation
  of "the framework owns the client." Instructive error message.

### Deliberate rejections (record the why)

- **npm/esbuild/webpack**: second ecosystem; breaks the pure-`mix` agent
  loop; network installs fail in sandboxed agent environments.
- **Sass/PostCSS**: solves problems LLMs don't have; native CSS suffices.
- **Tailwind** (for now): agents are fluent in it and it co-locates styling
  with markup — philosophically compatible — but it needs a standalone
  binary + watch step, and binary downloads are exactly what fails in agent
  sandboxes. Scoped plain CSS gets most of the value with zero toolchain.
  Revisit only if styling quality proves insufficient; the served-bundle
  path leaves room for it.

### Known tension (watch, don't over-engineer)

Page-scoped CSS fights *reuse* — twenty pages each styling their own buttons
is the failure mode. Mitigations: shared `app.css` design tokens; the
existing convention that shared helpers live in one place; possibly a future
verify *warning* for near-duplicate style blocks. Not solved in this task.

## Constraints

- Keep the 1-file per page structure (`style/0` lives in the page module).
- No Node, no external binaries, no new build step — `mix` only.
- Use `Plug.Static` for file serving; own only the manifest/fingerprinting.
- No user-authored JavaScript, and nothing that invites it.

## Files expected to change

New: `lib/fractal/assets.ex` (collector, manifest, `asset_path/1`),
`assets/app.css` (extracted from the layout), `assets/static/` (with a demo
image), `guides/assets.md`, `mix fractal.assets.digest` task (prod manifest;
dev works without it). Modified: `lib/fractal/page.ex` (`style/0` callback),
`lib/fractal/layout.ex` (`<link>` to the bundle, `data-page` wrapper, drop
inline CSS), `lib/fractal/router.ex` (serve `/fractal/assets/*` +
`Plug.Static`), `lib/fractal/reloader.ex` (watch `assets/`),
`lib/fractal/verify.ex` (brace check, `<style>` ban, external-origin ban,
missing-asset failures), `lib/mix/tasks/fractal.gen.page.ex` (optional
`--style` scaffold), guides touch-ups, `AGENTS.md`, tests throughout.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] I can launch the server and see pages styled from the shared
`assets/app.css` plus their own scoped `style/0` blocks; editing either
hot-reloads the browser.
- [ ] A page's styles cannot affect another page (scoping demonstrated).
- [ ] Images in `assets/static/` are served fingerprinted and referenced via
`asset_path/1`; a reference to a missing asset fails `mix fractal.verify`
naming the page.
- [ ] Rendered `<style>` tags and external CDN `script`/`link` references
fail verification with instructive messages.
- [ ] I can prompt an agent to style a page, and it does so via `style/0`
and `app.css` tokens without touching a build tool.
- [ ] I can run all the tests with `mix test` and they pass.
