defmodule Fractal.Pages.Post do
  @moduledoc "Shows a single post, served at /posts/:id."

  use Fractal.Page, path: "/posts/:id", title: "Post", delete: "/posts/:id"

  import Fractal.Form

  alias Fractal.Components.EmptyState
  alias Fractal.Repo

  @impl Fractal.Page
  def meta(assigns) do
    case fetch(assigns.params["id"]) do
      nil ->
        %{}

      post ->
        %{
          description: excerpt(post.body),
          canonical: "/posts/#{post.id}",
          og: %{title: to_string(post.title), type: "article"}
        }
    end
  end

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
        tag(:section, [], [
          tag(:h1, [], [to_string(post.title)]),
          tag(:p, [], [tag(:strong, [], ["Author: "]), to_string(post.author)]),
          tag(:p, [], [tag(:strong, [], ["Body: "]), to_string(post.body)]),
          tag(:p, [], [
            tag(:a, [href: "/posts/#{post.id}/edit"], ["Edit"]),
            " · ",
            tag(:a, [href: "/posts"], ["Back to posts"])
          ]),
          tag(:p, [], [
            button_to("Delete post", "/posts/#{post.id}", method: :delete)
          ])
        ])
    end
  end

  @impl Fractal.Page
  def handle_delete(assigns) do
    case fetch(assigns.params["id"]) do
      nil ->
        {:redirect, "/posts"}

      post ->
        Repo.delete!(post)
        {:redirect, "/posts"}
    end
  end

  defp fetch(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> Repo.get(Fractal.Post, id)
      _ -> nil
    end
  end

  defp fetch(_id), do: nil

  defp excerpt(body) do
    body = to_string(body)
    if String.length(body) > 150, do: String.slice(body, 0, 147) <> "...", else: body
  end
end
