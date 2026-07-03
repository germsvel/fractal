defmodule Fractal.Pages.LoginTest do
  use ExUnit.Case, async: true

  import Fractal.Test

  alias Fractal.Pages.Login

  test "passes Fractal's verification checks" do
    results = Fractal.Verify.run([Login])
    assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
  end

  test "logged out, renders the login form" do
    conn = get("/login")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(action="/login")
    assert conn.resp_body =~ ~s(name="name")
    refute conn.resp_body =~ ~s(class="session-bar")
  end

  test "logging in writes the session and redirects with a flash" do
    conn = post("/login", %{"name" => "Ada"})

    assert conn.status == 303
    assert Plug.Conn.get_resp_header(conn, "location") == ["/login"]
    assert Plug.Conn.get_session(conn, "user_name") == "Ada"
  end

  test "a blank name re-renders with an error and no session write" do
    conn = post("/login", %{"name" => "   "})

    assert conn.status == 200
    assert conn.resp_body =~ "Please enter a name."
    assert Plug.Conn.get_session(conn, "user_name") == nil
  end

  test "logged in, the page and the layout show the user" do
    conn = get("/login", %{}, session: %{"user_name" => "Ada"})

    assert conn.status == 200
    assert conn.resp_body =~ "Hello, "
    assert conn.resp_body =~ "Ada"
    # the layout's signed-in bar appears on every page, not just /login
    assert conn.resp_body =~ ~s(class="session-bar")

    assert get("/counter", %{}, session: %{"user_name" => "Ada"}).resp_body =~
             ~s(class="session-bar")
  end

  test "logging out clears the session" do
    conn = delete("/logout", %{}, session: %{"user_name" => "Ada", "theme" => "dark"})

    assert conn.status == 303
    assert Plug.Conn.get_session(conn, "user_name") == nil
    assert Plug.Conn.get_session(conn, "theme") == nil
    # the logout flash survives the clear
    assert Plug.Conn.get_session(conn, "_fractal_flash") == %{"info" => "Signed out."}
  end

  test "the flash shows once and is then cleared" do
    login = post("/login", %{"name" => "Ada"})
    flash = Plug.Conn.get_session(login, "_fractal_flash")

    first = get("/login", %{}, session: %{"user_name" => "Ada", "_fractal_flash" => flash})
    assert first.resp_body =~ "Welcome, Ada!"
    assert first.resp_body =~ "flash-info"
    assert Plug.Conn.get_session(first, "_fractal_flash") == nil

    second = get("/login", %{}, session: %{"user_name" => "Ada"})
    refute second.resp_body =~ "Welcome, Ada!"
  end

  test "the flash never leaks into assigns.session" do
    conn =
      get("/login", %{}, session: %{"user_name" => "Ada", "_fractal_flash" => %{"info" => "hi"}})

    # pages see the session without framework internals
    refute conn.resp_body =~ "_fractal_flash"
  end
end
