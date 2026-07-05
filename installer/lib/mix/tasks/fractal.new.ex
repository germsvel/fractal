defmodule Mix.Tasks.Fractal.New do
  @shortdoc "Creates a new Fractal application"

  @moduledoc """
  Creates a new Fractal application:

      $ mix fractal.new APP_NAME

  `APP_NAME` can also be a path (`mix fractal.new ~/code/blog`); the
  final segment names the app. There are no flags — every app starts
  from the same, verified template.

  The generated app is born green:

      $ cd blog
      $ mix deps.get
      $ mix ecto.setup
      $ mix fractal.verify

  It contains a Home page, an interactive Counter page (delete it once
  you've seen how events work), the app's checkpoint, invariants, and
  EmptyState component — all with tests — plus an `AGENTS.md` contract
  and a prompt-first `README.md`. Postgres is expected on localhost
  (override with `PGUSER`/`PGPASSWORD`/`PGHOST`).

  Fractal is fetched as a git dependency. Set the `FRACTAL_PATH`
  environment variable to use a local checkout instead (used by the
  framework's own integration tests).
  """

  use Mix.Task

  @fractal_git "https://github.com/germsvel/fractal.git"

  templates_root = Path.expand("../../../templates", __DIR__)

  template_files =
    templates_root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()

  for file <- template_files do
    @external_resource file
  end

  # Templates are embedded at compile time so the archive-installed task
  # carries them; keys are template-relative paths.
  @templates Map.new(template_files, fn file ->
               {Path.relative_to(file, templates_root), File.read!(file)}
             end)

  @impl Mix.Task
  def run(argv) do
    case argv do
      [path] ->
        generate(path)

      _other ->
        Mix.raise("usage: mix fractal.new APP_NAME (no flags — see `mix help fractal.new`)")
    end
  end

  defp generate(path) do
    app = path |> Path.expand() |> Path.basename()

    unless app =~ ~r/^[a-z][a-z0-9_]*$/ do
      Mix.raise(
        "the app name must start with a lowercase letter and contain only " <>
          "lowercase letters, digits, and underscores — got #{inspect(app)}"
      )
    end

    if File.exists?(path) do
      Mix.raise("#{path} already exists — pick a new directory")
    end

    assigns = [
      app: app,
      mod: Macro.camelize(app),
      fractal_dep: fractal_dep(),
      secret_dev: secret(),
      secret_test: secret()
    ]

    for {template, contents} <- Enum.sort(@templates) do
      destination = Path.join(path, destination_for(template, app))
      Mix.shell().info("* creating #{destination}")
      File.mkdir_p!(Path.dirname(destination))
      File.write!(destination, EEx.eval_string(contents, assigns: assigns))
    end

    Mix.shell().info("""

    Your Fractal app is ready. Get it running:

        cd #{path}
        mix deps.get
        mix ecto.setup      # create the database
        mix fractal.server  # http://localhost:4000

    Then open your AI agent in that directory and prompt it — start with
    the README's quickstart, or go straight to your own first page:

        Create a Fractal page at /pricing that lists three plans

    `mix fractal.verify` keeps every change honest.
    """)
  end

  # "lib/app_name/pages/home.ex.eex" -> "lib/blog/pages/home.ex"
  # "dot_gitignore.eex"              -> ".gitignore"
  defp destination_for(template, app) do
    template
    |> String.replace_suffix(".eex", "")
    |> Path.split()
    |> Enum.map(fn
      "app_name" -> app
      "dot_" <> name -> "." <> name
      segment -> segment
    end)
    |> Path.join()
  end

  defp fractal_dep do
    case System.get_env("FRACTAL_PATH") do
      nil -> ~s({:fractal, git: "#{@fractal_git}"})
      path -> ~s[{:fractal, path: #{inspect(Path.expand(path))}}]
    end
  end

  defp secret do
    64 |> :crypto.strong_rand_bytes() |> Base.encode64()
  end
end
