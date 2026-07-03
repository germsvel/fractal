defmodule Mix.Tasks.Fractal.Gen.PageTest do
  use ExUnit.Case

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(original_shell) end)
    :ok
  end

  @tag :tmp_dir
  test "generates a page module and its test", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Page.run(["ContactUs", "--path", "/contact", "--title", "Contact us"])

      page = File.read!("lib/fractal/pages/contact_us.ex")
      assert page =~ "defmodule Fractal.Pages.ContactUs do"
      assert page =~ ~s(use Fractal.Page, path: "/contact", title: "Contact us")
      assert page =~ "def render(_assigns) do"

      test_file = File.read!("test/fractal/pages/contact_us_test.exs")
      assert test_file =~ "defmodule Fractal.Pages.ContactUsTest do"
      assert test_file =~ "Fractal.Verify.run([Fractal.Pages.ContactUs])"
      assert test_file =~ ~s{assert Fractal.Pages.ContactUs.path() == "/contact"}
    end)
  end

  @tag :tmp_dir
  test "derives the route and title from the page name", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Page.run(["TeamMembers"])

      page = File.read!("lib/fractal/pages/team_members.ex")
      assert page =~ ~s(use Fractal.Page, path: "/team-members", title: "Team members")
    end)
  end

  @tag :tmp_dir
  test "refuses to overwrite an existing page", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Page.run(["About"])

      assert_raise Mix.Error, ~r/already exists/, fn ->
        Mix.Tasks.Fractal.Gen.Page.run(["About"])
      end
    end)
  end

  test "requires a page name" do
    assert_raise Mix.Error, ~r/usage/, fn ->
      Mix.Tasks.Fractal.Gen.Page.run([])
    end
  end
end
