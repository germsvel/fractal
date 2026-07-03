defmodule Mix.Tasks.Fractal.Gen.ComponentTest do
  use ExUnit.Case

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(original_shell) end)
    :ok
  end

  @tag :tmp_dir
  test "generates a component and its test", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Component.run(["StatBox"])

      component = File.read!("lib/fractal/components/stat_box.ex")
      assert component =~ "defmodule Fractal.Components.StatBox do"
      assert component =~ "use Fractal.Component"
      assert component =~ "def render(assigns) do"
      assert component =~ "def style do"
      assert component =~ "def example do"
      assert component =~ ~s(class: "stat-box")

      tests = File.read!("test/fractal/components/stat_box_test.exs")
      assert tests =~ "Fractal.Verify.run_components([StatBox])"
      assert tests =~ ~s(data-component="stat-box")
    end)
  end

  @tag :tmp_dir
  test "refuses to overwrite an existing component", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Component.run(["Card"])

      assert_raise Mix.Error, ~r/already exists/, fn ->
        Mix.Tasks.Fractal.Gen.Component.run(["Card"])
      end
    end)
  end

  test "requires a name" do
    assert_raise Mix.Error, ~r/usage/, fn ->
      Mix.Tasks.Fractal.Gen.Component.run([])
    end
  end
end
