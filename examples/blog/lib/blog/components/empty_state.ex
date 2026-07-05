defmodule Blog.Components.EmptyState do
  @moduledoc """
  A "nothing here" section: a muted title and a link back to safety.

  Used wherever a record is missing or a list has no content — show and
  edit pages render it when their `:id` doesn't resolve.

  Assigns: `:title`, `:back_href`, `:back_label`.
  """

  use Fractal.Component

  @impl Fractal.Component
  def render(assigns) do
    tag(:section, [class: "empty-state"], [
      tag(:h1, [], [assigns.title]),
      tag(:p, [], [tag(:a, [href: assigns.back_href], [assigns.back_label])])
    ])
  end

  @impl Fractal.Component
  def style do
    """
    h1 { font-size: 1.6rem; color: var(--muted); }
    """
  end

  @impl Fractal.Component
  def example do
    %{title: "Nothing here yet", back_href: "/", back_label: "Back home"}
  end
end
