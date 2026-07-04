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
    * every `require:` names a defined guard, and every `expect/2`
      declaration is honored by every matching page (see `Fractal.Checkpoint`)
    * every page's `render/1` runs without raising (with empty params
      and session) and returns renderable content — which also catches
      references to missing assets, since `asset_path/1` raises
    * every `<form>` a page renders carries a CSRF token (i.e. was
      built with `Fractal.Form`, not by hand)
    * rendered output contains no `<style>` tags (styles belong in
      `style/0` / `assets/app.css`) and no external `script`/`link`
      references (the framework owns the client — vendor files into
      `assets/static/`)

  `mix fractal.verify` composes these with the other layers of the
  contract: `pending_migrations/0` and `secret_key/0` (environment),
  `run_components/1` (components), `run_invariants/1` (the app's own
  invariants from `Fractal.Invariant`, run against every page), and
  `test_coverage/1` (every page and component must be referenced by a
  test file — the test file is the per-page behavioral contract, and
  its existence is enforced, not hoped for).
  """

  alias Fractal.{HTML, Page, Router}

  @type result :: {name :: String.t(), :ok | {:error, String.t()}}

  @doc """
  Runs all component checks against `components` (defaults to the
  discovered ones).

  Each component is smoke-rendered with its `example/0` through the
  same scans as pages (escaping, no `<style>` tags, no external
  references, CSRF tokens in forms), and its `style/0` is checked for
  balance.
  """
  @spec run_components([module()]) :: [result()]
  def run_components(components \\ Fractal.Component.all()) do
    Enum.flat_map(components, fn component ->
      [
        {"#{inspect(component)} declares valid styles", validate_style(component)},
        {"#{inspect(component)} renders its example", validate_component_render(component)}
      ]
    end)
  end

  @doc """
  Runs the app's invariants (see `Fractal.Invariant`) against `pages`
  (defaults to the discovered ones).

  Each invariant runs per page with `%{page: page, rendered: html}`;
  a crashing invariant is a failing one. Pages that don't render get a
  failing result pointing at their render check.
  """
  @spec run_invariants([module()]) :: [result()]
  def run_invariants(pages \\ Router.pages()) do
    case Fractal.Invariant.names() do
      [] -> []
      names -> Enum.flat_map(pages, &invariant_checks(&1, names))
    end
  end

  @doc """
  Checks that at most one invariants module exists.
  """
  @spec invariants() :: result()
  def invariants do
    name = "invariants are well-formed"

    case Fractal.Invariant.modules() do
      many when length(many) > 1 ->
        {name,
         {:error,
          "found #{length(many)} invariants modules (#{Enum.map_join(many, ", ", &inspect/1)}) — " <>
            "the app's invariants live in exactly one"}}

      _zero_or_one ->
        {name, :ok}
    end
  end

  @doc """
  Checks that every page and component is referenced by a test file.

  The test file is the per-page behavioral contract; this converts
  "forgot to write tests entirely" from silent to loud. It cannot judge
  test quality — that isn't its job.
  """
  @spec test_coverage([module()]) :: [result()]
  def test_coverage(modules \\ Router.pages() ++ Fractal.Component.all()) do
    blob =
      "test/**/*_test.exs"
      |> Path.wildcard()
      |> Enum.map_join("\n", &File.read!/1)

    Enum.map(modules, fn module ->
      name = "#{inspect(module)} has tests"

      if String.contains?(blob, inspect(module)) do
        {name, :ok}
      else
        kind = if Fractal.Component.component?(module), do: "components", else: "pages"
        file_base = module |> Module.split() |> List.last() |> Macro.underscore()

        {name,
         {:error,
          "no test file references #{inspect(module)} — add " <>
            "test/fractal/#{kind}/#{file_base}_test.exs (the generators scaffold these; " <>
            "see the testing conventions in the guides)"}}
      end
    end)
  end

  @doc "Runs all checks against `pages` (defaults to the discovered pages)."
  @spec run([module()]) :: [result()]
  def run(pages \\ Router.pages()) do
    action_uniqueness =
      for action <- Page.actions() do
        check_unique_routes(pages, method_name(action), &Page.action_route(&1, action))
      end

    [
      check_pages_exist(pages),
      check_unique_routes(pages, "GET", & &1.path()),
      check_expectations(pages)
    ] ++
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
  Checks the checkpoint module: at most one exists, every guard smoke-runs
  with empty assigns (returning `:ok` or a redirect, never crashing),
  and `context/1` tolerates an empty session.
  """
  @spec checkpoint() :: [result()]
  def checkpoint do
    case Fractal.Checkpoint.modules() do
      [] ->
        [{"the checkpoint is well-formed", :ok}]

      [_single] ->
        assigns = %{conn: nil, params: %{}, session: %{}, path: "/", context: %{}}

        [check_context(assigns) | Enum.map(Fractal.Checkpoint.names(), &check_guard(&1, assigns))]

      many ->
        [
          {"the checkpoint is well-formed",
           {:error,
            "found #{length(many)} checkpoint modules (#{Enum.map_join(many, ", ", &inspect/1)}) — " <>
              "cross-cutting behavior lives in exactly one"}}
        ]
    end
  end

  defp check_context(assigns) do
    name = "guard context tolerates an empty session"

    result =
      try do
        case Fractal.Checkpoint.context(assigns) do
          context when is_map(context) -> :ok
          other -> {:error, "context/1 must return a map, got: #{inspect(other)}"}
        end
      rescue
        exception -> {:error, "context/1 raised: #{Exception.message(exception)}"}
      end

    {name, result}
  end

  defp check_guard(guard_name, assigns) do
    name = "guard #{inspect(guard_name)} tolerates an empty session"

    result =
      try do
        assigns = Map.put(assigns, :context, Fractal.Checkpoint.context(assigns))

        case Fractal.Checkpoint.run([guard_name], assigns) do
          :ok -> :ok
          {:redirect, to, _directives} when is_binary(to) -> :ok
        end
      rescue
        exception -> {:error, "the guard raised: #{Exception.message(exception)}"}
      end

    {name, result}
  end

  @doc """
  Guards no page requires. Informational — reported by
  `mix fractal.verify`, but not a failure.
  """
  @spec unused_guards() :: [atom()]
  def unused_guards do
    required = Enum.flat_map(Router.pages(), &Page.requires/1)
    expected = Enum.map(Fractal.Checkpoint.expectations(), fn {_prefix, guard} -> guard end)

    Fractal.Checkpoint.names() -- (required ++ expected)
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
  Components no page source renders via `component/2`. Informational —
  reported by `mix fractal.verify`, but not a failure.
  """
  @spec unused_components() :: [String.t()]
  def unused_components do
    sources =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&String.starts_with?(&1, "lib/fractal/components/"))
      |> Enum.map_join("\n", &File.read!/1)

    for component <- Fractal.Component.all(),
        name = component |> Module.split() |> List.last(),
        not String.contains?(sources, name) do
      inspect(component)
    end
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
        {"#{inspect(page)} requires defined guards", validate_requires(page)},
        {"#{inspect(page)} declares valid styles", validate_style(page)},
        {"#{inspect(page)} renders", validate_render(page)}
      ]
  end

  defp invariant_checks(page, names) do
    case smoke_render(page) do
      {:ok, rendered} ->
        context = %{page: page, rendered: rendered}

        for name <- names do
          {"#{inspect(page)} satisfies invariant '#{name}'", run_invariant(name, context)}
        end

      :error ->
        for name <- names do
          {"#{inspect(page)} satisfies invariant '#{name}'",
           {:error, "the page does not render (fix its render check first)"}}
        end
    end
  end

  defp run_invariant(name, context) do
    case Fractal.Invariant.run(name, context) do
      :ok ->
        :ok

      {:error, message} when is_binary(message) ->
        {:error, message}

      other ->
        {:error, "invariants must return :ok or {:error, message}, got: #{inspect(other)}"}
    end
  rescue
    exception -> {:error, "the invariant raised: #{Exception.message(exception)}"}
  end

  defp smoke_render(page) do
    case page.render(smoke_assigns(page)) do
      %HTML.Safe{} = safe ->
        {:ok, HTML.safe_to_string(safe)}

      content when is_binary(content) or is_list(content) ->
        {:ok, content |> HTML.to_safe() |> HTML.safe_to_string()}

      _other ->
        :error
    end
  rescue
    _exception -> :error
  end

  defp smoke_assigns(page) do
    %{
      conn: nil,
      params: %{},
      session: %{},
      context: %{},
      flash: %{},
      path: safe_route(page, & &1.path()) || "/"
    }
  end

  # expectations turn "every /admin page must be guarded" into a
  # verification contract instead of hidden runtime behavior
  defp check_expectations(pages) do
    name = "guard expectations are honored"

    violations =
      for {prefix, guard} <- Fractal.Checkpoint.expectations(),
          page <- pages,
          path = safe_route(page, & &1.path()),
          path != nil and Fractal.Checkpoint.under?(path, prefix),
          guard not in Page.requires(page) do
        "#{inspect(page)} (#{path}) must declare require: #{inspect(guard)}"
      end

    case violations do
      [] -> {name, :ok}
      violations -> {name, {:error, Enum.join(violations, "; ")}}
    end
  end

  defp validate_requires(page) do
    requires = Page.requires(page)

    cond do
      requires == [] ->
        :ok

      Fractal.Checkpoint.module() == nil ->
        {:error,
         "requires guards #{inspect(requires)} but no checkpoint module exists — " <>
           "create lib/fractal/checkpoints.ex with `use Fractal.Checkpoint`"}

      true ->
        case Enum.reject(requires, &(&1 in Fractal.Checkpoint.names())) do
          [] ->
            :ok

          missing ->
            {:error,
             "requires undefined guard(s) #{inspect(missing)} — define them in " <>
               "#{inspect(Fractal.Checkpoint.module())} with `guard #{inspect(hd(missing))} do ... end`"}
        end
    end
  rescue
    exception -> {:error, "requires/0 raised: #{Exception.message(exception)}"}
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
    case page.render(smoke_assigns(page)) do
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

  defp validate_component_render(component) do
    example = component.example()

    if is_map(example) do
      component
      |> Fractal.Component.component(example)
      |> HTML.safe_to_string()
      |> scan_html()
    else
      {:error, "example/0 must return an assigns map, got: #{inspect(example)}"}
    end
  rescue
    exception -> {:error, "rendering the example raised: #{Exception.message(exception)}"}
  end

  # works for pages and components alike: both optionally export style/0
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
