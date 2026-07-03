defmodule Fractal.LiveReload do
  @moduledoc """
  Holds the live-reload token.

  The token changes whenever the dev reloader recompiles code. Browsers
  poll it via `GET /fractal/reload` (see `Fractal.Layout`) and reload the
  page when it changes.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(&new_token/0, name: __MODULE__)
  end

  @doc "The current reload token."
  @spec token() :: pos_integer()
  def token, do: Agent.get(__MODULE__, & &1)

  @doc "Invalidates the current token, telling connected browsers to reload."
  @spec bump() :: :ok
  def bump, do: Agent.update(__MODULE__, fn _token -> new_token() end)

  defp new_token, do: System.unique_integer([:positive, :monotonic])
end
