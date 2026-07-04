defmodule Fractal.GuardTest do
  use ExUnit.Case, async: true

  alias Fractal.Guard

  # a fixture guards module — in-memory, so discovery never sees it and
  # the app's real Fractal.Guards stays the single discovered module
  defmodule Fixture do
    use Fractal.Guard

    def context(assigns) do
      %{"role" => assigns.session["role"]}
    end

    guard :always_ok do
      _ = assigns
      :ok
    end

    guard :admins_only do
      if assigns.context["role"] == "admin" do
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
      use Fractal.Guard
    end

    assert NoContext.context(%{session: %{}}) == %{}
    assert Fixture.context(%{session: %{"role" => "admin"}}) == %{"role" => "admin"}
  end

  test "an expectation referencing an undefined guard fails to compile" do
    error =
      try do
        defmodule BadExpect do
          use Fractal.Guard

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
          use Fractal.Guard

          guard :twice do
            _ = assigns
            :ok
          end

          guard :twice do
            _ = assigns
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

  describe "run/2 (through the app's real Fractal.Guards)" do
    test "no guards required is always :ok" do
      assert Guard.run([], %{}) == :ok
    end

    test "passes a signed-in session" do
      assigns = %{session: %{}, context: %{"user_name" => "Ada"}, path: "/admin"}

      assert Guard.run([:signed_in], assigns) == :ok
    end

    test "denies with a redirect and directives, and emits telemetry" do
      :telemetry.attach(
        "guard-denied-test",
        [:fractal, :guard, :denied],
        fn _event, _measure, metadata, pid -> send(pid, {:denied, metadata}) end,
        self()
      )

      on_exit(fn -> :telemetry.detach("guard-denied-test") end)

      assigns = %{session: %{}, context: %{"user_name" => nil}, path: "/admin"}

      assert {:redirect, "/login", directives} = Guard.run([:signed_in], assigns)
      assert directives[:flash] == %{"error" => "Please log in first."}
      assert_received {:denied, %{guard: :signed_in, path: "/admin"}}
    end

    test "an undefined guard fails closed" do
      assert_raise FunctionClauseError, fn ->
        Guard.run([:no_such_guard], %{session: %{}, context: %{}, path: "/"})
      end
    end
  end

  test "the app's guards module is discovered, once" do
    assert Guard.module() == Fractal.Guards
    assert Guard.modules() == [Fractal.Guards]
    assert :signed_in in Guard.names()
    assert {"/admin", :signed_in} in Guard.expectations()
  end

  test "under?/2 is segment-aware" do
    assert Guard.under?("/admin", "/admin")
    assert Guard.under?("/admin/posts", "/admin")
    refute Guard.under?("/administrator", "/admin")
    refute Guard.under?("/posts", "/admin")
  end
end
