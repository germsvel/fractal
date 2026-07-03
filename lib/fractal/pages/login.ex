defmodule Fractal.Pages.Login do
  @moduledoc """
  A demo login page, served at /login.

  Demonstrates Fractal's session model: `handle_post/1` writes the
  session with the `session:` directive, `handle_delete/1` (the /logout
  route) clears it, and pages read it via `assigns.session`. The layout
  shows a signed-in bar whenever the session has a `"user_name"`.

  This is a name-only demo login — there is no password or user record.
  """

  use Fractal.Page, path: "/login", title: "Log in", post: "/login", delete: "/logout"

  import Fractal.Form

  @impl Fractal.Page
  def render(assigns) do
    case assigns.session["user_name"] do
      nil -> login_form(assigns[:error])
      name -> signed_in(name)
    end
  end

  @impl Fractal.Page
  def handle_post(assigns) do
    case String.trim(assigns.params["name"] || "") do
      "" ->
        {:render, %{error: "Please enter a name."}}

      name ->
        {:redirect, "/login",
         session: %{"user_name" => name}, flash: %{"info" => "Welcome, #{name}!"}}
    end
  end

  @impl Fractal.Page
  def handle_delete(_assigns) do
    {:redirect, "/login", clear_session: true, flash: %{"info" => "Signed out."}}
  end

  defp login_form(error) do
    tag(:section, [], [
      tag(:h1, [], ["Log in"]),
      tag(:p, [class: "lead"], [
        "A demo of Fractal sessions: your name is stored in an encrypted ",
        "cookie and shown by the layout on every page."
      ]),
      if(error, do: tag(:p, [class: "error"], [error])),
      form_for(nil, "/login", [
        input(nil, :name, label: "Your name"),
        submit("Log in")
      ])
    ])
  end

  defp signed_in(name) do
    tag(:section, [], [
      tag(:h1, [], ["Hello, ", name]),
      tag(:p, [], [
        "You are signed in — your name travels with every request in the ",
        "session cookie. Use the bar above (on any page) to log out, or:"
      ]),
      tag(:p, [], [button_to("Log out", "/logout", method: :delete)])
    ])
  end
end
