defmodule Fractal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Framework services only. The framework reads about the host's repo
    # (Fractal.Discovery.host_repo/0) but never supervises one — host
    # apps supervise their own.
    children = [Fractal.Bus, Fractal.LiveReload]

    Supervisor.start_link(children, strategy: :one_for_one, name: Fractal.Supervisor)
  end
end
