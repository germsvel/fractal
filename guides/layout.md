# The document and the layout

The ownership model in one sentence: **the framework owns the document,
the app's layout contributes app-wide data and chrome, the page
contributes content.**

## The document (framework-owned)

`Fractal.Document` renders the HTML envelope around every page: the
doctype/head/body skeleton, charset and viewport, the CSRF token meta
tag, the fingerprinted stylesheet link, the `data-page` scoping
attribute, flash banners, the interactivity runtime, and the dev
live-reload script. Apps never copy or edit it — that machinery is
security- and correctness-bearing and must stay upgradable. There is no
app-owned root template, deliberately.

## The layout (app-owned)

Apps influence the document through one optional module — discovered
like the checkpoint, at most one — that contributes **data and safe
HTML, never envelope markup**:

```elixir
# lib/<app>/layouts.ex
defmodule MyApp.Layouts do
  use Fractal.Layout

  # app-wide document data: rendered and escaped by the framework
  def site do
    %{
      name: "My App",                  # <title>Page — My App</title>
      lang: "en",                      # <html lang="en">
      favicon: asset_path("logo.svg"), # missing files fail verify
      theme_color: "#0b1021"
    }
  end

  # app UI above <main> on every page: nav, session bar, footer
  def chrome(assigns) do
    case assigns.session["user_name"] do
      nil -> nil
      name -> tag(:div, [class: "session-bar"], ["Signed in as ", tag(:strong, [], [name])])
    end
  end

  # scoped to the chrome — cannot leak into pages
  def style do
    """
    .session-bar { display: flex; justify-content: flex-end; }
    """
  end
end
```

The rules:

- All callbacks are optional; without a layout module the app gets the
  plain document.
- `chrome/1` receives the usual assigns (session, context, path), must
  tolerate them empty, and passes the same verification scans as pages
  (no `<style>`, no CDNs, CSRF tokens in any forms it renders). Any
  session keys or routes it uses are the app's own — the framework
  knows nothing about them.
- A page title equal to the site name is not composed (the home page
  reads `<title>My App</title>`, not `My App — My App`).
- Per-page head data (descriptions, og tags, canonical URLs) is a
  separate, page-level channel — see the roadmap; app-wide data lives
  here.

## Verification

`mix fractal.verify` checks the layout like everything else: at most
one layout module exists, `site/0` returns well-formed data, `style/0`
is balanced, and `chrome/1` renders with empty assigns through the
standard scans.
