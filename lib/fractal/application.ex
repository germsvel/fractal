defmodule Fractal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Fractal.Repo,
      Fractal.LiveReload
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Fractal.Supervisor)
  end
end
