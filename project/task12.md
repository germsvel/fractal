# Task 12: mix fractal.new — born green, prompt-ready

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

Depends on task 10 (host-agnostic framework, the Document/Layout
ownership model) and task 11 (per-page head data) — so the guides and
showcase app the installer ships are complete.

## Framing: two contracts make the installer Fractal-shaped

1. **Born green.** `mix fractal.new blog && cd blog && mix ecto.setup &&
   mix fractal.verify` passes, out of the box, always — the feedback loop
   works from minute zero. This is CI-tested: an integration test generates
   a fresh app from the real templates and runs its full verify inside it.
   That closes the classic scaffold failure mode (template rot) with our
   own machinery — the first-run experience is itself under verification,
   and it doubles as the framework's honest end-to-end test against a
   consumer that isn't the dogfood app.
2. **The most important generated file is AGENTS.md.** If the fundamental
   pattern is prompting the AI, a new Fractal app is chiefly a
   *prompt-ready workspace*. The generated README's quickstart is a list of
   prompts ("Ask your agent: *create a page at /pricing*"), not a code
   tutorial.

## Scope

### Repo layout (Phoenix's proven shape)

- Framework library stays at the repo root.
- `installer/` — its own small mix project publishing the `fractal.new`
  task (archive-installable), with the app templates.
- `examples/blog/` — the current sample app (posts CRUD, login, admin,
  search, its checkpoint/invariants, migrations, and all its tests) moves
  here as a standalone project with `{:fractal, path: "../.."}`. It keeps
  its job as dogfood and living documentation; it stops shipping inside
  the framework package.

### What `mix fractal.new blog` generates

The smallest app that teaches the vocabulary and verifies green:

- **Pages**: Home (the welcome page — logo, registered-pages list,
  commands, "prompt your agent" as the visible next step) and Counter
  (the events model proven in ~40 lines, deletable as one file). Both
  with tests.
- **The one-well-known-place modules, present from birth** so agents
  extend them instead of creating rivals: a minimal checkpoint (empty
  `context/1`, no guards yet), the invariants module with one real
  starter rule (title fits in a search result), and the EmptyState
  component (the gallery is never empty; `gen.resource` templates depend
  on it). All with tests.
- **Plumbing**: `mix.exs` (fractal dep), config for dev/test/prod with a
  freshly generated `secret_key_base` per app, the app's own Application
  supervising its Repo, `Blog.Repo`, DataCase, test_helper, `.formatter.exs`,
  `.gitignore`, `assets/app.css` (tokens) + `assets/static/logo.svg`.
- **Docs**: generated `AGENTS.md` (the app-facing contract — today's file
  minus framework-contributor concerns) and a README whose quickstart is
  prompts. Guides move into the framework package (`priv/guides`);
  `mix fractal.ai.docs` reads them from the dep — doc improvements reach
  every app on upgrade — and appends the app's live inventories
  (components, guards, invariants) as today.
- **Deliberately absent**: posts CRUD, login, admin, search, and an app
  Layout module (task 10's app-owned Layout is opt-in; a fresh app has no
  nav or app-wide head data yet — the guides and the showcase app
  demonstrate it). Demos of our
  framework, not the user's domain — the first real prompt should create
  their actual resource via `gen.resource`, not delete a fake blog. A
  fresh scaffold has no migrations, so `ecto.setup` just creates the
  empty database. Sessions/guards remain guide material and showcase-app
  features.
- **Zero flags.** No `--database`, no `--no-ecto` (Postgres is a stated
  constraint). Options that exist get pasted wrong; add flags when a real
  second need exists.

### AGENTS.md split

The framework repo's `AGENTS.md` becomes contributor-facing ("how to build
Fractal": conventions for framework code, fixtures, the examples app,
model-routing section preserved). The installer's template is the
app-facing contract ("how to build with Fractal") — reviewed so nothing
assumes this repo's layout.

### The born-green integration test

A test (framework CI) that:

1. runs the installer's generator into a tmp dir (path-dep override
   pointing at the local framework checkout),
2. runs `mix deps.get`, `mix ecto.setup`, `mix fractal.verify`, and
   `mix test` inside the generated app,
3. fails loudly with the generated app's output if anything is red.

Template rot becomes impossible to ship.

### Non-goals

- No hex publication mechanics (package metadata beyond what the split
  requires) — separate chore when the time comes.
- No umbrella. No release/deploy story yet.
- No installer flags, no alternative databases, no template variants.

## Constraints

- Everything the generated app contains must satisfy the framework's own
  contracts: coverage (every page/component referenced by tests),
  invariants, verify fully green — enforced by the integration test.
- The examples app keeps working identically after the move (path dep,
  its own config/secrets), and its tests run in CI alongside the
  framework's.
- Generated apps never reference `Fractal.Pages.*` or `lib/fractal/`
  paths — task 10's derivation is the only naming source.

## Files expected to change

New: `installer/` (mix project: `fractal.new` task + templates for every
generated file), `priv/guides/` (guides relocated into the package),
integration test (e.g. `test/integration/new_app_test.exs` or a CI
script), `examples/blog/` (the relocated sample). Modified:
`lib/mix/tasks/fractal.ai.docs.ex` (read guides from the package with a
local override), root `AGENTS.md` (contributor-facing rewrite), root
`mix.exs`/`.formatter.exs`/CI config for the new layout, the framework's
`test/support` fixtures absorb anything framework tests still needed from
the sample.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] `mix fractal.new blog` generates an app where
`mix ecto.setup && mix fractal.verify && mix test` is green with no manual
edits, and `mix fractal.server` shows the Home and Counter pages —
demonstrated end to end.
- [ ] The generated AGENTS.md and README read as the app's contract
(prompt-first quickstart); `mix fractal.ai.docs` in the generated app
prints the framework guides plus the app's own inventories.
- [ ] The sample app lives in `examples/blog`, runs on the path dep, and
its full suite + verify are green.
- [ ] The born-green integration test exists and fails when a template is
broken (demonstrated by breaking one temporarily).
- [ ] The framework's own `mix test` passes, using only its fixtures.
