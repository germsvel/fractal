defmodule Blog.Pages.BlogTest do
  use ExUnit.Case, async: true

  alias Fractal.HTML
  alias Blog.Pages.Blog

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Blog])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "declares its route" do
    assert Blog.path() == "/blog"
    assert Blog.title() == "Blog"
  end

  test "renders the blog content and sample post" do
    html =
      %{params: %{}, path: "/blog", conn: nil}
      |> Blog.render()
      |> HTML.to_safe()
      |> HTML.safe_to_string()

    assert html =~ "Essays, release notes, and field notes"
    assert html =~ "Sample post: Building with Fractal"
    assert html =~ "What this sample shows"
    assert html =~ "How Fractal discovers pages automatically"
    assert html =~ "July 3, 2026"
    assert html =~ ~s(href="/")
  end
end
