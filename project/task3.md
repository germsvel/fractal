# [x] Task 3: extend page functionality to all CRUD actions

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

- For the third task, we want to handle more form submissions:
  - put/patch for update
  - delete for destroy


## Constraints

- Keep 1-file per page structure, including the form requests.
  - If the "edit" post page shows a delete button, the destroy action
  corresponding to `DELETE /posts/:id` should likely be in that same page. If you
  disagree, stop and consult me.
  - Same is true about updates to a resource

## Plan first

Before changing anything, map the full plan and list the files
you'll touch. Wait for my go-ahead, then execute in one pass.

## Definition of done

- [x] I can launch a web server with a `mix` task and see the new page with a
form that creates a new resource and then takes me to that new resource's page.
- [x] I can prompt an agent to update an existing page with a form, and it does so. It
  also creates the migration to change the database (if needed).
- [x] I can run all the tests with `mix test` and they pass
