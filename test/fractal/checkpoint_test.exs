defmodule Fractal.CheckpointTest do
  use ExUnit.Case, async: true

  alias Fractal.Checkpoint

  # a fixture checkpoint module — in-memory, so discovery never sees it and
  # the app's real Fractal.Checkpoints stays the single discovered module
  defmodule Fixture do
    use Fractal.Checkpoint

    def context(assigns) do
      %{"role" => assigns.session["role"]}
    end

    guard :always_ok do
      :ok
    end

    guard :admins_only, %{context: context} do
      if context["role"] == "admin" do
        :ok
      else
        {:redirect, "/login", flash: %{"error" => "Admins only."}}
      end
    end

    expect("/secret", :admins_only)
  end

  test "the guard macro accumulates names and defines check clauses" do
    assert Fixture.__fractal_guards__() == [:always_ok, :admins_only]
    assert Fixture.check(:always_ok, %{}) == :ok

    assert {:redirect, "/login", flash: %{"error" => "Admins only."}} =
             Fixture.check(:admins_only, %{context: %{"role" => nil}})
  end

  test "expect accumulates expectations" do
    assert Fixture.__fractal_expectations__() == [{"/secret", :admins_only}]
  end

  test "context/1 defaults to an empty map and is overridable" do
    defmodule NoContext do
      use Fractal.Checkpoint
    end

    assert NoContext.context(%{session: %{}}) == %{}
    assert Fixture.context(%{session: %{"role" => "admin"}}) == %{"role" => "admin"}
  end

  test "an expectation referencing an undefined guard fails to compile" do
    error =
      try do
        defmodule BadExpect do
          use Fractal.Checkpoint

          expect("/x", :ghost)
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "defines no such guard"
  end

  test "duplicate guard names fail to compile" do
    error =
      try do
        defmodule Dup do
          use Fractal.Checkpoint

          guard :twice do
            :ok
          end

          guard :twice do
            :ok
          end
        end

        :no_raise
      rescue
        exception -> exception
      end

    refute error == :no_raise
    assert Exception.message(error) =~ "duplicate guards"
  end

  describe "run/2 (through the discovered fixture checkpoint)" do
    test "no guards required is always :ok" do
      assert Checkpoint.run([], %{}) == :ok
    end

    test "passes a signed-in session" do
      assigns = %{session: %{}, context: %{"fixture_user" => "Ada"}, path: "/fixtures/admin"}

      assert Checkpoint.run([:fixture_signed_in], assigns) == :ok
    end

    test "denies with a redirect and directives, and emits telemetry" do
      :telemetry.attach(
        "guard-denied-test",
        [:fractal, :checkpoint, :denied],
        fn _event, _measure, metadata, pid -> send(pid, {:denied, metadata}) end,
        self()
      )

      on_exit(fn -> :telemetry.detach("guard-denied-test") end)

      assigns = %{session: %{}, context: %{"fixture_user" => nil}, path: "/fixtures/admin"}

      assert {:redirect, "/fixtures", directives} =
               Checkpoint.run([:fixture_signed_in], assigns)

      assert directives[:flash] == %{"error" => "Fixtures say: log in first."}
      assert_received {:denied, %{guard: :fixture_signed_in, path: "/fixtures/admin"}}
    end

    test "an undefined guard fails closed" do
      assert_raise FunctionClauseError, fn ->
        Checkpoint.run([:no_such_guard], %{session: %{}, context: %{}, path: "/"})
      end
    end
  end

  test "the app's checkpoint module is discovered, once" do
    assert Checkpoint.module() == Fractal.Fixtures.Checkpoint
    assert Checkpoint.modules() == [Fractal.Fixtures.Checkpoint]
    assert :fixture_signed_in in Checkpoint.names()
    assert {"/fixtures/admin", :fixture_signed_in} in Checkpoint.expectations()
  end

  test "under?/2 is segment-aware" do
    assert Checkpoint.under?("/admin", "/admin")
    assert Checkpoint.under?("/admin/posts", "/admin")
    refute Checkpoint.under?("/administrator", "/admin")
    refute Checkpoint.under?("/posts", "/admin")
  end
end
