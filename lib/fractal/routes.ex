defmodule Fractal.Routes do
  @moduledoc false

  # The discovery table: the router's route set plus the other
  # per-request discovery products (the checkpoint and layout modules),
  # built in one pass and cached in :persistent_term for prod-like
  # execution. Not a primitive — an implementation detail of the router
  # and the request path.
  #
  # persistent_term rules this module lives by (from the OTP docs, see
  # project/task16.md):
  #   * one key, one large term — everything under @key; never
  #     per-method or per-page entries
  #   * written at most once per boot: the cache gate
  #     (Fractal.Discovery.cache?/0) is false wherever code or
  #     discovery config can change (dev via live_reload, tests via
  #     config :fractal, cache_discovery: false), so no update — and
  #     therefore no global GC — can ever happen
  #   * readers must use the term transiently: request processes die,
  #     and the SSE loops must not capture it in loop state — a
  #     long-lived holder would be copied wholesale if the term were
  #     ever updated
  #
  # On the live (uncached) path each function computes only the piece
  # it was asked for, matching today's per-request cost — it never
  # builds the whole table per call.

  alias Fractal.Page

  @key {Fractal.Router, :routes}
  @methods [:get, :post, :put, :delete]

  @doc "All discovered page modules, sorted by path."
  def pages do
    case cached() do
      %{pages: pages} -> pages
      nil -> discover_pages()
    end
  end

  @doc "The app's checkpoint module, or nil."
  def checkpoint do
    case cached() do
      %{checkpoint: checkpoint} -> checkpoint
      nil -> Fractal.Checkpoint.modules() |> List.first()
    end
  end

  @doc "The app's layout module, or nil."
  def layout do
    case cached() do
      %{layout: layout} -> layout
      nil -> Fractal.Layout.modules() |> List.first()
    end
  end

  @doc """
  Resolves `path_segments` for `method` to `{page, path_params}`, or
  nil. Same semantics as matching every page's declared route sorted by
  param count: fully-static routes win via exact lookup, then dynamic
  patterns match in param-count order (stable by page path).
  """
  def find(method, path_segments) when method in @methods do
    routes =
      case cached() do
        %{methods: methods} -> methods
        nil -> build_methods(discover_pages())
      end

    %{static: static, dynamic: dynamic} = Map.fetch!(routes, method)

    case static do
      %{^path_segments => page} ->
        {page, %{}}

      _no_exact_match ->
        Enum.find_value(dynamic, fn {pattern_segments, page} ->
          case Page.match_segments(pattern_segments, path_segments) do
            {:ok, params} -> {page, params}
            :error -> nil
          end
        end)
    end
  end

  # -- the table ----------------------------------------------------------

  defp cached do
    if Fractal.Discovery.cache?() do
      case :persistent_term.get(@key, nil) do
        nil ->
          table = build()
          :persistent_term.put(@key, table)
          table

        table ->
          table
      end
    end
  end

  defp build do
    pages = discover_pages()

    %{
      pages: pages,
      methods: build_methods(pages),
      checkpoint: Fractal.Checkpoint.modules() |> List.first(),
      layout: Fractal.Layout.modules() |> List.first()
    }
  end

  defp discover_pages do
    Fractal.Discovery.modules()
    |> Enum.filter(&Page.page?/1)
    |> Enum.sort_by(& &1.path())
  end

  defp build_methods(pages) do
    Map.new(@methods, fn method ->
      # pages order (sorted by path) + stable param-count sort preserves
      # the exact precedence the router has always had
      routes =
        for page <- pages,
            pattern = route_pattern(page, method),
            pattern != nil,
            do: {pattern, page}

      {static, dynamic} =
        Enum.split_with(routes, fn {pattern, _page} -> Page.param_count(pattern) == 0 end)

      static_map =
        Enum.reduce(static, %{}, fn {pattern, page}, acc ->
          # first page wins, as in the sorted scan (duplicates are a
          # verify failure anyway)
          Map.put_new(acc, split(pattern), page)
        end)

      dynamic_list =
        dynamic
        |> Enum.sort_by(fn {pattern, _page} -> Page.param_count(pattern) end)
        |> Enum.map(fn {pattern, page} -> {split(pattern), page} end)

      {method, %{static: static_map, dynamic: dynamic_list}}
    end)
  end

  defp route_pattern(page, :get), do: page.path()
  defp route_pattern(page, action), do: Page.action_route(page, action)

  defp split(pattern), do: pattern |> String.split("/") |> Enum.reject(&(&1 == ""))
end
