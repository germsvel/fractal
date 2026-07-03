defmodule Fractal.Repo do
  @moduledoc """
  Fractal's Ecto repository (PostgreSQL).

  Database access goes through Ecto — schemas, changesets, and queries —
  rather than any framework-specific layer. See `guides/forms_and_data.md`.
  """

  use Ecto.Repo,
    otp_app: :fractal,
    adapter: Ecto.Adapters.Postgres
end
