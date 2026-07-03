defmodule Fractal.Server do
  @moduledoc """
  Starts the HTTP server (Bandit) serving `Fractal.Router`, plus the dev
  file watcher when `watch: true`.

  Usually started via `mix fractal.server`; call `start/1` directly when
  embedding Fractal in another supervision tree.
  """

  @doc """
  Starts the server supervisor.

  ## Options

    * `:port` — TCP port to listen on (default: 4000)
    * `:watch` — start `Fractal.Reloader` for recompilation and live
      reload (default: false)
  """
  @spec start(keyword()) :: Supervisor.on_start()
  def start(opts \\ []) do
    port = Keyword.get(opts, :port, 4000)
    watch? = Keyword.get(opts, :watch, false)

    children =
      [{Bandit, plug: Fractal.Router, port: port, ip: {0, 0, 0, 0}}] ++
        if watch?, do: [Fractal.Reloader], else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: Fractal.Server.Supervisor)
  end
end
