defmodule Fractal.Pages.HomeTest do
  use ExUnit.Case, async: true

  alias Fractal.HTML
  alias Fractal.Pages.Home

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Home])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "is served at the root path" do
    assert Home.path() == "/"
    assert Home.title() == "Fractal"
  end

  test "renders the welcome content and links to registered pages" do
    html =
      %{params: %{}, path: "/", conn: nil}
      |> Home.render()
      |> HTML.to_safe()
      |> HTML.safe_to_string()

    assert html =~ "AI-first web framework"
    assert html =~ ~s(href="/")
    assert html =~ "mix fractal.verify"
    assert html =~ "mix fractal.gen.page"
    assert html =~ "mix fractal.ai.docs"
  end
end
