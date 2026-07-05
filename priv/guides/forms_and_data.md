# Forms and data

Fractal uses **Ecto with PostgreSQL** for data. Schemas, changesets,
queries, and migrations are plain Ecto — do not hand-roll persistence.
What Fractal adds is the wiring: form submissions are handled **in the
same page module that renders the form**, and a resource generator emits
the whole stack at once.

## The fast path: the resource generator

```
mix fractal.gen.resource Post title:string body:text
```

generates the schema + changeset, the **migration**, four pages
(index, new-with-form, show, edit-with-delete-button), and their tests.
Field types: `string`, `text` (textarea), `integer`, `float`, `boolean`
(checkbox), `date`. Then:

```
mix ecto.migrate
mix fractal.verify
```

`mix fractal.verify` fails if a migration is pending, so forgetting
`ecto.migrate` is caught, not discovered in the browser.

## Form pages: render and handle in one file

A page declares its form's POST route with the `:post` option and
handles it with `handle_post/1` — same module, one file:

```elixir
defmodule MyApp.Pages.NewPost do
  use Fractal.Page, path: "/posts/new", title: "New post", post: "/posts"

  import Fractal.Form

  alias MyApp.Repo

  @impl Fractal.Page
  def render(assigns) do
    changeset = assigns[:changeset] || MyApp.Post.changeset(%MyApp.Post{}, %{})

    tag(:section, [], [
      tag(:h1, [], ["New post"]),
      form_for(changeset, "/posts", [
        input(changeset, :title),
        textarea(changeset, :body, rows: 6),
        submit("Create post")
      ])
    ])
  end

  @impl Fractal.Page
  def handle_post(assigns) do
    case Repo.insert(MyApp.Post.changeset(%MyApp.Post{}, assigns.params)) do
      {:ok, post} -> {:redirect, "/posts/#{post.id}"}
      {:error, changeset} -> {:render, %{changeset: changeset}}
    end
  end
end
```

The contract:

- `handle_post/1` gets the same assigns shape as `render/1`;
  `assigns.params` merges path, query, and form body params
  (string-keyed).
- Return `{:redirect, to}` → 303 redirect (the create-then-show flow).
- Return `{:render, extra_assigns}` → this page's `render/1` runs again
  with the extras merged in. Pass the failed changeset back this way and
  the form re-renders with the attempted values and inline errors.
- Declaring `post:` without `handle_post/1` (or vice versa) fails at
  compile time.

## Updating and deleting

Updates and deletes follow the exact same shape: the edit page declares
`put:` and `delete:` routes and handles both in the same file:

```elixir
defmodule MyApp.Pages.EditPost do
  use Fractal.Page,
    path: "/posts/:id/edit",
    title: "Edit post",
    put: "/posts/:id",        # matches PUT and PATCH
    delete: "/posts/:id"

  import Fractal.Form

  alias MyApp.Repo

  @impl Fractal.Page
  def render(assigns) do
    post = Repo.get(MyApp.Post, assigns.params["id"])
    changeset = assigns[:changeset] || MyApp.Post.changeset(post, %{})

    tag(:section, [], [
      form_for(changeset, "/posts/#{post.id}", [method: :put], [
        input(changeset, :title),
        submit("Save post")
      ]),
      button_to("Delete post", "/posts/#{post.id}", method: :delete)
    ])
  end

  @impl Fractal.Page
  def handle_put(assigns) do
    post = Repo.get(MyApp.Post, assigns.params["id"])

    case Repo.update(MyApp.Post.changeset(post, assigns.params)) do
      {:ok, post} -> {:redirect, "/posts/#{post.id}"}
      {:error, changeset} -> {:render, %{changeset: changeset}}
    end
  end

  @impl Fractal.Page
  def handle_delete(assigns) do
    assigns.params["id"] |> then(&Repo.get(MyApp.Post, &1)) |> Repo.delete!()
    {:redirect, "/posts"}
  end
end
```

Handlers must guard against a missing record (redirect away is fine —
the generated pages show the pattern). The same
`{:redirect, to}` / `{:render, extras}` contract and compile-time
pairing checks apply to `put:`/`handle_put/1` and
`delete:`/`handle_delete/1`.

Browsers only submit GET/POST forms, so `form_for(..., method: :put)`
and `button_to(..., method: :delete)` emit a hidden `_method` field
that the router rewrites before dispatch. Native PUT/PATCH/DELETE
requests (API clients, tests) dispatch directly.

## Form helpers (`Fractal.Form`)

`form_for/3,4` (with `method: :post | :put | :delete`), `input/3`,
`textarea/3`, `checkbox/3`, `submit/2`, `button_to/3`, `errors_for/2`.
All output goes through `Fractal.HTML`, so values are escaped. Field names are flat (`name="title"`) — exactly what
`Ecto.Changeset.cast/4` expects from `assigns.params`. Errors render
only after a failed `Repo.insert` (when the changeset has an `:action`).

Every form automatically carries a CSRF token, which is why forms must
be built with these helpers — never hand-write a `<form>` tag (see
`guides/sessions.md`).

## Dynamic routes

Route segments starting with `:` bind parameters:
`path: "/posts/:id"` puts `params["id"]` in the assigns (always a
string — parse it). Static routes win over dynamic ones when both match.
Pages must render something sensible when their params are missing or
invalid (verification renders every page with empty params), e.g. a
"not found" body.

## Database workflow

- `mix ecto.setup` — create the database and run migrations
- `mix ecto.migrate` — run pending migrations
- New migration without the generator: `mix ecto.gen.migration name`
- Config lives in `config/dev.exs` and `config/test.exs`; defaults are
  `postgres:postgres@localhost` (override with `PGUSER`/`PGPASSWORD`/
  `PGHOST`).

## Testing data-backed pages

Use the `MyApp.DataCase` template — each test gets a sandboxed,
rolled-back DB connection and can run `async: true` — and drive pages
through the router with the `Fractal.Test` helpers:

```elixir
defmodule MyApp.Pages.PostsTest do
  use MyApp.DataCase, async: true

  import Fractal.Test

  test "POST /posts creates and redirects" do
    conn = post("/posts", %{"title" => "Hi", "body" => "There"})
    assert conn.status == 303
  end
end
```

Cover at least: the happy POST (creates + redirects), the invalid POST
(re-renders with errors, nothing inserted), and the show page for a
missing record.
