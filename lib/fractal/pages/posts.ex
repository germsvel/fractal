defmodule Fractal.Pages.Posts do
  @moduledoc "Lists all posts, served at /posts."

  use Fractal.Page, path: "/posts", title: "Posts"

  import Ecto.Query, only: [order_by: 2]

  alias Fractal.Repo

  @impl Fractal.Page
  def render(_assigns) do
    posts = Repo.all(order_by(Fractal.Post, desc: :id))

    tag(:section, [], [
      tag(:h1, [], ["Posts"]),
      render_list(posts),
      tag(:p, [], [tag(:a, [href: "/posts/new"], ["New post"])])
    ])
  end

  defp render_list([]), do: tag(:p, [], ["No posts yet."])

  defp render_list(posts) do
    tag(
      :ul,
      [],
      for post <- posts do
        tag(:li, [], [
          tag(:a, [href: "/posts/#{post.id}"], [to_string(post.title)])
        ])
      end
    )
  end
end
