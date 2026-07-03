defmodule Fractal.Pages.Blog do
  @moduledoc "A placeholder blog page, served at /blog."

  use Fractal.Page, path: "/blog", title: "Blog"

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [], [
      tag(:h1, [], ["Blog"]),
      tag(:p, [class: "lead"], [
        "A future home for essays, release notes, and notes from building Fractal."
      ]),
      tag(:article, [], [
        tag(:p, [], [tag(:time, [datetime: "2026-07-03"], ["July 3, 2026"])]),
        tag(:h2, [], ["Sample post: Building with Fractal"]),
        tag(:p, [], [
          "This sample post is a placeholder for the blog. Soon, this space will collect short updates about the framework, page patterns, and AI-first development workflows."
        ]),
        tag(:p, [], [
          tag(:a, [href: "/"], ["Return home"])
        ])
      ])
    ])
  end
end
