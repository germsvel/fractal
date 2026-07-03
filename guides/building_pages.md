# Building pages

A Fractal page is **one module** that declares its route and renders its
content. There is no router file to edit, no controller, no template file:
drop a module in `lib/fractal/pages/` and it is served.

## Anatomy of a page

```elixir
defmodule Fractal.Pages.About do
  @moduledoc "The About page, served at /about."

  use Fractal.Page, path: "/about", title: "About"

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [], [
      tag(:h1, [], ["About"]),
      tag(:p, [], ["Hello from Fractal."])
    ])
  end
end
```

Rules:

- Module name: `Fractal.Pages.<Name>`; file: `lib/fractal/pages/<name>.ex`
  (snake_case of the module suffix).
- `use Fractal.Page` takes `path:` (required, string starting with `/`,
  validated at compile time) and `title:` (optional).
- `render/1` receives an assigns map with `:params` (query params as a
  string-keyed map), `:path`, and `:conn` (the `Plug.Conn`, or `nil` when
  rendered outside a request, e.g. by verification). It must handle
  `conn: nil` gracefully.
- Routes are exact-match. `/about` does not match `/about/team`.

## Rendering HTML

`use Fractal.Page` imports `Fractal.HTML`. Build markup with `tag/3`:

```elixir
tag(:ul, [class: "plans"], for plan <- plans do
  tag(:li, [], [plan.name, " — ", tag(:strong, [], [plan.price])])
end)
```

- Everything is **escaped by default**: strings in children and attribute
  values are HTML-escaped automatically.
- `raw/1` is the only escape hatch for pre-built HTML. Avoid it unless the
  content is fully under the page's control.
- Attributes: `true` renders a bare attribute, `false`/`nil` omit it, and
  underscores become dashes (`aria_label:` → `aria-label=`).
- `render/1` may return the result of `tag/3`/`raw/1`, a plain string
  (which will be escaped), or a list of those.

Pages are wrapped in `Fractal.Layout` (document shell, `<title>`, default
stylesheet, and the live-reload script in dev). Pages only render their
body content.

## The fast path: the generator

```
mix fractal.gen.page Pricing --path /pricing --title "Pricing"
```

creates `lib/fractal/pages/pricing.ex` and
`test/fractal/pages/pricing_test.exs`. Then edit `render/1` and keep the
test meaningful: assert on the real content you added.

## Development loop

With `mix fractal.server` running in dev, saving any `.ex` file recompiles
the project and open browser tabs reload automatically — new pages appear
without restarting anything.

## After every change

Run `mix fractal.verify`. It compiles with warnings as errors, checks all
pages (valid unique routes, rendering works), and runs the test suite. Do
not consider a change done until it passes.
