defmodule Fractal.VerifyTest do
  use ExUnit.Case, async: true

  alias Fractal.Verify

  defmodule GoodPage do
    use Fractal.Page, path: "/verify-good", title: "Good"

    @impl Fractal.Page
    def render(_assigns), do: tag(:p, [], ["fine"])
  end

  defmodule DuplicateA do
    use Fractal.Page, path: "/verify-dup"

    @impl Fractal.Page
    def render(_assigns), do: "a"
  end

  defmodule DuplicateB do
    use Fractal.Page, path: "/verify-dup"

    @impl Fractal.Page
    def render(_assigns), do: "b"
  end

  defmodule RaisingRender do
    use Fractal.Page, path: "/verify-raise"

    @impl Fractal.Page
    def render(_assigns), do: raise("boom")
  end

  # bypasses `use Fractal.Page` so compile-time validation can't catch it
  defmodule SneakyBadPath do
    @behaviour Fractal.Page

    @impl Fractal.Page
    def path, do: "not-a-path"

    @impl Fractal.Page
    def title, do: "Sneaky"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  defmodule BadReturn do
    use Fractal.Page, path: "/verify-bad-return"

    @impl Fractal.Page
    def render(_assigns), do: {:not, :renderable}
  end

  test "the app's discovered pages pass verification" do
    results = Verify.run()
    assert Verify.ok?(results), inspect(Verify.errors(results))
  end

  test "a well-formed page passes all checks" do
    results = Verify.run([GoodPage])
    assert Verify.ok?(results)
  end

  test "detects when no pages exist" do
    results = Verify.run([])
    refute Verify.ok?(results)
    assert [{"pages are defined", {:error, message}}] = Verify.errors(results)
    assert message =~ "no page modules found"
  end

  test "detects duplicate routes" do
    results = Verify.run([DuplicateA, DuplicateB])
    assert [{"routes are unique", {:error, message}}] = Verify.errors(results)
    assert message =~ "/verify-dup"
    assert message =~ "DuplicateA"
    assert message =~ "DuplicateB"
  end

  test "detects a render that raises" do
    results = Verify.run([RaisingRender])
    assert [{name, {:error, message}}] = Verify.errors(results)
    assert name =~ "renders"
    assert message =~ "render/1 raised"
    assert message =~ "boom"
  end

  test "detects a malformed path even when compile-time checks were bypassed" do
    results = Verify.run([SneakyBadPath])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "valid path" and message =~ "not-a-path"
           end)
  end

  test "detects a render returning something unrenderable" do
    results = Verify.run([BadReturn])
    assert [{name, {:error, message}}] = Verify.errors(results)
    assert name =~ "renders"
    assert message =~ "must return"
  end
end
