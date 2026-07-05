defmodule Fractal.RouterTest do
  # framework routing tests run against the DB-less fixture pages in
  # test/support/fixtures.ex — no sample-app content, no DataCase
  use ExUnit.Case, async: true

  import Fractal.Test
  import Plug.Test, only: [conn: 3]

  alias Fractal.Fixtures.{EchoPage, EditPage, EventPage, FormPage, ShowPage, StaticPage}
  alias Fractal.Router

  # a request built without the Fractal.Test helpers: no test session,
  # no CSRF exemption — what a real (or forged) client sends
  defp raw(method, path, params) do
    method |> conn(path, params) |> Router.call([])
  end

  test "discovers pages, including the fixtures" do
    pages = Router.pages()

    assert StaticPage in pages
    assert EchoPage in pages
    assert ShowPage in pages
    assert FormPage in pages
    assert EditPage in pages
    assert EventPage in pages
  end

  test "GET renders a page inside the document" do
    conn = get("/fixtures")

    assert conn.status == 200
    assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
    assert conn.resp_body =~ "<!DOCTYPE html>"
    assert conn.resp_body =~ "<title>Fixtures"
    assert conn.resp_body =~ "The framework&#39;s own test pages."
    assert conn.resp_body =~ ~s(<main data-page="static-page">)
  end

  test "POST on an unknown path renders a 404" do
    conn = post("/nowhere")

    assert conn.status == 404
  end

  test "methods without a matching route render a 404" do
    conn = put("/")

    assert conn.status == 404
  end

  test "dynamic segments bind params, static segments win" do
    conn = get("/fixtures/42")

    assert conn.status == 200
    assert conn.resp_body =~ "Fixture 42"

    # /fixtures/new is a static route that also matches /fixtures/:id
    assert get("/fixtures/new").resp_body =~ "New fixture"
  end

  test "POST dispatches to the page's post route" do
    conn = post("/fixtures", %{"name" => "alpha"})

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/fixtures/alpha"]

    invalid = post("/fixtures", %{"name" => "  "})

    assert invalid.status == 200
    assert invalid.resp_body =~ "name is required"
  end

  test "framework plumbing params never reach pages" do
    posted = post("/fixtures/echo", %{"name" => "ada", "_csrf_token" => "tok"})

    assert posted.resp_body =~ ~s(&quot;name&quot; =&gt; &quot;ada&quot;)
    refute posted.resp_body =~ "&quot;_csrf_token&quot;"
    refute posted.resp_body =~ "&quot;_method&quot;"

    fired = fire_event("/fixtures/echo", "echo", %{"n" => "1"})

    assert fired.resp_body =~ ~s(&quot;n&quot; =&gt; &quot;1&quot;)
    refute fired.resp_body =~ "&quot;_fx_event&quot;"
    refute fired.resp_body =~ "&quot;_csrf_token&quot;"
  end

  test "native PUT and PATCH dispatch to the page's put route" do
    put_conn = put("/fixtures/7", %{"name" => "via PUT"})

    assert put_conn.status == 200
    assert put_conn.resp_body =~ "updated to via PUT (7)"

    patch_conn = patch("/fixtures/7", %{"name" => "via PATCH"})

    assert patch_conn.status == 200
    assert patch_conn.resp_body =~ "updated to via PATCH (7)"
  end

  test "a POST with a hidden _method field is rewritten before dispatch" do
    conn = post("/fixtures/7", %{"_method" => "put", "name" => "via override"})

    assert conn.status == 200
    assert conn.resp_body =~ "updated to via override (7)"

    delete_conn = post("/fixtures/7", %{"_method" => "delete"})

    assert delete_conn.status == 303
    assert Plug.Conn.get_resp_header(delete_conn, "location") == ["/fixtures?deleted=7"]
  end

  test "native DELETE dispatches to the page's delete route" do
    conn = delete("/fixtures/9")

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/fixtures?deleted=9"]
  end

  describe "POST /fractal/event" do
    test "dispatches to the page's handle_event/2 and returns the fragment" do
      conn = fire_event("/fixtures/ping", "ping", %{"n" => "41"})

      assert conn.status == 200
      assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
      assert conn.resp_body =~ "pong 42"
      refute conn.resp_body =~ "<html"
    end

    test "supports {:redirect, to} via the fx-redirect header" do
      conn = fire_event("/fixtures/ping", "reset")

      assert conn.status == 204
      assert Plug.Conn.get_resp_header(conn, "fx-redirect") == ["/fixtures/ping"]
    end

    test "rejects events the page does not declare, naming the declared ones" do
      conn = fire_event("/fixtures/ping", "explode")

      assert conn.status == 404
      assert conn.resp_body =~ ~s("explode")
      assert conn.resp_body =~ "ping"
    end

    test "rejects events for paths with no page" do
      conn = fire_event("/nowhere", "ping")

      assert conn.status == 404
      assert conn.resp_body =~ "no page found"
    end
  end

  describe "CSRF protection" do
    test "a state-changing request without a token is rejected with instructions" do
      conn = raw(:post, "/fixtures", %{"name" => "mallory"})

      assert conn.status == 403
      assert conn.resp_body =~ "CSRF token missing or invalid"
      assert conn.resp_body =~ "Fractal.Form"
      assert conn.resp_body =~ "Fractal.Test"
    end

    test "a token-less event is rejected too" do
      conn =
        raw(:post, "/fractal/event", %{"_fx_path" => "/fixtures/ping", "_fx_event" => "ping"})

      assert conn.status == 403
      assert conn.resp_body =~ "CSRF token missing or invalid"
    end

    test "the real token round-trip works: page renders token, POST with it succeeds" do
      get_conn = raw(:get, "/fixtures/new", %{})

      assert [token] =
               Regex.run(~r/name="fractal-csrf-token" content="([^"]+)"/, get_conn.resp_body,
                 capture: :all_but_first
               )

      assert [set_cookie | _] = Plug.Conn.get_resp_header(get_conn, "set-cookie")
      cookie = set_cookie |> String.split(";") |> hd()

      conn =
        :post
        |> conn("/fixtures", %{"name" => "ada", "_csrf_token" => token})
        |> Plug.Conn.put_req_header("cookie", cookie)
        |> Router.call([])

      assert conn.status == 303
    end

    test "the session cookie is SameSite=Lax" do
      get_conn = raw(:get, "/fixtures/new", %{})

      assert [set_cookie | _] = Plug.Conn.get_resp_header(get_conn, "set-cookie")
      assert set_cookie =~ "SameSite=Lax"
    end
  end

  test "GET on an unknown path renders a helpful 404" do
    conn = get("/does-not-exist")

    assert conn.status == 404
    assert conn.resp_body =~ "404"
    assert conn.resp_body =~ "/does-not-exist"
    # the 404 page lists existing routes and how to create the missing one
    assert conn.resp_body =~ ~s(href="/fixtures")
    assert conn.resp_body =~ "Create a Fractal page at /does-not-exist"
  end

  test "GET /fractal/reload returns the live-reload token" do
    conn = get("/fractal/reload")

    assert conn.status == 200
    assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
    assert %{"token" => token} = JSON.decode!(conn.resp_body)
    assert is_integer(token)
  end

  test "the reload token changes after a bump" do
    %{"token" => before_token} = JSON.decode!(get("/fractal/reload").resp_body)
    Fractal.LiveReload.bump()
    %{"token" => after_token} = JSON.decode!(get("/fractal/reload").resp_body)

    assert after_token != before_token
  end

  describe "assets" do
    test "serves the CSS bundle with immutable caching" do
      conn = get(Fractal.Assets.css_path())

      assert conn.status == 200
      assert {"content-type", "text/css; charset=utf-8"} in conn.resp_headers
      assert {"cache-control", "public, max-age=31536000, immutable"} in conn.resp_headers
      assert conn.resp_body =~ "--accent:"
    end

    test "serves static files under /assets" do
      conn = get("/assets/logo.svg")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "missing static files fall through to the 404 page" do
      conn = get("/assets/nope.png")

      assert conn.status == 404
    end
  end
end
