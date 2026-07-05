defmodule Fractal.InvariantTest do
  use ExUnit.Case, async: true

  alias Fractal.Invariant

  # a fixture invariants module — in-memory, so discovery never sees it
  # and the app's real Fractal.Invariants stays the single discovered one
  defmodule Fixture do
    use Fractal.Invariant

    invariant "always holds" do
      :ok
    end

    invariant "page is not nil", %{page: page} do
      if page, do: :ok, else: {:error, "no page"}
    end

    invariant "rendered mentions fractal", %{rendered: rendered} do
      if rendered =~ "fractal", do: :ok, else: {:error, "add some fractal"}
    end
  end

  test "the invariant macro accumulates names and defines run clauses" do
    assert Fixture.__fractal_invariants__() == [
             "always holds",
             "page is not nil",
             "rendered mentions fractal"
           ]

    assert Fixture.run("always holds", %{}) == :ok
    assert Fixture.run("page is not nil", %{page: Fractal.Fixtures.StaticPage}) == :ok
    assert Fixture.run("page is not nil", %{page: nil}) == {:error, "no page"}

    assert Fixture.run("rendered mentions fractal", %{rendered: "no"}) ==
             {:error, "add some fractal"}
  end

  test "duplicate invariant names fail to compile" do
    error =
      try do
        defmodule Dup do
          use Fractal.Invariant

          invariant "twice" do
            :ok
          end

          invariant "twice" do
            :ok
          end
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "duplicate invariants"
  end

  test "use Fractal.Invariant rejects options" do
    error =
      try do
        defmodule Sneaky do
          use Fractal.Invariant, only: "/admin"
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "takes no options"
  end

  test "the app's invariants module is discovered, once" do
    assert Invariant.module() == Fractal.Fixtures.Invariants
    assert Invariant.modules() == [Fractal.Fixtures.Invariants]
    assert "title fits in a search result" in Invariant.names()
    assert "every page renders exactly one h1" in Invariant.names()
  end

  test "run/2 dispatches to the discovered module" do
    assert Invariant.run("title fits in a search result", %{page: Fractal.Fixtures.StaticPage}) ==
             :ok
  end

  test "invariant_module?/1 rejects non-invariant modules" do
    assert Invariant.invariant_module?(Fractal.Fixtures.Invariants)
    refute Invariant.invariant_module?(Fractal.Fixtures.StaticPage)
    refute Invariant.invariant_module?(Fractal.Fixtures.Checkpoint)
  end
end
