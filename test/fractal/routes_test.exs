defmodule Fractal.RoutesTest do
  # not async: the cache tests toggle the global cache_discovery config
  # and touch the shared persistent_term key
  use ExUnit.Case

  alias Fractal.Fixtures.{EditPage, FormPage, GuardedPage, ShowPage}
  alias Fractal.Routes

  @key {Fractal.Router, :routes}

  setup do
    on_exit(fn ->
      Application.put_env(:fractal, :cache_discovery, false)
      :persistent_term.erase(@key)
    end)

    :ok
  end

  describe "find/2 (live path)" do
    test "static routes win over dynamic ones via exact lookup" do
      assert {FormPage, %{}} = Routes.find(:get, ["fixtures", "new"])
      assert {ShowPage, %{"id" => "42"}} = Routes.find(:get, ["fixtures", "42"])
    end

    test "resolves each method's own routes" do
      assert {FormPage, %{}} = Routes.find(:post, ["fixtures"])
      assert {EditPage, %{"id" => "7"}} = Routes.find(:put, ["fixtures", "7"])
      assert {EditPage, %{"id" => "7"}} = Routes.find(:delete, ["fixtures", "7"])
    end

    test "unmatched paths and methods resolve to nil" do
      assert Routes.find(:get, ["nowhere"]) == nil
      assert Routes.find(:delete, ["fixtures"]) == nil
    end
  end

  describe "discovery singletons" do
    test "pages/0, checkpoint/0, and layout/0 return the discovered modules" do
      assert GuardedPage in Routes.pages()
      assert Routes.checkpoint() == Fractal.Fixtures.Checkpoint
      assert Routes.layout() == Fractal.Fixtures.Layout
    end
  end

  describe "the cache" do
    test "the test env never populates the persistent term" do
      :persistent_term.erase(@key)

      Routes.pages()
      Routes.find(:get, ["fixtures"])
      Routes.checkpoint()

      assert :persistent_term.get(@key, nil) == nil
    end

    test "when cache-eligible, one term is built once and answers everything" do
      :persistent_term.erase(@key)
      Application.put_env(:fractal, :cache_discovery, true)

      live_pages = Routes.pages()

      table = :persistent_term.get(@key, nil)
      assert %{pages: ^live_pages, methods: methods, checkpoint: checkpoint} = table
      assert map_size(methods) == 4
      assert checkpoint == Fractal.Fixtures.Checkpoint

      # cached answers match the live ones exactly
      assert {ShowPage, %{"id" => "9"}} = Routes.find(:get, ["fixtures", "9"])
      assert Routes.layout() == Fractal.Fixtures.Layout

      # reads do not rewrite the term
      assert :persistent_term.get(@key) == table
    end

    test "the flag is a one-line off-switch even when live_reload is off" do
      :persistent_term.erase(@key)
      Application.put_env(:fractal, :cache_discovery, false)

      Routes.pages()

      assert :persistent_term.get(@key, nil) == nil
    end
  end
end
