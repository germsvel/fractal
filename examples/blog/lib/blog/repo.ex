defmodule Blog.Repo do
  @moduledoc """
  The blog's Ecto repository (PostgreSQL).

  Database access goes through Ecto — schemas, changesets, and queries —
  rather than any framework-specific layer. See the forms_and_data guide.
  """

  use Ecto.Repo,
    otp_app: :blog,
    adapter: Ecto.Adapters.Postgres
end
