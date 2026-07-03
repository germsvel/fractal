defmodule Fractal.Assets do
  @moduledoc """
  Fractal's asset pipeline — no Node, no bundler, no build step beyond
  `mix compile`.

  ## CSS

  One stylesheet is served at `css_path/0`, assembled from:

    * `assets/app.css` — app-wide design tokens and shared styles
    * every page's optional `style/0`, scoped automatically: each block
      is wrapped in `[data-page="<slug>"] { ... }` (the layout puts the
      matching attribute on `<main>`), so page styles physically cannot
      leak between pages.

  The bundle URL carries a content hash, so it caches immutably and
  changes whenever any style changes. In development the bundle is
  rebuilt per request and the file watcher reloads the browser on
  `assets/` changes.

  ## Static files

  Images, fonts, and other files live in `assets/static/` and are served
  by `Plug.Static` under `/assets/`. Reference them only through
  `asset_path/1`, which appends a content-hash `?vsn=` (long-lived
  caching) and **raises for missing files** — since verification
  smoke-renders every page, a broken asset reference fails
  `mix fractal.verify` naming the page.

  There is deliberately no user JavaScript pipeline: interactivity is a
  framework primitive (see `Fractal.Interactive`).
  """

  alias Fractal.{Page, Router}

  defmodule MissingAssetError do
    defexception [:message]
  end

  @app_css "assets/app.css"
  @static_dir "assets/static"

  @doc """
  The URL of an asset in `assets/static/`, fingerprinted for caching.

      tag(:img, src: asset_path("logo.svg"), alt: "Fractal")

  Raises `Fractal.Assets.MissingAssetError` when the file does not
  exist — `mix fractal.verify` turns that into a failed check for any
  page referencing it.
  """
  @spec asset_path(String.t()) :: String.t()
  def asset_path(name) when is_binary(name) do
    file = Path.join(@static_dir, name)

    unless String.starts_with?(Path.expand(file), Path.expand(@static_dir)) do
      raise ArgumentError, "asset names cannot escape #{@static_dir}: #{inspect(name)}"
    end

    case File.read(file) do
      {:ok, contents} ->
        "/assets/#{name}?vsn=#{short_hash(contents)}"

      {:error, _reason} ->
        raise MissingAssetError,
          message:
            "asset #{inspect(name)} not found in #{@static_dir}/ — " <>
              available_assets_hint()
    end
  end

  @doc "The URL of the CSS bundle, fingerprinted for caching."
  @spec css_path() :: String.t()
  def css_path do
    {hash, _css} = css_bundle()
    "/fractal/assets/app-#{hash}.css"
  end

  @doc """
  The CSS bundle: `assets/app.css` plus every page's scoped `style/0`.

  Returns `{hash, css}`. Rebuilt per request in development (when live
  reload is on); cached otherwise.
  """
  @spec css_bundle() :: {String.t(), String.t()}
  def css_bundle do
    if cache?() do
      case :persistent_term.get({__MODULE__, :css}, nil) do
        nil ->
          bundle = build_css()
          :persistent_term.put({__MODULE__, :css}, bundle)
          bundle

        bundle ->
          bundle
      end
    else
      build_css()
    end
  end

  @doc "All files under `assets/static/`, relative to it."
  @spec static_files() :: [String.t()]
  def static_files do
    @static_dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, @static_dir))
    |> Enum.sort()
  end

  @doc false
  def app_css_file, do: @app_css

  defp build_css do
    app =
      case File.read(@app_css) do
        {:ok, css} -> css
        {:error, _reason} -> ""
      end

    page_styles =
      for page <- Router.pages(),
          style = Page.style(page),
          is_binary(style) and String.trim(style) != "" do
        ["\n[data-page=\"", Page.slug(page), "\"] {\n", style, "\n}\n"]
      end

    css = IO.iodata_to_binary([app | page_styles])
    {short_hash(css), css}
  end

  defp available_assets_hint do
    case static_files() do
      [] -> "the directory is empty; add the file first"
      files -> "available: #{Enum.join(files, ", ")}"
    end
  end

  defp short_hash(data) do
    :md5 |> :crypto.hash(data) |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  # rebuild per request in dev so style edits show up on reload
  defp cache?, do: not Application.get_env(:fractal, :live_reload, false)
end
