defmodule Fractal.Reloader do
  @moduledoc """
  Watches source files in development, recompiles on change, and bumps the
  live-reload token so open browser tabs refresh.

  Started by `mix fractal.server` (unless `--no-watch` is given). Compile
  failures are logged and the previous code keeps serving requests.
  """

  use GenServer

  require Logger

  @debounce_ms 100
  @extensions ~w(.ex .exs .eex)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :watch, true) do
      dirs = opts |> Keyword.get(:dirs, ["lib"]) |> Enum.map(&Path.expand/1)

      case FileSystem.start_link(dirs: dirs) do
        {:ok, watcher} ->
          FileSystem.subscribe(watcher)

        other ->
          Logger.warning(
            "[fractal] could not start the file watcher (#{inspect(other)}) — " <>
              "live reload is disabled. On Linux, install inotify-tools."
          )
      end
    end

    {:ok, %{pending: false}}
  end

  @impl true
  def handle_info({:file_event, _watcher, {path, _events}}, state) do
    if source_file?(path) and not state.pending do
      Process.send_after(self(), :recompile, @debounce_ms)
      {:noreply, %{state | pending: true}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:recompile, state) do
    recompile()
    {:noreply, %{state | pending: false}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc "Recompiles the project and bumps the live-reload token."
  def recompile do
    Logger.info("[fractal] change detected, recompiling...")

    try do
      Mix.Task.rerun("compile.elixir", ["--ignore-module-conflict"])
      Fractal.LiveReload.bump()
      Logger.info("[fractal] reload ready")
    rescue
      exception ->
        Logger.error("[fractal] compile failed: #{Exception.message(exception)}")
    catch
      :exit, reason ->
        Logger.error("[fractal] compile failed: #{inspect(reason)}")
    end
  end

  defp source_file?(path), do: Path.extname(to_string(path)) in @extensions
end
