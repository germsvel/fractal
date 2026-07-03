defmodule Fractal.Page do
  @moduledoc """
  The core Fractal primitive: a page is one module that declares its
  routes and handles them — including form submissions for the full
  create/update/destroy lifecycle.

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
      `handle_post/1`.
    * `:put` (optional) — an update route handled by `handle_put/1`.
      Matches both PUT and PATCH requests.
    * `:delete` (optional) — a destroy route handled by `handle_delete/1`.
    * `:events` (optional) — the interactive events this page handles
      with `handle_event/2`. See `Fractal.Interactive`.

  Each action option keeps a form and the action it submits to in one
  file. Declaring an action route without defining its handler (or vice
  versa) is a compile-time error — the same goes for `:events` and
  `handle_event/2`.

  ## Form submissions

      defmodule Fractal.Pages.EditPost do
        use Fractal.Page,
          path: "/posts/:id/edit",
          title: "Edit post",
          put: "/posts/:id",
          delete: "/posts/:id"

        @impl Fractal.Page
        def render(assigns) do
          # ... render the edit form and a delete button (see Fractal.Form) ...
        end

        @impl Fractal.Page
        def handle_put(assigns) do
          post = Fractal.Repo.get(Fractal.Post, assigns.params["id"])

          case Fractal.Repo.update(Fractal.Post.changeset(post, assigns.params)) do
            {:ok, post} -> {:redirect, "/posts/\#{post.id}"}
            {:error, changeset} -> {:render, %{changeset: changeset}}
          end
        end

        @impl Fractal.Page
        def handle_delete(assigns) do
          # ... delete, then ...
          {:redirect, "/posts"}
        end
      end

  Every handler must return:

    * `{:redirect, to}` — respond 303 and send the browser to `to`
    * `{:render, extra_assigns}` — re-render this page's `render/1` with
      `extra_assigns` merged in (how validation errors round-trip)

  ## Sessions

  The session is an encrypted cookie — the server stays stateless.
  Read it via `assigns.session` (a string-keyed map, like params).
  Write it declaratively, by appending directives to any handler
  result — never by touching the conn:

      {:redirect, "/dashboard", session: %{"user_id" => user.id}}
      {:redirect, "/", clear_session: true}                # logout
      {:redirect, "/posts", flash: %{"info" => "Saved."}}  # one-shot banner

  Directives: `session:` (map merged into the session),
  `clear_session: true` (empties it first), and `flash:` (a map of
  level → message the layout shows once on the next page load). They
  compose with `{:render, ...}` and `{:fragment, ...}` too. Keep the
  session for identity-scale data — it lives in a ~4KB cookie; app
  state belongs in the database or in the DOM (event `values:`).

  Browsers only submit GET and POST forms, so PUT/PATCH/DELETE arrive as
  a POST carrying a hidden `_method` field — `Fractal.Form.form_for/4`
  with `method: :put` and `Fractal.Form.button_to/3` emit it, and the
  router rewrites the method before dispatching. Native PUT/PATCH/DELETE
  requests work too.

  ## Assigns

  `render/1` and the `handle_*/1` callbacks receive a map with:

    * `:params` — merged path, query, and (for non-GET) body parameters,
      all string-keyed
    * `:session` — the session, a string-keyed map
    * `:path` — the request path
    * `:conn` — the raw `Plug.Conn` (or `nil` outside a request, e.g.
      during verification — `render/1` must not crash when params and
      session are empty)

  ## Interactive events

  Pages declare interactive events with `events:` and handle them with
  `handle_event/2`, which receives the event name and the usual assigns
  and returns `{:fragment, content}` (swapped into the trigger's target
  element) or `{:redirect, to}` (the browser navigates). See
  `Fractal.Interactive` for the full model.

  `use Fractal.Page` imports `Fractal.HTML` and `Fractal.Interactive`,
  so `tag/3`, `raw/1`, `fx/2`, `trigger/3`, and friends are available
  directly.
  """

  @callback path() :: String.t()
  @callback title() :: String.t()
  @callback post_path() :: String.t() | nil
  @callback put_path() :: String.t() | nil
  @callback delete_path() :: String.t() | nil
  @callback events() :: [String.t()]
  @callback render(assigns :: map()) :: Fractal.HTML.Safe.t() | iodata()
  @callback handle_post(assigns :: map()) :: {:redirect, String.t()} | {:render, map()}
  @callback handle_put(assigns :: map()) :: {:redirect, String.t()} | {:render, map()}
  @callback handle_delete(assigns :: map()) :: {:redirect, String.t()} | {:render, map()}
  @callback handle_event(event :: String.t(), assigns :: map()) ::
              {:fragment, Fractal.HTML.Safe.t() | iodata()} | {:redirect, String.t()}

  @optional_callbacks post_path: 0,
                      put_path: 0,
                      delete_path: 0,
                      events: 0,
                      handle_post: 1,
                      handle_put: 1,
                      handle_delete: 1,
                      handle_event: 2

  @actions [:post, :put, :delete]

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Fractal.Page
      import Fractal.HTML
      import Fractal.Interactive

      @fractal_page_path Keyword.get(opts, :path)
      @fractal_page_title Keyword.get(opts, :title)
      @fractal_page_post Keyword.get(opts, :post)
      @fractal_page_put Keyword.get(opts, :put)
      @fractal_page_delete Keyword.get(opts, :delete)
      @fractal_page_events Keyword.get(opts, :events, [])
      @before_compile Fractal.Page
    end
  end

  defmacro __before_compile__(env) do
    path = Module.get_attribute(env.module, :fractal_page_path)
    title = Module.get_attribute(env.module, :fractal_page_title)

    actions =
      for action <- @actions do
        {action, Module.get_attribute(env.module, :"fractal_page_#{action}")}
      end

    events = Module.get_attribute(env.module, :fractal_page_events)

    validate_path!(env.module, path)

    for {action, route} <- actions do
      if route, do: validate_action_route!(env.module, action, route)

      validate_handler!(
        env.module,
        action,
        route,
        Module.defines?(env.module, {:"handle_#{action}", 1})
      )
    end

    validate_events!(env.module, events, Module.defines?(env.module, {:handle_event, 2}))

    title = title || default_title(env.module)

    quote bind_quoted: [path: path, title: title, actions: actions, events: events] do
      @impl Fractal.Page
      def path, do: unquote(path)

      @impl Fractal.Page
      def title, do: unquote(title)

      @impl Fractal.Page
      def events, do: unquote(events)

      for {action, route} <- actions do
        @impl Fractal.Page
        def unquote(:"#{action}_path")(), do: unquote(route)
      end
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
  def validate_action_route!(module, action, route) do
    unless route?(route) do
      raise ArgumentError,
            "#{inspect(module)} has an invalid #{action} route #{inspect(route)} — " <>
              "it must be a string starting with \"/\" with segments like " <>
              "\"posts\" or \":id\""
    end
  end

  @doc false
  def validate_handler!(module, action, route, defines_handler?) do
    handler = "handle_#{action}/1"

    cond do
      route && not defines_handler? ->
        raise ArgumentError,
              "#{inspect(module)} declares #{action}: #{inspect(route)} but does not " <>
                "define #{handler}"

      is_nil(route) && defines_handler? ->
        raise ArgumentError,
              "#{inspect(module)} defines #{handler} but does not declare a " <>
                "#{action} route: use Fractal.Page, path: ..., #{action}: \"/example\""

      true ->
        :ok
    end
  end

  @doc false
  def validate_events!(module, events, defines_handler?) do
    cond do
      not valid_events?(events) ->
        raise ArgumentError,
              "#{inspect(module)} has invalid events #{inspect(events)} — " <>
                "events must be a list of unique, non-empty strings"

      events != [] and not defines_handler? ->
        raise ArgumentError,
              "#{inspect(module)} declares events: #{inspect(events)} but does not " <>
                "define handle_event/2"

      events == [] and defines_handler? ->
        raise ArgumentError,
              "#{inspect(module)} defines handle_event/2 but does not declare its " <>
                "events: use Fractal.Page, path: ..., events: [\"example\"]"

      true ->
        :ok
    end
  end

  @doc "Returns `true` if `events` is a valid event declaration."
  @spec valid_events?(term()) :: boolean()
  def valid_events?(events) do
    is_list(events) and
      Enum.all?(events, &(is_binary(&1) and &1 != "")) and
      Enum.uniq(events) == events
  end

  @doc "Returns the events `module` declares (works for any page)."
  @spec events(module()) :: [String.t()]
  def events(module) do
    if function_exported?(module, :events, 0), do: module.events(), else: []
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

  @doc "The actions a page can declare besides GET: `#{inspect(@actions)}`."
  @spec actions() :: [atom()]
  def actions, do: @actions

  @doc """
  Returns the route `module` declares for `action`, or `nil`.

  Works for any page, including ones that predate an action's existence.
  """
  @spec action_route(module(), atom()) :: String.t() | nil
  def action_route(module, action) when action in @actions do
    fun = :"#{action}_path"
    if function_exported?(module, fun, 0), do: apply(module, fun, []), else: nil
  end

  @doc "Returns the post route of `module`, or `nil` (works for any page)."
  @spec post_path(module()) :: String.t() | nil
  def post_path(module), do: action_route(module, :post)

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
