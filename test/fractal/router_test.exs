defmodule Fractal.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Fractal.Router

  defp get(path) do
    :get |> conn(path) |> Router.call(Router.init([]))
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
