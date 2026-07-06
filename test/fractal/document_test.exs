defmodule Fractal.DocumentTest do
  use ExUnit.Case

  alias Fractal.{Document, HTML}

  # the app's Layout is a single-instance module (like the checkpoint),
  # so document tests observe it through the discovered fixture layout
  @site Fractal.Layout.site()

  test "shell/3 wraps content in a full document with an escaped, composed title" do
    html = Document.shell("A <b>title</b>", HTML.tag(:p, [], ["body"]))

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "<title>A &lt;b&gt;title&lt;/b&gt; — #{@site.name}</title>"
    assert html =~ "<main><p>body</p></main>"
  end

  test "a title equal to the site name is not composed" do
    assert Document.shell(@site.name, "b") =~ "<title>#{@site.name}</title>"
  end

  test "the app layout's site data reaches the head" do
    html = Document.shell("t", "b")

    assert html =~ ~s(<html lang="#{@site.lang}">)
    assert html =~ ~s(<link rel="icon" href="#{@site.favicon}">)
    assert html =~ ~s(<meta name="theme-color" content="#{@site.theme_color}">)
  end

  test "render/2 uses the page's title and content" do
    html =
      Document.render(Fractal.Fixtures.StaticPage, %{
        params: %{},
        session: %{},
        context: %{},
        path: "/fixtures",
        conn: nil
      })

    assert html =~ "<title>Fixtures — #{@site.name}</title>"
    assert html =~ "The framework&#39;s own test pages."
  end

  test "always includes the interactivity runtime" do
    assert Document.shell("t", "b") =~ "/fractal/event"
    assert Document.shell("t", "b") =~ "data-fx-event"
    # the push half is part of the same runtime; it only activates on
    # pages that carry the data-fx-watch on-switch
    assert Document.shell("t", "b") =~ "/fractal/watch"
    assert Document.shell("t", "b") =~ "EventSource"
  end

  test "only pages that declare watch: carry the data-fx-watch on-switch" do
    assigns = %{params: %{"room" => "1"}, session: %{}, context: %{}, path: "/", conn: nil}

    assert Document.render(Fractal.Fixtures.WatchPage, assigns) =~
             ~s(<main data-page="watch-page" data-fx-watch>)

    # (the runtime JS mentions the attribute name; the <main> tag is
    # what decides whether a connection opens)
    assert Document.render(Fractal.Fixtures.StaticPage, %{assigns | params: %{}}) =~
             ~s(<main data-page="static-page">)
  end

  test "always includes the CSRF token meta tag" do
    assert Document.shell("t", "b") =~ ~s(<meta name="fractal-csrf-token" content=")
  end

  test "links the fingerprinted CSS bundle instead of inlining styles" do
    html = Document.shell("t", "b")

    assert html =~ ~r|<link rel="stylesheet" href="/fractal/assets/app-[0-9a-f]{8}\.css">|
    refute html =~ "<style>"
  end

  test "render/2 scopes the page with a data-page attribute" do
    html =
      Document.render(Fractal.Fixtures.StaticPage, %{
        params: %{},
        session: %{},
        context: %{},
        path: "/fixtures",
        conn: nil
      })

    assert html =~ ~s(<main data-page="static-page">)
    # shells without a page (404/error) carry no scope
    assert Document.shell("t", "b") =~ "<main>"
  end

  test "renders the app layout's chrome, scoped, when it renders something" do
    signed_in = %{
      conn: nil,
      params: %{},
      context: %{},
      path: "/",
      session: %{"fixture_user" => "Ada"}
    }

    html = Document.shell("t", "b", assigns: signed_in)

    assert html =~ ~s(<div data-layout style="display: contents">)
    assert html =~ ~s(class="session-bar")
    assert html =~ "Ada"

    # chrome returning nil renders nothing
    refute Document.shell("t", "b") =~ "data-layout"
    refute Document.shell("t", "b") =~ ~s(class="session-bar")
  end

  test "every page gets the site's default description" do
    assert Document.shell("t", "b") =~
             ~s(<meta name="description" content="#{@site.description}">)
  end

  test "page meta/1 renders into the head, escaped, over site defaults" do
    html =
      Document.render(Fractal.Fixtures.MetaPage, %{
        params: %{},
        session: %{},
        context: %{},
        path: "/fixtures/meta",
        conn: nil
      })

    # page description overrides the site default, escaped
    assert html =~
             ~s(<meta name="description" content="A page about &lt;b&gt;fixtures&lt;/b&gt;">)

    refute html =~ ~s(content="#{@site.description}")

    assert html =~ ~s(<link rel="canonical" href="/fixtures/meta">)
    assert html =~ ~s(<meta name="robots" content="noindex">)

    # og block with defaults filled in
    assert html =~ ~s(<meta property="og:title" content="Meta fixture">)
    assert html =~ ~s(<meta property="og:site_name" content="#{@site.name}">)
    assert html =~ ~s(<meta property="og:type" content="article">)
    assert html =~ ~r{<meta property="og:image" content="/assets/logo\.svg\?vsn=[0-9a-f]+">}
    assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)

    # the generic tail renders as data
    assert html =~ ~s(<link rel="alternate" type="application/rss+xml" href="/feed">)
  end

  test "pages without meta/1 render no og block or canonical" do
    html =
      Document.render(Fractal.Fixtures.StaticPage, %{
        params: %{},
        session: %{},
        context: %{},
        path: "/fixtures",
        conn: nil
      })

    refute html =~ "og:title"
    refute html =~ ~s(rel="canonical")
  end

  test "renders flash banners, escaped" do
    html = Document.shell("t", "b", flash: %{"info" => "Saved <b>!</b>"})

    assert html =~ ~s(class="flash flash-info")
    assert html =~ "Saved &lt;b&gt;!&lt;/b&gt;"
    refute Document.shell("t", "b") =~ "class=\"flash"
  end

  describe "dev-only provenance and the dev bar" do
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

    @assigns %{params: %{}, session: %{}, context: %{}, path: "/fixtures", conn: nil}

    test "dev documents carry the page source meta and the dev bar" do
      Application.put_env(:fractal, :live_reload, true)

      html = Document.render(Fractal.Fixtures.StaticPage, @assigns)

      assert html =~
               ~s(<meta name="fractal-source" content="test/support/fixtures.ex">)

      assert html =~ "fractal-dev-bar"

      # the dev reload client: SSE listener, css swap, error overlay
      assert html =~ ~s{new EventSource("/fractal/reload")}
      assert html =~ "fractal-compile-error"
    end

    test "the layout chrome carries data-source in dev" do
      Application.put_env(:fractal, :live_reload, true)

      signed_in = %{@assigns | session: %{"fixture_user" => "Ada"}}
      html = Document.shell("t", "b", assigns: signed_in)

      assert html =~
               ~s(<div data-layout data-source="test/support/fixtures.ex" style="display: contents">)
    end

    test "prod documents carry none of it" do
      html = Document.render(Fractal.Fixtures.StaticPage, @assigns)

      refute html =~ "fractal-source"
      refute html =~ "fractal-dev-bar"
      refute html =~ "data-source"
      refute html =~ "/fractal/reload"
      refute html =~ "fractal-compile-error"

      signed_in = %{@assigns | session: %{"fixture_user" => "Ada"}}

      assert Document.shell("t", "b", assigns: signed_in) =~
               ~s(<div data-layout style="display: contents">)
    end
  end

  test "the layout's style/0 lands in the bundle, scoped under data-layout" do
    {_hash, css} = Fractal.Assets.css_bundle()

    assert css =~ "[data-layout] {"
    assert css =~ ".session-bar"
  end
end
