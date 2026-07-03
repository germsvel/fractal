# Task 7: reusable UI components

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

## Framing: components for coherence, not for effort

Humans need components to save effort — editing twenty copies of a card is
expensive. Agents don't have that problem; editing twenty copies is cheap.
What agents have instead:

- **A drift problem**: ask for twenty pages and you get twenty subtly
  different card markups and twenty `style/0` blocks re-styling buttons — a
  UI with no coherent visual language (this is the known tension recorded in
  task 6: page-scoped CSS fights reuse).
- **A discovery problem**: an agent can't know a Card already exists unless
  something tells it, so it reinvents one (Button, PrimaryButton,
  NewButton2).

So Fractal components are NOT a general abstraction mechanism. They are a
**design-system vocabulary with built-in discovery** — the shared visual
language, governed by the same machinery as everything else.

## Scope

### The shape: one file per component, mirroring pages at smaller scale

A `Fractal.Component` behaviour that is the page pattern minus routes:

```elixir
defmodule Fractal.Components.Card do
  use Fractal.Component

  @impl true
  def render(assigns) do
    tag(:div, [class: "card"], [
      tag(:h3, [], [assigns.title]),
      assigns.body
    ])
  end

  @impl true
  def style do
    """
    .card { background: var(--surface); border-radius: 0.5rem; padding: 1.25rem; }
    h3 { margin-top: 0; }
    """
  end

  @impl true
  def example do
    %{title: "Example card", body: tag(:p, [], ["Body content"])}
  end
end
```

Used from any page as `component(Card, title: "Stats", body: ...)`
(helper imported by `use Fractal.Page`). Components live in
`lib/fractal/components/` and are auto-discovered like pages.

Decisions:

- **Plain functions of assigns, no new template language.** `tag/3`
  composition already works; "slots" are just assign keys carrying safe HTML
  (children, headers, whatever). No macro DSL to learn or misgenerate.
- **Scoped styles, same trick as pages**: `component/2` wraps output in a
  layout-neutral `<div data-component="card" style="display:contents">`; the
  CSS collector emits `[data-component="card"] { ... }` into the same
  bundle. This resolves the task-6 tension: one-off looks stay in page
  `style/0`, shared looks live once in the component, and neither can leak.
- **`example/0` is required — it's the linchpin.** It powers both:
  - **verification**: every component is smoke-rendered with its example
    through all the existing scans (escaping, no `<style>` tags, no CDN
    references, forms carry CSRF tokens), plus the style brace check;
  - **the gallery**: a dev-only page at `/fractal/components` rendering
    every component live with its name, example assigns, and moduledoc.
    Built-in documentation, mechanized. `mix fractal.ai.docs` also prints
    the component inventory so agents see what exists without a browser.

### Hard boundaries (where the philosophy bites)

- **Components are pure render functions**: no routes, no
  `events:`/`handle_event`, no DB queries — data arrives via assigns. A
  component with behavior would smuggle logic out of the page file and break
  one-file-per-page legibility; if it needs handlers, it's a page. (A
  component may render `trigger/3` buttons; the events they fire belong to
  the page that uses it.) Enforce what's enforceable at compile time
  (`use Fractal.Component` accepts no route/event options); document the
  no-queries rule.
- **When NOT to componentize** (agents over-abstract; the guide must say
  this): used on one page → private function in that page (today's pattern,
  unchanged); shared or part of the visual language → component; thin
  wrappers around `Fractal.Form`/`trigger/3` → no, those primitives already
  are the vocabulary.
- **Anti-proliferation via visibility, not policing**: the gallery makes
  duplicates embarrassing; verify reports *unused* components
  informationally (like orphaned assets). No clever near-duplicate detection
  until real drift shows up.

### Agent workflow update

The AGENTS.md loop gains a step: **check the gallery/inventory before
creating a component; prefer using or extending an existing one.**
`mix fractal.gen.component Name` scaffolds a component + test.

### Dogfooding

- Extract at least one real component from existing duplication (e.g. the
  "not found" section repeated across show/edit pages, or a Card used by
  the home page) rather than inventing speculative ones.
- Update `gen.resource` page templates to emit component-based markup where
  a component genuinely fits, so generated resources speak the same visual
  language from birth. Don't force it.

### Deliberate rejections (record the why)

- **No variants/inheritance system** — assigns + design tokens cover it.
- **No component-local state** — violates statelessness; state lives in
  assigns, the DOM (`values:`), or the database.
- **No external component libraries** — same supply-chain stance as the CDN
  ban.
- **No live/stateful components** (LiveComponent-style) — revisit only if
  page-level events prove insufficient in practice.

## Constraints

- Keep the 1-file per page structure; components extend the pattern
  (1 file per component), they don't dilute it.
- Components are render-only: any route, event, or session capability
  stays exclusively on pages.
- No new template syntax — `tag/3` and safe-HTML assigns only.

## Files expected to change

New: `lib/fractal/component.ex` (behaviour + `component/2` helper),
`lib/fractal/components/` (starter component(s) extracted from real
duplication), `lib/fractal/pages/components.ex` or a framework-served
gallery route (dev-only), `lib/mix/tasks/fractal.gen.component.ex`,
`guides/components.md`, tests. Modified: `lib/fractal/page.ex` (import the
helper), `lib/fractal/assets.ex` (collect component styles),
`lib/fractal/verify.ex` (component checks + unused-components info),
`lib/mix/tasks/fractal.verify.ex`, `lib/mix/tasks/fractal.ai.docs.ex`
(print the inventory), `lib/mix/tasks/fractal.gen.resource.ex` (templates
use components where they fit), `guides/assets.md` + `AGENTS.md`
touch-ups.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] I can define a component in one file (render + scoped style + example)
and use it from pages via `component/2`; its styles cannot leak beyond it.
- [ ] I can open `/fractal/components` in dev and see every component
rendered live with its example; `mix fractal.ai.docs` lists the inventory.
- [ ] `mix fractal.verify` smoke-renders every component through the
existing scans (escaping, no `<style>`, no CDNs, CSRF in forms) and fails
on broken examples or unbalanced component styles; unused components are
reported informationally.
- [ ] I can prompt an agent to build a page that reuses an existing
component, and it finds it via the inventory instead of reinventing it.
- [ ] At least one existing duplication is replaced by a real component,
and generated resource pages use components where they genuinely fit.
- [ ] I can run all the tests with `mix test` and they pass.
