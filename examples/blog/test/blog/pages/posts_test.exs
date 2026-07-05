defmodule Blog.Pages.PostsTest do
  use Blog.DataCase, async: true

  import Fractal.Test

  alias Blog.Repo

  @valid_params %{
    "title" => "some value 1",
    "author" => "some author",
    "body" => "some longer value 2"
  }

  test "all post pages pass Fractal's verification checks" do
    pages = [
      Blog.Pages.Posts,
      Blog.Pages.NewPost,
      Blog.Pages.Post,
      Blog.Pages.EditPost
    ]

    results = Fractal.Verify.run(pages)
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "GET /posts lists posts" do
    {:ok, _post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = get("/posts")

    assert conn.status == 200
    assert conn.resp_body =~ "some value 1"
  end

  test "GET /posts/new shows the form" do
    conn = get("/posts/new")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(action="/posts")
    assert conn.resp_body =~ ~s(name="title")
  end

  test "POST /posts with valid params creates and redirects to the new post" do
    conn = post("/posts", @valid_params)

    assert conn.status == 303
    [location] = Plug.Conn.get_resp_header(conn, "location")
    assert location =~ ~r{^/posts/\d+$}

    shown = get(location)
    assert shown.status == 200
    assert shown.resp_body =~ "some value 1"
  end

  test "POST /posts with invalid params re-renders the form with errors" do
    conn = post("/posts", %{})

    assert conn.status == 200
    assert conn.resp_body =~ "can&#39;t be blank"
    assert Repo.aggregate(Blog.Post, :count) == 0
  end

  test "GET /posts/:id for a missing post renders not found" do
    conn = get("/posts/0")

    assert conn.status == 200
    assert conn.resp_body =~ "not found"
  end

  test "GET /posts/:id renders the post's head data over the site defaults" do
    {:ok, post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = get("/posts/#{post.id}")

    assert conn.resp_body =~ ~s(<meta name="description" content="some longer value 2">)
    assert conn.resp_body =~ ~s(<link rel="canonical" href="/posts/#{post.id}">)
    assert conn.resp_body =~ ~s(<meta property="og:title" content="some value 1">)
    assert conn.resp_body =~ ~s(<meta property="og:type" content="article">)
    # the page's description replaced the app-wide default
    refute conn.resp_body =~ "AI-first web framework written in Elixir"
  end

  test "GET /posts/:id shows the delete button" do
    {:ok, post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = get("/posts/#{post.id}")

    assert conn.status == 200
    assert conn.resp_body =~ ~s[action="/posts/#{post.id}"]
    assert conn.resp_body =~ ~s[name="_method" value="delete"]
    assert conn.resp_body =~ "Delete post"
  end

  test "GET /posts/:id/edit shows the pre-filled edit form" do
    {:ok, post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = get("/posts/#{post.id}/edit")

    assert conn.status == 200
    assert conn.resp_body =~ ~s[action="/posts/#{post.id}"]
    assert conn.resp_body =~ ~s[name="_method" value="put"]
    refute conn.resp_body =~ ~s[name="_method" value="delete"]
    assert conn.resp_body =~ "some value 1"
  end

  test "PUT /posts/:id updates the post and redirects to it" do
    {:ok, post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = put("/posts/#{post.id}", %{"title" => "some value 9"})

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/posts/#{post.id}"]
    assert to_string(Repo.get!(Blog.Post, post.id).title) == "some value 9"
  end

  test "PUT /posts/:id with invalid params re-renders the edit form with errors" do
    {:ok, post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = put("/posts/#{post.id}", %{"title" => ""})

    assert conn.status == 200
    assert conn.resp_body =~ "can&#39;t be blank"
    assert to_string(Repo.get!(Blog.Post, post.id).title) == "some value 1"
  end

  test "DELETE /posts/:id destroys the post and redirects to the index" do
    {:ok, post} =
      Repo.insert(Blog.Post.changeset(%Blog.Post{}, @valid_params))

    conn = delete("/posts/#{post.id}")

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/posts"]
    assert Repo.get(Blog.Post, post.id) == nil
  end
end
