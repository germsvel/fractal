defmodule Fractal.Component do
  @moduledoc """
  Reusable UI components: Fractal's design-system vocabulary.

  Components exist for **coherence, not effort** — they are the shared
  visual language, not a general abstraction mechanism. A component is
  one module (the page pattern at smaller scale): a pure render
  function, an optional scoped style, and a required example.

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
          \"\"\"
          .card { background: var(--surface); border-radius: 0.5rem; padding: 1.25rem; }
          \"\"\"
        end

        @impl Fractal.Component
        def example do
          %{title: "Example card", body: tag(:p, [], ["Body content"])}
        end
      end

  Pages render components with `component/2` (imported by
  `use Fractal.Page`):

      component(Fractal.Components.Card, title: "Stats", body: chart)

  ## The rules

    * Components live in `lib/fractal/components/` and are
      auto-discovered — the dev gallery at `/fractal/components` and
      `mix fractal.ai.docs` list every one. **Check there before
      creating a new component.**
    * Components are **pure functions of assigns**: no routes, no
      events, no session, no database queries — data arrives via
      assigns. If it needs handlers, it's a page. (Rendering `trigger/3`
      buttons is fine; the events they fire belong to the page.)
    * "Slots" are just assign keys carrying safe HTML — no special
      syntax.
    * `style/0` is scoped to the component (via a `data-component`
      wrapper) exactly like page styles — it cannot leak.
    * `example/0` is required: verification smoke-renders every
      component with it, and the gallery displays it.
    * Don't componentize single-page markup (private functions in the
      page are right for that) or thinly wrap `Fractal.Form`/`trigger/3`.
  """

  alias Fractal.HTML

  @callback render(assigns :: map()) :: HTML.Safe.t() | iodata()
  @callback style() :: String.t()
  @callback example() :: map()

  @optional_callbacks style: 0

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if opts != [] do
        raise ArgumentError,
              "use Fractal.Component takes no options — components are render-only; " <>
                "routes, events, and sessions belong to pages"
      end

      @behaviour Fractal.Component

      import Fractal.HTML
      import Fractal.Interactive
      import Fractal.Assets, only: [asset_path: 1]
      import Fractal.Component, only: [component: 1, component: 2]
    end
  end

  @doc """
  Renders a component with `assigns` (map or keyword).

  The output is wrapped in a layout-neutral element
  (`display: contents`) carrying the `data-component` attribute that
  scopes the component's `style/0`.
  """
  @spec component(module(), map() | keyword()) :: HTML.Safe.t()
  def component(module, assigns \\ []) do
    HTML.tag(
      :div,
      ["data-component": slug(module), style: "display: contents"],
      [HTML.to_safe(module.render(Map.new(assigns)))]
    )
  end

  @doc "All discovered components, sorted by name."
  @spec all() :: [module()]
  def all do
    Fractal.Discovery.modules()
    |> Enum.filter(&component?/1)
    |> Enum.sort_by(&inspect/1)
  end

  @doc "Returns `true` if `module` is a compiled Fractal component."
  @spec component?(module()) :: boolean()
  def component?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :render, 1) and
      function_exported?(module, :example, 0) and
      __MODULE__ in behaviours(module)
  end

  @doc "The component's slug, used to scope its styles (`data-component`)."
  @spec slug(module()) :: String.t()
  def slug(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", "-")
  end

  @doc "Returns the component's `style/0` CSS, or `nil`."
  @spec style(module()) :: String.t() | nil
  def style(module) do
    if function_exported?(module, :style, 0), do: module.style(), else: nil
  end

  @doc """
  The component gallery: every component rendered live with its
  example. Served at `/fractal/components` in development.
  """
  @spec gallery() :: HTML.Safe.t()
  def gallery do
    HTML.tag(:section, [], [
      HTML.tag(:h1, [], ["Components"]),
      HTML.tag(:p, [class: "lead"], [
        "Fractal's design-system vocabulary — every component, rendered from its ",
        HTML.tag(:code, [], ["example/0"]),
        ". Use one with ",
        HTML.tag(:code, [], ["component(Module, assigns)"]),
        ". Check here before creating a new one."
      ]),
      gallery_entries(all())
    ])
  end

  defp gallery_entries([]) do
    HTML.tag(:p, [], [
      "No components yet — scaffold one with ",
      HTML.tag(:code, [], ["mix fractal.gen.component Name"]),
      "."
    ])
  end

  defp gallery_entries(components) do
    Enum.map(components, fn comp ->
      HTML.tag(:section, [class: "gallery-entry"], [
        HTML.tag(:h2, [], [HTML.tag(:code, [], [inspect(comp)])]),
        gallery_doc(comp),
        HTML.tag(:div, [class: "gallery-preview"], [component(comp, comp.example())]),
        HTML.tag(:details, [], [
          HTML.tag(:summary, [], ["Example assigns"]),
          HTML.tag(:pre, [], [inspect(comp.example(), pretty: true)])
        ])
      ])
    end)
  end

  defp gallery_doc(comp) do
    case Code.fetch_docs(comp) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
        HTML.tag(:p, [], [doc |> String.split("\n\n") |> hd() |> String.trim()])

      _other ->
        nil
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
