defmodule Fractal.Page do
  @moduledoc """
  The core Fractal primitive: a page is one module that declares its route
  and renders its content.

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

  Pages are auto-discovered by `Fractal.Router` — dropping a page module
  under `lib/fractal/pages/` is all it takes to serve a new route. There
  is no router file to edit and no registration step.

  ## Options

    * `:path` (required) — the route, a string starting with `/`.
      Validated at compile time.
    * `:title` (optional) — the page title used in the layout. Defaults
      to a humanized version of the module name.

  ## Assigns

  `render/1` receives a map with:

    * `:params` — merged query parameters (a map of strings)
    * `:path` — the request path
    * `:conn` — the raw `Plug.Conn` (or `nil` outside a request, e.g.
      during verification)

  `use Fractal.Page` imports `Fractal.HTML`, so `tag/3`, `raw/1`, and
  friends are available directly.
  """

  @callback path() :: String.t()
  @callback title() :: String.t()
  @callback render(assigns :: map()) :: Fractal.HTML.Safe.t() | iodata()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Fractal.Page
      import Fractal.HTML

      @fractal_page_path Keyword.get(opts, :path)
      @fractal_page_title Keyword.get(opts, :title)
      @before_compile Fractal.Page
    end
  end

  defmacro __before_compile__(env) do
    path = Module.get_attribute(env.module, :fractal_page_path)
    title = Module.get_attribute(env.module, :fractal_page_title)

    validate_path!(env.module, path)

    title = title || default_title(env.module)

    quote do
      @impl Fractal.Page
      def path, do: unquote(path)

      @impl Fractal.Page
      def title, do: unquote(title)
    end
  end

  @doc false
  def validate_path!(module, path) do
    cond do
      is_nil(path) ->
        raise ArgumentError,
              "#{inspect(module)} must declare a route: use Fractal.Page, path: \"/example\""

      not is_binary(path) or not String.starts_with?(path, "/") ->
        raise ArgumentError,
              "#{inspect(module)} has an invalid path #{inspect(path)} — " <>
                "it must be a string starting with \"/\""

      true ->
        :ok
    end
  end

  @doc "Returns `true` if `module` is a compiled Fractal page."
  @spec page?(module()) :: boolean()
  def page?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :path, 0) and
      function_exported?(module, :render, 1) and
      __MODULE__ in behaviours(module)
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp default_title(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
