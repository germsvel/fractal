defmodule Fractal.MixProject do
  use Mix.Project

  def project do
    [
      app: :fractal,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
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

  # Direct dependencies only — modules the framework calls (Plug/Bandit
  # for transport, Ecto/Postgrex for data, FileSystem for live reload,
  # Phoenix.PubSub for watch fan-out, :telemetry for events). Hex
  # resolves the transitive tree.
  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:plug, "~> 1.20"},
      {:file_system, "~> 1.1"},
      {:telemetry, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"}
    ]
  end
end
