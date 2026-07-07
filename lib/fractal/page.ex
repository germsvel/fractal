defmodule Fractal.Page do
  @moduledoc """
  The core Fractal primitive: a page is one module that declares its
  routes and handles them — including form submissions for the full
  create/update/destroy lifecycle.

      defmodule MyApp.Pages.About do
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
    * `:title` (optional) — the page title used in the document. Defaults
      to a humanized version of the module name.
    * `:post` (optional) — a POST route handled by this same module's
      `handle_post/1`.
    * `:put` (optional) — an update route handled by `handle_put/1`.
      Matches both PUT and PATCH requests.
    * `:delete` (optional) — a destroy route handled by `handle_delete/1`.
    * `:events` (optional) — the interactive events this page handles
      with `handle_event/2`. See `Fractal.Interactive`.
    * `:watch` (optional) — the server-push topics this page handles
      with `handle_watch/2`. See the "Server push" section below.
    * `:require` (optional) — a guard name (or list of them) that must
      pass before this page renders or handles anything, including
      events and watch subscriptions. Guards are defined once, in the
      app's checkpoint module. See `Fractal.Checkpoint`.

  ## Styles

  A page optionally implements `style/0`, returning plain CSS for this
  page only:

      @impl Fractal.Page
      def style do
        \"\"\"
        .plans { display: grid; gap: 1rem; }
        h2 { color: var(--accent); }
        \"\"\"
      end

  Styles are collected into the app stylesheet automatically and scoped
  to the page (they cannot affect other pages). Shared design tokens
  live in `assets/app.css`. See `Fractal.Assets` and the assets guide
  in `mix fractal.ai.docs`.

  Shared markup belongs in components — one-file modules rendered with
  the imported `component/2` helper. Check `/fractal/components` (dev)
  or `mix fractal.ai.docs` for the existing vocabulary before creating
  one. See `Fractal.Component`.

  ## Head data

  A page optionally implements `meta/1` — its search/link-preview data,
  computed from the same assigns as `render/1`. Data in, framework
  renders and escapes into the `<head>`; pages never write head markup:

      @impl Fractal.Page
      def meta(assigns) do
        %{
          description: excerpt(assigns.params["id"]),
          canonical: "/posts/\#{assigns.params["id"]}",
          og: %{title: "My post", image: asset_path("cover.png")},
          extra: [{:link, [rel: "alternate", type: "application/rss+xml", href: "/feed"]}]
        }
      end

  Known keys: `:description` (falls back to the layout's site
  description), `:canonical`, `:robots`, `:og` (title/description/
  image/url/type — og tags render only when `:og` is present; missing
  subkeys get sensible defaults), and `:extra` (a bounded generic tail
  of `{:meta, attrs}`/`{:link, attrs}` entries — data, never markup;
  script-shaped entries are rejected by verification). Like `render/1`,
  `meta/1` must tolerate empty assigns. There is no `meta:` option on
  `use Fractal.Page` — a static map is a one-line callback.

  Each action option keeps a form and the action it submits to in one
  file. Declaring an action route without defining its handler (or vice
  versa) is a compile-time error — the same goes for `:events` and
  `handle_event/2`.

  ## Form submissions

      defmodule MyApp.Pages.EditPost do
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
          post = MyApp.Repo.get(MyApp.Post, assigns.params["id"])

          case MyApp.Repo.update(MyApp.Post.changeset(post, assigns.params)) do
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
  level → message the document shows once on the next page load). They
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
    * `:context` — request-scoped derivations (e.g. the current user)
      from the checkpoint module's `context/1`; empty when none is defined
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

  ## Server push

  Events are the client→server direction; `watch:` is the reverse. A
  page declares path-shaped topics and handles them with
  `handle_watch/2`; any code rings the doorbell with `publish/1`:

      use Fractal.Page, path: "/rooms/:id", watch: ["rooms/:id/messages"]

      @impl Fractal.Page
      def handle_watch("rooms/:id/messages", assigns) do
        {:fragment, messages_region(assigns.params["id"])}
      end

  Browsers on the page hold one server-sent-events connection (opened by
  the injected runtime — no user JavaScript); when the topic fires, the
  handler re-renders and the fragment replaces the element matching its
  root `id`. Two rules, both compile-checked: a watched topic's `:name`
  segments must bind from the page's own path params, and there are no
  wildcards — publish a broader topic instead. `publish/1` carries no
  payload; handlers re-query the database, which is why a dropped
  connection self-heals on reconnect. See the push guide in
  `mix fractal.ai.docs`.

  `use Fractal.Page` imports `Fractal.HTML` and `Fractal.Interactive`,
  so `tag/3`, `raw/1`, `fx/2`, `trigger/3`, `publish/1`, and friends
  are available directly.
  """

  @callback path() :: String.t()
  @callback title() :: String.t()
  @callback post_path() :: String.t() | nil
  @callback put_path() :: String.t() | nil
  @callback delete_path() :: String.t() | nil
  @callback events() :: [String.t()]
  @callback watches() :: [String.t()]
  @callback style() :: String.t()
  @callback requires() :: [atom()]
  @callback meta(assigns :: map()) :: map()
  @callback render(assigns :: map()) :: Fractal.HTML.Safe.t() | iodata()
  @callback handle_post(assigns :: map()) :: {:redirect, String.t()} | {:render, map()}
  @callback handle_put(assigns :: map()) :: {:redirect, String.t()} | {:render, map()}
  @callback handle_delete(assigns :: map()) :: {:redirect, String.t()} | {:render, map()}
  @callback handle_event(event :: String.t(), assigns :: map()) ::
              {:fragment, Fractal.HTML.Safe.t() | iodata()} | {:redirect, String.t()}
  @callback handle_watch(topic :: String.t(), assigns :: map()) ::
              {:fragment, Fractal.HTML.Safe.t() | iodata()} | {:redirect, String.t()}

  @optional_callbacks post_path: 0,
                      put_path: 0,
                      delete_path: 0,
                      events: 0,
                      watches: 0,
                      style: 0,
                      requires: 0,
                      meta: 1,
                      handle_post: 1,
                      handle_put: 1,
                      handle_delete: 1,
                      handle_event: 2,
                      handle_watch: 2

  @actions [:post, :put, :delete]

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Fractal.Page
      import Fractal.HTML
      import Fractal.Interactive
      import Fractal.Assets, only: [asset_path: 1]
      import Fractal.Component, only: [component: 1, component: 2]

      @fractal_page_path Keyword.get(opts, :path)
      @fractal_page_title Keyword.get(opts, :title)
      @fractal_page_post Keyword.get(opts, :post)
      @fractal_page_put Keyword.get(opts, :put)
      @fractal_page_delete Keyword.get(opts, :delete)
      @fractal_page_events Keyword.get(opts, :events, [])
      @fractal_page_watches Keyword.get(opts, :watch, [])
      @fractal_page_requires opts |> Keyword.get(:require, []) |> List.wrap()
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
    watches = Module.get_attribute(env.module, :fractal_page_watches)
    requires = Module.get_attribute(env.module, :fractal_page_requires)

    validate_path!(env.module, path)
    validate_requires!(env.module, requires)

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
    validate_watches!(env.module, path, watches, Module.defines?(env.module, {:handle_watch, 2}))

    title = title || default_title(env.module)

    quote bind_quoted: [
            path: path,
            title: title,
            actions: actions,
            events: events,
            watches: watches,
            requires: requires
          ] do
      @impl Fractal.Page
      def path, do: unquote(path)

      @impl Fractal.Page
      def title, do: unquote(title)

      @impl Fractal.Page
      def events, do: unquote(events)

      @impl Fractal.Page
      def watches, do: unquote(watches)

      @impl Fractal.Page
      def requires, do: unquote(requires)

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

  @doc false
  def validate_watches!(module, path, watches, defines_handler?) do
    path_params = if route?(path), do: params(path), else: []

    cond do
      not valid_watches?(watches) ->
        raise ArgumentError,
              "#{inspect(module)} has invalid watch topics #{inspect(watches)} — " <>
                "watch: must be a list of unique, path-shaped topics like " <>
                "\"rooms/:id/messages\" (no leading slash, no wildcards)"

      watches != [] and not defines_handler? ->
        raise ArgumentError,
              "#{inspect(module)} declares watch: #{inspect(watches)} but does not " <>
                "define handle_watch/2"

      watches == [] and defines_handler? ->
        raise ArgumentError,
              "#{inspect(module)} defines handle_watch/2 but does not declare its " <>
                "topics: use Fractal.Page, path: ..., watch: [\"example/topic\"]"

      unbound_topic_params(watches, path_params) != [] ->
        unbound = unbound_topic_params(watches, path_params)

        raise ArgumentError,
              "#{inspect(module)} watches topics with params #{inspect(unbound)} that its " <>
                "path #{inspect(path)} does not bind — a watched topic's :name segments " <>
                "must all come from the page's own path params"

      true ->
        :ok
    end
  end

  @doc "Returns `true` if `watches` is a valid watch declaration."
  @spec valid_watches?(term()) :: boolean()
  def valid_watches?(watches) do
    is_list(watches) and
      Enum.all?(watches, &Fractal.Bus.valid_topic?/1) and
      Enum.uniq(watches) == watches
  end

  @doc "Returns the watch topics `module` declares (works for any page)."
  @spec watches(module()) :: [String.t()]
  def watches(module) do
    if function_exported?(module, :watches, 0), do: module.watches(), else: []
  end

  defp unbound_topic_params(watches, path_params) do
    watches
    |> Enum.filter(&Fractal.Bus.valid_topic?/1)
    |> Enum.flat_map(&Fractal.Bus.topic_params/1)
    |> Enum.uniq()
    |> Kernel.--(path_params)
  end

  @doc false
  def validate_requires!(module, requires) do
    valid? =
      is_list(requires) and
        Enum.all?(requires, &(is_atom(&1) and not is_nil(&1) and not is_boolean(&1))) and
        Enum.uniq(requires) == requires

    unless valid? do
      raise ArgumentError,
            "#{inspect(module)} has an invalid require: #{inspect(requires)} — " <>
              "it must be a guard name or a list of unique guard names (atoms)"
    end
  end

  @doc "Returns the guards `module` requires (works for any page)."
  @spec requires(module()) :: [atom()]
  def requires(module) do
    if function_exported?(module, :requires, 0), do: module.requires(), else: []
  end

  @doc "Returns the page's `meta/1` head data for `assigns`, or `%{}`."
  @spec meta(module(), map()) :: map()
  def meta(module, assigns) do
    if function_exported?(module, :meta, 1), do: module.meta(assigns), else: %{}
  end

  @doc "Returns the page's `style/0` CSS, or `nil` (works for any page)."
  @spec style(module()) :: String.t() | nil
  def style(module) do
    if function_exported?(module, :style, 0), do: module.style(), else: nil
  end

  @doc """
  The page's slug, used to scope its styles (`data-page` attribute).

      iex> Fractal.Page.slug(MyApp.Pages.NewPost)
      "new-post"
  """
  @spec slug(module()) :: String.t()
  def slug(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", "-")
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

  @doc false
  # `match/2` for pre-split patterns — the route table splits once at
  # build time instead of per request
  def match_segments(pattern_segments, path_segments) do
    do_match(pattern_segments, path_segments, %{})
  end

  @doc "The number of dynamic (`:name`) segments in a route pattern."
  @spec param_count(String.t()) :: non_neg_integer()
  def param_count(pattern) do
    Enum.count(segments(pattern), &String.starts_with?(&1, ":"))
  end

  @doc "The names of the dynamic (`:name`) segments in a route pattern."
  @spec params(String.t()) :: [String.t()]
  def params(pattern) do
    for ":" <> name <- segments(pattern), do: name
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
