# Task 10: make the framework host-agnostic

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

## Framing: the framework has exactly one user, and that hides bugs

The sample app is currently both the framework's test fixture and the proof
that the framework works — so "the framework works" means "it works for the
one app that grew up with it." Every hard-coded assumption is invisible
because the only consumer satisfies it by construction. This task applies
the verification pillar to the framework itself: make it correct for *any*
host app, with the in-tree sample app kept green throughout as the canary.

This is step one. Task 12 (the `fractal.new` installer) depends on
this; the sample app does NOT move in this task.

## Scope

### De-hardcode the host app

The framework currently assumes its host is the `:fractal` app. Enumerated
couplings and their resolutions:

- **Discovery** (`Fractal.Discovery`) scans `:code.lib_dir(:fractal)`.
  → Scan the host app: default to `Mix.Project.config()[:app]` (the
  framework runs inside the host's mix context), overridable with
  `config :fractal, otp_app: :blog`.
- **Namespace and paths**: generators write `lib/fractal/pages/`, coverage
  checks look under `test/fractal/...`, scaffolds emit `Fractal.Pages.*`.
  → Derive from the host: base module defaults to
  `Macro.camelize("#{otp_app}")` (overridable with
  `config :fractal, namespace: MyApp`), paths become
  `lib/<otp_app>/pages/`, `test/<otp_app>/pages/`, etc. All four
  generators, `Verify.test_coverage/1`, and the guides' path references
  update together.
- **The Repo**: `Fractal.Repo` is named directly by `Fractal.DataCase`,
  `Verify.pending_migrations/0`, and config.
  → The framework finds the host's repo through the host's `:ecto_repos`
  config (first entry). `Fractal.Repo` itself remains only as this repo's
  host-app repo, not a framework module contract.
- **Supervision ownership**: `Fractal.Application` currently starts the
  Repo. → The framework's application starts only framework services
  (`Fractal.LiveReload`); the host app's own Application supervises its
  repo. (In this repo, the host and framework are still the same app —
  keep one application module doing both until task 12 splits them.)
- **Framework config stays under `:fractal`** — `secret_key_base`,
  `response_headers`, `live_reload`, `otp_app`, `namespace` — these
  already generalize.
- **Expectations that already hold** (no change needed, just precise
  language): `assets/app.css` is *enforced* by `Verify.stylesheet/0`, and
  `assets/static/` references are enforced per-use (`asset_path/1` raises,
  verify catches). The `_fractal_flash` session key is a framework
  implementation detail — apps only ever touch the `flash:` directive and
  `assigns.flash`; nothing to document or configure. `guides/` location
  moves into the package in task 12.

### Document and Layout: who owns the envelope

The session bar in today's framework layout is a task-5 leftover, not a
convention: framework code hard-codes two app-level decisions — that the
display name lives at `session["user_name"]` and that a `DELETE /logout`
route exists. It exposes a bigger gap: once Fractal is a dependency, apps
have **no way to influence the page chrome or the document head at all** —
no nav bar, no favicon, no meta description; even `<html lang="en">` is
hard-coded. The sample app only coped because the layout was in-tree.

Consumers don't need markup ownership; they need **representation**. The
resolution keeps the house rule — contribute data, never markup — and
gives the ownership model its sentence: **the framework owns the
document, the app's layout contributes app-wide data and chrome, the
page contributes content** (and, in task 11, its own head data).

- **`Fractal.Layout` (framework) is renamed `Fractal.Document`** — the
  HTML document envelope and its machinery: doctype/head/body, charset
  and viewport, the CSRF meta tag, the fingerprinted bundle link, the
  `data-page` scoping attribute, flash rendering, the interactivity and
  live-reload scripts, and the framework pages (404/500/gallery). These
  are security- and correctness-bearing and must be upgradable without
  app cooperation — apps never copy or edit this (the Phoenix
  root-layout approach is deliberately rejected: app copies drift, and
  agents editing raw head boilerplate is the error-prone freedom Fractal
  removes everywhere else).
- **`Layout` becomes the app's module** — one optional module, discovered
  like the checkpoint (at most one, behaviour `Fractal.Layout`), owning
  the app's presentation frame in two halves, both as data/safe HTML:
  - **chrome**: a render function receiving the usual assigns (session,
    context, path), returning safe HTML the document places above
    `<main>`; optional scoped `style/0`; verified with the same scans as
    pages (empty-assigns render, no `<style>`, no CDNs, CSRF in forms).
  - **app-wide document data**: language (killing the hard-coded `"en"`),
    site name (the document composes `<title>Page — Site</title>`),
    favicon (via `asset_path/1` — missing files fail verify), and
    theme-color. Data in, framework renders and escapes.
- The framework document **loses the session bar entirely**; the sample
  app's Layout reimplements it from `session["user_name"]` and its own
  `/logout` route — both now genuinely app-owned.
- Per-page head data (`meta/1` — descriptions, og tags, canonical) is
  task 11; this task only establishes the Document/Layout contract.

### Framework tests stand on their own fixtures

Framework tests currently lean on sample pages (router tests exercise
`/posts`, verify tests smoke the discovered app, etc.). Move them onto
dedicated fixtures in `test/support/fixtures/` (compiled in the test env,
hence discoverable): a minimal page set covering each capability — static,
dynamic segment, each action, events, style, a component, a checkpoint, an
invariants module conflict case where needed. Sample pages remain in-tree
and discovered (tests that enumerate "all discovered pages" cover both);
assertions stop *depending* on sample content.

### Non-goals

- No installer, no template files, no moving the sample app — task 12.
- No release support: the framework remains mix-run (dev-first); revisit
  when a deploy story becomes a task.
- No new configuration beyond `otp_app`/`namespace` — resist turning
  conventions into options while generalizing.

## Constraints

- The sample app stays exactly where it is and stays green after every
  change — it is the canary for the de-hardcoding pass.
- Defaults must make the framework repo itself need zero new config
  (self-hosting continues to work unconfigured).
- `grep -r ":fractal" lib/fractal` at the end should show only the
  framework's own config namespace reads, with host-app references gone
  (or defaulted through the otp_app lookup).

## Files expected to change

`lib/fractal/discovery.ex` (host-app lookup), `lib/fractal/verify.ex`
(paths, repo lookup), `lib/fractal/test.ex` + `test/support/data_case.ex`
(repo lookup), `lib/fractal/application.ex`, all four
`lib/mix/tasks/fractal.gen.*.ex` (derived namespace/paths),
`lib/mix/tasks/fractal.{verify,ai.docs,server}.ex` as needed,
`lib/fractal/assets.ex`/`router.ex` if any host assumptions surface,
`lib/fractal/layout.ex` renamed to `lib/fractal/document.ex` (session
bar removed; layout slot + app-wide head data), new `Fractal.Layout`
behaviour + the sample app's `lib/fractal/layouts.ex`-style
implementation (naming per the checkpoint precedent), new
`test/support/fixtures/` modules, updates across `test/`, guides
touch-ups where paths are named (sessions guide's signed-in-bar section
moves to the layout story; a new or extended guide for the
Document/Layout ownership model), `AGENTS.md` conventions section.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] A scratch project with a different app name (e.g. `probe`, module
`Probe`) can depend on the framework via a path dep: its `Probe.Pages.*`
pages are discovered and served, generators write to `lib/probe/pages/` and
`test/probe/pages/` with `Probe.*` modules, and `mix fractal.verify` passes
inside it — demonstrated end to end.
- [ ] The framework's own test suite passes using its fixtures; deleting a
sample page's content assertion from framework tests is a no-op (no
framework test depends on sample-app content).
- [ ] The in-tree sample app still works: server boots, all pages serve,
`mix fractal.verify` green — with zero new config in this repo.
- [ ] No hard-coded host-app references remain (grep check per
constraints), and `Fractal.Document` contains no app-level session keys,
routes, or locale — the sample app's session bar comes from its own
Layout module and still works end to end (sign in, bar on every page,
log out), and its Layout sets the site name, language, and favicon
(visible in the rendered head).
- [ ] I can run all the tests with `mix test` and they pass.
