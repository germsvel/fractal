defmodule Fractal.Router do
  @moduledoc """
  Fractal's auto-discovering router.

  There is no route table to maintain: on each request the router matches
  the request against the routes every page module declares — `path/0`
  for GET, `post_path/0` for POST. Route patterns may contain dynamic
  segments (`"/posts/:id"`), which are bound into `assigns.params`.
  Static segments win over dynamic ones when both match. New page modules
  are picked up as soon as they are compiled, which is what makes the
  development loop (agent writes a page → watcher recompiles → browser
  reloads) work without restarts.

  The router also serves `GET /fractal/reload`, the live-reload token
  endpoint polled by the script `Fractal.Layout` injects in development.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Fractal.{HTML, Layout, LiveReload, Page}

  @parsers_opts Plug.Parsers.init(parsers: [:urlencoded, :multipart], pass: ["*/*"])

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "GET", path_info: ["fractal", "reload"]} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, ~s({"token":#{LiveReload.token()}}))
  end

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    case find_route(:get, conn.path_info) do
      {page, path_params} -> render_page(conn, page, path_params)
      nil -> not_found(conn, current_path(conn))
    end
  end

  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    case find_route(:post, conn.path_info) do
      {page, path_params} -> handle_post(conn, page, path_params)
      nil -> not_found(conn, current_path(conn))
    end
  end

  def call(conn, _opts), do: not_found(conn, current_path(conn))

  @doc "All discovered page modules, sorted by path."
  @spec pages() :: [module()]
  def pages do
    candidate_modules()
    |> Enum.filter(&Page.page?/1)
    |> Enum.sort_by(& &1.path())
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
  defp route_pattern(page, :post), do: Page.post_path(page)

  defp current_path(conn), do: "/" <> Enum.join(conn.path_info, "/")

  defp render_page(conn, page, path_params) do
    conn = fetch_query_params(conn)
    assigns = build_assigns(conn, path_params)
    html = Layout.render(page, assigns)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      render_error(conn, page, exception, __STACKTRACE__)
  end

  defp handle_post(conn, page, path_params) do
    conn = conn |> Plug.Parsers.call(@parsers_opts) |> fetch_query_params()
    assigns = build_assigns(conn, path_params)

    case page.handle_post(assigns) do
      {:redirect, to} when is_binary(to) ->
        conn
        |> put_resp_header("location", to)
        |> send_resp(303, "")

      {:render, extra_assigns} when is_map(extra_assigns) ->
        html = Layout.render(page, Map.merge(assigns, extra_assigns))

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      other ->
        raise ArgumentError,
              "#{inspect(page)}.handle_post/1 must return {:redirect, to} or " <>
                "{:render, extra_assigns}, got: #{inspect(other)}"
    end
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      render_error(conn, page, exception, __STACKTRACE__)
  end

  defp build_assigns(conn, path_params) do
    %{conn: conn, params: Map.merge(conn.params, path_params), path: current_path(conn)}
  end

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

  # Scans the app's ebin for modules instead of using Application.spec/2 so
  # that pages compiled after boot (by the dev reloader) are still found.
  defp candidate_modules do
    case :code.lib_dir(:fractal) do
      {:error, _reason} ->
        Application.spec(:fractal, :modules) || []

      dir ->
        [List.to_string(dir), "ebin", "*.beam"]
        |> Path.join()
        |> Path.wildcard()
        |> Enum.map(&(&1 |> Path.basename(".beam") |> String.to_atom()))
    end
  end

  defp dev_mode?, do: Application.get_env(:fractal, :live_reload, false)
end
