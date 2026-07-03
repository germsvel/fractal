defmodule Fractal.Router do
  @moduledoc """
  Fractal's auto-discovering router.

  There is no route table to maintain: on each request the router looks up
  the page module whose `path/0` exactly matches the request path. New page
  modules are picked up as soon as they are compiled, which is what makes
  the development loop (agent writes a page → watcher recompiles → browser
  reloads) work without restarts.

  The router also serves `GET /fractal/reload`, the live-reload token
  endpoint polled by the script `Fractal.Layout` injects in development.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Fractal.{HTML, Layout, LiveReload, Page}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "GET", path_info: ["fractal", "reload"]} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, ~s({"token":#{LiveReload.token()}}))
  end

  def call(conn, _opts) do
    path = current_path(conn)

    case Enum.find(pages(), &(&1.path() == path)) do
      nil -> not_found(conn, path)
      page -> render_page(conn, page, path)
    end
  end

  @doc "All discovered page modules, sorted by path."
  @spec pages() :: [module()]
  def pages do
    candidate_modules()
    |> Enum.filter(&Page.page?/1)
    |> Enum.sort_by(& &1.path())
  end

  defp current_path(conn), do: "/" <> Enum.join(conn.path_info, "/")

  defp render_page(conn, page, path) do
    conn = fetch_query_params(conn)
    assigns = %{conn: conn, params: conn.params, path: path}
    html = Layout.render(page, assigns)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      render_error(conn, page, exception, __STACKTRACE__)
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
          " raised while rendering. Fix its ",
          HTML.tag(:code, [], ["render/1"]),
          " and run ",
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
