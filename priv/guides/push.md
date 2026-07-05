# Server push

Events (see the interactivity guide) are the client→server direction.
Push is the reverse: the server tells browsers a page's data changed,
and the page re-renders a fragment for them — chat messages appearing,
a list updating when someone else adds to it. Same mental model as
everything in Fractal: *event in, HTML out*. No user JavaScript, no
WebSockets, no client state.

## The three parts

A page declares topics with `watch:`, handles them with
`handle_watch/2`, and any code rings the doorbell with `publish/1`:

```elixir
defmodule MyApp.Pages.Room do
  use Fractal.Page,
    path: "/rooms/:id",
    title: "Room",
    events: ["send"],                 # client → server
    watch: ["rooms/:id/messages"]     # server → client

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

  defp messages_region(room_id) do
    tag(:div, [id: "messages"], [
      # ... query the messages, render the list ...
    ])
  end
end
```

Browsers on a watching page hold one server-sent-events connection
(opened automatically by the injected runtime — the `watch:`
declaration is the on-switch; pages without it open nothing). When a
topic fires, `handle_watch/2` runs with the usual assigns (params from
the page's own path, session, context) and the returned fragment
replaces the element matching its **root `id`** — so the fragment's
root must carry one (verify checks this). `{:redirect, to}` is also
allowed: every watching browser navigates (a deleted room can send
everyone home). Watch results cannot carry `session:`/`flash:`
directives — the stream's headers are already sent.

## Topics

- **Path-shaped**: `rooms/:id/messages` — the same segment vocabulary
  as routes, without the leading slash.
- **`:name` segments bind from the page's own path params.** A page at
  `/rooms/:id` may watch `rooms/:id/messages`; a page without `:id` may
  not (compile-time error). Viewing `/rooms/42` subscribes exactly to
  `rooms/42/messages` — scoping falls out of the vocabulary.
- **No wildcards.** A page that wants broad updates watches a broader
  topic, and publishers ring both doorbells:

  ```elixir
  publish("rooms/#{message.room_id}/messages")  # the room's viewers
  publish("rooms")                              # e.g. a lobby's activity feed
  ```

- Multiple pages may watch the same topic; each renders its own
  fragment. Publishers never know who is listening.

## The doorbell rule

`publish/1` carries **no payload** — it takes a concrete topic
(`"rooms/42/messages"`, every `:name` interpolated) and nothing else.
Handlers re-query the database and re-render. This is what keeps the
server stateless and the model simple:

- **Missed pushes are free.** The connection is a dumb pipe; on
  connect and on every browser reconnect (EventSource reconnects
  natively) the framework runs each watched handler once, so the page
  self-heals. No delivery history matters, because correctness never
  depended on it.
- Publishers stay decoupled from what subscribers render — each
  handler queries what it needs.
- Publish from anywhere: page handlers have `publish/1` imported;
  other code (a background job) uses `import Fractal.Interactive`.

## Verification

- `watch:` without `handle_watch/2` (or vice versa), unbound `:name`
  segments, and malformed topics fail at compile time.
- `mix fractal.verify` smoke-runs every watch handler (fragments pass
  the same scans as renders, and must carry a root id) and
  cross-checks the topology: **a watched topic no code publishes is a
  failure** (a dead wire); published topics nothing watches are
  reported informationally. `mix fractal.ai.docs` prints the live
  topic inventory — check it before wiring a new feature.

## Testing

`Fractal.Test.fire_watch/3` delivers a topic to a page exactly as a
publish would — resolve, guards, handler — and returns the response:

```elixir
test "the message list is live" do
  message = create_message!(room_id: 42)

  conn = fire_watch("/rooms/42", "rooms/:id/messages")

  assert conn.status == 200
  assert conn.resp_body =~ message.body
end
```

Pass the topic as declared (the pattern); guard denials come back as
303s, like page requests.

## Guards and limits

- Subscriptions run the page's `require:` guards with the real session
  — a guarded page cannot be watched by a signed-out browser (the
  stream answers with a redirect the runtime follows).
- One connection per open tab of a watching page, multiplexing all its
  topics. Over HTTP/1.1 browsers cap ~6 connections per origin, so
  production apps expecting many watching tabs should serve HTTP/2
  (Bandit speaks it). Push is currently node-local: publishes reach
  the browsers connected to the node that published.
