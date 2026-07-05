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
    assert output =~ "guide: building_pages.md"
    assert output =~ "# Building pages"
    assert output =~ "guide: verification.md"
    assert output =~ "# Verification"
    assert output =~ "component inventory"
    assert output =~ "Fractal.Fixtures.Note"
    assert output =~ "example assigns:"
    assert output =~ "guard inventory"
    assert output =~ ":fixture_signed_in"

    assert output =~
             "every page under /fixtures/admin must declare require: :fixture_signed_in"

    assert output =~ "invariant inventory"
    assert output =~ "- title fits in a search result"
    assert output =~ "- meta description fits a search snippet"
    assert output =~ "- every page renders exactly one h1"
  end

  @tag :tmp_dir
  test "works from any directory — guides ship in the package", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Ai.Docs.run([])
      assert flush_output() =~ "guide: building_pages.md"
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
