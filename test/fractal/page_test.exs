defmodule Fractal.PageTest do
  use ExUnit.Case, async: true

  alias Fractal.HTML

  defmodule Sample do
    use Fractal.Page, path: "/sample", title: "Sample page"

    @impl Fractal.Page
    def render(assigns) do
      tag(:p, [], ["hello from ", assigns.path])
    end
  end

  defmodule NoTitle do
    use Fractal.Page, path: "/no-title"

    @impl Fractal.Page
    def render(_assigns), do: tag(:p, [], ["untitled"])
  end

  test "path/0 and title/0 come from the use options" do
    assert Sample.path() == "/sample"
    assert Sample.title() == "Sample page"
  end

  test "title defaults to a humanized module name" do
    assert NoTitle.title() == "No title"
  end

  test "render/1 receives assigns and builds safe HTML" do
    html =
      %{params: %{}, path: "/sample", conn: nil}
      |> Sample.render()
      |> HTML.safe_to_string()

    assert html == "<p>hello from /sample</p>"
  end

  test "page?/1 recognizes pages and rejects other modules" do
    assert Fractal.Page.page?(Sample)
    assert Fractal.Page.page?(Fractal.Pages.Home)
    refute Fractal.Page.page?(Fractal.HTML)
    refute Fractal.Page.page?(:not_a_module)
  end

  test "compiling a page without a path fails" do
    error =
      try do
        defmodule MissingPath do
          use Fractal.Page, []

          @impl Fractal.Page
          def render(_assigns), do: "x"
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "must declare a route"
  end

  test "compiling a page with a malformed path fails" do
    error =
      try do
        defmodule BadPath do
          use Fractal.Page, path: "no-leading-slash"

          @impl Fractal.Page
          def render(_assigns), do: "x"
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "invalid path"
  end
end
