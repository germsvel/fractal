defmodule Fractal.VerifyTest do
  # DataCase: discovered pages include database-backed ones, which render
  # real queries during verification
  use Fractal.DataCase, async: true

  alias Fractal.Verify

  defmodule GoodPage do
    use Fractal.Page, path: "/verify-good", title: "Good"

    @impl Fractal.Page
    def render(_assigns), do: tag(:p, [], ["fine"])
  end

  defmodule DuplicateA do
    use Fractal.Page, path: "/verify-dup"

    @impl Fractal.Page
    def render(_assigns), do: "a"
  end

  defmodule DuplicateB do
    use Fractal.Page, path: "/verify-dup"

    @impl Fractal.Page
    def render(_assigns), do: "b"
  end

  defmodule RaisingRender do
    use Fractal.Page, path: "/verify-raise"

    @impl Fractal.Page
    def render(_assigns), do: raise("boom")
  end

  # bypasses `use Fractal.Page` so compile-time validation can't catch it
  defmodule SneakyBadPath do
    @behaviour Fractal.Page

    @impl Fractal.Page
    def path, do: "not-a-path"

    @impl Fractal.Page
    def title, do: "Sneaky"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  defmodule BadReturn do
    use Fractal.Page, path: "/verify-bad-return"

    @impl Fractal.Page
    def render(_assigns), do: {:not, :renderable}
  end

  defmodule PostDupA do
    use Fractal.Page, path: "/verify-post-dup/a", post: "/verify-post-dup"

    @impl Fractal.Page
    def render(_assigns), do: "a"

    @impl Fractal.Page
    def handle_post(_assigns), do: {:redirect, "/"}
  end

  defmodule PostDupB do
    use Fractal.Page, path: "/verify-post-dup/b", post: "/verify-post-dup"

    @impl Fractal.Page
    def render(_assigns), do: "b"

    @impl Fractal.Page
    def handle_post(_assigns), do: {:redirect, "/"}
  end

  # declares put/delete routes but bypasses the compile-time handler checks
  defmodule SneakyPutDelete do
    @behaviour Fractal.Page

    @impl Fractal.Page
    def path, do: "/verify-sneaky-pd/edit"

    @impl Fractal.Page
    def title, do: "Sneaky put/delete"

    @impl Fractal.Page
    def put_path, do: "/verify-sneaky-pd"

    @impl Fractal.Page
    def delete_path, do: "/verify-sneaky-pd"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  # declares events but bypasses the compile-time handle_event check
  defmodule SneakyEvents do
    @behaviour Fractal.Page

    @impl Fractal.Page
    def path, do: "/verify-sneaky-events"

    @impl Fractal.Page
    def title, do: "Sneaky events"

    @impl Fractal.Page
    def events, do: ["ping"]

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  # declares a post route but bypasses the compile-time handle_post check
  defmodule SneakyPost do
    @behaviour Fractal.Page

    @impl Fractal.Page
    def path, do: "/verify-sneaky-post"

    @impl Fractal.Page
    def title, do: "Sneaky post"

    @impl Fractal.Page
    def post_path, do: "/verify-sneaky-post"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  test "the app's discovered pages pass verification" do
    results = Verify.run()
    assert Verify.ok?(results), inspect(Verify.errors(results))
  end

  test "a well-formed page passes all checks" do
    results = Verify.run([GoodPage])
    assert Verify.ok?(results)
  end

  test "detects when no pages exist" do
    results = Verify.run([])
    refute Verify.ok?(results)
    assert [{"pages are defined", {:error, message}}] = Verify.errors(results)
    assert message =~ "no page modules found"
  end

  test "detects duplicate routes" do
    results = Verify.run([DuplicateA, DuplicateB])
    assert [{"GET routes are unique", {:error, message}}] = Verify.errors(results)
    assert message =~ "/verify-dup"
    assert message =~ "DuplicateA"
    assert message =~ "DuplicateB"
  end

  test "detects duplicate POST routes" do
    results = Verify.run([PostDupA, PostDupB])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name == "POST routes are unique" and message =~ "/verify-post-dup"
           end)
  end

  test "detects a post route without handle_post/1" do
    results = Verify.run([SneakyPost])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "handles its post route" and message =~ "does not export handle_post/1"
           end)
  end

  test "detects put and delete routes without their handlers" do
    results = Verify.run([SneakyPutDelete])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "handles its put route" and message =~ "does not export handle_put/1"
           end)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "handles its delete route" and message =~ "does not export handle_delete/1"
           end)
  end

  test "detects declared events without handle_event/2" do
    results = Verify.run([SneakyEvents])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "handles its events" and message =~ "does not export handle_event/2"
           end)
  end

  test "pending_migrations/0 passes on a migrated database" do
    assert {"migrations are up", :ok} = Verify.pending_migrations()
  end

  test "detects a render that raises" do
    results = Verify.run([RaisingRender])
    assert [{name, {:error, message}}] = Verify.errors(results)
    assert name =~ "renders"
    assert message =~ "render/1 raised"
    assert message =~ "boom"
  end

  test "detects a malformed path even when compile-time checks were bypassed" do
    results = Verify.run([SneakyBadPath])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "valid path" and message =~ "not-a-path"
           end)
  end

  test "detects a render returning something unrenderable" do
    results = Verify.run([BadReturn])
    assert [{name, {:error, message}}] = Verify.errors(results)
    assert name =~ "renders"
    assert message =~ "must return"
  end
end
