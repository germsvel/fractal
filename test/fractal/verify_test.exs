defmodule Fractal.VerifyTest do
  # not async: the secret_key test briefly mutates global config, and the
  # tmp_dir tests change the working directory
  use ExUnit.Case

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

  test "pending_migrations/0 passes on a repo-less app — nothing to migrate" do
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
      assert Verify.ok?(Verify.run_components([Fractal.Fixtures.Note]))
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

  @tag :tmp_dir
  test "unused_components/0 only reports components no page renders", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      File.mkdir_p!("lib/fractal/pages")

      # no page source renders Note
      assert inspect(Fractal.Fixtures.Note) in Verify.unused_components()

      File.write!("lib/fractal/pages/home.ex", ~s{component(Note, title: "t", body: "b")})
      refute inspect(Fractal.Fixtures.Note) in Verify.unused_components()
    end)
  end

  defmodule UndefinedGuardPage do
    use Fractal.Page, path: "/verify-undefined-guard", require: :no_such_guard

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  defmodule UnguardedAdminPage do
    use Fractal.Page, path: "/fixtures/admin/verify-sneaky"

    @impl Fractal.Page
    def render(_assigns), do: "x"
  end

  defmodule MisshapenMetaPage do
    use Fractal.Page, path: "/verify-misshapen-meta"

    @impl Fractal.Page
    def meta(_assigns), do: [:not, :a, :map]

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule UnknownMetaKeyPage do
    use Fractal.Page, path: "/verify-unknown-meta"

    @impl Fractal.Page
    def meta(_assigns), do: %{descripton: "a typo"}

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule CrashingMetaPage do
    use Fractal.Page, path: "/verify-crashing-meta"

    @impl Fractal.Page
    def meta(_assigns), do: raise("meta boom")

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule MissingOgImagePage do
    use Fractal.Page, path: "/verify-missing-og-image"

    @impl Fractal.Page
    def meta(_assigns), do: %{og: %{image: asset_path("no-such-cover.png")}}

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule HandlerAttrMetaPage do
    use Fractal.Page, path: "/verify-handler-meta"

    @impl Fractal.Page
    def meta(_assigns), do: %{extra: [{:meta, [name: "x", onload: "evil()"]}]}

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule ScriptExtraMetaPage do
    use Fractal.Page, path: "/verify-script-meta"

    @impl Fractal.Page
    def meta(_assigns), do: %{extra: [{:script, [src: "/x.js"]}]}

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule ExternalStylesheetMetaPage do
    use Fractal.Page, path: "/verify-external-stylesheet-meta"

    @impl Fractal.Page
    def meta(_assigns) do
      %{extra: [{:link, [rel: "stylesheet", href: "https://cdn.example.com/x.css"]}]}
    end

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule LongDescriptionPage do
    use Fractal.Page, path: "/verify-long-description"

    @impl Fractal.Page
    def meta(_assigns), do: %{description: String.duplicate("wordy ", 40)}

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["x"])
  end

  defmodule CanonicalLinkPage do
    use Fractal.Page, path: "/verify-canonical-link"

    @impl Fractal.Page
    def render(_assigns) do
      raw(~s(<h1>x</h1><link rel="canonical" href="https://example.com/here">))
    end
  end

  defmodule LongTitlePage do
    use Fractal.Page,
      path: "/verify-long-title",
      title: "An exceedingly long and thoroughly search-result-unfriendly page title"

    @impl Fractal.Page
    def render(_assigns), do: tag(:h1, [], ["hi"])
  end

  defmodule NoH1Page do
    use Fractal.Page, path: "/verify-no-h1"

    @impl Fractal.Page
    def render(_assigns), do: tag(:p, [], ["headless"])
  end

  describe "invariants" do
    test "the app's discovered pages satisfy the invariants" do
      results = Verify.run_invariants()
      assert Verify.ok?(results), inspect(Verify.errors(results))
    end

    test "a violating page fails with the invariant's message, per invariant" do
      errors = Verify.errors(Verify.run_invariants([LongTitlePage]))

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name =~ "satisfies invariant 'title fits in a search result'" and
                 message =~ "keep it under 60"
             end)

      errors = Verify.errors(Verify.run_invariants([NoH1Page]))

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name =~ "exactly one h1" and message =~ "renders 0 h1"
             end)
    end

    test "a page that cannot render fails invariants with a pointer, not a crash" do
      errors = Verify.errors(Verify.run_invariants([RaisingRender]))

      assert errors != []

      assert Enum.all?(errors, fn {_name, {:error, message}} ->
               message =~ "does not render"
             end)
    end

    test "invariants/0 is ok with the single app module" do
      assert {"invariants are well-formed", :ok} = Verify.invariants()
    end
  end

  describe "test coverage" do
    test "every discovered page and component is referenced by a test" do
      results = Verify.test_coverage()
      assert Verify.ok?(results), inspect(Verify.errors(results))
    end

    test "a module no test references fails, naming the expected path" do
      assert [{name, {:error, message}}] = Verify.errors(Verify.test_coverage([GoodPage]))

      assert name =~ "has tests"
      assert message =~ "no test file references"
      assert message =~ "test/fractal/pages/good_page_test.exs"
    end

    @tag :tmp_dir
    test "commented-out tests don't count as coverage", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.mkdir_p!("test/fractal/pages")

        # the module name appears, but only in comments — same as no test
        File.write!("test/fractal/pages/good_page_test.exs", """
        # defmodule Fractal.VerifyTest.GoodPageTest do
        #   use ExUnit.Case
        #
        #   test "renders" do
        #     assert Fractal.VerifyTest.GoodPage.path() == "/verify-good"
        #   end
        # end
        """)

        assert [{_name, {:error, message}}] = Verify.errors(Verify.test_coverage([GoodPage]))
        assert message =~ "no test file references"

        # uncommented, the same content counts
        File.write!("test/fractal/pages/good_page_test.exs", """
        defmodule Fractal.VerifyTest.GoodPageTest do
          use ExUnit.Case

          test "renders" do
            assert Fractal.VerifyTest.GoodPage.path() == "/verify-good"
          end
        end
        """)

        assert Verify.ok?(Verify.test_coverage([GoodPage]))
      end)
    end

    @tag :tmp_dir
    test "multi-alias references count as coverage", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.mkdir_p!("test/fractal/pages")

        File.write!("test/fractal/pages/grouped_test.exs", """
        defmodule Fractal.VerifyTest.GroupedTest do
          use ExUnit.Case

          alias Fractal.VerifyTest.{DuplicateA, GoodPage}

          test "uses them", do: assert(GoodPage.path() != DuplicateA.path())
        end
        """)

        assert Verify.ok?(Verify.test_coverage([GoodPage, DuplicateA]))
      end)
    end
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
                 message =~ "require: :fixture_signed_in"
             end)
    end

    test "the guarded fixture page honors the expectation" do
      results = Verify.run([Fractal.Fixtures.GuardedPage])
      assert Verify.ok?(results), inspect(Verify.errors(results))
    end

    test "guards/0 smoke-runs every guard and the context with empty assigns" do
      results = Verify.checkpoint()

      assert Verify.ok?(results), inspect(Verify.errors(results))

      assert Enum.any?(results, fn {name, _} ->
               name =~ "guard :fixture_signed_in tolerates an empty session"
             end)

      assert Enum.any?(results, fn {name, _} ->
               name =~ "context tolerates an empty session"
             end)
    end

    test "unused_guards/0 only reports guards nothing uses" do
      # :fixture_signed_in is required by the guarded fixture page and
      # expected under /fixtures/admin
      refute :fixture_signed_in in Verify.unused_guards()
    end
  end

  describe "meta" do
    test "a well-formed meta/1 passes" do
      assert Verify.ok?(Verify.run([Fractal.Fixtures.MetaPage]))
    end

    test "misshapen, unknown-key, and crashing meta/1 fail, naming the page" do
      assert [{name, {:error, message}}] = Verify.errors(Verify.run([MisshapenMetaPage]))
      assert name =~ "declares valid meta"
      assert message =~ "must return a map"

      assert [{_name, {:error, message}}] = Verify.errors(Verify.run([UnknownMetaKeyPage]))
      assert message =~ ":descripton"
      assert message =~ "allowed:"

      assert [{_name, {:error, message}}] = Verify.errors(Verify.run([CrashingMetaPage]))
      assert message =~ "meta/1 raised"
      assert message =~ "meta boom"
    end

    test "a missing og image asset fails via the smoke-run" do
      assert [{_name, {:error, message}}] = Verify.errors(Verify.run([MissingOgImagePage]))
      assert message =~ "no-such-cover.png"
    end

    test "script-shaped generic entries are rejected" do
      assert [{_name, {:error, message}}] = Verify.errors(Verify.run([HandlerAttrMetaPage]))
      assert message =~ "event-handler"

      assert [{_name, {:error, message}}] = Verify.errors(Verify.run([ScriptExtraMetaPage]))
      assert message =~ "{:meta, attrs} or {:link, attrs}"

      assert [{_name, {:error, message}}] =
               Verify.errors(Verify.run([ExternalStylesheetMetaPage]))

      assert message =~ "reference rel"
    end

    test "external canonical links pass the refined origin rule; resources still fail" do
      assert Verify.ok?(Verify.run([CanonicalLinkPage]))

      # external script and stylesheet loading still fail (existing fixtures)
      refute Verify.ok?(Verify.run([CdnPage]))
    end

    test "the description invariant catches over-long descriptions" do
      errors = Verify.errors(Verify.run_invariants([LongDescriptionPage]))

      assert Enum.any?(errors, fn {name, {:error, message}} ->
               name =~ "search snippet" and message =~ "keep it under 160"
             end)
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

  @tag :tmp_dir
  test "orphaned_assets/0 only reports unreferenced files", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      File.mkdir_p!("assets/static")
      File.mkdir_p!("lib/fractal/pages")
      File.write!("assets/static/used.svg", "<svg></svg>")
      File.write!("assets/static/orphan.svg", "<svg></svg>")
      File.write!("lib/fractal/pages/home.ex", ~s{asset_path("used.svg")})

      assert Verify.orphaned_assets() == ["orphan.svg"]
    end)
  end

  test "detects a hand-rolled <form> without a CSRF token" do
    results = Verify.run([RawFormPage])
    errors = Verify.errors(results)

    assert Enum.any?(errors, fn {name, {:error, message}} ->
             name =~ "renders" and message =~ "without a CSRF token" and
               message =~ "Fractal.Form"
           end)

    # forms built with Fractal.Form pass
    assert Verify.ok?(Verify.run([Fractal.Fixtures.FormPage]))
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
