defmodule Fractal.Page do
  @moduledoc """
  The core Fractal primitive: a page is one module that declares its
  routes and handles them — including form submissions.

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

    * `:path` (required) — the GET route, a string starting with `/`.
      Segments may be dynamic: `"/posts/:id"` binds `params["id"]`.
      Validated at compile time.
    * `:title` (optional) — the page title used in the layout. Defaults
      to a humanized version of the module name.
    * `:post` (optional) — a POST route handled by this same module's
      `handle_post/1`. This keeps a form and the action it submits to in
      one file. Declaring `:post` without defining `handle_post/1` (or
      vice versa) is a compile-time error.

  ## Form submissions

      defmodule Fractal.Pages.NewPost do
        use Fractal.Page, path: "/posts/new", title: "New post", post: "/posts"

        @impl Fractal.Page
        def render(assigns) do
          changeset = assigns[:changeset] || Fractal.Post.changeset(%Fractal.Post{}, %{})
          # ... render the form (see Fractal.Form) ...
        end

        @impl Fractal.Page
        def handle_post(assigns) do
          case Fractal.Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, assigns.params)) do
            {:ok, post} -> {:redirect, "/posts/\#{post.id}"}
            {:error, changeset} -> {:render, %{changeset: changeset}}
          end
        end
      end

  `handle_post/1` must return:

    * `{:redirect, to}` — respond 303 and send the browser to `to`
    * `{:render, extra_assigns}` — re-render this page's `render/1` with
      `extra_assigns` merged in (how validation errors round-trip)

  ## Assigns

  `render/1` and `handle_post/1` receive a map with:

    * `:params` — merged path, query, and (for POST) body parameters,
      all string-keyed
    * `:path` — the request path
    * `:conn` — the raw `Plug.Conn` (or `nil` outside a request, e.g.
      during verification — `render/1` must not crash when params are
      empty)

  `use Fractal.Page` imports `Fractal.HTML`, so `tag/3`, `raw/1`, and
  friends are available directly.
  """

  @callback path() :: String.t()
  @callback title() :: String.t()
  @callback post_path() :: String.t() | nil
  @callback render(assigns :: map()) :: Fractal.HTML.Safe.t() | iodata()
  @callback handle_post(assigns :: map()) ::
              {:redirect, String.t()} | {:render, map()}

  @optional_callbacks post_path: 0, handle_post: 1

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Fractal.Page
      import Fractal.HTML

      @fractal_page_path Keyword.get(opts, :path)
      @fractal_page_title Keyword.get(opts, :title)
      @fractal_page_post Keyword.get(opts, :post)
      @before_compile Fractal.Page
    end
  end

  defmacro __before_compile__(env) do
    path = Module.get_attribute(env.module, :fractal_page_path)
    title = Module.get_attribute(env.module, :fractal_page_title)
    post = Module.get_attribute(env.module, :fractal_page_post)

    validate_path!(env.module, path)
    if post, do: validate_post!(env.module, post)
    validate_handle_post!(env.module, post, Module.defines?(env.module, {:handle_post, 1}))

    title = title || default_title(env.module)

    quote do
      @impl Fractal.Page
      def path, do: unquote(path)

      @impl Fractal.Page
      def title, do: unquote(title)

      @impl Fractal.Page
      def post_path, do: unquote(post)
    end
  end

  @doc false
  def validate_path!(module, path) do
    cond do
      is_nil(path) ->
        raise ArgumentError,
              "#{inspect(module)} must declare a route: use Fractal.Page, path: \"/example\""

      not route?(path) ->
        raise ArgumentError,
              "#{inspect(module)} has an invalid path #{inspect(path)} — " <>
                "it must be a string starting with \"/\" with segments like " <>
                "\"about\" or \":id\""

      true ->
        :ok
    end
  end

  @doc false
  def validate_post!(module, post) do
    unless route?(post) do
      raise ArgumentError,
            "#{inspect(module)} has an invalid post route #{inspect(post)} — " <>
              "it must be a string starting with \"/\" with segments like " <>
              "\"posts\" or \":id\""
    end
  end

  @doc false
  def validate_handle_post!(module, post, defines_handle_post?) do
    cond do
      post && not defines_handle_post? ->
        raise ArgumentError,
              "#{inspect(module)} declares post: #{inspect(post)} but does not " <>
                "define handle_post/1"

      is_nil(post) && defines_handle_post? ->
        raise ArgumentError,
              "#{inspect(module)} defines handle_post/1 but does not declare a " <>
                "post route: use Fractal.Page, path: ..., post: \"/example\""

      true ->
        :ok
    end
  end

  @doc "Returns `true` if `route` is a well-formed route pattern."
  @spec route?(term()) :: boolean()
  def route?(route) do
    is_binary(route) and String.starts_with?(route, "/") and
      Enum.all?(segments(route), &valid_segment?/1)
  end

  @doc """
  Matches a route pattern against request path segments.

  Returns `{:ok, params}` binding `:name` segments, or `:error`.

      iex> Fractal.Page.match("/posts/:id", ["posts", "42"])
      {:ok, %{"id" => "42"}}
  """
  @spec match(String.t(), [String.t()]) :: {:ok, map()} | :error
  def match(pattern, path_segments) do
    do_match(segments(pattern), path_segments, %{})
  end

  @doc "The number of dynamic (`:name`) segments in a route pattern."
  @spec param_count(String.t()) :: non_neg_integer()
  def param_count(pattern) do
    Enum.count(segments(pattern), &String.starts_with?(&1, ":"))
  end

  @doc "Returns the post route of `module`, or `nil` (works for any page)."
  @spec post_path(module()) :: String.t() | nil
  def post_path(module) do
    if function_exported?(module, :post_path, 0), do: module.post_path(), else: nil
  end

  @doc "Returns `true` if `module` is a compiled Fractal page."
  @spec page?(module()) :: boolean()
  def page?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :path, 0) and
      function_exported?(module, :render, 1) and
      __MODULE__ in behaviours(module)
  end

  defp do_match([], [], params), do: {:ok, params}

  defp do_match([pattern | pattern_rest], [segment | segment_rest], params) do
    cond do
      String.starts_with?(pattern, ":") ->
        do_match(
          pattern_rest,
          segment_rest,
          Map.put(params, String.slice(pattern, 1..-1//1), segment)
        )

      pattern == segment ->
        do_match(pattern_rest, segment_rest, params)

      true ->
        :error
    end
  end

  defp do_match(_pattern, _segments, _params), do: :error

  defp segments(route), do: route |> String.split("/") |> Enum.reject(&(&1 == ""))

  defp valid_segment?(":" <> name), do: name =~ ~r/^[a-z_][a-zA-Z0-9_]*$/
  defp valid_segment?(segment), do: segment =~ ~r/^[a-zA-Z0-9._~-]+$/

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
