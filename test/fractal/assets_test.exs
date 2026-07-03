defmodule Fractal.AssetsTest do
  use ExUnit.Case, async: true

  alias Fractal.Assets

  describe "asset_path/1" do
    test "returns a fingerprinted URL for an existing file" do
      path = Assets.asset_path("logo.svg")

      assert path =~ ~r|^/assets/logo\.svg\?vsn=[0-9a-f]{8}$|
    end

    test "the fingerprint is stable for the same content" do
      assert Assets.asset_path("logo.svg") == Assets.asset_path("logo.svg")
    end

    test "raises for a missing file, listing what exists" do
      error =
        assert_raise Assets.MissingAssetError, fn ->
          Assets.asset_path("does-not-exist.png")
        end

      assert error.message =~ "does-not-exist.png"
      assert error.message =~ "logo.svg"
    end

    test "rejects paths that escape assets/static" do
      assert_raise ArgumentError, ~r/cannot escape/, fn ->
        Assets.asset_path("../../mix.exs")
      end
    end
  end

  describe "css_bundle/0" do
    test "starts with the app stylesheet" do
      {_hash, css} = Assets.css_bundle()

      assert css =~ "--accent:"
      assert css =~ "box-sizing: border-box"
    end

    test "includes every page's style/0, scoped by page slug" do
      {_hash, css} = Assets.css_bundle()

      assert css =~ ~s([data-page="home"] {)
      assert css =~ ".logo { width: 3.5rem;"
    end

    test "includes every component's style/0, scoped, before page styles" do
      {_hash, css} = Assets.css_bundle()

      assert css =~ ~s([data-component="empty-state"] {)

      {component_index, _} = :binary.match(css, ~s([data-component="empty-state"]))
      {page_index, _} = :binary.match(css, ~s([data-page="home"]))
      assert component_index < page_index
    end

    test "css_path/0 carries the bundle hash" do
      {hash, _css} = Assets.css_bundle()

      assert Assets.css_path() == "/fractal/assets/app-#{hash}.css"
    end
  end

  test "static_files/0 lists the files under assets/static" do
    assert "logo.svg" in Assets.static_files()
  end
end
