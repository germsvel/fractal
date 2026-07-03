defmodule Fractal.Verify do
  @moduledoc """
  Fractal's built-in verification checks.

  These checks are the feedback loop for AI-generated code: after an agent
  creates or edits a page, `mix fractal.verify` runs them (plus the test
  suite) and reports precisely what is wrong, so the agent can fix it
  without a human reading stack traces.

  Checks:

    * at least one page module exists
    * no two pages claim the same route for the same method
      (GET/POST/PUT/DELETE)
    * every page has a well-formed path (and action routes, if any) and
      a non-empty title
    * every declared action route (`post:`, `put:`, `delete:`) has its
      handler (`handle_post/1`, `handle_put/1`, `handle_delete/1`)
    * every page's `render/1` runs without raising (with empty params)
      and returns renderable content

  `pending_migrations/0` additionally checks the database is migrated;
  `mix fractal.verify` runs it alongside these checks.
  """

  alias Fractal.{HTML, Page, Router}

  @type result :: {name :: String.t(), :ok | {:error, String.t()}}

  @doc "Runs all checks against `pages` (defaults to the discovered pages)."
  @spec run([module()]) :: [result()]
  def run(pages \\ Router.pages()) do
    action_uniqueness =
      for action <- Page.actions() do
        check_unique_routes(pages, method_name(action), &Page.action_route(&1, action))
      end

    [check_pages_exist(pages), check_unique_routes(pages, "GET", & &1.path())] ++
      action_uniqueness ++ Enum.flat_map(pages, &check_page/1)
  end

  @doc "Returns `true` when every result passed."
  @spec ok?([result()]) :: boolean()
  def ok?(results), do: results == [] or Enum.all?(results, &match?({_name, :ok}, &1))

  @doc "Returns only the failed results."
  @spec errors([result()]) :: [result()]
  def errors(results), do: Enum.reject(results, &match?({_name, :ok}, &1))

  @doc """
  Checks that no database migrations are pending.

  Requires the repo to be started and the database to exist.
  """
  @spec pending_migrations() :: result()
  def pending_migrations do
    pending =
      for {:down, version, name} <- Ecto.Migrator.migrations(Fractal.Repo) do
        "#{version}_#{name}"
      end

    case pending do
      [] ->
        {"migrations are up", :ok}

      pending ->
        {"migrations are up",
         {:error, "pending: #{Enum.join(pending, ", ")} — run `mix ecto.migrate`"}}
    end
  rescue
    exception ->
      {"migrations are up",
       {:error,
        "could not check migrations (is the database running? try `mix ecto.setup`): " <>
          Exception.message(exception)}}
  end

  defp check_pages_exist([]) do
    {"pages are defined",
     {:error, "no page modules found — create one with `mix fractal.gen.page`"}}
  end

  defp check_pages_exist(_pages), do: {"pages are defined", :ok}

  defp check_unique_routes(pages, method, route_fun) do
    duplicates =
      pages
      |> Enum.group_by(fn page -> safe_route(page, route_fun) end)
      |> Enum.filter(fn {route, modules} -> route != nil and length(modules) > 1 end)

    case duplicates do
      [] ->
        {"#{method} routes are unique", :ok}

      duplicates ->
        detail =
          Enum.map_join(duplicates, "; ", fn {route, modules} ->
            "#{route} is claimed by #{Enum.map_join(modules, " and ", &inspect/1)}"
          end)

        {"#{method} routes are unique", {:error, detail}}
    end
  end

  defp check_page(page) do
    action_checks =
      for action <- Page.actions() do
        {"#{inspect(page)} handles its #{action} route", validate_action(page, action)}
      end

    [
      {"#{inspect(page)} declares a valid path", validate_path(page)},
      {"#{inspect(page)} declares a valid title", validate_title(page)}
    ] ++ action_checks ++ [{"#{inspect(page)} renders", validate_render(page)}]
  end

  defp validate_path(page) do
    path = page.path()

    if Page.route?(path) do
      :ok
    else
      {:error, "invalid path #{inspect(path)} — must be a string starting with \"/\""}
    end
  rescue
    exception -> {:error, "path/0 raised: #{Exception.message(exception)}"}
  end

  defp validate_title(page) do
    title = page.title()

    if is_binary(title) and title != "" do
      :ok
    else
      {:error, "invalid title #{inspect(title)} — must be a non-empty string"}
    end
  rescue
    exception -> {:error, "title/0 raised: #{Exception.message(exception)}"}
  end

  defp validate_action(page, action) do
    case Page.action_route(page, action) do
      nil ->
        :ok

      route ->
        cond do
          not Page.route?(route) ->
            {:error,
             "invalid #{action} route #{inspect(route)} — must be a string starting with \"/\""}

          not function_exported?(page, :"handle_#{action}", 1) ->
            {:error, "declares #{action} route #{route} but does not export handle_#{action}/1"}

          true ->
            :ok
        end
    end
  rescue
    exception -> {:error, "#{action}_path/0 raised: #{Exception.message(exception)}"}
  end

  defp method_name(action), do: action |> to_string() |> String.upcase()

  defp validate_render(page) do
    assigns = %{conn: nil, params: %{}, path: safe_route(page, & &1.path()) || "/"}

    case page.render(assigns) do
      %HTML.Safe{} ->
        :ok

      content when is_binary(content) or is_list(content) ->
        :ok

      other ->
        {:error, "render/1 must return Fractal.HTML content or a string, got: #{inspect(other)}"}
    end
  rescue
    exception -> {:error, "render/1 raised: #{Exception.message(exception)}"}
  end

  defp safe_route(page, route_fun) do
    route_fun.(page)
  rescue
    _exception -> nil
  end
end
