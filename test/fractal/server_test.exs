defmodule Fractal.ServerTest do
  use ExUnit.Case

  @port 4297

  setup do
    {:ok, supervisor} = Fractal.Server.start(port: @port)
    # unlink so the supervisor survives until on_exit stops it explicitly
    Process.unlink(supervisor)
    on_exit(fn -> stop_supervisor(supervisor) end)
    :ok
  end

  test "serves a page over real HTTP" do
    assert {:ok, {{_http, 200, _reason}, _headers, body}} =
             :httpc.request(:get, {~c"http://127.0.0.1:#{@port}/fixtures", []}, [], [])

    assert to_string(body) =~ "Fixtures"
  end

  test "serves 404s for unknown paths over real HTTP" do
    assert {:ok, {{_http, 404, _reason}, _headers, body}} =
             :httpc.request(:get, {~c"http://127.0.0.1:#{@port}/nope", []}, [], [])

    assert to_string(body) =~ "404"
  end

  test "streams watch fragments over a real SSE connection" do
    url = ~c"http://127.0.0.1:#{@port}/fractal/watch?_fx_path=/fixtures/watch/lobby"

    {:ok, ref} =
      :httpc.request(:get, {url, []}, [], sync: false, stream: :self)

    assert_receive {:http, {^ref, :stream_start, headers}}, 2_000
    assert {~c"content-type", ~c"text/event-stream; charset=utf-8"} in headers

    # the initial catch-up: both watched topics render once on connect
    initial = collect_until(ref, ~s(data: <p id="all-ticks">))
    assert initial =~ ~s(data: <p id="ticks">tick in lobby</p>)
    assert initial =~ ~s(data: <p id="all-ticks">)

    # a publish reaches the open connection with a fresh fragment
    Fractal.Interactive.publish("fixtures/rooms/lobby/ticks")
    assert collect_until(ref, ~s(data: <p id="ticks">tick in lobby</p>)) =~ "tick in lobby"

    :httpc.cancel_request(ref)
  end

  # accumulates stream chunks (keepalives included) until the pattern
  # shows up or ~2s pass
  defp collect_until(ref, pattern, acc \\ "", attempts \\ 40) do
    if acc =~ pattern or attempts == 0 do
      acc
    else
      receive do
        {:http, {^ref, :stream, chunk}} ->
          collect_until(ref, pattern, acc <> to_string(chunk), attempts - 1)
      after
        50 -> collect_until(ref, pattern, acc, attempts - 1)
      end
    end
  end

  defp stop_supervisor(supervisor) do
    if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
  catch
    :exit, _reason -> :ok
  end
end
