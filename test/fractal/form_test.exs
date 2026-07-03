defmodule Fractal.FormTest do
  use ExUnit.Case, async: true

  import Fractal.Form

  alias Fractal.HTML

  defp changeset(params \\ %{}) do
    {%{}, %{title: :string, body: :string}}
    |> Ecto.Changeset.cast(params, [:title, :body])
    |> Ecto.Changeset.validate_required([:title, :body])
  end

  defp render(safe), do: safe |> HTML.to_safe() |> HTML.safe_to_string()

  test "form_for/3 renders a POST form" do
    html = render(form_for(changeset(), "/posts", [submit("Go")]))

    assert html =~ ~s(<form action="/posts" method="post">)
    assert html =~ ~s(<button type="submit">Go</button>)
  end

  test "input/3 renders a labelled, named input" do
    html = render(input(changeset(), :title))

    assert html =~ ~s(<label for="title">Title</label>)
    assert html =~ ~s(name="title")
    assert html =~ ~s(type="text")
  end

  test "input/3 pre-fills the attempted value, escaped" do
    html = render(input(changeset(%{"title" => ~s(a "<b>" quote)}), :title))

    assert html =~ ~s(value="a &quot;&lt;b&gt;&quot; quote")
  end

  test "errors stay hidden until the changeset has an action" do
    pristine = changeset(%{})
    refute render(input(pristine, :title)) =~ "error"

    failed = Map.put(pristine, :action, :insert)
    assert render(input(failed, :title)) =~ ~s(<p class="error">can&#39;t be blank</p>)
  end

  test "errors_for/2 translates and interpolates error options" do
    failed =
      changeset(%{"title" => "hi", "body" => "x"})
      |> Ecto.Changeset.validate_length(:title, min: 5)
      |> Map.put(:action, :insert)

    assert ["should be at least 5 character(s)"] = errors_for(failed, :title)
  end

  test "textarea/3 renders the value as escaped content" do
    html = render(textarea(changeset(%{"body" => "a <script>"}), :body, rows: 3))

    assert html =~ ~s(<textarea name="body" id="body" rows="3">a &lt;script&gt;</textarea>)
  end

  test "checkbox/3 renders a hidden false followed by the checkbox" do
    html = render(checkbox(changeset(%{"title" => "true"}), :title))

    assert html =~ ~s(<input type="hidden" value="false" name="title">)
    assert html =~ ~s(<input type="checkbox" value="true" checked name="title" id="title">)
  end

  test "helpers accept nil instead of a changeset" do
    html = render(input(nil, :title))

    assert html =~ ~s(name="title")
    refute html =~ "value="
  end
end
