defmodule Mix.Tasks.Fractal.Server do
  @shortdoc "Starts the Fractal web server"

  @moduledoc """
  Starts the Fractal web server.

      mix fractal.server
      mix fractal.server --port 8080
      mix fractal.server --no-watch

  ## Options

    * `--port` — TCP port to listen on (default: 4000)
    * `--no-watch` — disable recompilation and browser live reload
      (watching is on by default in the dev environment)
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _errors} = OptionParser.parse(args, strict: [port: :integer, watch: :boolean])

    port = Keyword.get(opts, :port, 4000)
    watch? = Keyword.get(opts, :watch, Mix.env() == :dev)

    Application.put_env(:fractal, :live_reload, watch?)

    case Fractal.Server.start(port: port, watch: watch?) do
      {:ok, _pid} ->
        Mix.shell().info(
          "Fractal listening on http://localhost:#{port} " <>
            "(env: #{Mix.env()}, live reload: #{watch?})"
        )

        Process.sleep(:infinity)

      {:error, reason} ->
        Mix.raise("could not start the server: #{inspect(reason)}")
    end
  end
end
