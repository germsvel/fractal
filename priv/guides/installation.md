# Installation

The fast path is the installer — a new app is born green:

```
mix fractal.new blog
cd blog && mix ecto.setup && mix fractal.verify
mix fractal.server
```

The rest of this guide is the manual path: adding Fractal to an
existing project. It also documents exactly what the installer
generates, tier by tier.

## Tier 1: pages only

1. **The dependency** (path or git until Fractal is on Hex):

   ```elixir
   defp deps do
     [{:fractal, git: "https://github.com/germsvel/fractal.git"}]
   end
   ```

2. **The session secret** in `config/config.exs` (create the config
   dir if your project doesn't have one):

   ```elixir
   import Config

   config :fractal, secret_key_base: "..."   # mix fractal.gen.secret
   ```

3. **The asset expectations** — verify enforces both:

   ```
   mkdir -p assets/static
   # assets/app.css with your design tokens (--accent, --muted, --surface, ...)
   ```

4. **A first page** — paths and namespaces derive from your app
   automatically (`lib/my_app/pages/`, `MyApp.Pages.*`):

   ```
   mix deps.get && mix fractal.gen.page Home --path /
   mix fractal.server
   ```

Everything else is automatic: the `:fractal` application starts its own
services, pages are discovered by behaviour, sessions and CSRF work off
the configured secret, and `mix fractal.verify` runs green — a repo-less
app has nothing to migrate, and the checkpoint, layout, and invariants
modules are all optional until you create them.

## Tier 2: the database

Ecto and Postgrex arrive transitively; the app owns its repo:

1. `lib/my_app/repo.ex`:

   ```elixir
   defmodule MyApp.Repo do
     use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
   end
   ```

2. **Supervise it yourself** in your application module — the framework
   deliberately does not start host repos.

3. Config: `config :my_app, ecto_repos: [MyApp.Repo]`, per-env database
   config (the test env uses `pool: Ecto.Adapters.SQL.Sandbox`), the
   test alias `test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]`,
   and `Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)` in
   `test_helper.exs`.

4. **Two prerequisites `mix fractal.gen.resource` assumes exist**:

   - `MyApp.DataCase` (`test/support/data_case.ex`, with
     `elixirc_paths: ["lib", "test/support"]` for the test env in
     `mix.exs`) — the sandboxed test case its generated tests use.
   - `MyApp.Components.EmptyState` — the component its show/edit pages
     render for missing records (`mix fractal.gen.component EmptyState`,
     then give it `:title`, `:back_href`, `:back_label` assigns).

   The installer generates both; by hand, add them before your first
   resource.

## Tier 3: the one-well-known-place modules (all optional)

Create these when the need arises; each is discovered the moment it
compiles, at most one of each:

- `MyApp.Checkpoints` (`use Fractal.Checkpoint`) — guards, request
  context, and coverage expectations. See the checkpoint guide.
- `MyApp.Layouts` (`use Fractal.Layout`) — app-wide document data
  (site name, language, favicon, default description) and chrome.
  See the layout guide.
- `MyApp.Invariants` (`use Fractal.Invariant`) — house rules verify
  enforces on every page. See the verification guide.

## Requirements

Elixir ~> 1.20, PostgreSQL for the database tier. Secrets: committed
values for dev/test are fine; production reads `SECRET_KEY_BASE` (and
`DATABASE_URL`) from the environment.
