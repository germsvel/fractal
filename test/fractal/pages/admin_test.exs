defmodule Fractal.Pages.AdminTest do
  use Fractal.DataCase, async: true

  import Fractal.Test

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Fractal.Pages.Admin])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "anonymous requests are redirected to log in with a flash" do
    conn = get("/admin")

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/login"]
    assert Plug.Conn.get_session(conn, "_fractal_flash") == %{"error" => "Please log in first."}
  end

  test "signed-in requests see the dashboard, with context derivations" do
    conn = get("/admin", %{}, session: %{"user_name" => "Ada"})

    assert conn.status == 200
    assert conn.resp_body =~ "Hello, "
    assert conn.resp_body =~ "Ada"
    assert conn.resp_body =~ "posts published"
  end

  test "the guard also protects the page's events" do
    denied = fire_event("/admin", "refresh")

    assert denied.status == 204
    assert Plug.Conn.get_resp_header(denied, "fx-redirect") == ["/login"]

    allowed = fire_event("/admin", "refresh", %{}, session: %{"user_name" => "Ada"})

    assert allowed.status == 200
    assert allowed.resp_body =~ "posts published"
  end
end
