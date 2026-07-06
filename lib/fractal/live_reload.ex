defmodule Fractal.LiveReload do
  @moduledoc """
  Holds the live-reload state and rings the dev event stream.

  The state is `{token, event}`. The token changes on every bump, so a
  browser that reconnects (or outlives a server restart) can detect it
  missed something. The event says what kind of change it was:

    * `:reload` — code recompiled successfully; browsers fully reload
      onto the already-compiled code
    * `{:css, href}` — an assets-only change; browsers swap the
      fingerprinted stylesheet link in place, preserving page state
    * `{:error, message}` — the last compile failed; browsers show the
      compiler output as an overlay while the old code keeps serving

  Browsers hold a dev-only SSE stream to `GET /fractal/reload` (see
  `Fractal.Router`); each bump is broadcast over the internal bus on a
  reserved topic.
  """

  use Agent

  @type event :: :reload | {:css, String.t()} | {:error, String.t()}

  # reserved for the framework — user watch: topics live in app vocabulary
  @topic "fractal/dev/reload"

  def start_link(_opts) do
    Agent.start_link(fn -> %{token: new_token(), event: :reload} end, name: __MODULE__)
  end

  @doc "The current reload token."
  @spec token() :: pos_integer()
  def token, do: Agent.get(__MODULE__, & &1.token)

  @doc "The current state: `{token, event}`."
  @spec current() :: {pos_integer(), event()}
  def current, do: Agent.get(__MODULE__, fn state -> {state.token, state.event} end)

  @doc "Signals connected browsers to fully reload (code changed)."
  @spec bump() :: :ok
  def bump, do: bump(:reload)

  @doc "Signals connected browsers with a dev event (see the module doc)."
  @spec bump(event()) :: :ok
  def bump(event) do
    Agent.update(__MODULE__, fn _state -> %{token: new_token(), event: event} end)
    Fractal.Bus.broadcast(@topic)
  end

  @doc false
  def subscribe, do: Fractal.Bus.subscribe(@topic)

  defp new_token, do: System.unique_integer([:positive, :monotonic])
end
