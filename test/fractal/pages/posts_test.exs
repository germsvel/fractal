defmodule Fractal.Pages.PostsTest do
  use Fractal.DataCase, async: true

  import Plug.Test

  alias Fractal.{Repo, Router}

  @valid_params %{
    "title" => "some value 1",
    "author" => "some author",
    "body" => "some longer value 2"
  }

  defp get_page(path), do: :get |> conn(path) |> Router.call([])
  defp post_page(path, params), do: :post |> conn(path, params) |> Router.call([])
  defp put_page(path, params), do: :put |> conn(path, params) |> Router.call([])
  defp delete_page(path), do: :delete |> conn(path) |> Router.call([])

  test "all post pages pass Fractal's verification checks" do
    pages = [
      Fractal.Pages.Posts,
      Fractal.Pages.NewPost,
      Fractal.Pages.Post,
      Fractal.Pages.EditPost
    ]

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

  test "GET /posts/:id shows the delete button" do
    {:ok, post} =
      Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @valid_params))

    conn = get_page("/posts/#{post.id}")

    assert conn.status == 200
    assert conn.resp_body =~ ~s[action="/posts/#{post.id}"]
    assert conn.resp_body =~ ~s[name="_method" value="delete"]
    assert conn.resp_body =~ "Delete post"
  end

  test "GET /posts/:id/edit shows the pre-filled edit form" do
    {:ok, post} =
      Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @valid_params))

    conn = get_page("/posts/#{post.id}/edit")

    assert conn.status == 200
    assert conn.resp_body =~ ~s[action="/posts/#{post.id}"]
    assert conn.resp_body =~ ~s[name="_method" value="put"]
    refute conn.resp_body =~ ~s[name="_method" value="delete"]
    assert conn.resp_body =~ "some value 1"
  end

  test "PUT /posts/:id updates the post and redirects to it" do
    {:ok, post} =
      Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @valid_params))

    conn = put_page("/posts/#{post.id}", %{"title" => "some value 9"})

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/posts/#{post.id}"]
    assert to_string(Repo.get!(Fractal.Post, post.id).title) == "some value 9"
  end

  test "PUT /posts/:id with invalid params re-renders the edit form with errors" do
    {:ok, post} =
      Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @valid_params))

    conn = put_page("/posts/#{post.id}", %{"title" => ""})

    assert conn.status == 200
    assert conn.resp_body =~ "can&#39;t be blank"
    assert to_string(Repo.get!(Fractal.Post, post.id).title) == "some value 1"
  end

  test "DELETE /posts/:id destroys the post and redirects to the index" do
    {:ok, post} =
      Repo.insert(Fractal.Post.changeset(%Fractal.Post{}, @valid_params))

    conn = delete_page("/posts/#{post.id}")

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/posts"]
    assert Repo.get(Fractal.Post, post.id) == nil
  end
end
