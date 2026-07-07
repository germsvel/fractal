defmodule Fractal.Discovery do
  @moduledoc false

  # The framework's knowledge of its host application. Fractal runs
  # inside the host's mix project; everything host-specific (which app
  # to scan for pages, what namespace generators emit, which repo owns
  # migrations) derives from here.

  @doc "The host application. Defaults to the enclosing mix project."
  @spec host_app() :: atom()
  def host_app do
    Application.get_env(:fractal, :otp_app) || Mix.Project.config()[:app]
  end

  @doc """
  The host's base module namespace as a string (e.g. \"Blog\").

  Defaults to the camelized app name; override with
  `config :fractal, namespace: MyApp`.
  """
  @spec namespace() :: String.t()
  def namespace do
    case Application.get_env(:fractal, :namespace) do
      nil -> host_app() |> to_string() |> Macro.camelize()
      module when is_atom(module) -> module |> Module.split() |> Enum.join(".")
      binary when is_binary(binary) -> binary
    end
  end

  @doc "The host's source directory name (`lib/<app_dir>/...`)."
  @spec app_dir() :: String.t()
  def app_dir, do: to_string(host_app())

  @doc """
  The host's repo (first entry of the host's `:ecto_repos`), or `nil`
  for repo-less apps.
  """
  @spec host_repo() :: module() | nil
  def host_repo do
    case Application.get_env(host_app(), :ecto_repos, []) do
      [repo | _rest] -> repo
      [] -> nil
    end
  end

  # Whether discovery products (the route table, the CSS bundle) may be
  # cached. False wherever they can change or be manipulated: dev (the
  # reloader recompiles code) and test envs (which set
  # `config :fractal, cache_discovery: false` so nothing can go stale
  # mid-suite). The flag also serves as a one-line diagnostic lever in
  # any environment if a stale-discovery bug is ever suspected.
  @spec cache?() :: boolean()
  def cache? do
    Application.get_env(:fractal, :cache_discovery, true) and
      not Application.get_env(:fractal, :live_reload, false)
  end

  # Scans the host app's ebin for modules instead of using
  # Application.spec/2 so that modules compiled after boot (by the dev
  # reloader) are still found. Used for pages, components, the
  # checkpoint, invariants, and the layout.
  @spec modules() :: [module()]
  def modules do
    app = host_app()

    case :code.lib_dir(app) do
      {:error, _reason} ->
        Application.spec(app, :modules) || []

      dir ->
        [List.to_string(dir), "ebin", "*.beam"]
        |> Path.join()
        |> Path.wildcard()
        |> Enum.map(&(&1 |> Path.basename(".beam") |> String.to_atom()))
    end
  end
end
