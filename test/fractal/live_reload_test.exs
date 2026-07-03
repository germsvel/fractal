defmodule Fractal.LiveReloadTest do
  use ExUnit.Case, async: true

  alias Fractal.LiveReload

  test "token/0 returns a positive integer" do
    token = LiveReload.token()
    assert is_integer(token) and token > 0
  end

  test "bump/0 changes the token" do
    before_token = LiveReload.token()
    assert :ok = LiveReload.bump()
    assert LiveReload.token() != before_token
  end
end
