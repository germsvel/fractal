defmodule Fractal.Invariants do
  @moduledoc """
  The app's invariants: properties `mix fractal.verify` guarantees for
  every page, current and future. See `Fractal.Invariant` for the model.

  These are house rules, not per-page checks — a page's behavioral spec
  lives in its test file.
  """

  use Fractal.Invariant

  invariant "title fits in a search result", %{page: page} do
    length = page.title() |> String.length()

    if length <= 60 do
      :ok
    else
      {:error, "title is #{length} chars — keep it under 60"}
    end
  end

  # one h1 per page: screen readers and scanners rely on it
  invariant "every page renders exactly one h1", %{rendered: rendered} do
    case rendered |> String.split("<h1") |> length() |> Kernel.-(1) do
      1 -> :ok
      count -> {:error, "renders #{count} h1 elements — pages need exactly one"}
    end
  end
end
