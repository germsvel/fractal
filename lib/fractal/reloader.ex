defmodule Fractal.Reloader do
  @moduledoc """
  Watches source files in development, recompiles on change, and bumps
  `Fractal.LiveReload` so open browser tabs react.

  Changes are debounced and classified: a batch touching any code file
  recompiles (and on success browsers fully reload — always onto
  already-compiled code); a batch touching only `assets/` skips the
  compile and pushes the new stylesheet href so browsers swap it in
  place. A failed compile keeps the previous code serving and pushes
  the compiler output for the browser's error overlay.

  Started by `mix fractal.server` (unless `--no-watch` is given). When
  the native file watcher is unavailable (missing inotify, NFS), it
  falls back to polling (`:fs_poll`).
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
      dirs =
        opts
        |> Keyword.get(:dirs, ["lib", "assets"])
        |> Enum.map(&Path.expand/1)
        |> Enum.filter(&File.dir?/1)

      case start_watcher(dirs) do
        {:ok, watcher} ->
          FileSystem.subscribe(watcher)

        other ->
          Logger.warning(
            "[fractal] could not start a file watcher (#{inspect(other)}) — " <>
              "live reload is disabled. On Linux, install inotify-tools."
          )
      end
    end

    {:ok, %{pending: false, paths: []}}
  end

  defp start_watcher(dirs) do
    case FileSystem.start_link(dirs: dirs) do
      {:ok, watcher} ->
        {:ok, watcher}

      _native_unavailable ->
        with {:ok, watcher} <- FileSystem.start_link(dirs: dirs, backend: :fs_poll) do
          Logger.warning(
            "[fractal] native file watcher unavailable — falling back to polling (:fs_poll)"
          )

          {:ok, watcher}
        end
    end
  end

  @impl true
  def handle_info({:file_event, _watcher, {path, _events}}, state) do
    path = to_string(path)

    if source_file?(path) do
      unless state.pending, do: Process.send_after(self(), :recompile, @debounce_ms)
      {:noreply, %{state | pending: true, paths: [path | state.paths]}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:recompile, state) do
    case classify(state.paths) do
      :css ->
        Logger.info("[fractal] assets changed, swapping styles...")
        Fractal.LiveReload.bump({:css, Fractal.Assets.css_path()})

      :code ->
        recompile()
    end

    {:noreply, %{state | pending: false, paths: []}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Classifies a debounce batch: `:code` when any path is a source file
  (a recompile is needed), `:css` when the batch touched only assets.
  """
  @spec classify([String.t()]) :: :code | :css
  def classify(paths) do
    if Enum.any?(paths, &(Path.extname(&1) in @extensions)), do: :code, else: :css
  end

  @doc """
  Recompiles the project and bumps the live-reload state — `:reload`
  on success, `{:error, message}` on failure (old code keeps serving).
  """
  def recompile do
    Logger.info("[fractal] change detected, recompiling...")

    try do
      # the compiler *returns* errors (it does not raise them)
      case Mix.Task.rerun("compile.elixir", ["--ignore-module-conflict", "--return-errors"]) do
        {:error, diagnostics} ->
          message = format_errors(diagnostics)
          Logger.error("[fractal] compile failed:\n#{message}")
          Fractal.LiveReload.bump({:error, message})

        _compiled ->
          Fractal.LiveReload.bump()
          Logger.info("[fractal] reload ready")
      end
    rescue
      exception ->
        message = Exception.message(exception)
        Logger.error("[fractal] compile failed: #{message}")
        Fractal.LiveReload.bump({:error, message})
    catch
      :exit, reason ->
        message = "compile exited: #{inspect(reason)}"
        Logger.error("[fractal] #{message}")
        Fractal.LiveReload.bump({:error, message})
    end
  end

  @doc false
  # compiler diagnostics → the overlay's text: file:line, then message
  def format_errors(diagnostics) do
    diagnostics
    |> Enum.filter(&(&1.severity == :error))
    |> Enum.map_join("\n\n", fn diagnostic ->
      "#{relative(diagnostic.file)}:#{line(diagnostic.position)}: #{diagnostic.message}"
    end)
  end

  defp relative(nil), do: "unknown"
  defp relative(file), do: Path.relative_to_cwd(file)

  defp line(line) when is_integer(line), do: line
  defp line({line, _column}), do: line
  defp line({line, _col, _end_line, _end_col}), do: line
  defp line(_unknown), do: 0

  defp source_file?(path) do
    # any change under assets/ (styles, images) also notifies browsers —
    # classified later as :css so no recompile runs for it
    Path.extname(path) in @extensions or String.contains?(path, "/assets/")
  end
end
