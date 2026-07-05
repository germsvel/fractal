defmodule Mix.Tasks.Fractal.VerifyTest do
  use ExUnit.Case

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(original_shell) end)
    :ok
  end

  test "passes on this project and reports each check" do
    Mix.Tasks.Fractal.Verify.run(["--no-tests"])

    messages = flush_messages()
    assert Enum.any?(messages, &(&1 =~ "✓ session secret is configured"))
    assert Enum.any?(messages, &(&1 =~ "✓ app stylesheet is well-formed"))
    assert Enum.any?(messages, &(&1 =~ "✓ migrations are up"))
    assert Enum.any?(messages, &(&1 =~ "✓ pages are defined"))
    assert Enum.any?(messages, &(&1 =~ "✓ GET routes are unique"))
    assert Enum.any?(messages, &(&1 =~ "✓ POST routes are unique"))
    assert Enum.any?(messages, &(&1 =~ "Fractal.Fixtures.StaticPage renders"))
    assert Enum.any?(messages, &(&1 =~ "✓ invariants are well-formed"))
    assert Enum.any?(messages, &(&1 =~ "✓ the layout is well-formed"))
    assert Enum.any?(messages, &(&1 =~ "✓ Fractal.Fixtures.Layout renders its chrome"))

    assert Enum.any?(
             messages,
             &(&1 =~
                 "Fractal.Fixtures.StaticPage satisfies invariant 'title fits in a search result'")
           )

    assert Enum.any?(messages, &(&1 =~ "✓ Fractal.Fixtures.StaticPage has tests"))
    assert Enum.any?(messages, &(&1 =~ "✓ Fractal.Fixtures.Note has tests"))
    assert Enum.any?(messages, &(&1 =~ "All verification checks passed"))
  end

  defp flush_messages(acc \\ []) do
    receive do
      {:mix_shell, :info, [message]} -> flush_messages([message | acc])
      {:mix_shell, :error, [message]} -> flush_messages([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
