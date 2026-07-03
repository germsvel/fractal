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

  alias Fractal.{Assets, Form, HTML, Page}

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
      session: assigns[:session],
      page: page
    )
  end

  @doc """
  Renders a full HTML document from a title and body content.

  Options: `:flash` (map of level → message, rendered as banners),
  `:session` (used for the signed-in bar when it has a `"user_name"`),
  and `:page` (the page module — sets the `data-page` attribute that
  scopes the page's `style/0`).
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
      "</title>\n<link rel=\"stylesheet\" href=\"",
      Assets.css_path(),
      "\">\n</head>\n<body>\n",
      session_bar(opts[:session]),
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

  defp page_attr(nil), do: ""
  defp page_attr(page), do: [" data-page=\"", Page.slug(page), "\""]

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
