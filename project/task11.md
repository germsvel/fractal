# Task 11: per-page head data — meta/1

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

Depends on task 10 (the Document/Layout ownership model: the framework owns
the document, the app's layout contributes app-wide data and chrome, the
page contributes content — and, with this task, its own head data).

## Framing: representation, not markup ownership

Pages need to appear correctly in search results and link previews —
descriptions, og tags, canonical URLs. That data is *page content in
disguise* (an og:description for a post page derives from the post), so
one-file-per-page puts it in the page module. But apps never get `<head>`
markup ownership: the head carries security machinery that must stay
framework-owned and upgradable. Pages **contribute data through a declared
channel; the framework renders and escapes it** — the same shape as every
other Fractal affordance.

## Scope

### The `meta/1` callback

An optional page callback, computed from assigns like `render/1`:

```elixir
@impl Fractal.Page
def meta(assigns) do
  %{
    description: excerpt(assigns.post),
    og: %{title: assigns.post.title, image: asset_path("cover.png")},
    canonical: "/posts/#{assigns.post.id}"
  }
end
```

- **Known keys** cover the common 95%: `description`, `canonical`,
  `robots`, and an `og` map (title/description/image/url/type; rendered
  as both og and twitter-equivalent tags where they coincide). The
  framework composes and renders them into the head, escaped, after the
  app-wide data from the Layout (page values win where they overlap, e.g.
  a page's og:image over the app default).
- **A bounded generic tail** for the long tail without markup: entries
  like `{:meta, attrs}` and `{:link, attrs}` (RSS discovery, site
  verification tags). Data, not strings of HTML — every attribute goes
  through the escaper, and verification scans the entries.
- Like `render/1`, `meta/1` must tolerate empty assigns (verification
  smoke-runs it); a page without the callback contributes nothing.
- No `meta:` option on `use Fractal.Page` for static cases — one way to
  do it (the callback); a static map is a one-line callback.

### Verification

- `meta/1` smoke-runs with empty assigns and must return the documented
  shape; crashing or misshapen results fail, naming the page.
- Asset references inside meta (og:image via `asset_path/1`) already fail
  loudly on missing files — the smoke-run surfaces them.
- **Script-shaped smuggling is rejected**: generic entries cannot express
  script tags or event-handler attributes; verification enforces the
  allowlist of renderable tags (`meta`, `link`) and rejects
  resource-loading `link` rels pointing at external origins (see below).
- **Refine the external-origin scan**: today it flags any
  `<link href="https://...">`, but `rel=canonical`/`rel=alternate` hrefs
  are content URLs, not resource loads. The rule becomes: external
  origins are forbidden for *resource-loading* tags (`script`,
  `link rel=stylesheet/preload/modulepreload/icon`), allowed for
  reference rels (`canonical`, `alternate`, `me`, ...). Applies to both
  the render scan and meta rendering.
- **A starter invariant ships**: `description` (when present) fits a
  search snippet (~160 chars) — the house-rule mechanism doing SEO work,
  surfaced in `mix fractal.ai.docs` like the title rule.

### Docs and generators

- `guides/building_pages.md` gains a head-data section (or the
  Document/Layout guide from task 10 does); AGENTS.md orientation bullet.
- No generator flag (`--meta`) — the callback is three lines; scaffold
  templates mention it in a comment only if it doesn't add noise.

### Deliberate rejections (record the why)

- **No raw head markup from pages or apps** — data through the declared
  channel only; the head's security machinery stays framework-owned.
- **No script or style entries in the generic tail** — the no-user-JS and
  no-`<style>` stances don't get a side door through meta.
- **No per-page `<html lang>`** for now — app-wide from the Layout
  (task 10); revisit if i18n becomes a real story.

## Constraints

- Keep the 1-file per page structure: a page's head data lives in the
  page module, computed from the same assigns as `render/1`.
- Everything renders through the existing escaping machinery; verify
  covers the new surface with the same fail-closed posture.

## Files expected to change

`lib/fractal/page.ex` (callback + docs), `lib/fractal/document.ex`
(render head data, compose with Layout app-wide data),
`lib/fractal/verify.ex` (meta smoke-run + shape checks + refined
external-origin rule), `lib/fractal/invariants.ex` (description-length
starter), guides + `AGENTS.md`, sample pages (give the post show page a
real `meta/1` as the demo), tests throughout.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] A page with `meta/1` renders its description, og tags, and
canonical link in the head, escaped, with page values overriding the
Layout's app-wide defaults — demonstrated on the post show page over real
HTTP.
- [ ] A misshapen or crashing `meta/1`, a missing og:image asset, and a
script-shaped generic entry each fail `mix fractal.verify` naming the
page.
- [ ] `rel=canonical` external URLs pass the external-origin rule;
external stylesheets/scripts still fail it.
- [ ] The description-length invariant appears in `mix fractal.ai.docs`
and fails a page with an over-long description.
- [ ] I can run all the tests with `mix test` and they pass.
