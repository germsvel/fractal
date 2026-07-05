defmodule Blog.Post do
  @moduledoc "The Post schema, backed by the posts table."

  use Ecto.Schema

  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :author, :string
    field :body, :string

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a post."
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :author, :body])
    |> validate_required([:title, :author, :body])
  end
end
