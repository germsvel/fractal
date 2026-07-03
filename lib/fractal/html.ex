defmodule Fractal.HTML do
  @moduledoc """
  A minimal, escaped-by-default HTML builder.

  All text content and attribute values passed to `tag/3` are HTML-escaped
  automatically. The only way to emit unescaped markup is the explicit
  `raw/1`, which makes unsafe output easy to spot in review and easy for
  verification tooling to flag.

  ## Example

      import Fractal.HTML

      tag(:section, [class: "hero"], [
        tag(:h1, [], ["Welcome"]),
        tag(:p, [], ["Hello, ", tag(:strong, [], ["world"]), "!"])
      ])

  Children may be safe HTML (built by `tag/3` or `raw/1`), strings
  (escaped), numbers, `nil` (ignored), or lists of any of those.

  Attribute values are escaped; `true` renders a bare attribute, and
  `false`/`nil` omit the attribute entirely. Underscores in attribute
  names become dashes (`aria_label:` → `aria-label=`).
  """

  defmodule Safe do
    @moduledoc "A wrapper marking iodata as already-escaped, render-ready HTML."
    defstruct content: []
    @type t :: %__MODULE__{content: iodata()}
  end

  @void_tags ~w(area base br col embed hr img input link meta source track wbr)a

  @doc """
  Builds an HTML element as safe HTML.

      iex> Fractal.HTML.tag(:p, [class: "note"], ["1 < 2"]) |> Fractal.HTML.safe_to_string()
      ~s(<p class="note">1 &lt; 2</p>)
  """
  @spec tag(atom(), keyword(), term()) :: Safe.t()
  def tag(name, attrs \\ [], children \\ []) when is_atom(name) and is_list(attrs) do
    tag_name = Atom.to_string(name)

    if name in @void_tags do
      %Safe{content: ["<", tag_name, render_attrs(attrs), ">"]}
    else
      %Safe{
        content: [
          "<",
          tag_name,
          render_attrs(attrs),
          ">",
          content(children),
          "</",
          tag_name,
          ">"
        ]
      }
    end
  end

  @doc """
  Marks iodata as safe HTML, skipping escaping.

  Use sparingly: anything passed here reaches the browser verbatim.
  """
  @spec raw(iodata()) :: Safe.t()
  def raw(iodata), do: %Safe{content: iodata}

  @doc "Escapes a string for safe inclusion in HTML text or attributes."
  @spec escape(String.t()) :: String.t()
  def escape(binary) when is_binary(binary) do
    binary
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  @doc """
  Converts any render result (safe HTML, string, number, list) into safe HTML.

  Strings are escaped; safe HTML passes through untouched.
  """
  @spec to_safe(term()) :: Safe.t()
  def to_safe(%Safe{} = safe), do: safe
  def to_safe(other), do: %Safe{content: content(other)}

  @doc "Renders safe HTML to a binary."
  @spec safe_to_string(Safe.t()) :: String.t()
  def safe_to_string(%Safe{content: content}), do: IO.iodata_to_binary(content)

  defp content(%Safe{content: content}), do: content
  defp content(binary) when is_binary(binary), do: escape(binary)
  defp content(nil), do: []
  defp content(list) when is_list(list), do: Enum.map(list, &content/1)
  defp content(number) when is_integer(number) or is_float(number), do: to_string(number)
  defp content(atom) when is_atom(atom), do: escape(Atom.to_string(atom))

  defp render_attrs(attrs) do
    Enum.map(attrs, fn
      {_key, false} -> []
      {_key, nil} -> []
      {key, true} -> [" ", attr_name(key)]
      {key, value} -> [" ", attr_name(key), "=\"", escape(to_string(value)), "\""]
    end)
  end

  defp attr_name(key), do: key |> to_string() |> String.replace("_", "-")
end
