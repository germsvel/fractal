defmodule Mix.Tasks.Fractal.Gen.Resource do
  @shortdoc "Generates a resource: schema, migration, pages with a form, and tests"

  @moduledoc """
  Generates everything a database-backed resource needs:

      mix fractal.gen.resource Post title:string body:text

  creates

    * `lib/fractal/post.ex` — the Ecto schema and changeset
    * `priv/repo/migrations/<timestamp>_create_posts.exs`
    * `lib/fractal/pages/posts.ex` — index page at `/posts`
    * `lib/fractal/pages/new_post.ex` — form at `/posts/new`, handling
      `POST /posts` in the same file
    * `lib/fractal/pages/post.ex` — show page at `/posts/:id`, with the
      delete button, handling `DELETE /posts/:id` in the same file
    * `lib/fractal/pages/edit_post.ex` — edit form at `/posts/:id/edit`,
      handling `PUT /posts/:id` in the same file
    * `test/fractal/pages/posts_test.exs` — tests for all four pages

  Supported field types: `string`, `text`, `integer`, `float`, `boolean`,
  `date`. All fields are required by default — edit the schema's
  changeset to loosen that.

  ## Options

    * `--plural` — override the naive `<name>s` pluralization

  After generating, run `mix ecto.migrate`, then `mix fractal.verify`.
  """

  use Mix.Task

  @types ~w(string text integer float boolean date)

  @impl Mix.Task
  def run(args) do
    {opts, argv, _errors} = OptionParser.parse(args, strict: [plural: :string])

    {name, field_args} =
      case argv do
        [name | fields] when fields != [] ->
          {name, fields}

        _ ->
          Mix.raise(
            "usage: mix fractal.gen.resource Name field:type [field:type ...]\n" <>
              "supported types: #{Enum.join(@types, ", ")}"
          )
      end

    camel = Macro.camelize(name)
    singular = Macro.underscore(camel)
    plural = opts[:plural] || singular <> "s"
    fields = Enum.map(field_args, &parse_field!/1)

    context = %{
      camel: camel,
      singular: singular,
      plural: plural,
      camel_plural: Macro.camelize(plural),
      route: "/" <> String.replace(plural, "_", "-"),
      human: humanize(singular),
      human_downcase: String.downcase(humanize(singular)),
      fields: fields
    }

    files = [
      {Path.join(["lib", "fractal", "#{singular}.ex"]), schema_template(context)},
      {migration_path(plural), migration_template(context)},
      {Path.join(["lib", "fractal", "pages", "#{plural}.ex"]), index_template(context)},
      {Path.join(["lib", "fractal", "pages", "new_#{singular}.ex"]), new_template(context)},
      {Path.join(["lib", "fractal", "pages", "#{singular}.ex"]), show_template(context)},
      {Path.join(["lib", "fractal", "pages", "edit_#{singular}.ex"]), edit_template(context)},
      {Path.join(["test", "fractal", "pages", "#{plural}_test.exs"]), test_template(context)}
    ]

    Enum.each(files, fn {file, _contents} ->
      if File.exists?(file), do: Mix.raise("#{file} already exists")
    end)

    Enum.each(files, fn {file, contents} ->
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, contents)
      Mix.shell().info("* created #{file}")
    end)

    Mix.shell().info("""

    Next steps:

        mix ecto.migrate
        mix fractal.verify
    """)
  end

  defp parse_field!(arg) do
    case String.split(arg, ":") do
      [name, type] when type in @types ->
        unless name =~ ~r/^[a-z_][a-z0-9_]*$/ do
          Mix.raise("invalid field name #{inspect(name)}")
        end

        {String.to_atom(name), String.to_atom(type)}

      _ ->
        Mix.raise(
          "invalid field #{inspect(arg)} — expected name:type with type in: " <>
            Enum.join(@types, ", ")
        )
    end
  end

  defp migration_path(plural) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    Path.join(["priv", "repo", "migrations", "#{timestamp}_create_#{plural}.exs"])
  end

  defp schema_type(:text), do: ":string"
  defp schema_type(:date), do: ":date"
  defp schema_type(type), do: ":#{type}"

  defp column_type(type), do: ":#{type}"

  defp form_control(:text), do: :textarea
  defp form_control(:boolean), do: :checkbox
  defp form_control(_type), do: :input

  defp form_field({name, type}) do
    case form_control(type) do
      :textarea -> "textarea(changeset, :#{name}, rows: 6)"
      :checkbox -> "checkbox(changeset, :#{name})"
      :input -> "input(changeset, :#{name}#{input_type_opt(type)})"
    end
  end

  defp input_type_opt(:integer), do: ~s(, type: "number")
  defp input_type_opt(:float), do: ~s(, type: "number", step: "any")
  defp input_type_opt(:date), do: ~s(, type: "date")
  defp input_type_opt(_type), do: ""

  defp sample_value({_name, :string}, index), do: "some value #{index}"
  defp sample_value({_name, :text}, index), do: "some longer value #{index}"
  defp sample_value({_name, :integer}, index), do: "#{index}"
  defp sample_value({_name, :float}, index), do: "#{index}.5"
  defp sample_value({_name, :boolean}, _index), do: "true"
  defp sample_value({_name, :date}, _index), do: "2026-01-01"

  defp humanize(name), do: name |> String.replace("_", " ") |> String.capitalize()

  defp schema_template(ctx) do
    field_lines =
      Enum.map_join(ctx.fields, "\n", fn {name, type} ->
        "    field :#{name}, #{schema_type(type)}"
      end)

    field_names = Enum.map_join(ctx.fields, ", ", fn {name, _type} -> ":#{name}" end)

    """
    defmodule Fractal.#{ctx.camel} do
      @moduledoc "The #{ctx.human} schema, backed by the #{ctx.plural} table."

      use Ecto.Schema

      import Ecto.Changeset

      schema "#{ctx.plural}" do
    #{field_lines}

        timestamps()
      end

      @doc "Builds a changeset for creating or updating a #{ctx.human_downcase}."
      def changeset(#{ctx.singular}, attrs) do
        #{ctx.singular}
        |> cast(attrs, [#{field_names}])
        |> validate_required([#{field_names}])
      end
    end
    """
  end

  defp migration_template(ctx) do
    column_lines =
      Enum.map_join(ctx.fields, "\n", fn {name, type} ->
        "      add :#{name}, #{column_type(type)}"
      end)

    """
    defmodule Fractal.Repo.Migrations.Create#{ctx.camel_plural} do
      use Ecto.Migration

      def change do
        create table(:#{ctx.plural}) do
    #{column_lines}

          timestamps()
        end
      end
    end
    """
  end

  defp index_template(ctx) do
    {first_field, _type} = hd(ctx.fields)

    """
    defmodule Fractal.Pages.#{ctx.camel_plural} do
      @moduledoc "Lists all #{ctx.plural}, served at #{ctx.route}."

      use Fractal.Page, path: "#{ctx.route}", title: "#{humanize(ctx.plural)}"

      import Ecto.Query, only: [order_by: 2]

      alias Fractal.Repo

      @impl Fractal.Page
      def render(_assigns) do
        #{ctx.plural} = Repo.all(order_by(Fractal.#{ctx.camel}, desc: :id))

        tag(:section, [], [
          tag(:h1, [], ["#{humanize(ctx.plural)}"]),
          render_list(#{ctx.plural}),
          tag(:p, [], [tag(:a, [href: "#{ctx.route}/new"], ["New #{ctx.human_downcase}"])])
        ])
      end

      defp render_list([]), do: tag(:p, [], ["No #{ctx.plural} yet."])

      defp render_list(#{ctx.plural}) do
        tag(
          :ul,
          [],
          for #{ctx.singular} <- #{ctx.plural} do
            tag(:li, [], [
              tag(:a, [href: "#{ctx.route}/\#{#{ctx.singular}.id}"], [to_string(#{ctx.singular}.#{first_field})])
            ])
          end
        )
      end
    end
    """
  end

  defp new_template(ctx) do
    form_fields = Enum.map_join(ctx.fields, ",\n        ", &form_field/1)

    """
    defmodule Fractal.Pages.New#{ctx.camel} do
      @moduledoc "Form to create a #{ctx.human_downcase}; handles POST #{ctx.route} in this same file."

      use Fractal.Page, path: "#{ctx.route}/new", title: "New #{ctx.human_downcase}", post: "#{ctx.route}"

      import Fractal.Form

      alias Fractal.Repo

      @impl Fractal.Page
      def render(assigns) do
        changeset = assigns[:changeset] || Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, %{})

        tag(:section, [], [
          tag(:h1, [], ["New #{ctx.human_downcase}"]),
          form_for(changeset, "#{ctx.route}", [
            #{form_fields},
            submit("Create #{ctx.human_downcase}")
          ]),
          tag(:p, [], [tag(:a, [href: "#{ctx.route}"], ["Back to #{ctx.plural}"])])
        ])
      end

      @impl Fractal.Page
      def handle_post(assigns) do
        case Repo.insert(Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, assigns.params)) do
          {:ok, #{ctx.singular}} -> {:redirect, "#{ctx.route}/\#{#{ctx.singular}.id}"}
          {:error, changeset} -> {:render, %{changeset: changeset}}
        end
      end
    end
    """
  end

  defp show_template(ctx) do
    {first_field, _type} = hd(ctx.fields)

    detail_lines =
      ctx.fields
      |> tl()
      |> Enum.map_join(",\n          ", fn {name, _type} ->
        ~s{tag(:p, [], [tag(:strong, [], ["#{humanize(to_string(name))}: "]), to_string(#{ctx.singular}.#{name})])}
      end)

    details = if detail_lines == "", do: "", else: "\n          " <> detail_lines <> ","

    """
    defmodule Fractal.Pages.#{ctx.camel} do
      @moduledoc "Shows a single #{ctx.human_downcase}, served at #{ctx.route}/:id; handles DELETE #{ctx.route}/:id in this same file."

      use Fractal.Page, path: "#{ctx.route}/:id", title: "#{ctx.human}", delete: "#{ctx.route}/:id"

      import Fractal.Form

      alias Fractal.Components.EmptyState
      alias Fractal.Repo

      @impl Fractal.Page
      def render(assigns) do
        case fetch(assigns.params["id"]) do
          nil ->
            component(EmptyState,
              title: "#{ctx.human} not found",
              back_href: "#{ctx.route}",
              back_label: "Back to #{ctx.plural}"
            )

          #{ctx.singular} ->
            tag(:section, [], [
              tag(:h1, [], [to_string(#{ctx.singular}.#{first_field})]),#{details}
              tag(:p, [], [
                tag(:a, [href: "#{ctx.route}/\#{#{ctx.singular}.id}/edit"], ["Edit"]),
                " · ",
                tag(:a, [href: "#{ctx.route}"], ["Back to #{ctx.plural}"])
              ]),
              tag(:p, [], [
                button_to("Delete #{ctx.human_downcase}", "#{ctx.route}/\#{#{ctx.singular}.id}", method: :delete)
              ])
            ])
        end
      end

      @impl Fractal.Page
      def handle_delete(assigns) do
        case fetch(assigns.params["id"]) do
          nil ->
            {:redirect, "#{ctx.route}"}

          #{ctx.singular} ->
            Repo.delete!(#{ctx.singular})
            {:redirect, "#{ctx.route}"}
        end
      end

      defp fetch(id) when is_binary(id) do
        case Integer.parse(id) do
          {id, ""} -> Repo.get(Fractal.#{ctx.camel}, id)
          _ -> nil
        end
      end

      defp fetch(_id), do: nil
    end
    """
  end

  defp edit_template(ctx) do
    form_fields = Enum.map_join(ctx.fields, ",\n              ", &form_field/1)

    """
    defmodule Fractal.Pages.Edit#{ctx.camel} do
      @moduledoc "Form to edit a #{ctx.human_downcase}; handles PUT #{ctx.route}/:id in this same file."

      use Fractal.Page,
        path: "#{ctx.route}/:id/edit",
        title: "Edit #{ctx.human_downcase}",
        put: "#{ctx.route}/:id"

      import Fractal.Form

      alias Fractal.Components.EmptyState
      alias Fractal.Repo

      @impl Fractal.Page
      def render(assigns) do
        case fetch(assigns.params["id"]) do
          nil ->
            component(EmptyState,
              title: "#{ctx.human} not found",
              back_href: "#{ctx.route}",
              back_label: "Back to #{ctx.plural}"
            )

          #{ctx.singular} ->
            changeset = assigns[:changeset] || Fractal.#{ctx.camel}.changeset(#{ctx.singular}, %{})

            tag(:section, [], [
              tag(:h1, [], ["Edit #{ctx.human_downcase}"]),
              form_for(changeset, "#{ctx.route}/\#{#{ctx.singular}.id}", [method: :put], [
                #{form_fields},
                submit("Save #{ctx.human_downcase}")
              ]),
              tag(:p, [], [tag(:a, [href: "#{ctx.route}/\#{#{ctx.singular}.id}"], ["Back to #{ctx.human_downcase}"])])
            ])
        end
      end

      @impl Fractal.Page
      def handle_put(assigns) do
        case fetch(assigns.params["id"]) do
          nil ->
            {:redirect, "#{ctx.route}"}

          #{ctx.singular} ->
            case Repo.update(Fractal.#{ctx.camel}.changeset(#{ctx.singular}, assigns.params)) do
              {:ok, #{ctx.singular}} -> {:redirect, "#{ctx.route}/\#{#{ctx.singular}.id}"}
              {:error, changeset} -> {:render, %{changeset: changeset}}
            end
        end
      end

      defp fetch(id) when is_binary(id) do
        case Integer.parse(id) do
          {id, ""} -> Repo.get(Fractal.#{ctx.camel}, id)
          _ -> nil
        end
      end

      defp fetch(_id), do: nil
    end
    """
  end

  defp test_template(ctx) do
    valid_params =
      ctx.fields
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {{name, _type} = field, index} ->
        ~s("#{name}" => "#{sample_value(field, index)}")
      end)

    {first_field, first_type} = hd(ctx.fields)
    first_value = sample_value({first_field, first_type}, 1)
    updated_value = sample_value({first_field, first_type}, 9)

    """
    defmodule Fractal.Pages.#{ctx.camel_plural}Test do
      use Fractal.DataCase, async: true

      import Fractal.Test

      alias Fractal.Repo

      @valid_params %{#{valid_params}}

      test "all #{ctx.human_downcase} pages pass Fractal's verification checks" do
        pages = [
          Fractal.Pages.#{ctx.camel_plural},
          Fractal.Pages.New#{ctx.camel},
          Fractal.Pages.#{ctx.camel},
          Fractal.Pages.Edit#{ctx.camel}
        ]

        results = Fractal.Verify.run(pages)
        assert Fractal.Verify.ok?(results), inspect(Fractal.Verify.errors(results))
      end

      test "GET #{ctx.route} lists #{ctx.plural}" do
        {:ok, _#{ctx.singular}} =
          Repo.insert(Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, @valid_params))

        conn = get("#{ctx.route}")

        assert conn.status == 200
        assert conn.resp_body =~ "#{first_value}"
      end

      test "GET #{ctx.route}/new shows the form" do
        conn = get("#{ctx.route}/new")

        assert conn.status == 200
        assert conn.resp_body =~ ~s(action="#{ctx.route}")
        assert conn.resp_body =~ ~s(name="#{first_field}")
      end

      test "POST #{ctx.route} with valid params creates and redirects to the new #{ctx.human_downcase}" do
        conn = post("#{ctx.route}", @valid_params)

        assert conn.status == 303
        [location] = Plug.Conn.get_resp_header(conn, "location")
        assert location =~ ~r{^#{ctx.route}/\\d+$}

        shown = get(location)
        assert shown.status == 200
        assert shown.resp_body =~ "#{first_value}"
        assert shown.resp_body =~ ~s[name="_method" value="delete"], "show page has a delete button"
      end

      test "POST #{ctx.route} with invalid params re-renders the form with errors" do
        conn = post("#{ctx.route}", %{})

        assert conn.status == 200
        assert conn.resp_body =~ "can&#39;t be blank"
        assert Repo.aggregate(Fractal.#{ctx.camel}, :count) == 0
      end

      test "GET #{ctx.route}/:id for a missing #{ctx.human_downcase} renders not found" do
        conn = get("#{ctx.route}/0")

        assert conn.status == 200
        assert conn.resp_body =~ "not found"
      end

      test "GET #{ctx.route}/:id/edit shows the pre-filled edit form" do
        {:ok, #{ctx.singular}} =
          Repo.insert(Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, @valid_params))

        conn = get("#{ctx.route}/\#{#{ctx.singular}.id}/edit")

        assert conn.status == 200
        assert conn.resp_body =~ ~s[action="#{ctx.route}/\#{#{ctx.singular}.id}"]
        assert conn.resp_body =~ ~s[name="_method" value="put"]
        assert conn.resp_body =~ "#{first_value}"
      end

      test "PUT #{ctx.route}/:id updates the #{ctx.human_downcase} and redirects to it" do
        {:ok, #{ctx.singular}} =
          Repo.insert(Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, @valid_params))

        conn = put("#{ctx.route}/\#{#{ctx.singular}.id}", %{"#{first_field}" => "#{updated_value}"})

        assert conn.status == 303
        assert Plug.Conn.get_resp_header(conn, "location") == ["#{ctx.route}/\#{#{ctx.singular}.id}"]
        assert to_string(Repo.get!(Fractal.#{ctx.camel}, #{ctx.singular}.id).#{first_field}) == "#{updated_value}"
      end

      test "PUT #{ctx.route}/:id with invalid params re-renders the edit form with errors" do
        {:ok, #{ctx.singular}} =
          Repo.insert(Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, @valid_params))

        conn = put("#{ctx.route}/\#{#{ctx.singular}.id}", %{"#{first_field}" => ""})

        assert conn.status == 200
        assert conn.resp_body =~ "can&#39;t be blank"
        assert to_string(Repo.get!(Fractal.#{ctx.camel}, #{ctx.singular}.id).#{first_field}) == "#{first_value}"
      end

      test "DELETE #{ctx.route}/:id destroys the #{ctx.human_downcase} and redirects to the index" do
        {:ok, #{ctx.singular}} =
          Repo.insert(Fractal.#{ctx.camel}.changeset(%Fractal.#{ctx.camel}{}, @valid_params))

        conn = delete("#{ctx.route}/\#{#{ctx.singular}.id}")

        assert conn.status == 303
        assert Plug.Conn.get_resp_header(conn, "location") == ["#{ctx.route}"]
        assert Repo.get(Fractal.#{ctx.camel}, #{ctx.singular}.id) == nil
      end
    end
    """
  end
end
