defmodule Fractal.Pages.Search do
  @moduledoc """
  Live search over posts, served at /search.

  A sample of database-backed interactivity: the input fires a debounced
  `search` event as you type, and the results region re-renders with the
  matching posts. No JavaScript was written for this page.
  """

  use Fractal.Page, path: "/search", title: "Search", events: ["search"]

  import Ecto.Query, only: [from: 2]

  alias Fractal.Repo

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [], [
      tag(:h1, [], ["Search posts"]),
      tag(:div, [class: "field"], [
        tag(
          :input,
          [
            type: "text",
            name: "q",
            placeholder: "Type to search by title...",
            autocomplete: "off"
          ] ++
            fx("search", target: "#results", on: :input)
        )
      ]),
      results("")
    ])
  end

  @impl Fractal.Page
  def handle_event("search", assigns) do
    {:fragment, results(String.trim(assigns.params["q"] || ""))}
  end

  defp results("") do
    tag(:div, [id: "results"], [tag(:p, [], ["Results appear here as you type."])])
  end

  defp results(query) do
    posts =
      Repo.all(
        from post in Fractal.Post,
          where: ilike(post.title, ^"%#{query}%"),
          order_by: [desc: post.id],
          limit: 10
      )

    tag(:div, [id: "results"], [
      case posts do
        [] ->
          tag(:p, [], ["No posts match ", tag(:code, [], [query]), "."])

        posts ->
          tag(
            :ul,
            [],
            for post <- posts do
              tag(:li, [], [
                tag(:a, [href: "/posts/#{post.id}"], [to_string(post.title)]),
                " by ",
                to_string(post.author)
              ])
            end
          )
      end
    ])
  end
end
