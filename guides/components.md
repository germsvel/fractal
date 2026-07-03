# Components

Components are Fractal's **design-system vocabulary** — the shared
visual language. They exist for *coherence*, not effort: without them,
twenty pages grow twenty subtly different card markups. They are not a
general abstraction mechanism.

## Check what exists first

Before creating a component, look at the inventory:

- **`/fractal/components`** in the browser (dev) — every component
  rendered live from its example, with its docs and assigns.
- The **component inventory** at the end of `mix fractal.ai.docs`.

Prefer using or extending an existing component over creating a
near-duplicate. `mix fractal.verify` lists components no page renders.

## Anatomy

One file per component in `lib/fractal/components/` — the page pattern
at smaller scale (render + scoped style + example, no routes):

```elixir
defmodule Fractal.Components.Card do
  @moduledoc "A surface for grouping related content."

  use Fractal.Component

  @impl Fractal.Component
  def render(assigns) do
    tag(:div, [class: "card"], [
      tag(:h3, [], [assigns.title]),
      assigns.body
    ])
  end

  @impl Fractal.Component
  def style do
    """
    .card { background: var(--surface); border-radius: 0.5rem; padding: 1.25rem; }
    """
  end

  @impl Fractal.Component
  def example do
    %{title: "Example card", body: tag(:p, [], ["Body content"])}
  end
end
```

Pages render it with the imported `component/2` helper:

```elixir
component(Fractal.Components.Card, title: "Stats", body: chart)
```

- **Assigns are the whole API.** "Slots" are just assign keys carrying
  safe HTML — children, headers, anything. No special syntax.
- **`style/0` is scoped to the component** (a `data-component` wrapper,
  like pages' `data-page`) — it cannot leak. Use `app.css` tokens
  (`var(--accent)`, `var(--surface)`) rather than hard-coded values.
- **`example/0` is required.** It renders in the gallery and drives
  verification: every component is smoke-rendered with it through the
  same scans as pages (escaping, no `<style>` tags, no external
  references, CSRF tokens in forms).

Scaffold one with `mix fractal.gen.component Name`.

## The rules

- **Components are pure functions of assigns**: no routes, no
  `events:`/`handle_event`, no session access, and **no database
  queries** — data comes in through assigns so the page keeps showing
  its own data dependencies. If it needs handlers, it's a page.
  Rendering `trigger/3` buttons is fine; the events they fire belong to
  the page that uses the component.
- **Don't componentize single-page markup.** Markup used by one page
  stays a private function in that page (`counter/1`-style). Component
  = shared across pages, or part of the visual language.
- **Don't thinly wrap the primitives.** `Fractal.Form` helpers and
  `trigger/3`/`fx/2` already are the vocabulary for forms and
  interactivity.
- No external component libraries — same stance as the CDN ban.

## Testing

```elixir
import Fractal.Component, only: [component: 2]

test "passes Fractal's component verification checks" do
  results = Fractal.Verify.run_components([Fractal.Components.Card])
  assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
end

test "renders a title" do
  html = Card |> component(%{title: "Hi", body: nil}) |> Fractal.HTML.safe_to_string()
  assert html =~ "Hi"
end
```
