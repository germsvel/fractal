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

  test "an assets-only batch skips the compile and pushes a css swap",
       %{reloader: reloader} do
    before_token = LiveReload.token()

    send(reloader, {:file_event, self(), {"/app/assets/app.css", [:modified]}})

    assert eventually(fn -> LiveReload.token() != before_token end),
           "expected the reload token to change after an assets change"

    assert {_token, {:css, href}} = LiveReload.current()
    assert href =~ ~r{^/fractal/assets/app-[0-9a-f]+\.css$}

    # leave the shared state clean for other tests
    LiveReload.bump()
  end

  test "classify/1 needs a compile only when a code file is in the batch" do
    assert Reloader.classify(["assets/app.css", "assets/static/logo.svg"]) == :css
    assert Reloader.classify(["assets/app.css", "lib/my_app/pages/home.ex"]) == :code
    assert Reloader.classify(["lib/my_app/pages/home.ex"]) == :code
  end

  test "format_errors/1 renders error diagnostics as file:line + message" do
    diagnostics = [
      %Mix.Task.Compiler.Diagnostic{
        compiler_name: "Elixir",
        file: Path.expand("lib/my_app/pages/home.ex"),
        position: {3, 12},
        message: "unexpected token: ,",
        severity: :error
      },
      %Mix.Task.Compiler.Diagnostic{
        compiler_name: "Elixir",
        file: Path.expand("lib/my_app/other.ex"),
        position: 9,
        message: "just a warning",
        severity: :warning
      }
    ]

    formatted = Reloader.format_errors(diagnostics)

    assert formatted =~ "lib/my_app/pages/home.ex:3: unexpected token: ,"
    refute formatted =~ "just a warning"
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
