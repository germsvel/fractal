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

  defp stop_supervisor(supervisor) do
    if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
  catch
    :exit, _reason -> :ok
  end
end
