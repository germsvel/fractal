defmodule Fractal.Form do
  @moduledoc """
  Form helpers that understand `Ecto.Changeset`.

  Inputs are pre-filled with the changeset's values (including the
  attempted values of a failed submission) and render their field's
  errors inline. Everything goes through `Fractal.HTML`, so all values
  are escaped.

      import Fractal.Form

      form_for(changeset, "/posts", [
        input(changeset, :title),
        textarea(changeset, :body, rows: 8),
        submit("Create post")
      ])

  Field names are flat (`name="title"`), matching what
  `Ecto.Changeset.cast/4` expects from `assigns.params`.

  Errors are only shown once the changeset has an `:action` (set by
  `Repo.insert/1` and friends on failure), so a pristine form renders
  clean.

  Note: Fractal does not have sessions yet, so forms carry no CSRF token.
  """

  import Fractal.HTML

  alias Ecto.Changeset

  @doc "Renders a POST form around `children`."
  @spec form_for(Changeset.t() | nil, String.t(), term()) :: Fractal.HTML.Safe.t()
  def form_for(_changeset, action, children) do
    tag(:form, [action: action, method: "post"], children)
  end

  @doc """
  Renders a labelled `<input>` for `field`, with its errors.

  ## Options

    * `:type` — the input type (default: `"text"`)
    * `:label` — the label text (default: humanized field name)

  Any other option becomes an attribute on the `<input>`.
  """
  @spec input(Changeset.t() | nil, atom(), keyword()) :: Fractal.HTML.Safe.t()
  def input(changeset, field, opts \\ []) do
    {type, opts} = Keyword.pop(opts, :type, "text")

    field_block(changeset, field, opts, fn value, attrs ->
      tag(:input, [type: type, value: value] ++ attrs)
    end)
  end

  @doc """
  Renders a labelled `<textarea>` for `field`, with its errors.

  Takes the same options as `input/3` (except `:type`).
  """
  @spec textarea(Changeset.t() | nil, atom(), keyword()) :: Fractal.HTML.Safe.t()
  def textarea(changeset, field, opts \\ []) do
    field_block(changeset, field, opts, fn value, attrs ->
      tag(:textarea, attrs, [to_string(value || "")])
    end)
  end

  @doc """
  Renders a labelled checkbox for a boolean `field`, with its errors.

  A hidden `"false"` input precedes the checkbox so unchecking the box
  submits `false` rather than omitting the field.
  """
  @spec checkbox(Changeset.t() | nil, atom(), keyword()) :: Fractal.HTML.Safe.t()
  def checkbox(changeset, field, opts \\ []) do
    field_block(changeset, field, opts, fn value, attrs ->
      [
        tag(:input, [type: "hidden", value: "false"] ++ Keyword.take(attrs, [:name])),
        tag(:input, [type: "checkbox", value: "true", checked: value in [true, "true"]] ++ attrs)
      ]
    end)
  end

  @doc "Renders a submit button."
  @spec submit(String.t(), keyword()) :: Fractal.HTML.Safe.t()
  def submit(label, opts \\ []) do
    tag(:button, [type: "submit"] ++ opts, [label])
  end

  @doc "The error messages for `field`, translated and interpolated."
  @spec errors_for(Changeset.t() | nil, atom()) :: [String.t()]
  def errors_for(nil, _field), do: []
  def errors_for(%Changeset{action: nil}, _field), do: []

  def errors_for(%Changeset{} = changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(&translate_error/1)
  end

  defp field_block(changeset, field, opts, control) do
    {label_text, opts} = Keyword.pop(opts, :label, humanize(field))
    name = to_string(field)
    errors = errors_for(changeset, field)

    tag(:div, [class: "field"], [
      tag(:label, [for: name], [label_text]),
      control.(field_value(changeset, field), [name: name, id: name] ++ opts),
      Enum.map(errors, &tag(:p, [class: "error"], [&1]))
    ])
  end

  defp field_value(nil, _field), do: nil

  defp field_value(%Changeset{} = changeset, field) do
    case Map.fetch(changeset.params || %{}, to_string(field)) do
      {:ok, value} -> value
      :error -> Changeset.get_field(changeset, field)
    end
  end

  defp translate_error({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp humanize(field) do
    field |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end
