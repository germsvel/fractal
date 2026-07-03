defmodule Mix.Tasks.Fractal.VerifyTest do
  use Fractal.DataCase

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
    assert Enum.any?(messages, &(&1 =~ "✓ migrations are up"))
    assert Enum.any?(messages, &(&1 =~ "✓ pages are defined"))
    assert Enum.any?(messages, &(&1 =~ "✓ GET routes are unique"))
    assert Enum.any?(messages, &(&1 =~ "✓ POST routes are unique"))
    assert Enum.any?(messages, &(&1 =~ "Fractal.Pages.Home renders"))
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
