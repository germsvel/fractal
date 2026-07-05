# Fractal

Fractal is an AI-first web framework written in Elixir.

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

## Quickstart

```sh
cd installer && mix fractal.new blog && cd ../blog
mix deps.get && mix ecto.setup   # Postgres on localhost
mix fractal.server               # http://localhost:4000
```

The generated app is born green — `mix fractal.verify` passes from the
first minute — and prompt-ready: open your AI agent in the new directory
and ask it for a page. Its `README.md` quickstart is a list of prompts.

## Repository layout

| Path | What |
| --- | --- |
| `lib/`, `test/` | The framework and its tests (DB-less; fixtures in `test/support`) |
| `priv/guides/` | The guides `mix fractal.ai.docs` prints in every app |
| `installer/` | The `mix fractal.new` project and its app templates |
| `examples/blog/` | The showcase app — posts, login, admin, search — on a path dep |

`AGENTS.md` is the contract for working on the framework itself; the
installer generates an app-facing one into every new app.
