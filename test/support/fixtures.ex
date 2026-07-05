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
end
