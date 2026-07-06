defmodule Fractal.LiveReloadTest do
  use ExUnit.Case, async: true

  alias Fractal.LiveReload

  test "token/0 returns a positive integer" do
    token = LiveReload.token()
    assert is_integer(token) and token > 0
  end

  test "bump/0 changes the token and resets the event to :reload" do
    before_token = LiveReload.token()

    assert :ok = LiveReload.bump()

    {token, event} = LiveReload.current()
    assert token != before_token
    assert event == :reload
  end

  test "bump/1 carries css and compile-error events" do
    LiveReload.bump({:css, "/fractal/assets/app-cafef00d.css"})
    assert {_token, {:css, "/fractal/assets/app-cafef00d.css"}} = LiveReload.current()

    LiveReload.bump({:error, "boom on line 3"})
    assert {_token, {:error, "boom on line 3"}} = LiveReload.current()

    # leave the shared state clean for other tests
    LiveReload.bump()
    assert {_token, :reload} = LiveReload.current()
  end

  test "every bump rings the internal bus topic" do
    :ok = LiveReload.subscribe()

    LiveReload.bump()

    assert_receive {:fractal_watch, "fractal/dev/reload"}
  end
end
