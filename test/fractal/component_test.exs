defmodule Fractal.ComponentTest do
  # not async: the gallery tests toggle the global live_reload config
  use ExUnit.Case

  import Fractal.Component
  import Fractal.Test, only: [get: 1]

  alias Fractal.Fixtures.Note
  alias Fractal.HTML

  defmodule Badge do
    use Fractal.Component

    @impl Fractal.Component
    def render(assigns) do
      tag(:span, [class: "badge"], [assigns.label])
    end

    @impl Fractal.Component
    def example, do: %{label: "New"}
  end

  describe "component/2" do
    test "renders wrapped in a layout-neutral scoping element" do
      html = Badge |> component(label: "Hi <b>") |> HTML.safe_to_string()

      assert html =~ ~s(<div data-component="badge" style="display: contents">)
      assert html =~ ~s(<span class="badge">Hi &lt;b&gt;</span>)
    end

    test "carries data-source provenance in dev only" do
      original = Application.get_env(:fractal, :live_reload)

      on_exit(fn ->
        if original == nil do
          Application.delete_env(:fractal, :live_reload)
        else
          Application.put_env(:fractal, :live_reload, original)
        end
      end)

      Application.put_env(:fractal, :live_reload, true)

      html = Badge |> component(label: "x") |> HTML.safe_to_string()

      assert html =~
               ~s(data-component="badge" data-source="test/fractal/component_test.exs")
    end

    test "accepts maps or keywords" do
      from_map = Badge |> component(%{label: "x"}) |> HTML.safe_to_string()
      from_kw = Badge |> component(label: "x") |> HTML.safe_to_string()

      assert from_map == from_kw
    end

    test "assigns carry safe HTML as slots" do
      html =
        Note
        |> component(title: "Empty", body: HTML.tag(:strong, [], ["Home"]))
        |> HTML.safe_to_string()

      assert html =~ "<strong>Home</strong>"
    end
  end

  test "use Fractal.Component rejects options — components are render-only" do
    error =
      try do
        defmodule Sneaky do
          use Fractal.Component, path: "/nope"

          def render(_assigns), do: "x"
          def example, do: %{}
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "render-only"
  end

  test "all/0 discovers components; component?/1 rejects non-components" do
    assert Note in all()
    refute Fractal.Fixtures.StaticPage in all()
    assert component?(Note)
    refute component?(Fractal.Fixtures.StaticPage)
    refute component?(Fractal.HTML)
  end

  test "slug/1 and style/1" do
    assert slug(Note) == "note"
    assert style(Note) =~ "border-left"
    assert style(Badge) == nil
  end

  describe "the gallery" do
    setup do
      original = Application.get_env(:fractal, :live_reload)

      on_exit(fn ->
        if original == nil do
          Application.delete_env(:fractal, :live_reload)
        else
          Application.put_env(:fractal, :live_reload, original)
        end
      end)

      :ok
    end

    test "renders every component with its example in dev" do
      Application.put_env(:fractal, :live_reload, true)

      conn = get("/fractal/components")

      assert conn.status == 200
      assert conn.resp_body =~ "Fractal.Fixtures.Note"
      # the example, rendered live
      assert conn.resp_body =~ "Heads up"
      assert conn.resp_body =~ ~s(data-component="note")
      assert conn.resp_body =~ "Example assigns"
    end

    test "is not served outside dev" do
      Application.put_env(:fractal, :live_reload, false)

      assert get("/fractal/components").status == 404
    end
  end
end
