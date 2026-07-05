# Fractal — contributor contract

This repo is the Fractal framework itself, built purely with AI — so this
file is the contract for agents working **on** the framework. Agents
working **in** a Fractal app get their own `AGENTS.md` from
`mix fractal.new` (template: `installer/templates/AGENTS.md.eex`).

## Repository layout

| Path | What |
| --- | --- |
| `lib/fractal/` | The framework: page/router/document/verify/checkpoint/invariant/layout/component/assets/bus/test |
| `lib/mix/tasks/` | `fractal.server`, `fractal.verify`, `fractal.ai.docs`, the `fractal.gen.*` generators |
| `priv/guides/` | The guides `mix fractal.ai.docs` ships into every app — update them with behavior changes |
| `test/` | Framework tests, mirroring `lib/`; DB-less and Postgres-free |
| `test/support/fixtures.ex` | The fixture app: pages, a checkpoint, invariants, a layout, a component |
| `test/integration/new_app_test.exs` | The born-green test (tagged `:integration`, excluded by default) |
| `installer/` | Its own mix project: the `fractal.new` task + templates for every generated file |
| `examples/blog/` | The showcase app (posts CRUD, login, admin, search) on `{:fractal, path: "../.."}` |
| `project/` | The numbered design/task documents driving development |

## The philosophy (what changes must preserve)

Fractal is AI-first: primitives agents can consume and extend, prompt-first
developer experience, built-in verification, built-in documentation.
Derived principles that shape every API decision:

- **One file per page** — route, render, handlers, style together; no
  routers, controllers, or templates to coordinate.
- **Stateless server** — state travels with the request (session cookie,
  event `values:`) or lives in the database.
- **Named primitives over general mechanisms** — checkpoint, not
  middleware; invariants, not hooks; `meta/1`, not a head template.
- **Declared where it applies, defined in one well-known place,
  guaranteed by verify** — `require: :guard` on the page, the guard in
  the checkpoint module, `expect`/coverage enforced by
  `mix fractal.verify`.
- **The framework owns the document, the app's layout contributes data
  and chrome, the page contributes content** — apps contribute data,
  never envelope markup.
- **Don't reimplement battle-tested plumbing** — Ecto, Plug, and Bandit
  underneath; Fractal owns the shape, not the transport.
- **Zero-API where the framework owns both ends** — CSRF, asset
  fingerprinting, live reload just happen.

When adding a feature, write the guide alongside it — `priv/guides/` is
part of the product, and `mix fractal.ai.docs` is how apps' agents learn
the feature exists.

## Working on the framework

- Framework tests must not need a database or the sample app. They run
  against `test/support/fixtures.ex` — a tiny host app (pages under
  `/fixtures`, `Fractal.Fixtures.Checkpoint`, `.Invariants`, `.Layout`,
  `.Note`, and the watch fixtures). The checkpoint/invariants/layout fixtures are the *only*
  discovered instances — those modules are one-per-app, so don't add
  rivals; extend the existing fixtures.
- `mix test` runs the suite (integration excluded);
  `mix test --only integration` generates a real app from the installer
  templates and runs its full verify — run it after touching the
  installer, the generators, or anything the templates rely on. It needs
  Postgres (`postgres:postgres@localhost`, override with
  `PGUSER`/`PGPASSWORD`/`PGHOST`).
- The showcase app is the dogfood: after framework changes, run
  `mix test && mix fractal.verify` inside `examples/blog/` too.
- Namespaces derive from the host app (`Fractal.Discovery`) — never
  hardcode an app name in framework code, generators, or templates.
  Doc examples use `MyApp.*`.
- Installer templates live in `installer/templates/` (`.eex`, embedded
  at compile time; `app_name` path segments and `dot_` prefixes are
  rewritten). Anything they generate must keep the born-green contract:
  generate → `mix ecto.setup` → `mix fractal.verify` green, no manual
  edits. No installer flags.
- Elixir ~> 1.20. Format with `mix format` before finishing. Every
  framework module has tests under `test/`, mirroring `lib/`.
- Deps are git-pinned in `mix.exs` (see the comment there) — keep new
  deps to effectively zero.

## Commands (framework repo)

| Command | Purpose |
| --- | --- |
| `mix test` | Framework suite (DB-less, integration excluded) |
| `mix test --only integration` | The born-green installer test (needs Postgres) |
| `mix fractal.server` | Serve the fixture-less framework root (mostly useful in `examples/blog/`) |
| `mix format` | Format before finishing |
| `cd examples/blog && mix fractal.verify` | Dogfood the framework end to end |
| `cd installer && mix fractal.new path/to/app` | Generate an app by hand (`FRACTAL_PATH=$PWD/..` for the local checkout) |

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
