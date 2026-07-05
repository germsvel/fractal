defmodule Fractal.ResponseHeadersTest do
  # not async: the override test mutates global config
  use ExUnit.Case

  import Fractal.Test, only: [get: 1]

  test "every response carries the secure defaults" do
    conn = get("/fixtures")

    assert Plug.Conn.get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert Plug.Conn.get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]

    assert Plug.Conn.get_resp_header(conn, "referrer-policy") ==
             ["strict-origin-when-cross-origin"]

    # 404s and framework endpoints too
    assert Plug.Conn.get_resp_header(get("/nope"), "x-content-type-options") == ["nosniff"]

    assert Plug.Conn.get_resp_header(get("/fractal/reload"), "x-content-type-options") ==
             ["nosniff"]
  end

  test "config adds and overrides headers — data, not code" do
    Application.put_env(:fractal, :response_headers, %{
      "permissions-policy" => "camera=()",
      "x-frame-options" => "DENY"
    })

    on_exit(fn -> Application.delete_env(:fractal, :response_headers) end)

    conn = get("/fixtures")

    assert Plug.Conn.get_resp_header(conn, "permissions-policy") == ["camera=()"]
    assert Plug.Conn.get_resp_header(conn, "x-frame-options") == ["DENY"]
  end

  test "requests emit telemetry with duration and status" do
    :telemetry.attach(
      "request-stop-test",
      [:fractal, :request, :stop],
      fn _event, measurements, metadata, pid -> send(pid, {:stop, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("request-stop-test") end)

    get("/fixtures")

    assert_received {:stop, %{duration: duration},
                     %{method: "GET", path: "/fixtures", status: 200}}

    assert is_integer(duration)
  end
end
