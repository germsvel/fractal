# The checkpoint: guards and cross-cutting behavior

Fractal deliberately has **no middleware**. An ordered stack of opaque
functions is the antithesis of "read one page file, understand the
route." Cross-cutting behavior follows one rule instead: **declared
where it applies, defined in one well-known place, guaranteed by
verify.** That one place is the checkpoint — the module every request
passes through, where the app establishes who is asking (`context/1`),
applies named checks (`guard`), and declares which zones require which
clearances (`expect`).

## Guards: protecting pages

The page declares what it needs — visible in the one file that matters:

```elixir
use Fractal.Page, path: "/admin", title: "Admin", require: :signed_in
```

`require:` takes one guard name or a list. Guards run in order before
`render/1`, every `handle_*/1`, **and every interactive event** —
events dispatch to a page, so they cannot bypass its guards.

Guard names are defined in exactly one module — the checkpoint,
`lib/fractal/checkpoints.ex`:

```elixir
defmodule Fractal.Checkpoints do
  use Fractal.Checkpoint

  def context(assigns) do
    %{"user_name" => assigns.session["user_name"]}
  end

  guard :signed_in, %{context: context} do
    if context["user_name"],
      do: :ok,
      else: {:redirect, "/login", flash: %{"error" => "Please log in first."}}
  end

  expect "/admin", :signed_in
end
```

The rules:

- A guard receives the assigns (params, session, path, context) as an
  explicit pattern-matched argument — `guard :name, %{context: context} do`,
  the same shape as ExUnit's `test "name", %{conn: conn}`; omit the
  pattern when unneeded. It returns `:ok` or
  `{:redirect, to[, directives]}` — the same vocabulary as page
  handlers, session/flash directives included.
- Guards **cannot mutate assigns** — they allow or redirect, nothing
  else. Derivation belongs to `context/1`.
- Guards may query the database (unlike components).
- Guards must tolerate an empty session — verify smoke-runs each one.
- An undefined guard name fails verification (and fails *closed* at
  runtime — it raises rather than letting the request through).

## Expectations: coverage as a verification contract

The dangerous failure isn't a broken guard — it's admin page #12
shipped without one. `expect/2` turns coverage into a contract:

```elixir
expect "/admin", :signed_in
```

This changes **nothing at runtime**. It makes `mix fractal.verify`
fail any page whose path lives under `/admin` (segment-aware) without
`require: :signed_in`, naming the page and the missing guard. Each
page still shows its own behavior; the guarantee is mechanical.

## Context: request-scoped derivation

Override `context/1` to compute identity-scale data once per request —
the current user, a locale. It lands under `assigns.context` for every
page and guard. Because it's namespaced, provenance is self-evident:
anything on `context.*` came from `lib/fractal/checkpoints.ex`, nowhere
else.

Rules: pure derivation from session/params/path (a `Repo.get` for the
current user is fine), must tolerate an empty session, never business
logic.

## Response headers: configuration, not code

Every response carries secure defaults (`x-content-type-options`,
`x-frame-options`, `referrer-policy`). Add or override via config —
data, not code; no user code runs in the response path:

```elixir
config :fractal, :response_headers, %{"permissions-policy" => "camera=()"}
```

## Observability: telemetry, not middleware

The router emits `[:fractal, :request, :stop]` (duration, method,
path, status) and `Fractal.Checkpoint` emits `[:fractal, :checkpoint, :denied]`
(guard, path). Attach `:telemetry` handlers in your own application
code.

## There is no middleware slot — deliberately

No `plugs: [...]` config, no `def middleware`. Invisible action at a
distance breaks the one-file promise, ordered stacks are the classic
failure mode, and an open hook collects whatever gets pasted into it.
When a genuinely new cross-cutting need appears, it becomes a new
named, verified primitive — the framework grows vocabulary, not hooks.
(Also rejected for now: rate limiting — use your reverse proxy — and
rewrite rules, which exact-match routing mostly precludes.)

## Testing guarded pages

`Fractal.Test`'s `session:` option covers both sides:

```elixir
test "anonymous users are sent to log in" do
  conn = get("/admin")

  assert conn.status == 303
  assert Plug.Conn.get_resp_header(conn, "location") == ["/login"]
end

test "signed-in users pass" do
  conn = get("/admin", %{}, session: %{"user_name" => "Ada"})

  assert conn.status == 200
end
```
