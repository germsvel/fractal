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

  test "always includes the interactivity runtime" do
    assert Layout.shell("t", "b") =~ "/fractal/event"
    assert Layout.shell("t", "b") =~ "data-fx-event"
  end

  test "always includes the CSRF token meta tag" do
    assert Layout.shell("t", "b") =~ ~s(<meta name="fractal-csrf-token" content=")
  end

  test "links the fingerprinted CSS bundle instead of inlining styles" do
    html = Layout.shell("t", "b")

    assert html =~ ~r|<link rel="stylesheet" href="/fractal/assets/app-[0-9a-f]{8}\.css">|
    refute html =~ "<style>"
  end

  test "render/2 scopes the page with a data-page attribute" do
    html = Layout.render(Fractal.Pages.Home, %{params: %{}, session: %{}, path: "/", conn: nil})

    assert html =~ ~s(<main data-page="home">)
    # shells without a page (404/error) carry no scope
    assert Layout.shell("t", "b") =~ "<main>"
  end

  test "shows the signed-in bar only when the session has a user_name" do
    html = Layout.shell("t", "b", session: %{"user_name" => "Ada"})
    assert html =~ ~s(class="session-bar")
    assert html =~ "Ada"
    assert html =~ ~s(action="/logout")

    refute Layout.shell("t", "b") =~ ~s(class="session-bar")
    refute Layout.shell("t", "b", session: %{}) =~ ~s(class="session-bar")
  end

  test "renders flash banners, escaped" do
    html = Layout.shell("t", "b", flash: %{"info" => "Saved <b>!</b>"})

    assert html =~ ~s(class="flash flash-info")
    assert html =~ "Saved &lt;b&gt;!&lt;/b&gt;"
    refute Layout.shell("t", "b") =~ "class=\"flash"
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
