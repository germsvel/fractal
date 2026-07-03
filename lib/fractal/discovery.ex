defmodule Fractal.Discovery do
  @moduledoc false

  # Scans the app's ebin for modules instead of using Application.spec/2 so
  # that modules compiled after boot (by the dev reloader) are still found.
  # Used by Fractal.Router (pages) and Fractal.Component (components).
  @spec modules() :: [module()]
  def modules do
    case :code.lib_dir(:fractal) do
      {:error, _reason} ->
        Application.spec(:fractal, :modules) || []

      dir ->
        [List.to_string(dir), "ebin", "*.beam"]
        |> Path.join()
        |> Path.wildcard()
        |> Enum.map(&(&1 |> Path.basename(".beam") |> String.to_atom()))
    end
  end
end
