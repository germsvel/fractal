defmodule Blog.Pages.Blog do
  @moduledoc "The Blog page, served at /blog."

  use Fractal.Page, path: "/blog", title: "Blog"

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [class: "blog"], [
      tag(:h1, [], ["Blog"]),
      tag(:p, [class: "lead"], [
        "Essays, release notes, and field notes from building Fractal."
      ]),
      sample_post(),
      tag(:aside, [class: "blog-notes"], [
        tag(:h2, [], ["More sample notes"]),
        tag(:ul, [], [
          tag(:li, [], ["How Fractal discovers pages automatically"]),
          tag(:li, [], ["Why HTML is escaped by default"]),
          tag(:li, [], ["Designing AI-first development feedback loops"])
        ])
      ])
    ])
  end

  defp sample_post do
    tag(:article, [class: "featured-post"], [
      tag(:header, [], [
        tag(:p, [], [tag(:time, [datetime: "2026-07-03"], ["July 3, 2026"])]),
        tag(:h2, [], ["Sample post: Building with Fractal"])
      ]),
      tag(:p, [], [
        "Fractal keeps pages small and explicit: one module declares a route, " <>
          "a title, and the HTML it renders. That shape makes it easy for AI " <>
          "agents to create, inspect, and verify pages without hunting through " <>
          "routers or templates."
      ]),
      tag(:h3, [], ["What this sample shows"]),
      tag(:ul, [], [
        tag(:li, [], ["A real /blog route backed by a Fractal page module"]),
        tag(:li, [], ["Semantic article markup for a featured sample post"]),
        tag(:li, [], ["A compact notes list for future blog entries"])
      ]),
      tag(:blockquote, [], [
        tag(:p, [], ["Pages are just modules, and verification is the feedback loop."])
      ]),
      tag(:p, [], [
        tag(:a, [href: "/"], ["Return home"])
      ])
    ])
  end
end
