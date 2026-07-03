defmodule Fractal.Pages.NewPost do
  @moduledoc "Form to create a post; handles POST /posts in this same file."

  use Fractal.Page, path: "/posts/new", title: "New post", post: "/posts"

  import Fractal.Form

  alias Fractal.Repo

  @impl Fractal.Page
  def render(assigns) do
    changeset = assigns[:changeset] || Fractal.Post.changeset(%Fractal.Post{}, %{})

    tag(:section, [], [
      tag(:h1, [], ["New post"]),
      form_for(changeset, "/posts", [
        input(changeset, :title),
        textarea(changeset, :body, rows: 6),
        submit("Create post")
      ]),
      tag(:p, [], [tag(:a, [href: "/posts"], ["Back to posts"])])
    ])
  end

  @impl Fractal.Page
  def handle_post(assigns) do
    case Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, assigns.params)) do
      {:ok, post} -> {:redirect, "/posts/#{post.id}"}
      {:error, changeset} -> {:render, %{changeset: changeset}}
    end
  end
end
