defmodule Fractal.MixProject do
  use Mix.Project

  def project do
    [
      app: :fractal,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Fractal.Application, []}
    ]
  end

  # Deps are pinned to git tags rather than hex packages because this
  # sandbox's TLS-intercepting proxy is incompatible with Erlang's TLS
  # stack (hex.pm is unreachable from Erlang). Same packages, same
  # versions; the transitive deps must be spelled out with override: true
  # since there is no hex resolver to fetch them.
  defp deps do
    [
      {:bandit, git: "https://github.com/mtrudel/bandit.git", tag: "1.12.0", override: true},
      {:plug, git: "https://github.com/elixir-plug/plug.git", tag: "v1.20.1", override: true},
      {:file_system, git: "https://github.com/falood/file_system.git", tag: "v1.1.1"},
      {:thousand_island,
       git: "https://github.com/mtrudel/thousand_island.git", tag: "1.5.0", override: true},
      {:plug_crypto,
       git: "https://github.com/elixir-plug/plug_crypto.git", tag: "v2.1.1", override: true},
      {:mime, git: "https://github.com/elixir-plug/mime.git", tag: "v2.0.7", override: true},
      {:websock,
       git: "https://github.com/phoenixframework/websock.git", tag: "0.5.3", override: true},
      {:websock_adapter,
       git: "https://github.com/phoenixframework/websock_adapter.git",
       tag: "0.6.0",
       override: true},
      {:hpax, git: "https://github.com/elixir-mint/hpax.git", tag: "v1.0.3", override: true},
      {:telemetry,
       git: "https://github.com/beam-telemetry/telemetry.git", tag: "v1.4.2", override: true},
      {:ecto_sql, git: "https://github.com/elixir-ecto/ecto_sql.git", tag: "v3.14.0"},
      {:ecto, git: "https://github.com/elixir-ecto/ecto.git", tag: "v3.14.0", override: true},
      {:postgrex,
       git: "https://github.com/elixir-ecto/postgrex.git", tag: "v0.22.2", override: true},
      {:db_connection,
       git: "https://github.com/elixir-ecto/db_connection.git", tag: "v2.10.1", override: true},
      {:decimal, git: "https://github.com/ericmj/decimal.git", tag: "v3.1.1", override: true}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
