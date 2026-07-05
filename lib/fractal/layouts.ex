defmodule Fractal.Layouts do
  @moduledoc """
  This app's layout: app-wide document data and the session bar.

  See `Fractal.Layout` for the model. The `"user_name"` session key and
  the `/logout` route referenced here are this app's own decisions (its
  Login page writes the key and serves the route) — the framework knows
  nothing about either.
  """

  use Fractal.Layout

  def site do
    %{
      name: "Fractal",
      lang: "en",
      favicon: asset_path("logo.svg"),
      theme_color: "#0b1021",
      description: "An AI-first web framework written in Elixir."
    }
  end

  def chrome(assigns) do
    case assigns.session["user_name"] do
      name when is_binary(name) and name != "" ->
        tag(:div, [class: "session-bar"], [
          "Signed in as ",
          tag(:strong, [], [name]),
          button_to("Log out", "/logout", method: :delete)
        ])

      _signed_out ->
        nil
    end
  end

  def style do
    """
    .session-bar {
      max-width: 44rem; margin: 0 auto 1.5rem; display: flex; gap: 0.75rem;
      align-items: baseline; justify-content: flex-end; color: var(--muted); font-size: 0.95rem;
    }
    .session-bar form.button-to button[type="submit"] {
      padding: 0.2rem 0.6rem; font-size: 0.85rem; background: rgba(255, 255, 255, 0.12);
      color: var(--text);
    }
    """
  end
end
