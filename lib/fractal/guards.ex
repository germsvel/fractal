defmodule Fractal.Guards do
  @moduledoc """
  The app's cross-cutting request behavior: guards, expectations, and
  context — all in this one file. See `Fractal.Guard` for the model.

  Pages opt in with `require:`:

      use Fractal.Page, path: "/admin", title: "Admin", require: :signed_in
  """

  use Fractal.Guard

  # Derivations available to every page and guard as assigns.context.
  # Identity-scale only; must tolerate an empty session.
  def context(assigns) do
    %{"user_name" => assigns.session["user_name"]}
  end

  guard :signed_in do
    if assigns.context["user_name"] do
      :ok
    else
      {:redirect, "/login", flash: %{"error" => "Please log in first."}}
    end
  end

  # verify fails any page under /admin that doesn't require :signed_in
  expect("/admin", :signed_in)
end
