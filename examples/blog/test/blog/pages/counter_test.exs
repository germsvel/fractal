defmodule Blog.Pages.CounterTest do
  use ExUnit.Case, async: true

  import Fractal.Test

  alias Fractal.HTML

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Blog.Pages.Counter])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "renders the counter region with its triggers" do
    html =
      %{params: %{}, path: "/counter", conn: nil}
      |> Blog.Pages.Counter.render()
      |> HTML.to_safe()
      |> HTML.safe_to_string()

    assert html =~ ~s(id="counter")
    assert html =~ "Count: </strong>0"
    assert html =~ ~s(data-fx-event="increment")
    assert html =~ ~s(data-fx-target="#counter")
  end

  test "increment returns the region fragment with the next count" do
    conn = fire_event("/counter", "increment", %{"count" => "41"})

    assert conn.status == 200
    assert conn.resp_body =~ "Count: </strong>42"
    # the fragment carries the new state for the next event
    assert conn.resp_body =~ ~s(&quot;count&quot;:&quot;42&quot;)
    refute conn.resp_body =~ "<html", "fragments are not wrapped in the layout"
  end

  test "decrement goes below zero" do
    conn = fire_event("/counter", "decrement", %{"count" => "0"})

    assert conn.status == 200
    assert conn.resp_body =~ "Count: </strong>-1"
  end

  test "a garbled count falls back to zero" do
    conn = fire_event("/counter", "increment", %{"count" => "not-a-number"})

    assert conn.status == 200
    assert conn.resp_body =~ "Count: </strong>1"
  end

  test "reset redirects the browser back to the page" do
    conn = fire_event("/counter", "reset")

    assert conn.status == 204
    assert Plug.Conn.get_resp_header(conn, "fx-redirect") == ["/counter"]
  end
end
