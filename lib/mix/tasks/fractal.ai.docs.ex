defmodule Mix.Tasks.Fractal.Ai.Docs do
  @shortdoc "Prints the framework documentation intended for AI agents"

  @moduledoc """
  Prints Fractal's guides to stdout, followed by the app's live
  inventories (components, guards, invariants).

      mix fractal.ai.docs

  This is the entry point for AI agents working on a Fractal app: run
  it before generating any code. The guides ship inside the framework
  package, so documentation improvements reach every app on upgrade.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    case Path.wildcard(Path.join(guides_dir(), "*.md")) do
      [] ->
        Mix.raise("no guides found in the fractal package (#{guides_dir()})")

      guides ->
        guides
        |> Enum.sort()
        |> Enum.each(fn file ->
          Mix.shell().info("\n<!-- guide: #{Path.basename(file)} -->\n")
          Mix.shell().info(File.read!(file))
        end)
    end

    print_component_inventory()
    print_guard_inventory()
    print_invariant_inventory()
  end

  # the guides live in the framework package, not the app
  defp guides_dir do
    case :code.priv_dir(:fractal) do
      {:error, _reason} -> "priv/guides"
      dir -> Path.join(List.to_string(dir), "guides")
    end
  end

  defp print_invariant_inventory do
    Mix.shell().info(
      "\n<!-- invariant inventory (live — house rules verify enforces on every page) -->\n"
    )

    case Fractal.Invariant.names() do
      [] ->
        Mix.shell().info("No invariants defined yet (see Fractal.Invariant).")

      names ->
        Enum.each(names, fn name -> Mix.shell().info("- #{name}") end)
    end
  end

  defp print_guard_inventory do
    Mix.shell().info("\n<!-- guard inventory (live — protect pages with require:) -->\n")

    case Fractal.Checkpoint.names() do
      [] ->
        Mix.shell().info("No guards defined yet (see Fractal.Checkpoint).")

      names ->
        Enum.each(names, fn name -> Mix.shell().info("- #{inspect(name)}") end)

        Enum.each(Fractal.Checkpoint.expectations(), fn {prefix, guard} ->
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
