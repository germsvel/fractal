# Fractal

An AI-first web framework written in Elixir. Humans build it, but they do
so purely with AI — so this file is the contract for how agents work here.

## Orientation

- A **page** is one module in `lib/fractal/pages/` using `Fractal.Page`.
  Routes are auto-discovered; there is no router file to edit. Dynamic
  segments (`/posts/:id`) bind `params["id"]`. (Paths and namespaces
  derive from the host app — in this repo the host is `fractal` itself;
  in a consuming app they'd be `lib/blog/pages/`, `Blog.Pages.*`.)
- **The framework owns the document, the app's layout contributes
  app-wide data and chrome, the page contributes content.** The layout
  module (`lib/fractal/layouts.ex`, `use Fractal.Layout`) supplies
  `site/0` (name, lang, favicon, theme color) and `chrome/1` (nav /
  session bar above `<main>`) — data and safe HTML in, framework
  renders. Per-page head data (description, og tags, canonical) is the
  page's `meta/1` callback — data only; descriptions must fit a search
  snippet. Never ask for an app-owned root template or `<head>` markup;
  there isn't one. See `guides/layout.md`.
- A page that renders a form also **handles the submission in the same
  file**: `use Fractal.Page, path: "/posts/new", post: "/posts"` plus
  `handle_post/1` — likewise `put:`/`handle_put/1` (updates; matches
  PUT and PATCH) and `delete:`/`handle_delete/1` (destroys) on the edit
  page. Keep it that way — do not add controllers.
- HTML is built with `Fractal.HTML.tag/3` — escaped by default, `raw/1`
  is the only escape hatch. Forms use `Fractal.Form`.
- **Interactivity needs no JavaScript**: declare `events:` on the page,
  wire elements with `trigger/3` or `fx/2`, handle them in
  `handle_event/2` returning `{:fragment, ...}`. State travels with the
  event (`values:`) or lives in the database — the server is stateless.
  See `guides/interactivity.md`. Never write `<script>` tags.
- **Sessions are encrypted cookies**: read `assigns.session`
  (string-keyed, like params); write via result directives —
  `{:redirect, to, session: %{...}}`, `clear_session: true`,
  `flash: %{"info" => "..."}` — never by touching a conn. Identity-scale
  data only. See `guides/sessions.md`.
- **CSRF is automatic and invisible**: `Fractal.Form` and the fx runtime
  attach tokens; the router rejects requests without them. Never
  hand-write `<form>` tags or `fetch` calls — verify flags them.
- **Styling is page-scoped CSS in the page module**: implement
  `style/0` (plain CSS, auto-scoped — it cannot leak to other pages);
  shared design tokens live in `assets/app.css`. Static files go in
  `assets/static/`, referenced only via `asset_path/1` (missing files
  fail verify). Never render `<style>` tags, never reference CDNs, and
  there is no Node/bundler — don't add one. See `guides/assets.md`.
- **Shared markup is a component**: one render-only module in
  `lib/fractal/components/` (render + scoped style + example), used via
  `component(Module, assigns)`. **Check the inventory first** —
  `/fractal/components` in dev or the end of `mix fractal.ai.docs` —
  and prefer extending over near-duplicating. Single-page markup stays
  a private function in the page. See `guides/components.md`.
- **Cross-cutting behavior is the checkpoint, not middleware**: pages
  declare `require: :signed_in` (visible in the page file); the guard
  names are defined once in the checkpoint module
  (`lib/fractal/checkpoints.ex`, `guard ... do`), which also derives
  `assigns.context` (e.g. the current user) and declares coverage
  contracts (`expect "/admin", :signed_in` — verify fails unguarded
  matches). Never put auth checks inside `render/1` or handlers, and
  never ask for a middleware/plug hook — there isn't one. See
  `guides/checkpoint.md`.
- **Tests drive pages through `Fractal.Test`** (`get`, `post`, `put`,
  `patch`, `delete`, `fire_event`, all with a `session:` opt).
- Data is **Ecto + PostgreSQL** (schemas, changesets, migrations). Do
  not hand-roll persistence.
- **App-wide rules are invariants**: defined once in
  `lib/fractal/invariants.ex` (`invariant "...", %{page: page} do`), run
  by verify against every page. Check the inventory at the end of
  `mix fractal.ai.docs` before writing a page. A page's own contract is
  its test file — verify fails any page or component no test references —
  and pages have no verification API of their own; never add one.
- `mix fractal.verify` is the feedback loop. A change is not done until
  it passes — it also fails on pending migrations.

## Agent workflow

When asked to create or change a page or feature:

1. **Read the docs first**: run `mix fractal.ai.docs` (or read
   `guides/*.md`). They define page anatomy, conventions, and testing
   expectations.
2. **Scaffold**: for a static page,
   `mix fractal.gen.page Name --path /route --title "Title"`. For a
   database-backed resource with a form,
   `mix fractal.gen.resource Name field:type ...` — it generates the
   schema, the migration, the pages, and their tests; then run
   `mix ecto.migrate`. Edit `render/1` for real content and keep the
   tests asserting on it.
3. **Verify**: run `mix fractal.verify`. Fix anything it reports and
   re-run until green.
4. In development, `mix fractal.server` auto-recompiles and reloads the
   browser — no restarts needed to see the change.

## Commands

| Command | Purpose |
| --- | --- |
| `mix fractal.server` | Start the dev server on port 4000 (live reload on) |
| `mix fractal.gen.page Name` | Scaffold a static page + test |
| `mix fractal.gen.page Name --events a,b` | Scaffold an interactive page + tests |
| `mix fractal.gen.page Name --style` | Scaffold a page with a scoped style/0 block |
| `mix fractal.gen.page Name --require guard` | Scaffold a guarded page |
| `mix fractal.gen.resource Name field:type ...` | Scaffold schema + migration + form pages + tests |
| `mix fractal.gen.component Name` | Scaffold a UI component + test (check /fractal/components first) |
| `mix ecto.setup` / `mix ecto.migrate` | Create the database / run pending migrations |
| `mix fractal.gen.secret` | Generate a session secret_key_base |
| `mix fractal.verify` | Compile (warnings-as-errors) + migration check + page checks + tests |
| `mix fractal.ai.docs` | Print the guides agents must read |
| `mix test` | Run the test suite directly (creates/migrates the test DB) |

## Conventions

- Elixir ~> 1.20. Format with `mix format` before finishing.
- Every module of framework code has test coverage under `test/`,
  mirroring the `lib/` layout.
- Keep pages self-contained; shared markup helpers belong in
  `Fractal.HTML` or a dedicated module, not copied between pages.
- Database tests use `Fractal.DataCase` (sandboxed, `async: true` safe).
- Postgres defaults to `postgres:postgres@localhost`; override with
  `PGUSER`/`PGPASSWORD`/`PGHOST`.

## Model routing (through July 7)

Default: Sonnet 5 for everyday work.

Use Fable 5 only for heavy, high-payoff tasks:
- large migrations (framework, language, dependency)
- codebase-wide refactors across many files
- complex multi-step builds
- hard bugs in tangled code (race conditions, subtle state)

Rule of thumb: weeks-by-hand → Fable 5, minutes-by-hand → Sonnet 5.
Protect the Fable 5 window. Don't spend it on small edits.

Note: some security-adjacent requests get rerouted to Opus 4.8
by the new safeguards. If quality drops on one call, check for a reroute.
