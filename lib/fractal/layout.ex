defmodule Fractal.Layout do
  @moduledoc """
  The default HTML document shell.

  Wraps a page's rendered content in a full HTML document with the page
  title, a small default stylesheet, the CSRF token meta tag, flash
  messages, a signed-in bar (when the session has a `"user_name"`), the
  interactivity runtime, and — when live reload is enabled
  (`config :fractal, :live_reload, true`, set automatically by
  `mix fractal.server` in development) — a script that polls
  `/fractal/reload` and reloads the browser when code recompiles.
  """

  alias Fractal.{Form, HTML}

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
  form.button-to { display: inline; }
  button[type="submit"] {
    padding: 0.55rem 1.2rem; border-radius: 0.35rem; border: none;
    background: #7cc4ff; color: #0b1021; font: inherit; font-weight: 600; cursor: pointer;
  }
  .session-bar {
    max-width: 44rem; margin: 0 auto 1.5rem; display: flex; gap: 0.75rem;
    align-items: baseline; justify-content: flex-end; color: #b8c0d9; font-size: 0.95rem;
  }
  .session-bar form.button-to button[type="submit"] {
    padding: 0.2rem 0.6rem; font-size: 0.85rem; background: rgba(255, 255, 255, 0.12);
    color: #e6e9f2;
  }
  .flash { max-width: 44rem; margin: 0 auto 1rem; padding: 0.6rem 0.9rem; border-radius: 0.35rem; }
  .flash-info { background: rgba(124, 196, 255, 0.15); border: 1px solid rgba(124, 196, 255, 0.5); }
  .flash-error { background: rgba(255, 135, 135, 0.15); border: 1px solid rgba(255, 135, 135, 0.5); }
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
    shell(page.title(), HTML.to_safe(page.render(assigns)),
      flash: assigns[:flash],
      session: assigns[:session]
    )
  end

  @doc """
  Renders a full HTML document from a title and body content.

  Options: `:flash` (map of level → message, rendered as banners) and
  `:session` (used for the signed-in bar when it has a `"user_name"`).
  """
  @spec shell(String.t(), term(), keyword()) :: String.t()
  def shell(title, body, opts \\ []) do
    IO.iodata_to_binary([
      "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n",
      "<meta charset=\"utf-8\">\n",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
      "<meta name=\"fractal-csrf-token\" content=\"",
      HTML.escape(Plug.CSRFProtection.get_csrf_token()),
      "\">\n",
      "<title>",
      HTML.escape(title),
      "</title>\n<style>",
      @css,
      "</style>\n</head>\n<body>\n",
      session_bar(opts[:session]),
      flash_banners(opts[:flash]),
      "<main>",
      HTML.to_safe(body).content,
      "</main>\n",
      Fractal.Interactive.runtime_js(),
      live_reload_script(),
      "</body>\n</html>\n"
    ])
  end

  defp session_bar(%{"user_name" => name}) when is_binary(name) and name != "" do
    HTML.tag(:div, [class: "session-bar"], [
      "Signed in as ",
      HTML.tag(:strong, [], [name]),
      Form.button_to("Log out", "/logout", method: :delete)
    ]).content
  end

  defp session_bar(_session), do: ""

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
