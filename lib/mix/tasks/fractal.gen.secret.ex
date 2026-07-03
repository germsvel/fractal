defmodule Mix.Tasks.Fractal.Gen.Secret do
  @shortdoc "Generates a secret_key_base for sessions"

  @moduledoc """
  Prints a cryptographically random secret suitable for
  `config :fractal, :secret_key_base` (used to encrypt and sign the
  session cookie).

      mix fractal.gen.secret

  Put the value in `config/dev.exs` for development; in production,
  provide it via the `SECRET_KEY_BASE` environment variable (see
  `config/prod.exs`). `mix fractal.verify` fails when the secret is
  missing or shorter than 64 bytes.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    secret = 64 |> :crypto.strong_rand_bytes() |> Base.encode64()

    Mix.shell().info("""
    #{secret}

    Add it to your config:

        config :fractal, secret_key_base: "#{secret}"
    """)
  end
end
