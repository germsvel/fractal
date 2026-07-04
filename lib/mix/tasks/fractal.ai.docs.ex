defmodule Mix.Tasks.Fractal.Ai.Docs do
  @shortdoc "Prints the framework documentation intended for AI agents"

  @moduledoc """
  Prints Fractal's guides to stdout.

      mix fractal.ai.docs

  This is the entry point for AI agents working on a Fractal app: run it
  (or read the files in `guides/`) before generating any code. The guides
  cover page anatomy, conventions, and the verification workflow.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    case Path.wildcard("guides/*.md") do
      [] ->
        Mix.raise("no guides found in guides/ — run this task from the project root")

      guides ->
        guides
        |> Enum.sort()
        |> Enum.each(fn file ->
          Mix.shell().info("\n<!-- #{file} -->\n")
          Mix.shell().info(File.read!(file))
        end)
    end

    print_component_inventory()
    print_guard_inventory()
  end

  defp print_guard_inventory do
    Mix.shell().info("\n<!-- guard inventory (live — protect pages with require:) -->\n")

    case Fractal.Guard.names() do
      [] ->
        Mix.shell().info("No guards defined yet (see Fractal.Guard).")

      names ->
        Enum.each(names, fn name -> Mix.shell().info("- #{inspect(name)}") end)

        Enum.each(Fractal.Guard.expectations(), fn {prefix, guard} ->
          Mix.shell().info(
            "- expectation: every page under #{prefix} must declare require: #{inspect(guard)}"
          )
        end)
    end
  end

  defp print_component_inventory do
    Mix.Task.run("app.start", [])

    Mix.shell().info("\n<!-- component inventory (live — check before creating one) -->\n")

    case Fractal.Component.all() do
      [] ->
        Mix.shell().info("No components defined yet (mix fractal.gen.component Name).")

      components ->
        Enum.each(components, fn component ->
          Mix.shell().info(
            "- #{inspect(component)} — example assigns: #{inspect(component.example())}"
          )
        end)
    end
  end
end
