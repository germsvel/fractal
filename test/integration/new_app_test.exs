defmodule Fractal.Integration.NewAppTest do
  # The born-green contract: `mix fractal.new` must produce an app where
  # setup and verify pass with no manual edits — template rot cannot ship.
  # Excluded by default (it generates a real app, hits the database, and
  # takes minutes); run with `mix test --only integration`.
  use ExUnit.Case

  @moduletag :integration
  @moduletag timeout: 600_000

  @app "sprout"

  test "a generated app is born green" do
    framework = File.cwd!()
    installer = Path.join(framework, "installer")
    tmp = Path.join(System.tmp_dir!(), "fractal_new_test#{System.unique_integer([:positive])}")
    app_path = Path.join(tmp, @app)

    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    # generation runs from the installer project; the path dep points the
    # generated app at this checkout, so it tests today's framework
    run!(["fractal.new", app_path], installer, [{"FRACTAL_PATH", framework}])

    run!(["deps.get"], app_path)
    run!(["ecto.setup"], app_path)
    on_exit(fn -> System.cmd("mix", ["ecto.drop"], cd: app_path, env: clean_env([])) end)

    output = run!(["fractal.verify"], app_path)

    assert output =~ "All verification checks passed"
  end

  defp run!(args, cd, extra_env \\ []) do
    {output, status} =
      System.cmd("mix", args, cd: cd, env: clean_env(extra_env), stderr_to_stdout: true)

    assert status == 0, """
    `mix #{Enum.join(args, " ")}` exited with #{status} in #{cd}:

    #{output}
    """

    output
  end

  # the child apps must not inherit this suite's MIX_ENV=test
  defp clean_env(extra_env), do: [{"MIX_ENV", nil} | extra_env]
end
