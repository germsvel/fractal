defmodule Fractal.Layout do
  @moduledoc """
  The app's layout: app-wide document data and chrome, in one module.

  The ownership model: **the framework owns the document
  (`Fractal.Document` — head machinery, security, scripts), the app's
  layout contributes app-wide data and chrome, the page contributes
  content.** Apps never write `<head>` or envelope markup — they
  contribute data and safe HTML through this module, discovered like
  the checkpoint (one optional module, at most one):

      # lib/my_app/layouts.ex
      defmodule MyApp.Layouts do
        use Fractal.Layout

        # app-wide document data — rendered by the framework, escaped
        def site do
          %{
            name: "My App",              # <title>Page — My App</title>
            lang: "en",                  # <html lang="en">
            favicon: asset_path("logo.svg"),
            theme_color: "#0b1021"
          }
        end

        # app UI above <main> on every page: nav, session bar, footer
        def chrome(assigns) do
          tag(:nav, [class: "site-nav"], [
            tag(:a, [href: "/"], ["Home"]),
            greeting(assigns.session["user_name"])
          ])
        end

        # scoped to the chrome — cannot leak into pages
        def style do
          \"\"\"
          .site-nav { display: flex; gap: 1rem; }
          \"\"\"
        end
      end

  ## The rules

    * All callbacks are optional; an app without a layout module gets
      the plain document.
    * `site/0` returns data — the framework composes and escapes it.
      Keys: `:name`, `:lang` (default `"en"`), `:favicon` (use
      `asset_path/1`, so missing files fail verify), `:theme_color`,
      and `:description` (the app-wide default meta description; a
      page's `meta/1` description overrides it).
    * `chrome/1` receives the usual assigns (session, context, path)
      and returns safe HTML (or `nil` to render nothing); it must
      tolerate empty assigns and goes through the same verification
      scans as pages. Session keys and routes it uses (a `"user_name"`,
      a `/logout`) are the app's own — the framework knows nothing
      about them.
    * `style/0` is scoped under the chrome (a `data-layout` wrapper),
      exactly like page and component styles.
  """

  alias Fractal.HTML

  @callback site() :: map()
  @callback chrome(assigns :: map()) :: HTML.Safe.t() | iodata() | nil
  @callback style() :: String.t()

  @optional_callbacks site: 0, chrome: 1, style: 0

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if opts != [] do
        raise ArgumentError, "use Fractal.Layout takes no options"
      end

      @behaviour Fractal.Layout

      import Fractal.HTML
      import Fractal.Interactive
      import Fractal.Form
      import Fractal.Assets, only: [asset_path: 1]
      import Fractal.Component, only: [component: 1, component: 2]

      @doc false
      def __fractal_layout__, do: true
    end
  end

  # -- discovery ----------------------------------------------------------

  @doc "The app's layout module, or `nil` (there should be at most one)."
  @spec module() :: module() | nil
  def module, do: modules() |> List.first()

  @doc false
  @spec modules() :: [module()]
  def modules do
    Fractal.Discovery.modules()
    |> Enum.filter(&layout_module?/1)
    |> Enum.sort_by(&inspect/1)
  end

  @doc "Returns `true` if `module` is a compiled layout module."
  @spec layout_module?(module()) :: boolean()
  def layout_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__fractal_layout__, 0) and
      __MODULE__ in behaviours(module)
  end

  @doc "The app-wide document data, with defaults applied."
  @spec site() :: map()
  def site do
    declared =
      case module() do
        nil -> %{}
        mod -> if function_exported?(mod, :site, 0), do: mod.site(), else: %{}
      end

    Map.merge(%{lang: "en"}, declared)
  end

  @doc "The app's chrome for these assigns, or `nil`."
  @spec chrome(map()) :: HTML.Safe.t() | iodata() | nil
  def chrome(assigns) do
    case module() do
      nil -> nil
      mod -> if function_exported?(mod, :chrome, 1), do: mod.chrome(assigns), else: nil
    end
  end

  @doc "The layout's `style/0` CSS, or `nil`."
  @spec style() :: String.t() | nil
  def style do
    case module() do
      nil -> nil
      mod -> if function_exported?(mod, :style, 0), do: mod.style(), else: nil
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
