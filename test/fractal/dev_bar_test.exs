defmodule Fractal.DevBarTest do
  # not async: tests toggle the global live_reload (dev mode) config
  use ExUnit.Case

  alias Fractal.DevBar

  setup do
    original = Application.get_env(:fractal, :live_reload)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:fractal, :live_reload)
      else
        Application.put_env(:fractal, :live_reload, original)
      end
    end)

    :ok
  end

  test "enabled?/0 follows the dev-mode gate" do
    refute DevBar.enabled?()

    Application.put_env(:fractal, :live_reload, true)
    assert DevBar.enabled?()
  end

  test "source_path/1 resolves a module to its project-relative source" do
    assert DevBar.source_path(Fractal.Fixtures.StaticPage) == "test/support/fixtures.ex"
    assert DevBar.source_path(Fractal.Document) == "lib/fractal/document.ex"
  end

  test "source_path/1 is nil for unresolvable modules" do
    assert DevBar.source_path(NoSuch.Module) == nil
  end

  test "the script builds its own isolated DOM and never leaks picks to the page" do
    script = DevBar.script()

    # everything lives under one root the picker ignores
    assert script =~ "fractal-dev-bar"
    assert script =~ ~s{closest("#" + BAR)}

    # capture-phase interception so pick-mode clicks never reach fx handlers
    assert script =~ ~s{document.addEventListener("click", onPick, true)}
    assert script =~ "e.stopPropagation()"

    # the composed prompt reads the provenance annotations
    assert script =~ ~s{meta[name="fractal-source"]}
    assert script =~ "[data-component]"
    assert script =~ "[data-layout]"

    # delivery is the clipboard, with the verify footer
    assert script =~ "navigator.clipboard"
    assert script =~ "mix fractal.verify"

    # styles are set from JS — no <style> tag to leak anywhere
    refute script =~ "<style>"
  end
end
