defmodule Fractal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The framework's application starts framework services: the watch
    # bus (server push) and live reload. Repos listed under :fractal's
    # own ecto_repos also start here — host apps supervise their own.
    children =
      Application.get_env(:fractal, :ecto_repos, []) ++ [Fractal.Bus, Fractal.LiveReload]

    Supervisor.start_link(children, strategy: :one_for_one, name: Fractal.Supervisor)
  end
end
