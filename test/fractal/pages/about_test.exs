defmodule Fractal.Pages.AboutTest do
  use ExUnit.Case, async: true

  alias Fractal.HTML

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Fractal.Pages.About])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "declares its route" do
    assert Fractal.Pages.About.path() == "/about"
  end

  test "renders its content" do
    html =
      %{params: %{}, path: "/about", conn: nil}
      |> Fractal.Pages.About.render()
      |> HTML.to_safe()
      |> HTML.safe_to_string()

    assert html =~ "About"
  end
end
