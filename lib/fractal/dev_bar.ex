defmodule Fractal.DevBar do
  @moduledoc """
  The development bar: select an element, copy a perfect prompt.

  In development, `Fractal.Document` injects a small picker UI. Toggle
  pick mode, hover to outline elements devtools-style, click one, type
  what you want changed — the panel composes a prompt carrying the
  element's HTML, the page/component/layout source files (from the
  dev-only provenance annotations), the current path, and your
  instruction. Copy it and paste it into whatever agent is open in your
  terminal; the built-in live reload shows the result when the agent is
  done.

  The whole feature is client-side — no server endpoint, no agent
  integration, no configuration. It exists because the browser is the
  one place that knows exactly which element you mean, and one file per
  page means naming the file *is* naming the code.

  None of this ships to production: the annotations and the script are
  emitted only in dev (the same gate as live reload and the component
  gallery).
  """

  @doc "Whether dev-only affordances (annotations, the bar) are active."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:fractal, :live_reload, false)

  @doc """
  The module's source file, relative to the project root — or `nil`
  when it cannot be determined.
  """
  @spec source_path(module()) :: String.t() | nil
  def source_path(module) do
    with true <- Code.ensure_loaded?(module),
         source when is_list(source) <- module.module_info(:compile)[:source] do
      source |> List.to_string() |> Path.relative_to(File.cwd!())
    else
      _no_source -> nil
    end
  rescue
    _exception -> nil
  end

  # All DOM is built and styled from JS (no <style> tags, no stylesheet
  # contribution), and everything lives under #fractal-dev-bar, which
  # the picker itself ignores. Pick-mode listeners run in the capture
  # phase and stop propagation, so selecting an element can never fire
  # the page's own data-fx-* handlers.
  @doc false
  def script do
    """
    <script>
    (function () {
      var picking = false;
      var BAR = "fractal-dev-bar";

      var bar = document.createElement("div");
      bar.id = BAR;
      bar.style.cssText =
        "position:fixed;bottom:1rem;right:1rem;z-index:2147483646;" +
        "font-family:ui-sans-serif,system-ui,sans-serif;font-size:14px;";

      var button = document.createElement("button");
      button.type = "button";
      button.textContent = "\\u2316 select element";
      button.title = "Select an element and compose an agent prompt (Esc to cancel)";
      button.style.cssText =
        "padding:0.4rem 0.8rem;border-radius:999px;border:1px solid rgba(124,196,255,0.6);" +
        "background:#0b1021;color:#7cc4ff;cursor:pointer;font:inherit;box-shadow:0 2px 8px rgba(0,0,0,0.4);";
      bar.appendChild(button);

      var overlay = document.createElement("div");
      overlay.style.cssText =
        "position:fixed;z-index:2147483645;pointer-events:none;display:none;" +
        "border:2px solid #7cc4ff;background:rgba(124,196,255,0.15);border-radius:2px;";
      bar.appendChild(overlay);

      var panel = null;

      function pascal(slug) {
        return slug.split("-").map(function (part) {
          return part.charAt(0).toUpperCase() + part.slice(1);
        }).join("");
      }

      function describe(el) {
        var parts = [];
        var pageMeta = document.querySelector('meta[name="fractal-source"]');
        var main = el.closest("main[data-page]");
        var layout = el.closest("[data-layout]");

        if (main && pageMeta) {
          parts.push("In " + pageMeta.getAttribute("content") +
            " (the page at " + window.location.pathname + ")");
        } else if (layout) {
          var layoutSource = layout.getAttribute("data-source");
          parts.push("In the app layout's chrome" +
            (layoutSource ? " (" + layoutSource + ")" : ""));
        } else {
          parts.push("On the page at " + window.location.pathname);
        }

        var node = el.closest("[data-component]");
        while (node) {
          var source = node.getAttribute("data-source");
          parts.push("inside the " + pascal(node.getAttribute("data-component")) +
            " component" + (source ? " (" + source + ")" : ""));
          node = node.parentElement && node.parentElement.closest("[data-component]");
        }

        return parts.join(", ");
      }

      function trimmedHtml(el) {
        var html = el.outerHTML;
        if (html.length > 4000) {
          html = html.slice(0, 4000) + "\\n<!-- truncated -->";
        }
        return html;
      }

      function composePrompt(context, html, instruction) {
        return context + ", this element:\\n\\n" +
          "```html\\n" + html + "\\n```\\n\\n" +
          (instruction || "(describe the change here)") + "\\n\\n" +
          "Run `mix fractal.verify` when the change is done.";
      }

      function openPanel(el) {
        closePanel();
        var context = describe(el);
        var html = trimmedHtml(el);

        panel = document.createElement("div");
        panel.style.cssText =
          "position:fixed;bottom:3.5rem;right:1rem;z-index:2147483646;width:26rem;" +
          "max-width:calc(100vw - 2rem);padding:0.75rem;border-radius:0.5rem;" +
          "background:#0b1021;color:#e6e9f2;border:1px solid rgba(124,196,255,0.4);" +
          "box-shadow:0 6px 24px rgba(0,0,0,0.5);display:flex;flex-direction:column;gap:0.5rem;";

        var instruction = document.createElement("textarea");
        instruction.rows = 2;
        instruction.placeholder = "What should change about this element?";
        instruction.style.cssText = fieldStyle();

        var preview = document.createElement("textarea");
        preview.rows = 12;
        preview.style.cssText = fieldStyle() + "font-family:ui-monospace,monospace;font-size:12px;";
        preview.value = composePrompt(context, html, "");

        instruction.addEventListener("input", function () {
          preview.value = composePrompt(context, html, instruction.value.trim());
        });

        var row = document.createElement("div");
        row.style.cssText = "display:flex;gap:0.5rem;justify-content:flex-end;";

        var copy = document.createElement("button");
        copy.type = "button";
        copy.textContent = "Copy prompt";
        copy.style.cssText = buttonStyle("#7cc4ff", "#0b1021");
        copy.addEventListener("click", function () {
          var done = function () {
            copy.textContent = "Copied — paste it into your agent";
            setTimeout(function () { copy.textContent = "Copy prompt"; }, 2000);
          };
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(preview.value).then(done);
          } else {
            preview.select();
            document.execCommand("copy");
            done();
          }
        });

        var close = document.createElement("button");
        close.type = "button";
        close.textContent = "Close";
        close.style.cssText = buttonStyle("rgba(255,255,255,0.12)", "#e6e9f2");
        close.addEventListener("click", closePanel);

        row.appendChild(close);
        row.appendChild(copy);
        panel.appendChild(instruction);
        panel.appendChild(preview);
        panel.appendChild(row);
        bar.appendChild(panel);
        instruction.focus();
      }

      function fieldStyle() {
        return "width:100%;box-sizing:border-box;padding:0.4rem 0.5rem;border-radius:0.35rem;" +
          "border:1px solid rgba(255,255,255,0.2);background:rgba(255,255,255,0.06);" +
          "color:#e6e9f2;font:inherit;resize:vertical;";
      }

      function buttonStyle(bg, fg) {
        return "padding:0.35rem 0.9rem;border-radius:0.35rem;border:none;cursor:pointer;" +
          "font:inherit;font-weight:600;background:" + bg + ";color:" + fg + ";";
      }

      function closePanel() {
        if (panel) { panel.remove(); panel = null; }
      }

      function startPicking() {
        picking = true;
        closePanel();
        button.textContent = "\\u2715 cancel";
        document.addEventListener("mousemove", onMove, true);
        document.addEventListener("click", onPick, true);
      }

      function stopPicking() {
        picking = false;
        button.textContent = "\\u2316 select element";
        overlay.style.display = "none";
        document.removeEventListener("mousemove", onMove, true);
        document.removeEventListener("click", onPick, true);
      }

      function onMove(e) {
        var target = e.target;
        if (!target || target.closest("#" + BAR)) {
          overlay.style.display = "none";
          return;
        }
        var rect = target.getBoundingClientRect();
        overlay.style.display = "block";
        overlay.style.left = rect.left - 2 + "px";
        overlay.style.top = rect.top - 2 + "px";
        overlay.style.width = rect.width + "px";
        overlay.style.height = rect.height + "px";
      }

      // capture phase + stopPropagation: the page's fx runtime (and the
      // page itself) never sees a pick-mode click
      function onPick(e) {
        var target = e.target;
        if (target && target.closest("#" + BAR)) return;
        e.preventDefault();
        e.stopPropagation();
        stopPicking();
        if (target) openPanel(target);
      }

      button.addEventListener("click", function () {
        if (picking) { stopPicking(); } else { startPicking(); }
      });

      document.addEventListener("keydown", function (e) {
        if (e.key !== "Escape") return;
        if (picking) stopPicking();
        else closePanel();
      });

      document.body.appendChild(bar);
    })();
    </script>
    """
  end
end
