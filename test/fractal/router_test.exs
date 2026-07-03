defmodule Fractal.RouterTest do
  # DataCase: the method-dispatch tests exercise the database-backed
  # posts pages
  use Fractal.DataCase, async: true

  import Fractal.Test
  import Plug.Test, only: [conn: 3]

  alias Fractal.Router

  @post_params %{"title" => "A title", "author" => "An author", "body" => "A body"}

  # a request built without the Fractal.Test helpers: no test session,
  # no CSRF exemption — what a real (or forged) client sends
  defp raw(method, path, params) do
    method |> conn(path, params) |> Router.call([])
  end

  defp insert_post! do
    {:ok, post} = Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @post_params))
    post
  end

  test "discovers the home page" do
    assert Fractal.Pages.Home in Router.pages()
  end

  test "GET / renders the home page inside the layout" do
    conn = get("/")

    assert conn.status == 200
    assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
    assert conn.resp_body =~ "<!DOCTYPE html>"
    assert conn.resp_body =~ "<title>Fractal</title>"
    assert conn.resp_body =~ "AI-first web framework"
  end

  test "POST on an unknown path renders a 404" do
    conn = post("/nowhere")

    assert conn.status == 404
  end

  test "methods without a matching route render a 404" do
    conn = put("/")

    assert conn.status == 404
  end

  test "dynamic segments bind params" do
    post = insert_post!()

    conn = get("/posts/#{post.id}")

    assert conn.status == 200
    assert conn.resp_body =~ "A title"
  end

  test "native PUT and PATCH dispatch to the page's put route" do
    post = insert_post!()

    put_conn =
      put("/posts/#{post.id}", %{"title" => "via PUT"})

    assert put_conn.status == 303
    assert Repo.get!(Fractal.Post, post.id).title == "via PUT"

    patch_conn = patch("/posts/#{post.id}", %{"title" => "via PATCH"})

    assert patch_conn.status == 303
    assert Repo.get!(Fractal.Post, post.id).title == "via PATCH"
  end

  test "a POST with a hidden _method field is rewritten before dispatch" do
    post = insert_post!()

    conn = post("/posts/#{post.id}", %{"_method" => "put", "title" => "via override"})

    assert conn.status == 303
    assert Repo.get!(Fractal.Post, post.id).title == "via override"

    delete_conn = post("/posts/#{post.id}", %{"_method" => "delete"})

    assert delete_conn.status == 303
    assert Repo.get(Fractal.Post, post.id) == nil
  end

  describe "POST /fractal/event" do
    test "dispatches to the page's handle_event/2 and returns the fragment" do
      conn = fire_event("/counter", "increment", %{"count" => "1"})

      assert conn.status == 200
      assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
      assert conn.resp_body =~ "Count: </strong>2"
      refute conn.resp_body =~ "<html"
    end

    test "supports {:redirect, to} via the fx-redirect header" do
      conn = fire_event("/counter", "reset")

      assert conn.status == 204
      assert Plug.Conn.get_resp_header(conn, "fx-redirect") == ["/counter"]
    end

    test "rejects events the page does not declare, naming the declared ones" do
      conn = fire_event("/counter", "explode")

      assert conn.status == 404
      assert conn.resp_body =~ ~s("explode")
      assert conn.resp_body =~ "increment"
    end

    test "rejects events for paths with no page" do
      conn = fire_event("/nowhere", "increment")

      assert conn.status == 404
      assert conn.resp_body =~ "no page found"
    end
  end

  test "native DELETE dispatches to the page's delete route" do
    post = insert_post!()

    conn = delete("/posts/#{post.id}")

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/posts"]
    assert Repo.get(Fractal.Post, post.id) == nil
  end

  describe "CSRF protection" do
    test "a state-changing request without a token is rejected with instructions" do
      post = insert_post!()

      conn = raw(:post, "/posts", @post_params)

      assert conn.status == 403
      assert conn.resp_body =~ "CSRF token missing or invalid"
      assert conn.resp_body =~ "Fractal.Form"
      assert conn.resp_body =~ "Fractal.Test"
      # nothing was created or changed
      assert Repo.aggregate(Fractal.Post, :count) == 1
      assert Repo.get!(Fractal.Post, post.id).title == "A title"
    end

    test "a token-less event is rejected too" do
      conn = raw(:post, "/fractal/event", %{"_fx_path" => "/counter", "_fx_event" => "increment"})

      assert conn.status == 403
      assert conn.resp_body =~ "CSRF token missing or invalid"
    end

    test "the real token round-trip works: page renders token, POST with it succeeds" do
      get_conn = raw(:get, "/login", %{})

      assert [token] =
               Regex.run(~r/name="fractal-csrf-token" content="([^"]+)"/, get_conn.resp_body,
                 capture: :all_but_first
               )

      assert [set_cookie | _] = Plug.Conn.get_resp_header(get_conn, "set-cookie")
      cookie = set_cookie |> String.split(";") |> hd()

      conn =
        :post
        |> conn("/login", %{"name" => "Ada", "_csrf_token" => token})
        |> Plug.Conn.put_req_header("cookie", cookie)
        |> Router.call([])

      assert conn.status == 303
    end

    test "the session cookie is SameSite=Lax" do
      get_conn = raw(:get, "/login", %{})

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
    assert conn.resp_body =~ ~s(href="/")
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
end
