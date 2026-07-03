defmodule Fractal.Layout do
  @moduledoc """
  The default HTML document shell.

  Wraps a page's rendered content in a full HTML document with the page
  title, a small default stylesheet, and — when live reload is enabled
  (`config :fractal, :live_reload, true`, set automatically by
  `mix fractal.server` in development) — a script that polls
  `/fractal/reload` and reloads the browser when code recompiles.
  """

  alias Fractal.HTML

  @css """
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    margin: 0; padding: 3rem 1.5rem; background: #0b1021; color: #e6e9f2;
  }
  main { max-width: 44rem; margin: 0 auto; line-height: 1.6; }
  h1 { font-size: 2.2rem; margin-bottom: 0.25rem; }
  h1, h2 { color: #ffffff; }
  a { color: #7cc4ff; }
  code {
    background: rgba(255, 255, 255, 0.08); padding: 0.15rem 0.35rem;
    border-radius: 0.25rem; font-size: 0.95em;
  }
  pre { background: rgba(255, 255, 255, 0.08); padding: 1rem; overflow-x: auto; }
  .lead { font-size: 1.15rem; color: #b8c0d9; }
  ul { padding-left: 1.25rem; }
  .field { margin: 1rem 0; }
  .field label { display: block; margin-bottom: 0.3rem; color: #b8c0d9; }
  .field input, .field textarea {
    width: 100%; padding: 0.5rem 0.65rem; border-radius: 0.35rem;
    border: 1px solid rgba(255, 255, 255, 0.2); background: rgba(255, 255, 255, 0.06);
    color: #e6e9f2; font: inherit;
  }
  .field .error { color: #ff8787; margin: 0.3rem 0 0; font-size: 0.9rem; }
  button[type="submit"] {
    padding: 0.55rem 1.2rem; border-radius: 0.35rem; border: none;
    background: #7cc4ff; color: #0b1021; font: inherit; font-weight: 600; cursor: pointer;
  }
  """

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
    shell(page.title(), HTML.to_safe(page.render(assigns)))
  end

  @doc "Renders a full HTML document from a title and body content."
  @spec shell(String.t(), term()) :: String.t()
  def shell(title, body) do
    IO.iodata_to_binary([
      "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n",
      "<meta charset=\"utf-8\">\n",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
      "<title>",
      HTML.escape(title),
      "</title>\n<style>",
      @css,
      "</style>\n</head>\n<body>\n<main>",
      HTML.to_safe(body).content,
      "</main>\n",
      live_reload_script(),
      "</body>\n</html>\n"
    ])
  end

  defp live_reload_script do
    if Application.get_env(:fractal, :live_reload, false), do: @live_reload_script, else: ""
  end
end
