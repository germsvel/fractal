defmodule Fractal.Interactive do
  @moduledoc """
  Fractal's interactivity primitives: declarative events over HTTP.

  Interactivity works without the developer (or the agent) writing any
  JavaScript. Elements declare an event with `fx/2` or `trigger/3`; a
  small runtime the document injects posts the event to the server; the
  page's `handle_event/2` returns an HTML fragment; the runtime swaps it
  into the target element. Request in, HTML out — the same mental model
  as the rest of the framework.

      defmodule MyApp.Pages.Counter do
        use Fractal.Page, path: "/counter", title: "Counter", events: ["increment"]

        @impl Fractal.Page
        def render(_assigns), do: counter(0)

        @impl Fractal.Page
        def handle_event("increment", assigns) do
          count = String.to_integer(assigns.params["count"] || "0") + 1
          {:fragment, counter(count)}
        end

        defp counter(count) do
          tag(:div, [id: "counter"], [
            tag(:p, [], ["Count: ", to_string(count)]),
            trigger("Increment", "increment", target: "#counter", values: %{count: count})
          ])
        end
      end

  State travels with the event — in `values:`, in the triggering
  element's own value, or in the database — so the server stays
  stateless. The fragment should re-render the whole target region
  (which is why the region carries an `id` and the trigger points at
  it).

  Page-level keyboard shortcuts are declarative browser actions too:
  declare `keys: ["/": {:focus, "#search"}, "r": {:event, "refresh"}]`
  beside `events:`. Supported local actions are focus, navigate, show,
  hide, and toggle; `{:event, name}` uses this same HTTP path. Targets
  are id selectors, and shortcuts never fire while a user is editing a
  form field. They are accelerators, never the only accessible control.

  The reverse direction — the server pushing to the browser — is the
  page-level `watch:` declaration plus `publish/1` (both documented in
  `Fractal.Page` and the push guide). The same runtime handles both.

  ## Trigger sources

    * `on: :click` (default) — buttons, links
    * `on: :input` — text inputs; debounced 300ms (live search)
    * `on: :change` — selects, checkboxes
    * `on: :submit` — a `<form>`; all its fields are sent as params
    * `on: :drop` — a drop target; the dragged card id is sent as `"card_id"`

  Inputs send their `name` (or `"value"` when unnamed) along with the
  event automatically.
  """

  import Fractal.HTML

  @doc """
  Returns the attributes that make any element trigger a page event.

      tag(:input, [type: "text", name: "q"] ++ fx("search", target: "#results", on: :input))

  ## Options

    * `:target` (required) — CSS selector of the element the returned
      fragment replaces
    * `:on` — `:click` (default), `:input`, `:change`, `:submit`, or `:drop`
    * `:values` — a map of extra params to send with the event
  """
  @spec fx(String.t(), keyword()) :: keyword()
  def fx(event, opts \\ []) when is_binary(event) do
    target =
      Keyword.get(opts, :target) ||
        raise ArgumentError,
              "fx/2 requires a :target — the CSS selector the returned fragment replaces"

    on = Keyword.get(opts, :on, :click)

    unless on in [:click, :input, :change, :submit, :drop] do
      raise ArgumentError, "fx/2 :on must be :click, :input, :change, :submit, or :drop"
    end

    [
      "data-fx-event": event,
      "data-fx-on": to_string(on),
      "data-fx-target": target,
      "data-fx-values": encode_values(Keyword.get(opts, :values, %{}))
    ]
  end

  @doc """
  A button that triggers a page event.

      trigger("Increment", "increment", target: "#counter", values: %{count: count})

  Takes the same options as `fx/2`; any other option becomes an
  attribute on the `<button>`.
  """
  @spec trigger(String.t(), String.t(), keyword()) :: Fractal.HTML.Safe.t()
  def trigger(label, event, opts \\ []) do
    {fx_opts, button_attrs} = Keyword.split(opts, [:target, :on, :values])

    tag(:button, [type: "button"] ++ fx(event, fx_opts) ++ button_attrs, [label])
  end

  @doc """
  Marks an element as a draggable card for a `fx(..., on: :drop)` target.

      tag(:li, [class: "card"] ++ drag_card(card.id), [...])

  The built-in runtime carries the card id to the drop target's event; no
  page JavaScript is needed.
  """
  @spec drag_card(String.t()) :: keyword()
  def drag_card(card_id) when is_binary(card_id) and card_id != "" do
    [draggable: true, "data-fx-drag-card": card_id]
  end

  @doc """
  Rings the doorbell for a watch topic: every browser on a page watching
  `topic` re-runs that page's `handle_watch/2` and receives the fresh
  fragment.

      publish("rooms/\#{message.room_id}/messages")

  The topic must be concrete (no `:name` segments left) and carries no
  payload — subscribers re-render from the database, so a missed publish
  costs nothing and the pub/sub backend stays swappable. Callable from
  page handlers (imported by `use Fractal.Page`) or any other code.
  Returns `:ok`.
  """
  @spec publish(String.t()) :: :ok
  def publish(topic) do
    unless Fractal.Bus.concrete_topic?(topic) do
      raise ArgumentError,
            "publish/1 needs a concrete, path-shaped topic like \"rooms/42/messages\" " <>
              "(no leading slash, no :name segments), got: #{inspect(topic)}"
    end

    Fractal.Bus.broadcast(topic)
  end

  @doc false
  def runtime_js do
    """
    <script>
    (function () {
      function fireEvent(event, target, extra) {
        var body = new URLSearchParams();
        body.set("_fx_path", window.location.pathname);
        body.set("_fx_event", event);
        var csrf = document.querySelector('meta[name="fractal-csrf-token"]');
        if (csrf) body.set("_csrf_token", csrf.getAttribute("content"));
        if (target) {
          var values = target.getAttribute("data-fx-values");
          if (values) {
            var parsed = JSON.parse(values);
            for (var key in parsed) body.set(key, parsed[key]);
          }
        }
        if (extra) {
          for (var extraKey in extra) body.set(extraKey, extra[extraKey]);
        }
        if (target && target.tagName === "FORM") {
          new FormData(target).forEach(function (value, key) { body.set(key, value); });
        } else if (target && (target.tagName === "INPUT" || target.tagName === "SELECT" || target.tagName === "TEXTAREA")) {
          body.set(target.getAttribute("name") || "value", target.value);
        }
        fetch("/fractal/event", {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded" },
          body: body.toString()
        }).then(function (resp) {
          var redirect = resp.headers.get("fx-redirect");
          if (redirect) { window.location.href = redirect; return; }
          return resp.text().then(function (html) {
            var replacement = document.querySelector(target && target.getAttribute("data-fx-target"));
            if (!replacement) {
              var tpl = document.createElement("template");
              tpl.innerHTML = html;
              var root = tpl.content.firstElementChild;
              replacement = root && root.id && document.getElementById(root.id);
            }
            if (replacement && resp.ok) replacement.outerHTML = html;
          });
        }).catch(function () {});
      }

      function fire(el, extra) { return fireEvent(el.getAttribute("data-fx-event"), el, extra); }

      function editable(el) {
        return el && el.closest("input, textarea, select, [contenteditable]");
      }

      function keyMatches(binding, e) {
        var parts = binding.split("+");
        var key = parts.pop();
        var mod = parts.indexOf("Mod") >= 0;
        var mac = /Mac|iPhone|iPad/.test(navigator.platform);
        return e.key === key && e.ctrlKey === (parts.indexOf("Ctrl") >= 0 || (mod && !mac)) &&
          e.metaKey === (mod && mac) && e.altKey === (parts.indexOf("Alt") >= 0) &&
          e.shiftKey === (parts.indexOf("Shift") >= 0);
      }

      document.addEventListener("keydown", function (e) {
        if (editable(e.target)) return;
        var main = document.querySelector("main[data-fx-keys]");
        if (!main) return;
        var bindings = JSON.parse(main.getAttribute("data-fx-keys"));
        for (var key in bindings) if (keyMatches(key, e)) {
          var action = bindings[key];
          e.preventDefault();
          if (action.type === "event") fireEvent(action.value);
          else if (action.type === "navigate") window.location.href = action.value;
          else {
            var target = document.getElementById(action.value.slice(1));
            if (!target) return;
            if (action.type === "focus") target.focus();
            if (action.type === "show") target.hidden = false;
            if (action.type === "hide") target.hidden = true;
            if (action.type === "toggle") target.hidden = !target.hidden;
          }
          return;
        }
      });

      function handler(kind, immediate) {
        return function (e) {
          var el = e.target.closest("[data-fx-event]");
          if (!el || el.getAttribute("data-fx-on") !== kind) return;
          if (kind === "click" || kind === "submit") e.preventDefault();
          if (immediate) { fire(el); return; }
          clearTimeout(el._fxTimer);
          el._fxTimer = setTimeout(function () { fire(el); }, 300);
        };
      }

      document.addEventListener("click", handler("click", true));
      document.addEventListener("change", handler("change", true));
      document.addEventListener("submit", handler("submit", true));
      document.addEventListener("input", handler("input", false));

      var draggedCard;
      document.addEventListener("dragstart", function (e) {
        var card = e.target.closest("[data-fx-drag-card]");
        if (!card) return;
        draggedCard = card.getAttribute("data-fx-drag-card");
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", draggedCard);
        card.classList.add("fx-dragging");
      });
      document.addEventListener("dragover", function (e) {
        var target = e.target.closest('[data-fx-event][data-fx-on="drop"]');
        if (!target || !draggedCard) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
      });
      document.addEventListener("drop", function (e) {
        var target = e.target.closest('[data-fx-event][data-fx-on="drop"]');
        if (!target) return;
        var cardId = draggedCard || e.dataTransfer.getData("text/plain");
        if (!cardId) return;
        e.preventDefault();
        fire(target, { card_id: cardId });
        draggedCard = null;
      });
      document.addEventListener("dragend", function (e) {
        var card = e.target.closest("[data-fx-drag-card]");
        if (card) card.classList.remove("fx-dragging");
        draggedCard = null;
      });

      // server push: pages that declare watch: carry data-fx-watch on
      // <main>; one EventSource per tab, fragments swap by root id, and
      // the browser's native reconnect re-runs the initial catch-up
      if (document.querySelector("main[data-fx-watch]") && window.EventSource) {
        var source = new EventSource(
          "/fractal/watch?_fx_path=" + encodeURIComponent(window.location.pathname)
        );
        source.onmessage = function (e) {
          var tpl = document.createElement("template");
          tpl.innerHTML = e.data;
          var next = tpl.content.firstElementChild;
          if (!next || !next.id) return;
          var current = document.getElementById(next.id);
          if (current) current.replaceWith(next);
        };
        source.addEventListener("fx-redirect", function (e) {
          source.close();
          window.location.href = e.data;
        });
      }
    })();
    </script>
    """
  end

  defp encode_values(values) when values == %{}, do: nil

  defp encode_values(values) when is_map(values) do
    values
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> JSON.encode!()
  end
end
