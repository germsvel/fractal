# Task: build Fractal Elixir app

## Goal

Fractal is a new web framework written in Elixir that is AI-first.

In practice that means at least the following:

- It provides primitives for building web-pages in a way that AI agents can
easily consume and extend (e.g. think of Pi the code harness and how it's easily
customizable by prompting the agent)

- It focuses on the developer experience using AI to build the web application.
Developers can dive in and write code, but the fundamental pattern is to prompt
the AI.

- It has built-in verification checks to ensure that the code AI produces is
correct.

- It has built-in documentation that the AI uses when a developer prompts it to
  create a new page or feature.

## Scope

- Out of scope: We probably want to use Ecto for database access. Do not
reimplement that portion of the stack.

## Constraints

- Use Elixir 1.20
- Code must have test coverage

## Plan first

Before changing anything, map the full plan and list the files
you'll touch. Wait for my go-ahead, then execute in one pass.

## Definition of done
- [ ] I can launch a web server with a `mix` task and see a web page rendered
- [ ] I can prompt an agent to create a new page, and it does so. In
development, the page auto-reloads and I see the changes.
- [ ] I can run all the testes with `mix test` and they pass
