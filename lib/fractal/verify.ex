defmodule Fractal.Verify do
  @moduledoc """
  Fractal's built-in verification checks.

  These checks are the feedback loop for AI-generated code: after an agent
  creates or edits a page, `mix fractal.verify` runs them (plus the test
  suite) and reports precisely what is wrong, so the agent can fix it
  without a human reading stack traces.

  Checks:

    * at least one page module exists
    * no two pages claim the same route
    * every page has a valid path (string, starts with `/`, no stray
      whitespace) and a non-empty title
    * every page's `render/1` runs without raising and returns renderable
      content
  """

  alias Fractal.{HTML, Router}

  @type result :: {name :: String.t(), :ok | {:error, String.t()}}

  @doc "Runs all checks against `pages` (defaults to the discovered pages)."
  @spec run([module()]) :: [result()]
  def run(pages \\ Router.pages()) do
    [check_pages_exist(pages), check_unique_paths(pages)] ++
      Enum.flat_map(pages, &check_page/1)
  end

  @doc "Returns `true` when every result passed."
  @spec ok?([result()]) :: boolean()
  def ok?(results), do: results == [] or Enum.all?(results, &match?({_name, :ok}, &1))

  @doc "Returns only the failed results."
  @spec errors([result()]) :: [result()]
  def errors(results), do: Enum.reject(results, &match?({_name, :ok}, &1))

  defp check_pages_exist([]) do
    {"pages are defined",
     {:error, "no page modules found — create one with `mix fractal.gen.page`"}}
  end

  defp check_pages_exist(_pages), do: {"pages are defined", :ok}

  defp check_unique_paths(pages) do
    duplicates =
      pages
      |> Enum.group_by(&page_path/1)
      |> Enum.filter(fn {_path, modules} -> length(modules) > 1 end)

    case duplicates do
      [] ->
        {"routes are unique", :ok}

      duplicates ->
        detail =
          Enum.map_join(duplicates, "; ", fn {path, modules} ->
            "#{path} is claimed by #{Enum.map_join(modules, " and ", &inspect/1)}"
          end)

        {"routes are unique", {:error, detail}}
    end
  end

  defp check_page(page) do
    [
      {"#{inspect(page)} declares a valid path", validate_path(page)},
      {"#{inspect(page)} declares a valid title", validate_title(page)},
      {"#{inspect(page)} renders", validate_render(page)}
    ]
  end

  defp validate_path(page) do
    path = page.path()

    if is_binary(path) and String.starts_with?(path, "/") and path == String.trim(path) do
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

  defp validate_render(page) do
    assigns = %{conn: nil, params: %{}, path: page_path(page)}

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

  defp page_path(page) do
    page.path()
  rescue
    _exception -> "/"
  end
end
