defmodule Mix.Tasks.Fractal.Gen.Component do
  @shortdoc "Generates a UI component and its test"

  @moduledoc """
  Generates a component under `lib/<app>/components/` and a matching
  test (paths and module names derive from the host app).

      mix fractal.gen.component Card

  **Check the existing vocabulary first** — `/fractal/components` in
  the browser or the inventory in `mix fractal.ai.docs`. Prefer using
  or extending an existing component over creating a near-duplicate.

  Components are render-only (no routes, events, sessions, or queries);
  see `Fractal.Component` and `guides/components.md`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    name =
      case args do
        [name | _rest] -> name
        [] -> Mix.raise("usage: mix fractal.gen.component ComponentName")
      end

    camel = Macro.camelize(name)
    file_base = Macro.underscore(camel)
    slug = String.replace(file_base, "_", "-")
    namespace = Fractal.Discovery.namespace()
    app_dir = Fractal.Discovery.app_dir()
    module = "#{namespace}.Components.#{camel}"

    component_file = Path.join(["lib", app_dir, "components", "#{file_base}.ex"])
    test_file = Path.join(["test", app_dir, "components", "#{file_base}_test.exs"])

    Enum.each([component_file, test_file], fn file ->
      if File.exists?(file), do: Mix.raise("#{file} already exists")
    end)

    File.mkdir_p!(Path.dirname(component_file))
    File.mkdir_p!(Path.dirname(test_file))
    File.write!(component_file, component_template(module, slug))
    File.write!(test_file, test_template(module, camel, slug))

    Mix.shell().info("""
    * created #{component_file}
    * created #{test_file}

    Edit render/1 and example/0, then run `mix fractal.verify`.
    It will appear in /fractal/components and mix fractal.ai.docs.
    """)
  end

  defp component_template(module, slug) do
    """
    defmodule #{module} do
      @moduledoc "TODO: one line on when to use this component."

      use Fractal.Component

      @impl Fractal.Component
      def render(assigns) do
        tag(:div, [class: "#{slug}"], [
          tag(:h3, [], [assigns.title]),
          assigns.body
        ])
      end

      # CSS scoped to this component only; shared tokens live in assets/app.css
      @impl Fractal.Component
      def style do
        \"\"\"
        .#{slug} { background: var(--surface); border-radius: 0.5rem; padding: 1.25rem; }
        \"\"\"
      end

      # renders in the /fractal/components gallery and in verification
      @impl Fractal.Component
      def example do
        %{title: "Example #{slug}", body: tag(:p, [], ["Body content"])}
      end
    end
    """
  end

  defp test_template(module, camel, slug) do
    """
    defmodule #{module}Test do
      use ExUnit.Case, async: true

      import Fractal.Component, only: [component: 2]

      alias #{module}
      alias Fractal.HTML

      test "passes Fractal's component verification checks" do
        results = Fractal.Verify.run_components([#{camel}])
        assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
      end

      test "renders its example, scoped" do
        html = #{camel} |> component(#{camel}.example()) |> HTML.safe_to_string()

        assert html =~ ~s(data-component="#{slug}")
        assert html =~ "Example #{slug}"
      end
    end
    """
  end
end
