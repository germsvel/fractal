defmodule Fractal.Document do
  @moduledoc """
  The HTML document: the envelope the framework owns around every page.

  The ownership model in one sentence: **the framework owns the
  document, the app's layout contributes app-wide data and chrome, the
  page contributes content.**

  The document carries the machinery that must stay framework-owned and
  upgradable — apps never copy or edit it: the doctype/head/body
  envelope, charset and viewport, the CSRF token meta tag, the
  fingerprinted stylesheet link, the `data-page` attribute that scopes
  page styles, flash rendering, the interactivity runtime, and (in dev)
  the live-reload script.

  Apps influence the document through `Fractal.Layout` — data and safe
  HTML in, framework renders and escapes: `site/0` supplies the
  language, site name (composed into `<title>Page — Site</title>`),
  favicon, and theme color; `chrome/1` renders app UI (nav, session
  bar) above `<main>`.
  """

  alias Fractal.{Assets, HTML, Layout, Page}

  @live_reload_script """
  <script>
  (function () {
    var token = null;
    setInterval(function () {
      fetch("/fractal/reload")
        .then(function (resp) { return resp.json(); })
        .then(function (data) {
          if (token === null) { token = data.token; }
          else if (token !== data.token) { location.reload(); }
        })
        .catch(function () {});
    }, 500);
  })();
  </script>
  """

  @doc "Renders a full HTML document for a page module."
  @spec render(module(), map()) :: String.t()
  def render(page, assigns) do
    shell(page.title(), HTML.to_safe(page.render(assigns)),
      flash: assigns[:flash],
      assigns: assigns,
      page: page,
      meta: Page.meta(page, assigns)
    )
  end

  @doc """
  Renders a full HTML document from a title and body content.

  Options: `:flash` (map of level → message, rendered as banners),
  `:assigns` (passed to the app layout's `chrome/1`), `:page` (the page
  module — sets the `data-page` attribute that scopes the page's
  `style/0`), and `:meta` (the page's head data from `meta/1`, composed
  over the layout's site defaults and rendered escaped).
  """
  @spec shell(String.t(), term(), keyword()) :: String.t()
  def shell(title, body, opts \\ []) do
    site = Layout.site()

    IO.iodata_to_binary([
      "<!DOCTYPE html>\n<html lang=\"",
      HTML.escape(site[:lang] || "en"),
      "\">\n<head>\n",
      "<meta charset=\"utf-8\">\n",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
      "<meta name=\"fractal-csrf-token\" content=\"",
      HTML.escape(Plug.CSRFProtection.get_csrf_token()),
      "\">\n",
      theme_color(site),
      favicon(site),
      head_meta(title, site, opts[:meta]),
      "<title>",
      HTML.escape(compose_title(title, site[:name])),
      "</title>\n<link rel=\"stylesheet\" href=\"",
      Assets.css_path(),
      "\">\n</head>\n<body>\n",
      chrome(opts[:assigns]),
      flash_banners(opts[:flash]),
      "<main",
      page_attr(opts[:page]),
      ">",
      HTML.to_safe(body).content,
      "</main>\n",
      Fractal.Interactive.runtime_js(),
      live_reload_script(),
      "</body>\n</html>\n"
    ])
  end

  # page head data over the layout's app-wide defaults; everything
  # rendered here is escaped — pages contribute data, never head markup
  defp head_meta(page_title, site, meta) do
    meta = meta || %{}
    description = meta[:description] || site[:description]

    [
      meta_name("description", description),
      meta_name("robots", meta[:robots]),
      link_tag("canonical", meta[:canonical]),
      og_tags(meta[:og], page_title, description, site),
      extra_tags(meta[:extra])
    ]
  end

  defp og_tags(nil, _page_title, _description, _site), do: ""

  defp og_tags(og, page_title, description, site) when is_map(og) do
    image = og[:image]

    [
      meta_property("og:title", og[:title] || page_title),
      meta_property("og:description", og[:description] || description),
      meta_property("og:site_name", site[:name]),
      meta_property("og:type", og[:type] || "website"),
      meta_property("og:url", og[:url] || nil),
      meta_property("og:image", image),
      meta_name("twitter:card", if(image, do: "summary_large_image", else: "summary"))
    ]
  end

  defp meta_name(_name, nil), do: ""

  defp meta_name(name, content) do
    [
      "<meta name=\"",
      HTML.escape(name),
      "\" content=\"",
      HTML.escape(to_string(content)),
      "\">\n"
    ]
  end

  defp meta_property(_property, nil), do: ""

  defp meta_property(property, content) do
    [
      "<meta property=\"",
      HTML.escape(property),
      "\" content=\"",
      HTML.escape(to_string(content)),
      "\">\n"
    ]
  end

  defp link_tag(_rel, nil), do: ""

  defp link_tag(rel, href) do
    ["<link rel=\"", HTML.escape(rel), "\" href=\"", HTML.escape(to_string(href)), "\">\n"]
  end

  defp extra_tags(nil), do: ""

  defp extra_tags(entries) when is_list(entries) do
    for {tag_name, attrs} <- entries, tag_name in [:meta, :link] do
      [HTML.tag(tag_name, attrs).content, "\n"]
    end
  end

  defp compose_title(title, nil), do: title
  defp compose_title(title, site_name) when title == site_name, do: title
  defp compose_title(title, site_name), do: "#{title} — #{site_name}"

  defp favicon(%{favicon: href}) when is_binary(href) do
    ["<link rel=\"icon\" href=\"", HTML.escape(href), "\">\n"]
  end

  defp favicon(_site), do: ""

  defp theme_color(%{theme_color: color}) when is_binary(color) do
    ["<meta name=\"theme-color\" content=\"", HTML.escape(color), "\">\n"]
  end

  defp theme_color(_site), do: ""

  # the app layout's chrome, scoped like a component so its style/0
  # cannot leak
  defp chrome(assigns) do
    assigns = assigns || %{conn: nil, params: %{}, session: %{}, context: %{}, path: nil}

    case Layout.chrome(assigns) do
      nil ->
        ""

      content ->
        HTML.tag(:div, ["data-layout": true, style: "display: contents"], [
          HTML.to_safe(content)
        ]).content
    end
  end

  defp page_attr(nil), do: ""
  defp page_attr(page), do: [" data-page=\"", Page.slug(page), "\""]

  defp flash_banners(flash) when flash in [nil, %{}], do: ""

  defp flash_banners(flash) do
    for {level, message} <- flash do
      HTML.tag(:div, [class: "flash flash-#{level}", role: "alert"], [to_string(message)]).content
    end
  end

  defp live_reload_script do
    if Application.get_env(:fractal, :live_reload, false), do: @live_reload_script, else: ""
  end
end
