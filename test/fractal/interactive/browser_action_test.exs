defmodule Fractal.Interactive.BrowserActionTest do
  use ExUnit.Case, async: true

  alias Fractal.Interactive.BrowserAction

  test "normalizes supported bindings and encodes runtime data" do
    assert {:ok, bindings} =
             BrowserAction.normalize(
               [j: {:event, "older"}, /: {:focus, "#search"}, n: {:navigate, "/new"}],
               ["older"]
             )

    assert {"j", {:event, "older"}} in bindings
    assert BrowserAction.encode(bindings) =~ ~s("type":"focus")
  end

  test "rejects malformed keys, duplicates, unknown events, and broad selectors" do
    assert {:error, message} = BrowserAction.normalize(["g n": {:event, "go"}], ["go"])
    assert message =~ "printable key"

    assert {:error, "duplicate key combination"} =
             BrowserAction.normalize([j: {:event, "go"}, j: {:event, "go"}], ["go"])

    assert {:error, message} = BrowserAction.normalize([j: {:event, "missing"}], ["go"])
    assert message =~ "not declared"

    assert {:error, message} = BrowserAction.normalize([j: {:focus, ".search"}], [])
    assert message =~ "id selector"
  end
end
