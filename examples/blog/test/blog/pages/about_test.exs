defmodule Blog.Pages.AboutTest do
  use ExUnit.Case, async: true

  alias Fractal.HTML

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Blog.Pages.About])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "declares its route" do
    assert Blog.Pages.About.path() == "/about"
  end

  test "renders its content" do
    html =
      %{params: %{}, path: "/about", conn: nil}
      |> Blog.Pages.About.render()
      |> HTML.to_safe()
      |> HTML.safe_to_string()

    assert html =~ "About"
  end
end
