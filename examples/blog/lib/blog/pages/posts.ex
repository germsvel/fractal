defmodule Blog.Pages.Posts do
  @moduledoc """
  Lists all posts, served at /posts.

  The list is live: it watches the "posts" topic, so a post created in
  another browser appears here without a reload (the new-post page rings
  the doorbell with `publish("posts")`).
  """

  use Fractal.Page, path: "/posts", title: "Posts", watch: ["posts"]

  import Ecto.Query, only: [order_by: 2]

  alias Blog.Repo

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [], [
      tag(:h1, [], ["Posts"]),
      posts_region(),
      tag(:p, [], [tag(:a, [href: "/posts/new"], ["New post"])])
    ])
  end

  @impl Fractal.Page
  def handle_watch("posts", _assigns) do
    {:fragment, posts_region()}
  end

  defp posts_region do
    tag(:div, [id: "posts"], [
      Blog.Post |> order_by(desc: :id) |> Repo.all() |> render_list()
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
