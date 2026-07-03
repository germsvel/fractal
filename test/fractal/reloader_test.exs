defmodule Fractal.ReloaderTest do
  use ExUnit.Case

  alias Fractal.{LiveReload, Reloader}

  setup do
    pid = start_supervised!({Reloader, watch: false, name: :test_reloader})
    %{reloader: pid}
  end

  test "a source file event triggers a recompile and bumps the reload token",
       %{reloader: reloader} do
    before_token = LiveReload.token()

    send(reloader, {:file_event, self(), {"lib/fractal/pages/home.ex", [:modified]}})

    assert eventually(fn -> LiveReload.token() != before_token end),
           "expected the reload token to change after a source file event"
  end

  test "a non-source file event is ignored", %{reloader: reloader} do
    before_token = LiveReload.token()

    send(reloader, {:file_event, self(), {"notes.txt", [:modified]}})

    # give the (unwanted) debounce a chance to fire
    Process.sleep(300)
    assert LiveReload.token() == before_token
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(100)
        eventually(fun, attempts - 1)
    end
  end
end
