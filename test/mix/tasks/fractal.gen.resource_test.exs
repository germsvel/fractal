defmodule Mix.Tasks.Fractal.Gen.ResourceTest do
  use ExUnit.Case

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(original_shell) end)
    :ok
  end

  @tag :tmp_dir
  test "generates schema, migration, pages, and tests", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Resource.run([
        "Widget",
        "name:string",
        "description:text",
        "count:integer",
        "published:boolean"
      ])

      schema = File.read!("lib/fractal/widget.ex")
      assert schema =~ "defmodule Fractal.Widget do"
      assert schema =~ ~s(schema "widgets" do)
      assert schema =~ "field :name, :string"
      assert schema =~ "field :description, :string"
      assert schema =~ "field :count, :integer"
      assert schema =~ "cast(attrs, [:name, :description, :count, :published])"

      [migration_file] = Path.wildcard("priv/repo/migrations/*_create_widgets.exs")
      migration = File.read!(migration_file)
      assert migration =~ "defmodule Fractal.Repo.Migrations.CreateWidgets do"
      assert migration =~ "create table(:widgets) do"
      assert migration =~ "add :description, :text"

      index = File.read!("lib/fractal/pages/widgets.ex")
      assert index =~ ~s(use Fractal.Page, path: "/widgets", title: "Widgets")

      new_page = File.read!("lib/fractal/pages/new_widget.ex")

      assert new_page =~
               ~s[use Fractal.Page, path: "/widgets/new", title: "New widget", post: "/widgets"]

      assert new_page =~ "def handle_post(assigns) do"
      assert new_page =~ "textarea(changeset, :description, rows: 6)"
      assert new_page =~ ~s[input(changeset, :count, type: "number")]
      assert new_page =~ "checkbox(changeset, :published)"

      show = File.read!("lib/fractal/pages/widget.ex")

      assert show =~
               ~s[use Fractal.Page, path: "/widgets/:id", title: "Widget", delete: "/widgets/:id"]

      assert show =~ ~s[/edit"], "show page links to the edit page"
      assert show =~ "def handle_delete(assigns) do"
      assert show =~ ~s[button_to("Delete widget"]
      assert show =~ "component(EmptyState,", "not-found uses the shared component"

      edit = File.read!("lib/fractal/pages/edit_widget.ex")
      assert edit =~ ~s[path: "/widgets/:id/edit"]
      assert edit =~ ~s[put: "/widgets/:id"]
      assert edit =~ "def handle_put(assigns) do"
      refute edit =~ "handle_delete", "delete lives on the show page"

      tests = File.read!("test/fractal/pages/widgets_test.exs")
      assert tests =~ "use Fractal.DataCase, async: true"
      assert tests =~ "import Fractal.Test"
      assert tests =~ ~s[post("/widgets", @valid_params)]
      assert tests =~ ~s[put("/widgets/]
      assert tests =~ ~s[delete("/widgets/]
      assert tests =~ "assert conn.status == 303"
    end)
  end

  @tag :tmp_dir
  test "supports a custom plural", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Resource.run(["Story", "title:string", "--plural", "stories"])

      assert File.exists?("lib/fractal/pages/stories.ex")
      assert File.read!("lib/fractal/story.ex") =~ ~s(schema "stories" do)
    end)
  end

  @tag :tmp_dir
  test "refuses to overwrite existing files", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Fractal.Gen.Resource.run(["Widget", "name:string"])

      assert_raise Mix.Error, ~r/already exists/, fn ->
        Mix.Tasks.Fractal.Gen.Resource.run(["Widget", "name:string"])
      end
    end)
  end

  test "requires a name and at least one field" do
    assert_raise Mix.Error, ~r/usage/, fn ->
      Mix.Tasks.Fractal.Gen.Resource.run(["Widget"])
    end
  end

  test "rejects unknown field types" do
    assert_raise Mix.Error, ~r/invalid field/, fn ->
      Mix.Tasks.Fractal.Gen.Resource.run(["Widget", "name:blob"])
    end
  end
end
