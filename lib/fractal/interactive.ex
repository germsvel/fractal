defmodule Fractal.Interactive do
  @moduledoc """
  Fractal's interactivity primitives: declarative events over HTTP.

  Interactivity works without the developer (or the agent) writing any
  JavaScript. Elements declare an event with `fx/2` or `trigger/3`; a
  small runtime the layout injects posts the event to the server; the
  page's `handle_event/2` returns an HTML fragment; the runtime swaps it
  into the target element. Request in, HTML out — the same mental model
  as the rest of the framework.

      defmodule Fractal.Pages.Counter do
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

  ## Trigger sources

    * `on: :click` (default) — buttons, links
    * `on: :input` — text inputs; debounced 300ms (live search)
    * `on: :change` — selects, checkboxes
    * `on: :submit` — a `<form>`; all its fields are sent as params

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
    * `:on` — `:click` (default), `:input`, `:change`, or `:submit`
    * `:values` — a map of extra params to send with the event
  """
  @spec fx(String.t(), keyword()) :: keyword()
  def fx(event, opts \\ []) when is_binary(event) do
    target =
      Keyword.get(opts, :target) ||
        raise ArgumentError,
              "fx/2 requires a :target — the CSS selector the returned fragment replaces"

    on = Keyword.get(opts, :on, :click)

    unless on in [:click, :input, :change, :submit] do
      raise ArgumentError, "fx/2 :on must be :click, :input, :change, or :submit"
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

  @doc false
  def runtime_js do
    """
    <script>
    (function () {
      function fire(el) {
        var body = new URLSearchParams();
        body.set("_fx_path", window.location.pathname);
        body.set("_fx_event", el.getAttribute("data-fx-event"));
        var csrf = document.querySelector('meta[name="fractal-csrf-token"]');
        if (csrf) body.set("_csrf_token", csrf.getAttribute("content"));
        var values = el.getAttribute("data-fx-values");
        if (values) {
          var parsed = JSON.parse(values);
          for (var key in parsed) body.set(key, parsed[key]);
        }
        if (el.tagName === "FORM") {
          new FormData(el).forEach(function (value, key) { body.set(key, value); });
        } else if (el.tagName === "INPUT" || el.tagName === "SELECT" || el.tagName === "TEXTAREA") {
          body.set(el.getAttribute("name") || "value", el.value);
        }
        fetch("/fractal/event", {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded" },
          body: body.toString()
        }).then(function (resp) {
          var redirect = resp.headers.get("fx-redirect");
          if (redirect) { window.location.href = redirect; return; }
          return resp.text().then(function (html) {
            var target = document.querySelector(el.getAttribute("data-fx-target"));
            if (target && resp.ok) target.outerHTML = html;
          });
        }).catch(function () {});
      }

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
