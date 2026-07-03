# Sessions and CSRF

## Sessions

The session is an **encrypted cookie** — the server stays stateless, the
same way event state travels in the DOM and app data lives in the
database. There is no session store to manage.

### Reading

`assigns.session` is a string-keyed map, exactly like `assigns.params`:

```elixir
def render(assigns) do
  case assigns.session["user_id"] do
    nil -> guest_view()
    id  -> member_view(Fractal.Repo.get(Fractal.User, id))
  end
end
```

Pages must tolerate an empty session (verification renders every page
with `session: %{}`).

### Writing

Session writes are **directives on handler results** — pages never
touch a conn:

```elixir
{:redirect, "/dashboard", session: %{"user_id" => user.id}}
{:redirect, "/login", clear_session: true}                   # logout
{:render, %{changeset: cs}, flash: %{"error" => "Try again."}}
{:fragment, region(state), session: %{"draft" => state}}
```

Three directives, composable with every return type:

- `session:` — a map merged into the session (keys become strings)
- `clear_session: true` — empties the session first (so a logout can
  still set a flash)
- `flash:` — a map of level → message (`"info"` and `"error"` are
  styled) shown by the layout **once**, on the next page load

`grep -r "session:" lib/fractal/pages` finds every place session state
changes.

### What belongs in the session

Identity-scale data only — a user id, a locale, a theme. It lives in a
~4KB cookie sent with every request. App state belongs in the database
or in event `values:`. Known tradeoff of cookie sessions: they can't be
force-expired server-side individually, only by rotating the secret.

### The secret

Sessions are encrypted/signed with `config :fractal, :secret_key_base`.
Generate one with `mix fractal.gen.secret`; dev/test keep committed
secrets, production reads the `SECRET_KEY_BASE` environment variable.
`mix fractal.verify` fails when the secret is missing or under 64
bytes. The session cookie is `SameSite=Lax`.

### The signed-in bar

The layout shows a "Signed in as … / Log out" bar on every page when
the session has a `"user_name"` (see the demo page at `/login`). Store
a display name under that key to use it; the log-out button targets a
`delete: "/logout"` route.

## CSRF protection

CSRF protection is **automatic and has no page-level API**. There is
nothing to configure, no token to handle, and no way to opt out:

- `form_for/3,4` and `button_to/3` inject a hidden `_csrf_token` into
  every form.
- The layout emits a `fractal-csrf-token` meta tag; the interactivity
  runtime attaches the token to every event automatically.
- The router rejects any POST/PUT/PATCH/DELETE or event without a valid
  token — 403, with a body explaining exactly this convention.

The one rule that follows: **never hand-write a `<form>` tag or a raw
`fetch` call.** Use `Fractal.Form` and `fx/2`/`trigger/3`, which exist
precisely so the framework can own both ends of every state-changing
request. `mix fractal.verify` flags any page that renders a `<form>`
without a token.

## Testing

Use `Fractal.Test` — its helpers route requests through the real
router with a test session and Plug's standard CSRF exemption for
tests (the protection itself is covered by framework tests):

```elixir
import Fractal.Test

test "logging in stores the name" do
  conn = post("/login", %{"name" => "Ada"})

  assert conn.status == 303
  assert Plug.Conn.get_session(conn, "user_name") == "Ada"
end

test "members see the dashboard" do
  conn = get("/dashboard", %{}, session: %{"user_id" => "1"})

  assert conn.status == 200
end
```

Helpers: `get/1..3`, `post/1..3`, `put/1..3`,
`delete/1..3`, and `fire_event/2..4` — all accept a trailing
`session:` option for logged-in scenarios; assert on writes with
`Plug.Conn.get_session/2`.
