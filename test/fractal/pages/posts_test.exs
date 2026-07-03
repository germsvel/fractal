defmodule Fractal.Pages.PostsTest do
  use Fractal.DataCase, async: true

  import Plug.Test

  alias Fractal.{Repo, Router}

  @valid_params %{"title" => "some value 1", "body" => "some longer value 2"}

  defp get_page(path), do: :get |> conn(path) |> Router.call([])
  defp post_page(path, params), do: :post |> conn(path, params) |> Router.call([])

  test "all post pages pass Fractal's verification checks" do
    pages = [Fractal.Pages.Posts, Fractal.Pages.NewPost, Fractal.Pages.Post]
    results = Fractal.Verify.run(pages)
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "GET /posts lists posts" do
    {:ok, _post} =
      Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @valid_params))

    conn = get_page("/posts")

    assert conn.status == 200
    assert conn.resp_body =~ "some value 1"
  end

  test "GET /posts/new shows the form" do
    conn = get_page("/posts/new")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(action="/posts")
    assert conn.resp_body =~ ~s(name="title")
  end

  test "POST /posts with valid params creates and redirects to the new post" do
    conn = post_page("/posts", @valid_params)

    assert conn.status == 303
    [location] = Plug.Conn.get_resp_header(conn, "location")
    assert location =~ ~r{^/posts/\d+$}

    shown = get_page(location)
    assert shown.status == 200
    assert shown.resp_body =~ "some value 1"
  end

  test "POST /posts with invalid params re-renders the form with errors" do
    conn = post_page("/posts", %{})

    assert conn.status == 200
    assert conn.resp_body =~ "can&#39;t be blank"
    assert Repo.aggregate(Fractal.Post, :count) == 0
  end

  test "GET /posts/:id for a missing post renders not found" do
    conn = get_page("/posts/0")

    assert conn.status == 200
    assert conn.resp_body =~ "not found"
  end
end
