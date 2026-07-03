defmodule Fractal.MixProject do
  use Mix.Project

  def project do
    [
      app: :fractal,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

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
       git: "https://github.com/beam-telemetry/telemetry.git", tag: "v1.4.2", override: true}
    ]
  end
end
