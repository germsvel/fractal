defmodule Fractal.Fixtures do
  @moduledoc false

  # Framework test fixtures: a minimal, DB-less page set covering each
  # capability, so framework tests don't depend on the sample app's
  # content. Compiled in the test env only (test/support), which makes
  # them discoverable like any host page.

  defmodule StaticPage do
    @moduledoc false
    use Fractal.Page, path: "/fixtures", title: "Fixtures"

    @impl Fractal.Page
    def render(_assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Fixtures"]),
        tag(:p, [], ["The framework's own test pages."])
      ])
    end

    @impl Fractal.Page
    def style do
      """
      h1 { letter-spacing: 0.02em; }
      """
    end
  end

  defmodule ShowPage do
    @moduledoc false
    use Fractal.Page, path: "/fixtures/:id", title: "Fixture"

    @impl Fractal.Page
    def render(assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Fixture ", to_string(assigns.params["id"])])
      ])
    end
  end

  defmodule FormPage do
    @moduledoc false
    use Fractal.Page, path: "/fixtures/new", title: "New fixture", post: "/fixtures"

    import Fractal.Form

    @impl Fractal.Page
    def render(assigns) do
      tag(:section, [], [
        tag(:h1, [], ["New fixture"]),
        if(assigns[:error], do: tag(:p, [class: "error"], [assigns.error])),
        form_for(nil, "/fixtures", [
          input(nil, :name),
          submit("Create fixture")
        ])
      ])
    end

    @impl Fractal.Page
    def handle_post(assigns) do
      case String.trim(assigns.params["name"] || "") do
        "" -> {:render, %{error: "name is required"}}
        name -> {:redirect, "/fixtures/#{name}"}
      end
    end
  end

  defmodule EditPage do
    @moduledoc false
    use Fractal.Page,
      path: "/fixtures/:id/edit",
      title: "Edit fixture",
      put: "/fixtures/:id",
      delete: "/fixtures/:id"

    import Fractal.Form

    @impl Fractal.Page
    def render(assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Edit fixture"]),
        if(assigns[:msg], do: tag(:p, [id: "msg"], [assigns.msg])),
        form_for(nil, "/fixtures/#{assigns.params["id"]}", [method: :put], [
          input(nil, :name),
          submit("Save fixture")
        ]),
        button_to("Delete fixture", "/fixtures/#{assigns.params["id"]}", method: :delete)
      ])
    end

    @impl Fractal.Page
    def handle_put(assigns) do
      {:render, %{msg: "updated to #{assigns.params["name"]} (#{assigns.params["id"]})"}}
    end

    @impl Fractal.Page
    def handle_delete(assigns) do
      {:redirect, "/fixtures?deleted=#{assigns.params["id"]}"}
    end
  end

  defmodule EchoPage do
    @moduledoc false
    use Fractal.Page,
      path: "/fixtures/echo",
      title: "Echo",
      post: "/fixtures/echo",
      events: ["echo"]

    @impl Fractal.Page
    def render(assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Echo"]),
        if(assigns[:msg], do: tag(:p, [id: "echo"], [assigns.msg]))
      ])
    end

    @impl Fractal.Page
    def handle_post(assigns), do: {:render, %{msg: inspect(assigns.params)}}

    @impl Fractal.Page
    def handle_event("echo", assigns) do
      {:fragment, tag(:p, [id: "echo"], [inspect(assigns.params)])}
    end
  end

  defmodule MetaPage do
    @moduledoc false
    use Fractal.Page, path: "/fixtures/meta", title: "Meta"

    @impl Fractal.Page
    def meta(_assigns) do
      %{
        description: "A page about <b>fixtures</b>",
        canonical: "/fixtures/meta",
        robots: "noindex",
        og: %{title: "Meta fixture", type: "article", image: asset_path("logo.svg")},
        extra: [{:link, [rel: "alternate", type: "application/rss+xml", href: "/feed"]}]
      }
    end

    @impl Fractal.Page
    def render(_assigns) do
      tag(:section, [], [tag(:h1, [], ["Meta"])])
    end
  end

  defmodule EventPage do
    @moduledoc false
    use Fractal.Page, path: "/fixtures/ping", title: "Ping", events: ["ping", "reset"]

    @impl Fractal.Page
    def render(_assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Ping"]),
        region("0")
      ])
    end

    @impl Fractal.Page
    def handle_event("ping", assigns) do
      count = String.to_integer(assigns.params["n"] || "0") + 1
      {:fragment, region(to_string(count))}
    end

    def handle_event("reset", _assigns), do: {:redirect, "/fixtures/ping"}

    defp region(count) do
      tag(:div, [id: "ping-region"], [
        tag(:p, [], ["pong ", count]),
        trigger("Ping", "ping", target: "#ping-region", values: %{n: count})
      ])
    end
  end

  defmodule KeyPage do
    @moduledoc false
    use Fractal.Page,
      path: "/fixtures/keys",
      title: "Keys",
      events: ["ping"],
      keys: [
        j: {:event, "ping"},
        /: {:focus, "#key-search"},
        "?": {:toggle, "#key-help"},
        Escape: {:hide, "#key-help"},
        n: {:navigate, "/fixtures/new"}
      ]

    @impl Fractal.Page
    def render(_assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Keys"]),
        tag(:input, id: "key-search", type: "search"),
        tag(:aside, [id: "key-help", hidden: true], ["Keyboard help"]),
        tag(:div, [id: "key-result"], ["waiting"])
      ])
    end

    @impl Fractal.Page
    def handle_event("ping", _assigns), do: {:fragment, tag(:div, [id: "key-result"], ["pong"])}
  end

  defmodule WatchPage do
    @moduledoc false
    use Fractal.Page,
      path: "/fixtures/watch/:room",
      title: "Watch",
      events: ["tick"],
      watch: ["fixtures/rooms/:room/ticks", "fixtures/ticks"]

    @impl Fractal.Page
    def render(assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Watch"]),
        region(assigns.params["room"]),
        trigger("Tick", "tick", target: "#ticks")
      ])
    end

    @impl Fractal.Page
    def handle_event("tick", assigns) do
      publish("fixtures/rooms/#{assigns.params["room"]}/ticks")
      publish("fixtures/ticks")
      {:fragment, region(assigns.params["room"])}
    end

    @impl Fractal.Page
    def handle_watch("fixtures/rooms/:room/ticks", assigns) do
      {:fragment, region(assigns.params["room"])}
    end

    def handle_watch("fixtures/ticks", _assigns) do
      {:fragment, tag(:p, [id: "all-ticks"], ["something ticked somewhere"])}
    end

    defp region(room) do
      tag(:p, [id: "ticks"], ["tick in ", to_string(room)])
    end
  end

  defmodule GuardedPage do
    @moduledoc false
    use Fractal.Page,
      path: "/fixtures/admin",
      title: "Fixture admin",
      require: :fixture_signed_in,
      watch: ["fixtures/ticks"]

    @impl Fractal.Page
    def render(assigns) do
      tag(:section, [], [
        tag(:h1, [], ["Fixture admin"]),
        tag(:p, [], ["Hello, ", assigns.context["fixture_user"] || "stranger"]),
        tag(:p, [id: "admin-ticks"], ["no ticks observed"])
      ])
    end

    @impl Fractal.Page
    def handle_watch("fixtures/ticks", _assigns) do
      {:fragment, tag(:p, [id: "admin-ticks"], ["a tick was observed"])}
    end
  end

  defmodule Checkpoint do
    @moduledoc false
    use Fractal.Checkpoint

    def context(assigns) do
      %{"fixture_user" => assigns.session["fixture_user"]}
    end

    guard :fixture_signed_in, %{context: context} do
      if context["fixture_user"] do
        :ok
      else
        {:redirect, "/fixtures", flash: %{"error" => "Fixtures say: log in first."}}
      end
    end

    expect("/fixtures/admin", :fixture_signed_in)
  end

  defmodule Invariants do
    @moduledoc false
    use Fractal.Invariant

    invariant "title fits in a search result", %{page: page} do
      length = page.title() |> String.length()

      if length <= 60 do
        :ok
      else
        {:error, "title is #{length} chars — keep it under 60"}
      end
    end

    invariant "meta description fits a search snippet", %{meta: meta} do
      case meta[:description] do
        nil ->
          :ok

        description ->
          length = String.length(description)

          if length <= 160 do
            :ok
          else
            {:error, "meta description is #{length} chars — keep it under 160"}
          end
      end
    end

    invariant "every page renders exactly one h1", %{rendered: rendered} do
      case rendered |> String.split("<h1") |> length() |> Kernel.-(1) do
        1 -> :ok
        count -> {:error, "renders #{count} h1 elements — pages need exactly one"}
      end
    end
  end

  defmodule Layout do
    @moduledoc false
    use Fractal.Layout

    def site do
      %{
        name: "Fixture Site",
        lang: "en",
        favicon: asset_path("logo.svg"),
        theme_color: "#0b1021",
        description: "Fixture pages for framework tests."
      }
    end

    def chrome(assigns) do
      case assigns.session["fixture_user"] do
        name when is_binary(name) and name != "" ->
          tag(:div, [class: "session-bar"], ["Signed in as ", tag(:strong, [], [name])])

        _signed_out ->
          nil
      end
    end

    def style do
      """
      .session-bar { display: flex; justify-content: flex-end; }
      """
    end
  end

  defmodule Note do
    @moduledoc false
    use Fractal.Component

    @impl Fractal.Component
    def render(assigns) do
      tag(:aside, [class: "note"], [
        tag(:strong, [], [assigns.title]),
        tag(:p, [], [assigns.body])
      ])
    end

    @impl Fractal.Component
    def style do
      """
      .note { border-left: 3px solid var(--accent, #888); padding-left: 1rem; }
      """
    end

    @impl Fractal.Component
    def example do
      %{title: "Heads up", body: "Fixtures are the framework's own test pages."}
    end
  end
end
