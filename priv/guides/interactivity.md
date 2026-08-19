# Interactivity

Fractal pages become interactive **without anyone writing JavaScript**.
The model is declarative events over HTTP (in the spirit of HTMX):

1. An element declares an event with `fx/2` attributes or a
   `trigger/3` button.
2. Fractal's built-in runtime (injected by the document) POSTs the event
   to `/fractal/event`.
3. The page's `handle_event/2` returns an HTML fragment.
4. The runtime swaps the fragment into the target element.

Request in, HTML out — the same mental model as every other part of the
framework, which also makes interactivity fully testable in ExUnit.

## An interactive page

```elixir
defmodule MyApp.Pages.Counter do
  use Fractal.Page, path: "/counter", title: "Counter", events: ["increment", "reset"]

  @impl Fractal.Page
  def render(_assigns), do: counter(0)

  @impl Fractal.Page
  def handle_event("increment", assigns) do
    count = String.to_integer(assigns.params["count"] || "0") + 1
    {:fragment, counter(count)}
  end

  def handle_event("reset", _assigns), do: {:redirect, "/counter"}

  defp counter(count) do
    tag(:div, [id: "counter"], [
      tag(:p, [], ["Count: ", to_string(count)]),
      trigger("+1", "increment", target: "#counter", values: %{count: count})
    ])
  end
end
```

The rules:

- Declare every event in `events:`; handle each with a
  `handle_event/2` clause. Declaring without handling (or vice versa)
  fails at compile time, and the router rejects undeclared events.
- `handle_event/2` receives the event name and the usual assigns
  (`:params` includes the trigger's `values:`, the element's own input
  value, and the page's path params; `:path` is the page's location;
  `:event` is the event name).
- Return `{:fragment, content}` to swap `content` into the trigger's
  `target:`, or `{:redirect, to}` to navigate the browser.
- **The server is stateless.** State lives in the DOM (send it back via
  `values:`), in inputs, or in the database. Extract the interactive
  region into a private function (like `counter/1` above) and have both
  `render/1` and the handlers call it — the fragment must re-render the
  whole target, including its `id` and triggers with the new state.

## Triggers

`trigger(label, event, opts)` renders a button. For any other element,
`fx(event, opts)` returns the attributes:

```elixir
tag(:input, [type: "text", name: "q", placeholder: "Search..."] ++
  fx("search", target: "#results", on: :input))
```

Options: `target:` (required — CSS selector the fragment replaces),
`values:` (map of extra params), and `on:` — `:click` (default),
`:input` (debounced 300ms, for live search), `:change` (selects,
checkboxes), `:submit` (a whole `<form>`; all fields become params), or `:drop`.
Inputs send their `name` (or `"value"`) automatically.

## Drag and drop

Use `drag_card/1` to make a card draggable and `fx(..., on: :drop)` on a
column or card to receive it. The runtime sends the dragged card's id as
`"card_id"`; keep board state in `values:` and return the full board region.
Dropping on a card can carry its id as `before_card_id` to place the dragged
card before it, while dropping on a column appends it.

## Keyboard shortcuts and browser actions

Pages can declare small, verified keyboard accelerators without writing
JavaScript. They remain accelerators: always render a button, link, or other
accessible path for the underlying action too.

```elixir
use Fractal.Page, path: "/search", events: ["refresh"], keys: [
  "/": {:focus, "#search"},
  "?": {:toggle, "#keyboard-help"},
  "Escape": {:hide, "#keyboard-help"},
  "r": {:event, "refresh"},
  "n": {:navigate, "/posts/new"}
]
```

Supported actions are `{:event, name}`, `{:focus, "#id"}`, `{:navigate,
"/path"}`, `{:show, "#id"}`, `{:hide, "#id"}`, and `{:toggle, "#id"}`.
Targets are id selectors only. `mix fractal.verify` checks that targets exist
in the page's normal render and that focus targets are focusable. Shortcuts do
not fire while a user is editing an input, textarea, select, or editable
content. Keys may be printable characters, `Escape`/`Enter`/arrow names, or
modifier chords such as `Mod+k` and `Ctrl+k`.

Test an event shortcut with `fire_key("/search", "r")`; local actions can be
checked with `assert_key_action(MyApp.Pages.Search, "/", {:focus, "#search"})`.

## The fast path: the generator

```
mix fractal.gen.page Counter --events increment,decrement
```

scaffolds an interactive page with a region, one `handle_event/2`
clause per event, and tests that fire each event through the router.

## Testing interactivity

Events go through `Fractal.Router` like any request — no browser
needed. Use the `Fractal.Test` helpers:

```elixir
import Fractal.Test

test "increment bumps the count" do
  conn = fire_event("/counter", "increment", %{"count" => "0"})

  assert conn.status == 200
  assert conn.resp_body =~ "Count: 1"
end
```

Cover at least: each event's happy path (fragment contains the new
state), and that state round-trips (the fragment's `values:` carry the
updated value). Undeclared events return 404; handler crashes return
500 with the exception in dev.

## Limitations (deliberate, for now)

- The runtime swaps `outerHTML` of one target per event — no DOM
  diffing, no streams. Keep regions small.
- Events are user-initiated. For the reverse direction — the server
  pushing updates to browsers (chat, live lists) — declare `watch:` on
  the page and ring the doorbell with `publish/1`; see the push guide.

Events carry the CSRF token automatically (the runtime reads it from
the document's meta tag) — one more reason interactions must go through
`fx/2`/`trigger/3` rather than hand-written `fetch` calls.
