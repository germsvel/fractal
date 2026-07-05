# Task 13: server push — watch, publish, handle_watch

## Goal

Fractal is a new web framework written in Elixir that is AI-first.

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

This task adds the missing direction: the server pushing changes to the
browser — enough to build a chat app — without giving up the stateless
server.

## Framing: connection state is not application state

Push sounds like it demands what Fractal has refused: a long-lived,
stateful thing per client. The distinction that keeps the pillar intact:
a push channel is a **dumb delivery pipe** — it holds a socket and a
subscription list, never application state. If it dies, the browser
reconnects and nothing is lost, because everything renderable is still
derived from the database plus the request.

Fractal already has the client→server direction (`events:` over HTTP).
Push is the missing half only, and it keeps the same mental model:
*request in, HTML out* — now also *event in, HTML out*. A server-side
event triggers a page handler that re-renders a fragment, exactly like a
click does today.

## Scope

### The primitive: `watch:` / `publish/1` / `handle_watch/2`

One new declared capability in the page file, alongside `events:`:

```elixir
defmodule MyApp.Pages.Room do
  use Fractal.Page,
    path: "/rooms/:id",
    title: "Room",
    events: ["send"],                 # client → server (existing)
    watch: ["rooms/:id/messages"]     # server → client (new)

  @impl Fractal.Page
  def handle_event("send", assigns) do
    message = create_message!(assigns)
    publish("rooms/#{message.room_id}/messages")
    {:fragment, messages_region(message.room_id)}
  end

  @impl Fractal.Page
  def handle_watch("rooms/:id/messages", assigns) do
    {:fragment, messages_region(assigns.params["id"])}
  end
end
```

- `publish/1` is importable anywhere (page handlers, background jobs) —
  but the *receiving* side is always a page. There is no general
  subscriber API.
- `handle_watch/2` receives the usual assigns (params from the page's
  own path, session, context) and returns `{:fragment, ...}`. The
  fragment's root element id determines what gets swapped — the same
  contract event fragments already have.
- Multiple pages may watch the same topic; each open tab runs its own
  `handle_watch` and renders its own fragment. Publishers never know who
  is listening.

### Topics are path-shaped, exact, and payload-free

- **Path vocabulary**: topics reuse route-segment syntax
  (`rooms/:id/messages`). A watched topic's dynamic segments must bind
  from the page's own path params — `/rooms/:id` may watch
  `rooms/:id/messages`; `/lobby` may not, because it has no `:id`.
  Checked at compile time, like the `events:`/`handle_event` pairing.
  Scoping falls out of vocabulary agents already know.
- **No wildcards.** A page that wants broad updates watches a broader
  topic, and the publisher rings two doorbells:
  `publish("rooms/#{id}/messages")` and `publish("rooms")`. Explicit,
  grep-able, and keeps verify's topology check exact.
- **Doorbell, not data channel.** `publish/1` carries no payload. The
  handler re-queries the database and re-renders. This buys the killer
  property: **missed pushes are free** — on (re)connect the framework
  runs each watched handler once and the page is correct again, because
  correct was never a function of delivery history. No event sourcing,
  no diffing, no client state. It also decouples publishers from
  subscribers' data needs — each handler queries what it renders.

### Transport: SSE, not WebSockets

- The injected runtime opens **one `EventSource` per tab** to
  `GET /fractal/watch` — and only on pages that declare `watch:`. Pages
  without it have zero overhead; the declaration is the on-switch, and
  `grep watch:` finds every page that holds connections.
- Server-Sent Events is plain HTTP (Bandit handles it; no new
  transport), and `EventSource` auto-reconnects — the browser ships our
  reconnect story. WebSockets would duplicate the client→server path we
  already have and add framing/heartbeat/reconnect machinery we'd own
  forever.
- One connection multiplexes all of the page's topics. On connect and on
  every reconnect, the framework runs each watched handler once
  (self-healing catch-up), then streams fragments as topics fire.
- Guide notes the one real constraint: over HTTP/1.1 browsers cap ~6
  connections per origin, so production apps with many watching tabs
  should serve HTTP/2 (Bandit speaks it).

### The bus: Phoenix.PubSub behind an internal seam

- `phoenix_pubsub` (standalone, dep-free, Phoenix-team-maintained,
  git-pinned like the rest) is the fan-out. It spans nodes automatically
  when a distributed Erlang cluster exists; unclustered it is node-local
  — no worse than the stdlib alternative, and multi-node push becomes a
  deploy-guide recipe later, not a framework change.
- It is an **implementation detail**: apps never call `Phoenix.PubSub`
  and never see its name or supervisor. A private `Fractal.Bus` module
  is the seam (subscribe/publish, topic normalization), so the backend
  can become Registry or Postgres LISTEN/NOTIFY without touching any app
  code. The doorbell rule is what makes the bus swappable — hold it
  firm even though the library would happily carry payloads.
- The framework supervises the bus in its own tree (zero-API, like live
  reload). Apps configure nothing.

### Security: the checkpoint applies to subscriptions

`GET /fractal/watch` resolves the page from the requested path, derives
context from the cookie session, and **runs the page's guards before
subscribing** — a `require:`-guarded page cannot be watched by a
signed-out socket. A denied subscription gets the guard's redirect
semantics (the runtime follows it), and emits the same telemetry as any
denial.

### Verification

- **Compile-time pairing** (mirrors `events:`): `watch:` without a
  matching `handle_watch/2` fails to compile; a watched topic whose
  dynamic segments don't all bind from the page path fails to compile.
- **Verify — handlers**: `handle_watch` is smoke-run with the standard
  smoke assigns; its fragment goes through the same scans as any render
  (escaping, no scripts, no external refs, assets exist).
- **Verify — topology**: publishes are literal-ish calls
  (interpolations normalize to `:param` segments), watches are
  declarations, so verify cross-references them. A watched topic nothing
  publishes is an **error** (dead wire); a published topic nothing
  watches is **informational** (like unused guards).
- **Coverage**: pages that watch are pages — the existing every-page-
  has-tests rule applies unchanged.
- `Fractal.Test` gains `fire_watch(path, topic, opts)` (mirrors
  `fire_event`, `session:` opt included) driving the full path: resolve
  page, run guards, run `handle_watch`, return the fragment response.
- `mix fractal.ai.docs` gains a **topic inventory**: each topic, who
  watches it, where it's published from — the pub/sub topology an agent
  reads before wiring a feature.

### Dogfood and docs

- `examples/blog`: the posts index updates live — `handle_post` on the
  new-post page publishes `"posts"`, the Posts page watches it. Small,
  honest, exercises the whole path end to end (and the showcase's
  guarded/scoped variants as useful).
- Framework fixtures gain a watch page (topic under `fixtures/...`) and
  a publisher, so router/verify/test-helper coverage stays DB-less; the
  real-HTTP SSE round-trip lands in `server_test`.
- New guide `priv/guides/push.md`: the model (doorbell, re-render from
  the DB), the two topic rules, when to publish twice, the HTTP/2 note,
  testing with `fire_watch`. The interactivity guide gets a pointer.
- Generated apps: no watch page in the installer template (Counter
  stays the interactivity demo; push is guide material) — but the
  generated AGENTS.md's orientation gains the watch/publish bullet.

### Non-goals

- No presence, typing indicators, or per-client/per-user channels —
  application code or later tasks, if ever.
- No payload-carrying messages, no wildcard topics, no
  subscribe-anywhere API, no exposure of Phoenix.PubSub to apps.
- No WebSockets. No `BroadcastChannel` tab-sharing of one connection.
- No clustering/deploy story (unchanged from task 12) — single-node
  semantics documented honestly.

## Constraints

- The stateless pillar holds: watch connections hold no application
  state; killing every connection loses nothing but latency.
- Everything the feature adds must satisfy the framework's own
  contracts: compile-time pairing, verify checks with named fixes,
  smoke-runs, coverage, guide + inventories shipped in the same task.
- `handle_watch` fragments follow every existing render rule — one
  contract for HTML no matter what triggered it.
- Deps: `phoenix_pubsub` only, git-pinned. `Fractal.Bus` stays private.

## Files expected to change

New: `lib/fractal/bus.ex` (private seam over Phoenix.PubSub),
`priv/guides/push.md`, watch fixtures in `test/support/fixtures.ex`,
`test/fractal/bus_test.exs` (plus watch coverage in router/verify/test
tests). Modified: `lib/fractal/page.ex` (`watch:` option, pairing
validation, `publish/1` import), `lib/fractal/router.ex` (the
`/fractal/watch` SSE endpoint), `lib/fractal/document.ex` /
`lib/fractal/interactive.ex` (runtime: open `EventSource` when the page
watches, swap pushed fragments by root id), `lib/fractal/verify.ex`
(smoke-run, topology check), `lib/fractal/test.ex` (`fire_watch`),
`lib/fractal/application.ex` (supervise the bus),
`lib/mix/tasks/fractal.ai.docs.ex` (topic inventory), `mix.exs`
(phoenix_pubsub pin), `installer/templates/AGENTS.md.eex` (orientation
bullet), `examples/blog` (live posts index + tests), `AGENTS.md`
(contributor notes if conventions shift).

## Plan first

Before changing anything, map the full plan and list the files you'll
touch. Wait for my go-ahead, then execute in one pass.

## Definition of done

- [x] A page can declare `watch:`, implement `handle_watch/2`, and any
  code can `publish/1`; browsers on that page receive re-rendered
  fragments over SSE with no user-written JavaScript — demonstrated live
  over real HTTP (two clients, one publishes, the other updates).
- [x] Pages without `watch:` open no connection; guarded pages refuse
  subscriptions that fail their guards.
- [x] Reconnect self-heals: killing the connection and reconnecting
  yields a correct page with no missed-update artifacts.
- [x] Compile-time pairing and binding checks fail broken pages with
  named fixes; verify smoke-runs handlers and cross-checks the
  publish/watch topology; `mix fractal.ai.docs` prints the topic
  inventory.
- [x] `fire_watch` drives watch handlers in tests; framework suite stays
  DB-less and green; `examples/blog` dogfoods a live region with tests
  and full verify green.
- [x] `priv/guides/push.md` ships with the feature; the installer's
  AGENTS.md template mentions the primitive.
