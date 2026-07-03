defmodule Fractal do
  @moduledoc """
  Fractal is an AI-first web framework for Elixir.

  AI-first means the framework is designed around four ideas:

    * **AI-consumable primitives** — a page is one small module
      (`Fractal.Page`) that declares its route and renders its content.
      Pages are auto-discovered; creating a page never requires editing
      a router or any other file.

    * **AI-driven workflow** — developers primarily prompt an agent to
      build features. `mix fractal.gen.page` scaffolds pages, and the
      project's `AGENTS.md` tells agents exactly how to work here.

    * **Built-in verification** — `mix fractal.verify` (backed by
      `Fractal.Verify`) checks that every page compiles, routes don't
      collide, and every page renders, then runs the test suite. It is
      the feedback loop that keeps AI-generated code correct.

    * **Built-in documentation for AI** — `mix fractal.ai.docs` prints
      the guides an agent should read before writing code.

  Start the server with `mix fractal.server` and visit
  [http://localhost:4000](http://localhost:4000). In development, code
  changes recompile automatically and open browser tabs reload themselves.
  """
end
