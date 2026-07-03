defmodule Fractal.Pages.Counter do
  @moduledoc """
  A sample interactive page, served at /counter.

  Demonstrates Fractal's interactivity model: the count lives in the
  DOM (sent back with each event via `values:`), handlers return
  fragments that replace the region, and no JavaScript is written.
  """

  use Fractal.Page,
    path: "/counter",
    title: "Counter",
    events: ["increment", "decrement", "reset"]

  @impl Fractal.Page
  def render(_assigns) do
    tag(:section, [], [
      tag(:h1, [], ["Counter"]),
      tag(:p, [class: "lead"], [
        "A sample interactive page — the buttons round-trip to ",
        tag(:code, [], ["handle_event/2"]),
        " and swap the fragment below. No JavaScript was written for this page."
      ]),
      counter(0)
    ])
  end

  @impl Fractal.Page
  def style do
    """
    #counter { display: flex; gap: 0.5rem; align-items: center; }
    #counter p { font-size: 1.5rem; margin: 0 1rem 0 0; }
    button { min-width: 3.5rem; }
    """
  end

  @impl Fractal.Page
  def handle_event("increment", assigns), do: {:fragment, counter(current(assigns) + 1)}
  def handle_event("decrement", assigns), do: {:fragment, counter(current(assigns) - 1)}
  def handle_event("reset", _assigns), do: {:redirect, "/counter"}

  defp current(assigns) do
    case Integer.parse(assigns.params["count"] || "0") do
      {count, ""} -> count
      _ -> 0
    end
  end

  defp counter(count) do
    tag(:div, [id: "counter"], [
      tag(:p, [], [tag(:strong, [], ["Count: "]), to_string(count)]),
      trigger("−1", "decrement", target: "#counter", values: %{count: count}),
      " ",
      trigger("+1", "increment", target: "#counter", values: %{count: count}),
      " ",
      trigger("Reset", "reset", target: "#counter")
    ])
  end
end
