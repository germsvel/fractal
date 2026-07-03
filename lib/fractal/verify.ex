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
    * declared events are unique non-empty strings and `handle_event/2`
      is exported when a page declares any
    * `style/0` (when defined) returns well-formed CSS (balanced braces)
    * every page's `render/1` runs without raising (with empty params
      and session) and returns renderable content — which also catches
      references to missing assets, since `asset_path/1` raises
    * every `<form>` a page renders carries a CSRF token (i.e. was
      built with `Fractal.Form`, not by hand)
    * rendered output contains no `<style>` tags (styles belong in
      `style/0` / `assets/app.css`) and no external `script`/`link`
      references (the framework owns the client — vendor files into
      `assets/static/`)

  `pending_migrations/0` and `secret_key/0` additionally check the
  database is migrated and the session secret is configured;
  `mix fractal.verify` runs them alongside these checks.
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

  @doc """
  Checks that the shared stylesheet exists and is well-formed.
  """
  @spec stylesheet() :: result()
  def stylesheet do
    name = "app stylesheet is well-formed"

    case File.read(Fractal.Assets.app_css_file()) do
      {:ok, css} ->
        if count_occurrences(css, "{") == count_occurrences(css, "}") do
          {name, :ok}
        else
          {name, {:error, "#{Fractal.Assets.app_css_file()} has unbalanced braces"}}
        end

      {:error, _reason} ->
        {name,
         {:error,
          "#{Fractal.Assets.app_css_file()} is missing — it holds the design tokens " <>
            "and app-wide styles"}}
    end
  end

  @doc """
  Files in `assets/static/` that no page source references via
  `asset_path/1`. Informational — reported by `mix fractal.verify`, but
  not a failure.
  """
  @spec orphaned_assets() :: [String.t()]
  def orphaned_assets do
    referenced =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        Regex.scan(~r/asset_path\(\s*"([^"]+)"/, File.read!(file), capture: :all_but_first)
      end)
      |> List.flatten()
      |> MapSet.new()

    Enum.reject(Fractal.Assets.static_files(), &MapSet.member?(referenced, &1))
  end

  @doc """
  Checks that the session secret is configured and strong enough.

  Sessions and CSRF tokens are encrypted/signed with
  `config :fractal, :secret_key_base`.
  """
  @spec secret_key() :: result()
  def secret_key do
    name = "session secret is configured"

    case Application.get_env(:fractal, :secret_key_base) do
      nil ->
        {name,
         {:error,
          "config :fractal, :secret_key_base is not set — generate one with " <>
            "`mix fractal.gen.secret`"}}

      secret when not is_binary(secret) or byte_size(secret) < 64 ->
        {name,
         {:error,
          "secret_key_base must be a string of at least 64 bytes — generate one with " <>
            "`mix fractal.gen.secret`"}}

      _secret ->
        {name, :ok}
    end
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
    ] ++
      action_checks ++
      [
        {"#{inspect(page)} handles its events", validate_events(page)},
        {"#{inspect(page)} declares valid styles", validate_style(page)},
        {"#{inspect(page)} renders", validate_render(page)}
      ]
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

  defp validate_events(page) do
    events = Page.events(page)

    cond do
      not Page.valid_events?(events) ->
        {:error, "invalid events #{inspect(events)} — must be unique, non-empty strings"}

      events != [] and not function_exported?(page, :handle_event, 2) ->
        {:error, "declares events #{inspect(events)} but does not export handle_event/2"}

      true ->
        :ok
    end
  rescue
    exception -> {:error, "events/0 raised: #{Exception.message(exception)}"}
  end

  defp method_name(action), do: action |> to_string() |> String.upcase()

  defp validate_render(page) do
    assigns = %{
      conn: nil,
      params: %{},
      session: %{},
      flash: %{},
      path: safe_route(page, & &1.path()) || "/"
    }

    case page.render(assigns) do
      %HTML.Safe{} = safe ->
        scan_html(HTML.safe_to_string(safe))

      content when is_binary(content) or is_list(content) ->
        scan_html(content |> HTML.to_safe() |> HTML.safe_to_string())

      other ->
        {:error, "render/1 must return Fractal.HTML content or a string, got: #{inspect(other)}"}
    end
  rescue
    exception -> {:error, "render/1 raised: #{Exception.message(exception)}"}
  end

  defp validate_style(page) do
    case Page.style(page) do
      nil ->
        :ok

      style when is_binary(style) ->
        cond do
          count_occurrences(style, "{") != count_occurrences(style, "}") ->
            {:error, "style/0 has unbalanced braces"}

          String.contains?(style, "</style") ->
            {:error, "style/0 must be plain CSS — no </style> tags"}

          true ->
            :ok
        end

      other ->
        {:error, "style/0 must return a CSS string, got: #{inspect(other)}"}
    end
  rescue
    exception -> {:error, "style/0 raised: #{Exception.message(exception)}"}
  end

  defp scan_html(html) do
    with :ok <- scan_forms(html),
         :ok <- scan_style_tags(html) do
      scan_external_refs(html)
    end
  end

  # every <form> must carry a CSRF token — i.e. be built with
  # Fractal.Form, which injects one, rather than by hand
  defp scan_forms(html) do
    forms = count_occurrences(html, "<form")
    tokens = count_occurrences(html, ~s(name="_csrf_token"))

    if forms > tokens do
      {:error,
       "renders a <form> without a CSRF token — build forms with " <>
         "Fractal.Form.form_for/4 or button_to/3 instead of raw <form> tags"}
    else
      :ok
    end
  end

  defp scan_style_tags(html) do
    if String.contains?(html, "<style") do
      {:error,
       "renders a <style> tag — put page styles in style/0 (scoped automatically) " <>
         "and shared styles in assets/app.css"}
    else
      :ok
    end
  end

  # agents love pasting CDN <script>/<link> lines; the framework owns
  # the client, so external code never loads from third-party origins
  defp scan_external_refs(html) do
    if Regex.match?(~r/<(script|link)[^>]+(src|href)="(https?:)?\/\//i, html) do
      {:error,
       "references an external script or stylesheet — Fractal owns the client; " <>
         "vendor files into assets/static/ and reference them with asset_path/1"}
    else
      :ok
    end
  end

  defp count_occurrences(string, pattern) do
    string |> String.split(pattern) |> length() |> Kernel.-(1)
  end

  defp safe_route(page, route_fun) do
    route_fun.(page)
  rescue
    _exception -> nil
  end
end
