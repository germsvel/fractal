defmodule Fractal.Components.EmptyStateTest do
  use ExUnit.Case, async: true

  import Fractal.Component, only: [component: 2]

  alias Fractal.Components.EmptyState
  alias Fractal.HTML

  test "passes Fractal's component verification checks" do
    results = Fractal.Verify.run_components([EmptyState])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "renders the title and the way back" do
    html =
      EmptyState
      |> component(title: "Post not found", back_href: "/posts", back_label: "Back to posts")
      |> HTML.safe_to_string()

    assert html =~ ~s(data-component="empty-state")
    assert html =~ "Post not found"
    assert html =~ ~s(<a href="/posts">Back to posts</a>)
  end
end
