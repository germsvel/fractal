defmodule Fractal.Pages.Admin do
  @moduledoc """
  A demo admin dashboard, served at /admin.

  Demonstrates guards: `require: :signed_in` runs before the render and
  before the refresh event, and the `expect "/admin", :signed_in`
  declaration in `Fractal.Guards` makes verification fail any future
  /admin page that forgets it.
  """

  use Fractal.Page,
    path: "/admin",
    title: "Admin",
    events: ["refresh"],
    require: :signed_in

  alias Fractal.Repo

  @impl Fractal.Page
  def render(assigns) do
    tag(:section, [], [
      tag(:h1, [], ["Admin"]),
      tag(:p, [class: "lead"], [
        "Only for the signed-in — this page (and its refresh event) sits behind ",
        tag(:code, [], ["require: :signed_in"]),
        "."
      ]),
      tag(:p, [], [
        "Hello, ",
        tag(:strong, [], [to_string(assigns.context["user_name"])]),
        "."
      ]),
      stats()
    ])
  end

  @impl Fractal.Page
  def handle_event("refresh", _assigns), do: {:fragment, stats()}

  defp stats do
    tag(:div, [id: "stats"], [
      tag(:p, [], [
        tag(:strong, [], [to_string(Repo.aggregate(Fractal.Post, :count))]),
        " posts published."
      ]),
      trigger("Refresh", "refresh", target: "#stats")
    ])
  end
end
