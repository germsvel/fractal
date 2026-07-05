# Blog — the Fractal showcase app

The framework's dogfood and living documentation: posts CRUD, login and
sessions, a guarded admin area, search, an app layout, checkpoint,
invariants, and a component — every Fractal feature in use, with tests.

It runs against the framework at the repo root via
`{:fractal, path: "../.."}`:

```sh
mix deps.get
mix ecto.setup      # Postgres on localhost (PGUSER/PGPASSWORD/PGHOST to override)
mix fractal.server  # http://localhost:4000
mix fractal.verify  # the full feedback loop
```

For a fresh app of your own, use the installer instead:
`cd ../../installer && mix fractal.new my_app`.
