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

generates the schema + changeset, the **migration**, three pages
(index, new-with-form, show), and their tests. Field types: `string`,
`text` (textarea), `integer`, `float`, `boolean` (checkbox), `date`.
Then:

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
defmodule Fractal.Pages.NewPost do
  use Fractal.Page, path: "/posts/new", title: "New post", post: "/posts"

  import Fractal.Form

  alias Fractal.Repo

  @impl Fractal.Page
  def render(assigns) do
    changeset = assigns[:changeset] || Fractal.Post.changeset(%Fractal.Post{}, %{})

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
    case Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, assigns.params)) do
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

## Form helpers (`Fractal.Form`)

`form_for/3`, `input/3`, `textarea/3`, `checkbox/3`, `submit/2`,
`errors_for/2`. All output goes through `Fractal.HTML`, so values are
escaped. Field names are flat (`name="title"`) — exactly what
`Ecto.Changeset.cast/4` expects from `assigns.params`. Errors render
only after a failed `Repo.insert` (when the changeset has an `:action`).

Known deferral: there are no sessions yet, so forms carry **no CSRF
token**. Revisit when sessions land.

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

Use the `Fractal.DataCase` template — each test gets a sandboxed,
rolled-back DB connection and can run `async: true`:

```elixir
defmodule Fractal.Pages.PostsTest do
  use Fractal.DataCase, async: true

  import Plug.Test

  test "POST /posts creates and redirects" do
    conn = :post |> conn("/posts", %{"title" => "Hi", "body" => "There"}) |> Fractal.Router.call([])
    assert conn.status == 303
  end
end
```

Cover at least: the happy POST (creates + redirects), the invalid POST
(re-renders with errors, nothing inserted), and the show page for a
missing record.
