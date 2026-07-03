defmodule Fractal.Pages.EditPost do
  @moduledoc "Form to edit a post; handles PUT /posts/:id in this same file."

  use Fractal.Page,
    path: "/posts/:id/edit",
    title: "Edit post",
    put: "/posts/:id"

  import Fractal.Form

  alias Fractal.Components.EmptyState
  alias Fractal.Repo

  @impl Fractal.Page
  def render(assigns) do
    case fetch(assigns.params["id"]) do
      nil ->
        component(EmptyState,
          title: "Post not found",
          back_href: "/posts",
          back_label: "Back to posts"
        )

      post ->
        changeset = assigns[:changeset] || Fractal.Post.changeset(post, %{})

        tag(:section, [], [
          tag(:h1, [], ["Edit post"]),
          form_for(changeset, "/posts/#{post.id}", [method: :put], [
            input(changeset, :title),
            input(changeset, :author),
            textarea(changeset, :body, rows: 6),
            submit("Save post")
          ]),
          tag(:p, [], [tag(:a, [href: "/posts/#{post.id}"], ["Back to post"])])
        ])
    end
  end

  @impl Fractal.Page
  def handle_put(assigns) do
    case fetch(assigns.params["id"]) do
      nil ->
        {:redirect, "/posts"}

      post ->
        case Repo.update(Fractal.Post.changeset(post, assigns.params)) do
          {:ok, post} -> {:redirect, "/posts/#{post.id}"}
          {:error, changeset} -> {:render, %{changeset: changeset}}
        end
    end
  end

  defp fetch(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> Repo.get(Fractal.Post, id)
      _ -> nil
    end
  end

  defp fetch(_id), do: nil
end
