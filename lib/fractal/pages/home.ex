defmodule Fractal.Pages.Home do
  @moduledoc "The default landing page, served at /."

  use Fractal.Page, path: "/", title: "Fractal"

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [], [
      tag(:h1, [], ["Fractal"]),
      tag(:p, [class: "lead"], [
        "An AI-first web framework for Elixir. You are looking at its default page."
      ]),
      tag(:h2, [], ["Registered pages"]),
      tag(:ul, [], page_links()),
      tag(:h2, [], ["Build your next page"]),
      tag(:p, [], [
        "Prompt your agent: ",
        tag(:code, [], ["Create a Fractal page at /pricing that lists three plans"]),
        " — it will read the built-in guides, generate the page, and verify it. ",
        "In development this page reloads on its own when code changes."
      ]),
      tag(:h2, [], ["Commands"]),
      tag(:ul, [], [
        tag(:li, [], [
          tag(:code, [], ["mix fractal.ai.docs"]),
          " — the docs agents read before writing code"
        ]),
        tag(:li, [], [
          tag(:code, [], ["mix fractal.gen.page Name"]),
          " — scaffold a page and its test"
        ]),
        tag(:li, [], [
          tag(:code, [], ["mix fractal.verify"]),
          " — run Fractal's verification checks and the test suite"
        ])
      ])
    ])
  end

  defp page_links do
    for page <- Fractal.Router.pages() do
      tag(:li, [], [
        tag(:a, [href: page.path()], [page.title()]),
        " — ",
        tag(:code, [], [page.path()])
      ])
    end
  end
end
