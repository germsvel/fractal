defmodule Fractal.DiscoveryTest do
  # not async: tests mutate the framework's host config
  use ExUnit.Case

  alias Fractal.Discovery

  setup do
    on_exit(fn ->
      Application.delete_env(:fractal, :otp_app)
      Application.delete_env(:fractal, :namespace)
    end)

    :ok
  end

  test "host_app/0 defaults to the enclosing mix project" do
    assert Discovery.host_app() == :fractal
  end

  test "host_app/0 honors the otp_app override" do
    Application.put_env(:fractal, :otp_app, :blog)
    assert Discovery.host_app() == :blog
  end

  test "namespace/0 camelizes the host app by default" do
    assert Discovery.namespace() == "Fractal"

    Application.put_env(:fractal, :otp_app, :my_blog)
    assert Discovery.namespace() == "MyBlog"
  end

  test "namespace/0 honors module and string overrides" do
    Application.put_env(:fractal, :namespace, Deeply.Nested.App)
    assert Discovery.namespace() == "Deeply.Nested.App"

    Application.put_env(:fractal, :namespace, "Custom")
    assert Discovery.namespace() == "Custom"
  end

  test "app_dir/0 is the host app's source directory name" do
    assert Discovery.app_dir() == "fractal"

    Application.put_env(:fractal, :otp_app, :my_blog)
    assert Discovery.app_dir() == "my_blog"
  end

  test "host_repo/0 reads the host's ecto_repos" do
    # the framework itself is repo-less
    assert Discovery.host_repo() == nil

    Application.put_env(:fractal, :ecto_repos, [Fractal.Fixtures.Repo])
    on_exit(fn -> Application.delete_env(:fractal, :ecto_repos) end)
    assert Discovery.host_repo() == Fractal.Fixtures.Repo
  end

  test "modules/0 scans the host app's beams" do
    modules = Discovery.modules()

    assert Fractal.Fixtures.StaticPage in modules
    assert Fractal.Router in modules

    # an unknown host yields nothing rather than crashing
    Application.put_env(:fractal, :otp_app, :no_such_app)
    assert Discovery.modules() == []
  end
end
