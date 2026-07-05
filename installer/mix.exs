defmodule Fractal.New.MixProject do
  use Mix.Project

  def project do
    [
      app: :fractal_new,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: false,
      deps: []
    ]
  end

  def application do
    [extra_applications: [:eex, :crypto]]
  end
end
