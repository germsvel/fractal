defmodule Fractal.VerifyTest do
  # DataCase: discovered pages include database-backed ones, which render
  # real queries during verification. Not async: the secret_key test
  # briefly mutates global config.
  use Fractal.DataCase

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

  defmodule BadStyle do
    use Fractal.Page, path: "/verify-bad-style"

    @impl Fractal.Page
    def style, do: "h1 { color: red;"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  defmodule InlineStylePage do
    use Fractal.Page, path: "/verify-inline-style"

    @impl Fractal.Page
    def render(_assigns), do: raw("<style>h1 { color: red; }</style>")
  end

  defmodule CdnPage do
    use Fractal.Page, path: "/verify-cdn"

    @impl Fractal.Page
    def render(_assigns) do
      raw(~s(<script src="https://cdn.example.com/lib.js"></script>))
    end
  end

  defmodule ExternalLinkPage do
    use Fractal.Page, path: "/verify-external-link"

    @impl Fractal.Page
    def render(_assigns) do
      tag(:a, [href: "https://elixir-lang.org"], ["Elixir"])
    end
  end

  defmodule MissingAssetPage do
    use Fractal.Page, path: "/verify-missing-asset"

    @impl Fractal.Page
    def render(_assigns) do
      tag(:img, src: asset_path("no-such-file.png"), alt: "nope")
    end
  end

  # a page that builds its form by hand instead of with Fractal.Form
  defmodule RawFormPage do
    use Fractal.Page, path: "/verify-raw-form"

    @impl Fractal.Page
    def render(_assigns) do
      raw(~s(<form action="/x" method="post"><button>go</button></form>))
    end
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

  test "secret_key/0 passes with the configured secret and fails on weak or missing ones" do
    assert {"session secret is configured", :ok} = Verify.secret_key()

    original = Application.get_env(:fractal, :secret_key_base)
    on_exit(fn -> Application.put_env(:fractal, :secret_key_base, original) end)

    Application.put_env(:fractal, :secret_key_base, "too-short")
    assert {_name, {:error, message}} = Verify.secret_key()
    assert message =~ "at least 64 bytes"
    assert message =~ "mix fractal.gen.secret"

    Application.delete_env(:fractal, :secret_key_base)
    assert {_name, {:error, message}} = Verify.secret_key()
    assert message =~ "is not set"
  end

  defmodule GoodComponent do
    use Fractal.Component

    @impl Fractal.Component
    def render(assigns), do: tag(:p, [], [assigns.text])

    @impl Fractal.Component
    def example, do: %{text: "hello"}
  end

  defmodule BrokenExampleComponent do
    use Fractal.Component

    @impl Fractal.Component
    def render(assigns), do: tag(:p, [], [assigns.missing_key])

    @impl Fractal.Component
    def example, do: %{}
  end

  defmodule BadStyleComponent do
    use Fractal.Component

    @impl Fractal.Component
    def render(_assigns), do: "x"

    @impl Fractal.Component
    def style, do: ".x { color: red;"

    @impl Fractal.Component
    def example, do: %{}
  end

  defmodule CdnComponent do
    use Fractal.Component

    @impl Fractal.Component
    def render(_assigns),
      do: raw(~s(<link href="https://cdn.example.com/x.css" rel="stylesheet">))

    @impl Fractal.Component
    def example, do: %{}
  end

  describe "run_components/1" do
    test "a well-formed component passes" do
      assert Verify.ok?(Verify.run_components([GoodComponent]))
      assert Verify.ok?(Verify.run_components([Fractal.Components.EmptyState]))
    end

    test "detects examples that fail to render" do
      errors = Verify.errors(Verify.run_components([BrokenExampleComponent]))

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name =~ "renders its example" and message =~ "raised"
             end)
    end

    test "detects unbalanced component styles" do
      errors = Verify.errors(Verify.run_components([BadStyleComponent]))

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name =~ "declares valid styles" and message =~ "unbalanced braces"
             end)
    end

    test "component renders go through the same scans as pages" do
      errors = Verify.errors(Verify.run_components([CdnComponent]))

      assert Enum.any?(errors, fn {_name, {:error, message}} ->
               message =~ "external script or stylesheet"
             end)
    end
  end

  test "unused_components/0 only reports components no page renders" do
    # EmptyState is rendered by the post show/edit pages
    refute inspect(Fractal.Components.EmptyState) in Verify.unused_components()
  end

  defmodule UndefinedGuardPage do
    use Fractal.Page, path: "/verify-undefined-guard", require: :no_such_guard

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  defmodule UnguardedAdminPage do
    use Fractal.Page, path: "/admin/verify-sneaky"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  describe "guards" do
    test "detects require: of an undefined guard, naming the fix" do
      results = Verify.run([UndefinedGuardPage])
      errors = Verify.errors(results)

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name =~ "requires defined guards" and message =~ ":no_such_guard" and
                 message =~ "guard :no_such_guard do"
             end)
    end

    test "expectations fail pages under a protected prefix that skip the guard" do
      results = Verify.run([UnguardedAdminPage])
      errors = Verify.errors(results)

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name == "guard expectations are honored" and
                 message =~ "UnguardedAdminPage" and
                 message =~ "require: :signed_in"
             end)
    end

    test "the guarded admin page honors the expectation" do
      results = Verify.run([Fractal.Pages.Admin])
      assert Verify.ok?(results), inspect(Verify.errors(results))
    end

    test "guards/0 smoke-runs every guard and the context with empty assigns" do
      results = Verify.guards()

      assert Verify.ok?(results), inspect(Verify.errors(results))

      assert Enum.any?(results, fn {name, _} ->
               name =~ "guard :signed_in tolerates an empty session"
             end)

      assert Enum.any?(results, fn {name, _} ->
               name =~ "context tolerates an empty session"
             end)
    end

    test "unused_guards/0 only reports guards nothing uses" do
      # :signed_in is required by the admin page and expected under /admin
      refute :signed_in in Verify.unused_guards()
    end
  end

  test "detects unbalanced braces in style/0" do
    results = Verify.run([BadStyle])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "declares valid styles" and message =~ "unbalanced braces"
           end)
  end

  test "detects rendered <style> tags" do
    results = Verify.run([InlineStylePage])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "renders" and message =~ "style/0" and message =~ "assets/app.css"
           end)
  end

  test "detects external script and stylesheet references" do
    results = Verify.run([CdnPage])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "renders" and message =~ "external script or stylesheet"
           end)

    # plain external <a> links are fine
    assert Verify.ok?(Verify.run([ExternalLinkPage]))
  end

  test "detects references to missing assets via the smoke render" do
    results = Verify.run([MissingAssetPage])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "renders" and message =~ "no-such-file.png"
           end)
  end

  test "stylesheet/0 checks assets/app.css" do
    assert {"app stylesheet is well-formed", :ok} = Verify.stylesheet()
  end

  test "orphaned_assets/0 only reports unreferenced files" do
    # logo.svg is referenced by the home page
    refute "logo.svg" in Verify.orphaned_assets()
  end

  test "detects a hand-rolled <form> without a CSRF token" do
    results = Verify.run([RawFormPage])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "renders" and message =~ "without a CSRF token" and
               message =~ "Fractal.Form"
           end)

    # forms built with Fractal.Form pass
    assert Verify.ok?(Verify.run([Fractal.Pages.Login]))
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
