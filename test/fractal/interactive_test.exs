defmodule Fractal.InteractiveTest do
  use ExUnit.Case, async: true

  import Fractal.Interactive

  alias Fractal.HTML

  defp render(safe), do: safe |> HTML.to_safe() |> HTML.safe_to_string()

  describe "fx/2" do
    test "returns the data attributes for an event" do
      attrs = fx("search", target: "#results", on: :input, values: %{page: 2})
      html = render(HTML.tag(:input, [type: "text"] ++ attrs))

      assert html =~ ~s(data-fx-event="search")
      assert html =~ ~s(data-fx-on="input")
      assert html =~ ~s(data-fx-target="#results")
      assert html =~ ~s(data-fx-values="{&quot;page&quot;:&quot;2&quot;}")
    end

    test "defaults to click and omits empty values" do
      html = render(HTML.tag(:a, fx("go", target: "#x")))

      assert html =~ ~s(data-fx-on="click")
      refute html =~ "data-fx-values"
    end

    test "requires a target" do
      assert_raise ArgumentError, ~r/:target/, fn -> fx("go") end
    end

    test "rejects unknown trigger kinds" do
      assert_raise ArgumentError, ~r/:on must be/, fn -> fx("go", target: "#x", on: :hover) end
    end
  end

  describe "trigger/3" do
    test "renders a button wired to the event" do
      html = render(trigger("Go", "go", target: "#x", values: %{n: 1}, class: "primary"))

      assert html =~ ~s(<button type="button")
      assert html =~ ~s(data-fx-event="go")
      assert html =~ ~s(data-fx-target="#x")
      assert html =~ ~s(class="primary")
      assert html =~ ">Go</button>"
    end
  end

  test "runtime_js posts to the event endpoint" do
    js = runtime_js()

    assert js =~ "/fractal/event"
    assert js =~ "_fx_path"
    assert js =~ "_fx_event"
    assert js =~ "fx-redirect"
  end
end
