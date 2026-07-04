defmodule Mix.Tasks.Fractal.Verify do
  @shortdoc "Runs Fractal's built-in verification checks and the test suite"

  @moduledoc """
  Fractal's verification loop. Run this after every change — especially
  AI-generated ones.

      mix fractal.verify
      mix fractal.verify --no-tests

  It compiles the project with warnings as errors, runs `Fractal.Verify`
  (page, route, and render checks), then runs `mix test`. Pass `--no-tests`
  to skip the test suite.

  Exits non-zero if anything fails, so it can gate CI and agent workflows.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _errors} = OptionParser.parse(args, strict: [tests: :boolean])

    Mix.Task.run("compile", ["--warnings-as-errors"])
    Mix.Task.run("app.start", [])

    results =
      [
        Fractal.Verify.secret_key(),
        Fractal.Verify.stylesheet(),
        Fractal.Verify.pending_migrations(),
        Fractal.Verify.invariants() | Fractal.Verify.checkpoint()
      ] ++
        Fractal.Verify.run() ++
        Fractal.Verify.run_components() ++
        Fractal.Verify.run_invariants() ++
        Fractal.Verify.test_coverage()

    Enum.each(results, fn
      {name, :ok} -> Mix.shell().info("✓ #{name}")
      {name, {:error, detail}} -> Mix.shell().error("✗ #{name}: #{detail}")
    end)

    failures = Fractal.Verify.errors(results)

    case Fractal.Verify.orphaned_assets() do
      [] ->
        :ok

      orphans ->
        Mix.shell().info(
          "\nℹ unreferenced files in assets/static/ (not a failure): " <>
            Enum.join(orphans, ", ")
        )
    end

    case Fractal.Verify.unused_components() do
      [] ->
        :ok

      unused ->
        Mix.shell().info(
          "\nℹ components no page renders (not a failure): " <> Enum.join(unused, ", ")
        )
    end

    case Fractal.Verify.unused_guards() do
      [] ->
        :ok

      unused ->
        Mix.shell().info(
          "\nℹ guards no page requires (not a failure): " <>
            Enum.map_join(unused, ", ", &inspect/1)
        )
    end

    tests_failed? =
      if Keyword.get(opts, :tests, true) and Mix.env() != :test do
        Mix.shell().info("\nRunning the test suite...")

        {_output, status} =
          System.cmd("mix", ["test", "--color"],
            env: [{"MIX_ENV", "test"}],
            into: IO.stream(:stdio, :line)
          )

        status != 0
      else
        false
      end

    cond do
      failures != [] ->
        Mix.raise("Verification failed: #{length(failures)} check(s) did not pass.")

      tests_failed? ->
        Mix.raise("Verification failed: the test suite did not pass.")

      true ->
        Mix.shell().info("\nAll verification checks passed.")
    end
  end
end
