defmodule Fractal.LayoutTest do
  use ExUnit.Case

  alias Fractal.{HTML, Layout}

  test "shell/2 wraps content in a full document with an escaped title" do
    html = Layout.shell("A <b>title</b>", HTML.tag(:p, [], ["body"]))

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "<title>A &lt;b&gt;title&lt;/b&gt;</title>"
    assert html =~ "<main><p>body</p></main>"
  end

  test "render/2 uses the page's title and content" do
    html = Layout.render(Fractal.Pages.Home, %{params: %{}, path: "/", conn: nil})

    assert html =~ "<title>Fractal</title>"
    assert html =~ "AI-first web framework"
  end

  test "includes the live-reload script only when enabled" do
    original = Application.get_env(:fractal, :live_reload)
    on_exit(fn -> reset_env(original) end)

    Application.put_env(:fractal, :live_reload, true)
    assert Layout.shell("t", "b") =~ "/fractal/reload"

    Application.put_env(:fractal, :live_reload, false)
    refute Layout.shell("t", "b") =~ "/fractal/reload"
  end

  defp reset_env(nil), do: Application.delete_env(:fractal, :live_reload)
  defp reset_env(value), do: Application.put_env(:fractal, :live_reload, value)
end
