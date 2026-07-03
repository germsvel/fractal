defmodule Fractal.RouterTest do
  # DataCase: the method-dispatch tests exercise the database-backed
  # posts pages
  use Fractal.DataCase, async: true

  import Plug.Test

  alias Fractal.Router

  @post_params %{"title" => "A title", "author" => "An author", "body" => "A body"}

  defp get(path) do
    :get |> conn(path) |> Router.call(Router.init([]))
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
    conn = :post |> conn("/nowhere", %{}) |> Router.call(Router.init([]))

    assert conn.status == 404
  end

  test "methods without a matching route render a 404" do
    conn = :put |> conn("/") |> Router.call(Router.init([]))

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
      :put |> conn("/posts/#{post.id}", %{"title" => "via PUT"}) |> Router.call([])

    assert put_conn.status == 303
    assert Repo.get!(Fractal.Post, post.id).title == "via PUT"

    patch_conn =
      :patch |> conn("/posts/#{post.id}", %{"title" => "via PATCH"}) |> Router.call([])

    assert patch_conn.status == 303
    assert Repo.get!(Fractal.Post, post.id).title == "via PATCH"
  end

  test "a POST with a hidden _method field is rewritten before dispatch" do
    post = insert_post!()

    conn =
      :post
      |> conn("/posts/#{post.id}", %{"_method" => "put", "title" => "via override"})
      |> Router.call([])

    assert conn.status == 303
    assert Repo.get!(Fractal.Post, post.id).title == "via override"

    delete_conn =
      :post
      |> conn("/posts/#{post.id}", %{"_method" => "delete"})
      |> Router.call([])

    assert delete_conn.status == 303
    assert Repo.get(Fractal.Post, post.id) == nil
  end

  test "native DELETE dispatches to the page's delete route" do
    post = insert_post!()

    conn = :delete |> conn("/posts/#{post.id}") |> Router.call([])

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/posts"]
    assert Repo.get(Fractal.Post, post.id) == nil
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
