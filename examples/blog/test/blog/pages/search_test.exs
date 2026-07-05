defmodule Blog.Pages.SearchTest do
  use Blog.DataCase, async: true

  import Fractal.Test

  alias Blog.Repo

  defp create_post!(title) do
    {:ok, post} =
      Repo.insert(
        Blog.Post.changeset(%Blog.Post{}, %{
          "title" => title,
          "author" => "Tester",
          "body" => "A body"
        })
      )

    post
  end

  defp search(query) do
    fire_event("/search", "search", %{"q" => query})
  end

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Blog.Pages.Search])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "renders the search input wired to the results region" do
    conn = get("/search")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-fx-event="search")
    assert conn.resp_body =~ ~s(data-fx-on="input")
    assert conn.resp_body =~ ~s(data-fx-target="#results")
    assert conn.resp_body =~ ~s(id="results")
  end

  test "the search event filters posts by title, case-insensitively" do
    create_post!("Elixir tips")
    create_post!("Cooking notes")

    conn = search("elixir")

    assert conn.status == 200
    assert conn.resp_body =~ "Elixir tips"
    refute conn.resp_body =~ "Cooking notes"
  end

  test "reports when nothing matches" do
    create_post!("Elixir tips")

    conn = search("quantum")

    assert conn.status == 200
    assert conn.resp_body =~ "No posts match"
  end

  test "a blank query renders the placeholder instead of querying" do
    conn = search("   ")

    assert conn.status == 200
    assert conn.resp_body =~ "Results appear here as you type."
  end
end
