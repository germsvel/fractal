
# Task 4: extend page functionality to be interactive

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

Keep in mind the AI-first principle and what that means in the "Goal" statements
above. We might want to get creative here or use prior art. Not sure.

- For the fourth task, we want to be able to handle more interactivity on the
page. That could mean adding JavaScript somehow, but ideally, it's completely
abstracted from the user of the framework. Do some research on what you think is
a good path for AI-first web development -- for example, maybe we want to use
WebSockets but maybe not!

## Constraints

- Keep the 1-file per page structure

## Plan first

Before changing anything, map the full plan and list the files
you'll touch. Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] I can launch a web server with a `mix` task and see the new page with
interactivity
- [ ] I can prompt an agent to create a new interactive page, and it does so.
- [ ] I can run all the tests with `mix test` and they pass. Tests verify
interactivity too!
