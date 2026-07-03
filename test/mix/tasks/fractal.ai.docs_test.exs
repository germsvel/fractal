defmodule Mix.Tasks.Fractal.Ai.DocsTest do
  use ExUnit.Case

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(original_shell) end)
    :ok
  end

  test "prints every guide and the component inventory" do
    Mix.Tasks.Fractal.Ai.Docs.run([])

    output = flush_output()
    assert output =~ "guides/building_pages.md"
    assert output =~ "# Building pages"
    assert output =~ "guides/verification.md"
    assert output =~ "# Verification"
    assert output =~ "component inventory"
    assert output =~ "Fractal.Components.EmptyState"
    assert output =~ "example assigns:"
  end

  @tag :tmp_dir
  test "fails helpfully when run outside the project root", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      assert_raise Mix.Error, ~r/no guides found/, fn ->
        Mix.Tasks.Fractal.Ai.Docs.run([])
      end
    end)
  end

  defp flush_output(acc \\ "") do
    receive do
      {:mix_shell, :info, [message]} -> flush_output(acc <> "\n" <> message)
    after
      0 -> acc
    end
  end
end
