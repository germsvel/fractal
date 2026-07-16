defmodule Fractal.Interactive.BrowserAction do
  @moduledoc false

  @named_keys ~w(Escape Enter ArrowUp ArrowDown ArrowLeft ArrowRight)
  @modifiers ~w(Mod Ctrl Alt Shift)
  @local_actions [:focus, :navigate, :show, :hide, :toggle]
  @reserved_chords ~w(Mod+w Mod+t Mod+n Mod+l Mod+r Ctrl+w Ctrl+t Ctrl+n Ctrl+l Ctrl+r)

  @spec normalize!(term(), [String.t()], module()) :: [{String.t(), tuple()}]
  def normalize!(keys, events, module) do
    case normalize(keys, events) do
      {:ok, bindings} -> bindings
      {:error, message} -> raise ArgumentError, "#{inspect(module)} has invalid keys: #{message}"
    end
  end

  @spec normalize(term(), [String.t()]) :: {:ok, [{String.t(), tuple()}]} | {:error, String.t()}
  def normalize(keys, events) when is_list(keys) do
    with true <-
           Enum.all?(keys, fn
             {key, _action} -> is_atom(key) or is_binary(key)
             _ -> false
           end) or
             {:error, "keys: must be a keyword list"},
         {:ok, bindings} <- normalize_bindings(keys, events),
         true <-
           Enum.uniq(Enum.map(bindings, &elem(&1, 0))) == Enum.map(bindings, &elem(&1, 0)) or
             {:error, "duplicate key combination"} do
      {:ok, bindings}
    else
      {:error, _message} = error -> error
      false -> {:error, "keys: must be a keyword list"}
    end
  end

  def normalize(_keys, _events), do: {:error, "keys: must be a keyword list"}

  @spec encode([{String.t(), tuple()}]) :: String.t()
  def encode(bindings) do
    bindings
    |> Map.new(fn {key, {type, value}} ->
      {key, %{"type" => to_string(type), "value" => value}}
    end)
    |> JSON.encode!()
  end

  @spec id_selector?(term()) :: boolean()
  def id_selector?(selector),
    do: is_binary(selector) and Regex.match?(~r/^#[A-Za-z][\w:.-]*$/, selector)

  @spec target_id(String.t()) :: String.t()
  def target_id("#" <> id), do: id

  defp normalize_bindings(keys, events) do
    Enum.reduce_while(keys, {:ok, []}, fn {key, action}, {:ok, acc} ->
      with {:ok, key} <- normalize_key(key),
           {:ok, action} <- normalize_action(action, events) do
        {:cont, {:ok, acc ++ [{key, action}]}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp normalize_key(key) when is_atom(key), do: normalize_key(Atom.to_string(key))

  defp normalize_key(key) when is_binary(key) do
    parts = String.split(key, "+")

    cond do
      parts == [] or Enum.any?(parts, &(&1 == "")) ->
        {:error, "key #{inspect(key)} is malformed"}

      length(parts) == 1 and valid_base_key?(key) ->
        {:ok, key}

      length(parts) > 1 and Enum.all?(Enum.drop(parts, -1), &(&1 in @modifiers)) and
        length(Enum.uniq(Enum.drop(parts, -1))) == length(parts) - 1 and
          valid_base_key?(List.last(parts)) ->
        normalized = Enum.join(parts, "+")

        if normalized in @reserved_chords,
          do: {:error, "key #{inspect(key)} is browser-reserved"},
          else: {:ok, normalized}

      true ->
        {:error, "key #{inspect(key)} must be a printable key, named key, or modifier chord"}
    end
  end

  defp normalize_key(key), do: {:error, "key #{inspect(key)} must be a string"}

  defp valid_base_key?(key) do
    key in @named_keys or (String.length(key) == 1 and key =~ ~r/^[\x20-\x7E]$/)
  end

  defp normalize_action({:event, event}, events) when is_binary(event) and event != "" do
    if event in events,
      do: {:ok, {:event, event}},
      else:
        {:error, "event action #{inspect(event)} is not declared in events: #{inspect(events)}"}
  end

  defp normalize_action({:event, event}, _events),
    do: {:error, "event name #{inspect(event)} must be a non-empty string"}

  defp normalize_action({:navigate, "/" <> rest = path}, _events) do
    if String.starts_with?(rest, "/"),
      do: {:error, "navigate target #{inspect(path)} must be an app path beginning with /"},
      else: {:ok, {:navigate, path}}
  end

  defp normalize_action({:navigate, path}, _events),
    do: {:error, "navigate target #{inspect(path)} must be an app path beginning with /"}

  defp normalize_action({type, selector}, _events) when type in @local_actions do
    if id_selector?(selector),
      do: {:ok, {type, selector}},
      else: {:error, "#{type} target #{inspect(selector)} must be an id selector like #search"}
  end

  defp normalize_action(action, _events), do: {:error, "action #{inspect(action)} is unsupported"}
end
