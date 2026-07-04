defmodule Fractal.Router do
  @moduledoc """
  Fractal's auto-discovering router.

  There is no route table to maintain: on each request the router matches
  the request against the routes every page module declares — `path/0`
  for GET, `post_path/0` for POST, `put_path/0` for PUT/PATCH, and
  `delete_path/0` for DELETE. A POST carrying a hidden `_method` field
  (emitted by `Fractal.Form`) is rewritten to that method before
  dispatch, since browsers only submit GET and POST forms. Route
  patterns may contain dynamic segments (`"/posts/:id"`), which are
  bound into `assigns.params`. Static segments win over dynamic ones
  when both match. New page modules are picked up as soon as they are
  compiled, which is what makes the development loop (agent writes a
  page → watcher recompiles → browser reloads) work without restarts.

  ## Sessions and CSRF

  Every page request runs through the session (an encrypted cookie —
  the server stays stateless) and CSRF protection. Pages read
  `assigns.session` and write it through result directives (see
  `Fractal.Page`); the router applies those directives to the response.
  State-changing requests (POST/PUT/PATCH/DELETE and interactive
  events) must carry the CSRF token that `Fractal.Form` and the
  interactivity runtime attach automatically — a request without one is
  rejected with a 403 explaining the convention.

  ## Guards and context

  Pages declaring `require:` have their guards run before `render/1`,
  every `handle_*/1`, and every interactive event — a denied request
  gets the guard's redirect (see `Fractal.Checkpoint`). Every request's
  assigns carry `:context`, derived once by the checkpoint module's
  `context/1`. Responses carry secure default headers, overridable via
  `config :fractal, :response_headers`. The router emits
  `[:fractal, :request, :stop]` telemetry (and `Fractal.Checkpoint` emits
  `[:fractal, :checkpoint, :denied]`).

  Interactive events (see `Fractal.Interactive`) arrive as
  `POST /fractal/event` with `_fx_path` (the page's location) and
  `_fx_event`; the router dispatches them to the page's
  `handle_event/2` and responds with the HTML fragment (or an
  `fx-redirect` header).

  The router also serves `GET /fractal/reload`, the live-reload token
  endpoint polled by the script `Fractal.Layout` injects in development.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Fractal.{Checkpoint, HTML, Layout, LiveReload, Page}

  @parsers_opts Plug.Parsers.init(parsers: [:urlencoded, :multipart], pass: ["*/*"])
  @static_opts Plug.Static.init(
                 at: "/assets",
                 from: "assets/static",
                 cache_control_for_vsn_requests: "public, max-age=31536000, immutable"
               )
  @method_override_opts Plug.MethodOverride.init([])
  @csrf_opts Plug.CSRFProtection.init([])
  @session_opts Plug.Session.init(
                  store: :cookie,
                  key: "_fractal_session",
                  encryption_salt: "fractal session encryption",
                  signing_salt: "fractal session signing",
                  same_site: "Lax"
                )

  @methods %{"POST" => :post, "PUT" => :put, "PATCH" => :put, "DELETE" => :delete}

  # merged with (and overridable by) config :fractal, :response_headers
  @default_headers %{
    "x-content-type-options" => "nosniff",
    "x-frame-options" => "SAMEORIGIN",
    "referrer-policy" => "strict-origin-when-cross-origin"
  }

  @flash_key "_fractal_flash"
  @directives [:session, :clear_session, :flash]

  @csrf_message """
  CSRF token missing or invalid.

  Fractal attaches CSRF tokens automatically — you never handle them
  yourself. Build forms with Fractal.Form (form_for/4, button_to/3) and
  interactions with trigger/3 or fx/2; hand-written <form> tags and raw
  fetch calls are not supported. In tests, use the Fractal.Test helpers.
  See `mix fractal.ai.docs` for the conventions.
  """

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    start = System.monotonic_time()
    conn = conn |> put_default_headers() |> dispatch(opts)

    :telemetry.execute(
      [:fractal, :request, :stop],
      %{duration: System.monotonic_time() - start},
      %{method: conn.method, path: conn.request_path, status: conn.status}
    )

    conn
  end

  defp put_default_headers(conn) do
    @default_headers
    |> Map.merge(Application.get_env(:fractal, :response_headers, %{}))
    |> Enum.reduce(conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)
  end

  defp dispatch(%Plug.Conn{method: "GET", path_info: ["fractal", "reload"]} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, ~s({"token":#{LiveReload.token()}}))
  end

  # the CSS bundle: assets/app.css + every page's scoped style/0
  defp dispatch(%Plug.Conn{method: "GET", path_info: ["fractal", "assets", name]} = conn, _opts) do
    if String.ends_with?(name, ".css") do
      {_hash, css} = Fractal.Assets.css_bundle()

      conn
      |> put_resp_content_type("text/css")
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_resp(200, css)
    else
      not_found(conn, current_path(conn))
    end
  end

  # the component gallery — development only
  defp dispatch(%Plug.Conn{method: "GET", path_info: ["fractal", "components"]} = conn, _opts) do
    if dev_mode?() do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, Layout.shell("Components", Fractal.Component.gallery()))
    else
      not_found(conn, current_path(conn))
    end
  end

  # files under assets/static/, referenced via Fractal.Assets.asset_path/1
  defp dispatch(%Plug.Conn{method: "GET", path_info: ["assets" | _rest]} = conn, _opts) do
    conn = Plug.Static.call(conn, @static_opts)

    if conn.halted do
      conn
    else
      not_found(conn, current_path(conn))
    end
  end

  defp dispatch(%Plug.Conn{method: "GET"} = conn, _opts) do
    # the CSRF plug only seeds the token on GET (it can still reject
    # cross-origin JavaScript requests)
    case conn |> fetch_query_params() |> session_pipeline() do
      {:ok, conn} ->
        case find_route(:get, conn.path_info) do
          {page, path_params} -> render_page(conn, page, path_params)
          nil -> not_found(conn, current_path(conn))
        end

      {:forbidden, conn} ->
        event_error(conn, 403, @csrf_message)
    end
  end

  defp dispatch(%Plug.Conn{method: "POST", path_info: ["fractal", "event"]} = conn, _opts) do
    conn = conn |> Plug.Parsers.call(@parsers_opts) |> fetch_query_params()

    case session_pipeline(conn) do
      {:ok, conn} -> dispatch_event(conn)
      {:forbidden, conn} -> event_error(conn, 403, @csrf_message)
    end
  end

  defp dispatch(%Plug.Conn{method: method} = conn, _opts)
       when method in ["POST", "PUT", "PATCH", "DELETE"] do
    # parse the body first: a POST may carry a hidden _method field that
    # rewrites it to PUT/PATCH/DELETE
    conn =
      conn
      |> Plug.Parsers.call(@parsers_opts)
      |> Plug.MethodOverride.call(@method_override_opts)
      |> fetch_query_params()

    case session_pipeline(conn) do
      {:ok, conn} ->
        action = Map.fetch!(@methods, conn.method)

        case find_route(action, conn.path_info) do
          {page, path_params} -> handle_action(conn, page, action, path_params)
          nil -> not_found(conn, current_path(conn))
        end

      {:forbidden, conn} ->
        event_error(conn, 403, @csrf_message)
    end
  end

  defp dispatch(conn, _opts), do: not_found(conn, current_path(conn))

  @doc "All discovered page modules, sorted by path."
  @spec pages() :: [module()]
  def pages do
    candidate_modules()
    |> Enum.filter(&Page.page?/1)
    |> Enum.sort_by(& &1.path())
  end

  # Session cookie + CSRF. Conns that already carry a session (from
  # Plug.Test.init_test_session, via Fractal.Test) keep it; real requests
  # get the encrypted cookie store.
  defp session_pipeline(conn) do
    conn =
      if conn.private[:plug_session_fetch] do
        conn
      else
        conn |> put_secret_key_base() |> Plug.Session.call(@session_opts)
      end

    {:ok, conn |> fetch_session() |> Plug.CSRFProtection.call(@csrf_opts)}
  rescue
    _exception in [
      Plug.CSRFProtection.InvalidCSRFTokenError,
      Plug.CSRFProtection.InvalidCrossOriginRequestError
    ] ->
      {:forbidden, conn}
  end

  defp put_secret_key_base(conn) do
    case Application.get_env(:fractal, :secret_key_base) do
      nil ->
        raise "config :fractal, :secret_key_base is not set — sessions need it. " <>
                "Generate one with `mix fractal.gen.secret` and add it to your config."

      secret ->
        %{conn | secret_key_base: secret}
    end
  end

  defp dispatch_event(conn) do
    path = conn.params["_fx_path"] || ""
    event = conn.params["_fx_event"] || ""
    segments = path |> String.split("/") |> Enum.reject(&(&1 == ""))

    case find_route(:get, segments) do
      {page, path_params} ->
        if event in Page.events(page) do
          handle_event(conn, page, event, path_params)
        else
          event_error(
            conn,
            404,
            "#{inspect(page)} (at #{path}) does not declare the event #{inspect(event)} — " <>
              "its events are #{inspect(Page.events(page))}"
          )
        end

      nil ->
        event_error(conn, 404, "no page found at #{inspect(path)}")
    end
  end

  defp find_route(method, path_segments) do
    pages()
    |> Enum.flat_map(fn page ->
      case route_pattern(page, method) do
        nil -> []
        pattern -> [{page, pattern}]
      end
    end)
    # static routes take precedence over ones with dynamic segments
    |> Enum.sort_by(fn {_page, pattern} -> Page.param_count(pattern) end)
    |> Enum.find_value(fn {page, pattern} ->
      case Page.match(pattern, path_segments) do
        {:ok, params} -> {page, params}
        :error -> nil
      end
    end)
  end

  defp route_pattern(page, :get), do: page.path()
  defp route_pattern(page, action), do: Page.action_route(page, action)

  defp current_path(conn), do: "/" <> Enum.join(conn.path_info, "/")

  defp render_page(conn, page, path_params) do
    {flash, conn} = pop_flash(conn)
    assigns = conn |> build_assigns(path_params) |> Map.put(:flash, flash)

    case Checkpoint.run(Page.requires(page), assigns) do
      :ok ->
        html = Layout.render(page, assigns)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:redirect, to, directives} ->
        conn
        |> apply_directives(directives)
        |> put_resp_header("location", to)
        |> send_resp(303, "")
    end
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      render_error(conn, page, exception, __STACKTRACE__)
  end

  defp handle_action(conn, page, action, path_params) do
    assigns = build_assigns(conn, path_params)

    result =
      case Checkpoint.run(Page.requires(page), assigns) do
        :ok -> apply(page, :"handle_#{action}", [assigns])
        {:redirect, _to, _directives} = denied -> denied
      end

    case normalize_result(page, "handle_#{action}/1", result) do
      {:redirect, to, directives} when is_binary(to) ->
        conn
        |> apply_directives(directives)
        |> put_resp_header("location", to)
        |> send_resp(303, "")

      {:render, extra_assigns, directives} when is_map(extra_assigns) ->
        conn = apply_directives(conn, directives)
        html = Layout.render(page, Map.merge(assigns, extra_assigns))

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)
    end
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      render_error(conn, page, exception, __STACKTRACE__)
  end

  defp handle_event(conn, page, event, path_params) do
    params =
      conn.params
      |> Map.drop(["_fx_path", "_fx_event"])
      |> Map.merge(path_params)

    assigns =
      %{
        conn: conn,
        params: params,
        path: conn.params["_fx_path"],
        event: event,
        session: page_session(conn)
      }
      |> put_context()

    result =
      case Checkpoint.run(Page.requires(page), assigns) do
        :ok -> page.handle_event(event, assigns)
        {:redirect, _to, _directives} = denied -> denied
      end

    case normalize_result(page, "handle_event/2", result) do
      {:fragment, content, directives} ->
        conn
        |> apply_directives(directives)
        |> put_resp_content_type("text/html")
        |> send_resp(200, content |> HTML.to_safe() |> HTML.safe_to_string())

      {:redirect, to, directives} when is_binary(to) ->
        conn
        |> apply_directives(directives)
        |> put_resp_header("fx-redirect", to)
        |> send_resp(204, "")
    end
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))

      detail =
        if dev_mode?(),
          do: "\n" <> Exception.format(:error, exception, __STACKTRACE__),
          else: ""

      event_error(conn, 500, "#{inspect(page)} raised handling #{inspect(event)}#{detail}")
  end

  # Handler results optionally carry response directives:
  #   {:redirect, to, session: %{"user_id" => 1}}
  #   {:redirect, to, clear_session: true}
  #   {:render, extras, flash: %{"info" => "Saved."}}
  defp normalize_result(_page, _fun, {:redirect, to}), do: {:redirect, to, []}
  defp normalize_result(_page, _fun, {:render, extras}), do: {:render, extras, []}
  defp normalize_result(_page, _fun, {:fragment, content}), do: {:fragment, content, []}

  defp normalize_result(_page, _fun, {kind, payload, directives})
       when kind in [:redirect, :render, :fragment] and is_list(directives) do
    case Keyword.keys(directives) -- @directives do
      [] ->
        {kind, payload, directives}

      unknown ->
        raise ArgumentError,
              "unknown result directive(s) #{inspect(unknown)} — supported directives are " <>
                "#{inspect(@directives)}"
    end
  end

  defp normalize_result(page, fun, other) do
    raise ArgumentError,
          "#{inspect(page)}.#{fun} must return {:redirect, to}, {:render, extra_assigns}, " <>
            "or {:fragment, content} (events only), each optionally with directives " <>
            "#{inspect(@directives)}, got: #{inspect(other)}"
  end

  defp apply_directives(conn, []), do: conn

  defp apply_directives(conn, directives) do
    # clear first, so session:/flash: in the same result write onto a
    # blank session (a logout can still set a flash)
    conn = if directives[:clear_session], do: clear_session(conn), else: conn

    conn =
      Enum.reduce(directives[:session] || %{}, conn, fn {key, value}, conn ->
        put_session(conn, to_string(key), value)
      end)

    case directives[:flash] do
      nil -> conn
      flash -> put_session(conn, @flash_key, stringify(flash))
    end
  end

  defp pop_flash(conn) do
    case get_session(conn, @flash_key) do
      nil -> {%{}, conn}
      flash -> {flash, delete_session(conn, @flash_key)}
    end
  end

  defp page_session(conn) do
    conn |> get_session() |> Map.delete(@flash_key)
  end

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp event_error(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end

  defp build_assigns(conn, path_params) do
    %{
      conn: conn,
      params: Map.merge(conn.params, path_params),
      path: current_path(conn),
      session: page_session(conn)
    }
    |> put_context()
  end

  defp put_context(assigns), do: Map.put(assigns, :context, Checkpoint.context(assigns))

  defp render_error(conn, page, exception, stacktrace) do
    details =
      if dev_mode?() do
        HTML.tag(:pre, [], [Exception.format(:error, exception, stacktrace)])
      end

    body =
      HTML.tag(:section, [], [
        HTML.tag(:h1, [], ["500 — page crashed"]),
        HTML.tag(:p, [], [
          HTML.tag(:code, [], [inspect(page)]),
          " raised while handling this request. Fix it and run ",
          HTML.tag(:code, [], ["mix fractal.verify"]),
          "."
        ]),
        details
      ])

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(500, Layout.shell("Error", body))
  end

  defp not_found(conn, path) do
    body =
      HTML.tag(:section, [], [
        HTML.tag(:h1, [], ["404 — no page at ", HTML.tag(:code, [], [path])]),
        HTML.tag(:p, [], [
          "To create it, prompt your agent: ",
          HTML.tag(:code, [], ["Create a Fractal page at #{path}"]),
          " (agents: run ",
          HTML.tag(:code, [], ["mix fractal.ai.docs"]),
          " first)."
        ]),
        HTML.tag(:h2, [], ["Registered pages"]),
        HTML.tag(
          :ul,
          [],
          for page <- pages() do
            HTML.tag(:li, [], [
              HTML.tag(:a, [href: page.path()], [page.title()]),
              " — ",
              HTML.tag(:code, [], [page.path()])
            ])
          end
        )
      ])

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, Layout.shell("Not found", body))
  end

  defp candidate_modules, do: Fractal.Discovery.modules()

  defp dev_mode?, do: Application.get_env(:fractal, :live_reload, false)
end
