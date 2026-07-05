# Task 14: the dev picker — select an element, copy a perfect prompt

## Goal

Fractal is a new web framework written in Elixir that is AI-first.

In practice that means at least the following:

- It provides primitives for building web-pages in a way that AI agents can
easily consume and extend.

- It focuses on the developer experience using AI to build the web application.
Developers can dive in and write code, but the fundamental pattern is to prompt
the AI.

- It has built-in verification checks to ensure that the code AI produces is
correct.

- It has built-in documentation that the AI uses when a developer prompts it to
create a new page or feature.

This task makes the prompt-first pillar literal: in development, the
browser helps you *produce the prompt*. Select an element devtools-style,
type what you want changed, and get a fully-contextualized prompt on the
clipboard — element, source files, route, instruction — ready to paste
into whatever agent is open in your terminal.

## Framing: the browser knows "this", the terminal knows the agent

Today's loop has a deixis gap: you see the element in the browser, but
you describe it to the agent in English, and the agent greps to find it.
Fractal can close that gap almost for free, because of two decisions
already made:

- **The framework stamps provenance into the DOM.** Every page renders
  inside `<main data-page="...">`, every component inside
  `data-component="..."`, the layout chrome inside `data-layout`. A
  picker walks up from the clicked element and knows the module.
- **One file per page makes file-grained provenance sufficient.** "This
  element is in `lib/pioneer/pages/pricing.ex`, here's its outerHTML"
  is everything an agent needs — the file is small, self-contained, and
  the markup is `tag(...)` calls that mirror the HTML. No source maps,
  no line numbers.

Delivery is **clipboard, deliberately**. Alternatives were weighed (a
staged-selection `mix fractal.selection` pull model; headless agent
dispatch with streamed output) and deferred: the pull model relies on
the agent *remembering* a convention from AGENTS.md — fallible under
context pressure — while the clipboard puts the context physically
inside the user's own turn, immune to context-window amnesia, working
identically with every agent. Start with the strongest guarantee and
the least machinery; see what it feels like.

## Scope

### Dev-only source annotations (data, not markup)

In dev mode only, the document contributes provenance as data:

- `<meta name="fractal-source" content="lib/pioneer/pages/pricing.ex">`
  — the rendered page's source, derived from the module's compile info,
  trimmed to a cwd-relative path.
- Component wrappers gain `data-source="lib/pioneer/components/plan_card.ex"`.
- The layout wrapper gains `data-source` likewise.

Zero app code, zero config — the framework owns render, so every
existing app gets this on upgrade. In prod builds none of it appears.

### The picker and panel

A small dev-bar runtime, injected like the live-reload script (dev
only), hand-written JS like the fx runtime — no deps, no node:

- A floating affordance (and a keyboard shortcut) toggles **pick
  mode**: hovering outlines elements devtools-style; clicking selects.
- A panel opens with a textarea for the instruction and a live preview
  of the **composed prompt**:
  - the selected element's outerHTML (trimmed if huge),
  - the scope chain: page module + source file, enclosing component(s)
    + source files, layout if inside the chrome,
  - the current path,
  - the user's instruction,
  - a one-line footer: run `mix fractal.verify` when done.
- **Copy** puts the composed prompt on the clipboard (localhost is a
  secure context, so the Clipboard API works). The preview is editable
  — the user sees and can shape exactly what the agent will receive,
  and learns what good context looks like.
- The dev bar's own DOM is invisible to the picker and carries inline/
  self-scoped styles so nothing leaks into the app's stylesheet or
  trips verification scans.

### Purely client-side

No new server endpoint. The feature is annotations + injected script;
the security surface added is zero (nothing to POST, nothing that
executes). This is the decisive advantage of clipboard-first.

### Docs and dogfood

- The generated README's quickstart mentions it ("select an element in
  dev, copy a ready-made prompt"); the generated AGENTS.md needs no
  change — the prompt arrives in the agent's turn by construction.
- A short section in the building_pages (or interactivity) guide for
  humans; agents don't need teaching for this one.
- Works in `examples/blog` automatically — demo it live there.

### Non-goals (recorded so future-us knows they were weighed)

- No staged-selection endpoint or `mix fractal.selection` pull model —
  deferred, not rejected; revisit if clipboard friction proves real.
- No agent dispatch (`:agent_command`, headless spawns, output
  streaming), no chat UI, no prompt history, no LLM client, no API
  keys. The conversation lives in the user's agent.
- No line-level source maps (`tag/3` stays a function; the page file is
  provenance enough).
- No terminal-injection adapters (tmux etc.).

## Constraints

- Dev-gated exactly like the component gallery and live reload; tests
  assert the annotations and the dev-bar script are absent from prod
  documents and present in dev.
- The picker must not interfere with the fx runtime (pick mode must not
  fire `data-fx-*` handlers while selecting) or with watch fragments
  (annotations live on scope wrappers that fragments preserve).
- Framework suite stays DB-less; the dev bar is testable through
  `Fractal.Document` output and real-HTTP server tests.
- No new deps.

## Files expected to change

Modified: `lib/fractal/document.ex` (dev meta + dev-bar injection),
`lib/fractal/component.ex` (dev `data-source` on wrappers),
`lib/fractal/layout.ex` or the document's chrome wrapper (layout
`data-source`), a new `lib/fractal/dev_bar.ex` (the script + prompt
composition), tests mirroring each, one guide section, the installer's
README template. No installer structure changes, no migration for
existing apps.

## Plan first

Before changing anything, map the full plan and list the files you'll
touch. Wait for my go-ahead, then execute in one pass.

## Definition of done

- [x] In dev, pick mode outlines and selects any element; the panel
  composes a prompt containing the element's HTML, the page/component/
  layout source paths, the route, and the typed instruction; Copy puts
  it on the clipboard — demonstrated live in `examples/blog`.
- [x] Pasting the composed prompt into a fresh agent session is enough
  for it to locate and edit the right code with no additional
  searching context (demonstrated: prompt names the exact files).
- [x] Prod documents contain no annotations and no dev-bar script;
  dev documents contain both — asserted by tests.
- [x] Pick mode does not trigger fx events; the dev bar's own DOM is
  unselectable and style-isolated.
- [x] Framework suite and blog suite + verify stay green; guide and
  README template updated.
