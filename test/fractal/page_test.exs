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

  defmodule WithPost do
    use Fractal.Page, path: "/with-post/new", post: "/with-post"

    @impl Fractal.Page
    def render(_assigns), do: tag(:p, [], ["form"])

    @impl Fractal.Page
    def handle_post(assigns), do: {:redirect, "/with-post/" <> (assigns.params["n"] || "0")}
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

  defmodule WithAllActions do
    use Fractal.Page,
      path: "/waa/:id/edit",
      put: "/waa/:id",
      delete: "/waa/:id"

    @impl Fractal.Page
    def render(_assigns), do: tag(:p, [], ["edit"])

    @impl Fractal.Page
    def handle_put(_assigns), do: {:redirect, "/waa/1"}

    @impl Fractal.Page
    def handle_delete(_assigns), do: {:redirect, "/"}
  end

  test "post_path/0 defaults to nil and reflects the :post option" do
    assert Sample.post_path() == nil
    assert WithPost.post_path() == "/with-post"
    assert Fractal.Page.post_path(Sample) == nil
    assert Fractal.Page.post_path(WithPost) == "/with-post"
  end

  test "put and delete routes are declared like post routes" do
    assert WithAllActions.put_path() == "/waa/:id"
    assert WithAllActions.delete_path() == "/waa/:id"
    assert WithAllActions.post_path() == nil
    assert Fractal.Page.action_route(WithAllActions, :put) == "/waa/:id"
    assert Fractal.Page.action_route(WithAllActions, :delete) == "/waa/:id"
    assert Fractal.Page.action_route(Sample, :put) == nil
  end

  describe "match/2" do
    test "matches static routes exactly" do
      assert Fractal.Page.match("/about", ["about"]) == {:ok, %{}}
      assert Fractal.Page.match("/", []) == {:ok, %{}}
      assert Fractal.Page.match("/about", ["about", "team"]) == :error
      assert Fractal.Page.match("/about", []) == :error
    end

    test "binds dynamic segments" do
      assert Fractal.Page.match("/posts/:id", ["posts", "42"]) == {:ok, %{"id" => "42"}}

      assert Fractal.Page.match("/a/:x/b/:y", ["a", "1", "b", "2"]) ==
               {:ok, %{"x" => "1", "y" => "2"}}

      assert Fractal.Page.match("/posts/:id", ["comments", "42"]) == :error
    end
  end

  test "param_count/1 counts dynamic segments" do
    assert Fractal.Page.param_count("/about") == 0
    assert Fractal.Page.param_count("/posts/:id") == 1
    assert Fractal.Page.param_count("/a/:x/:y") == 2
  end

  test "route?/1 validates route patterns" do
    assert Fractal.Page.route?("/")
    assert Fractal.Page.route?("/posts/:id")
    refute Fractal.Page.route?("posts")
    refute Fractal.Page.route?("/spa ce")
    refute Fractal.Page.route?("/:123bad")
    refute Fractal.Page.route?(nil)
  end

  test "declaring post: without handle_post/1 fails to compile" do
    error =
      try do
        defmodule PostNoHandler do
          use Fractal.Page, path: "/pnh/new", post: "/pnh"

          @impl Fractal.Page
          def render(_assigns), do: "x"
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "does not define handle_post/1"
  end

  test "declaring put: without handle_put/1 fails to compile" do
    error =
      try do
        defmodule PutNoHandler do
          use Fractal.Page, path: "/pnh2/:id/edit", put: "/pnh2/:id"

          @impl Fractal.Page
          def render(_assigns), do: "x"
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "does not define handle_put/1"
  end

  test "defining handle_delete/1 without delete: fails to compile" do
    error =
      try do
        defmodule DeleteNoRoute do
          use Fractal.Page, path: "/dnr"

          @impl Fractal.Page
          def render(_assigns), do: "x"

          def handle_delete(_assigns), do: {:redirect, "/"}
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "does not declare a delete route"
  end

  test "defining handle_post/1 without post: fails to compile" do
    error =
      try do
        defmodule HandlerNoPost do
          use Fractal.Page, path: "/hnp"

          @impl Fractal.Page
          def render(_assigns), do: "x"

          def handle_post(_assigns), do: {:redirect, "/"}
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "does not declare a post route"
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
