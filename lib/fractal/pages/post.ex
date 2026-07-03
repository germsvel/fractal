defmodule Fractal.Pages.Post do
  @moduledoc "Shows a single post, served at /posts/:id."

  use Fractal.Page, path: "/posts/:id", title: "Post"

  alias Fractal.Repo

  @impl Fractal.Page
  def render(assigns) do
    case fetch(assigns.params["id"]) do
      nil ->
        tag(:section, [], [
          tag(:h1, [], ["Post not found"]),
          tag(:p, [], [tag(:a, [href: "/posts"], ["Back to posts"])])
        ])

      post ->
        tag(:section, [], [
          tag(:h1, [], [to_string(post.title)]),
          tag(:p, [], [tag(:strong, [], ["Body: "]), to_string(post.body)]),
          tag(:p, [], [tag(:a, [href: "/posts"], ["Back to posts"])])
        ])
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
