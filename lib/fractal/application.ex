defmodule Fractal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The framework's application starts framework services. Repos listed
    # under :fractal's own ecto_repos also start here — that's this repo
    # self-hosting its sample app; host apps supervise their own repos.
    children = Application.get_env(:fractal, :ecto_repos, []) ++ [Fractal.LiveReload]

    Supervisor.start_link(children, strategy: :one_for_one, name: Fractal.Supervisor)
  end
end
