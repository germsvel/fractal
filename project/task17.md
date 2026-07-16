# Task 17: declarative browser actions — keyboard shortcuts without user JavaScript

## Goal

Fractal is a new web framework written in Elixir that is AI-first.

In practice that means at least the following:

- It provides primitives for building web-pages in a way that AI agents can
  easily consume and extend.

- It focuses on the developer experience using AI to build the web application.
  Developers can dive in and write code, but the fundamental pattern is to
  prompt the AI.

- It has built-in verification checks to ensure that the code AI produces is
  correct.

- It has built-in documentation that the AI uses when a developer prompts it to
  create a new page or feature.

This task adds page-level keyboard shortcuts as declarative browser actions:
small, framework-owned interactions that require no user JavaScript. Shortcuts
can call existing `handle_event/2` handlers or perform a tiny set of local
browser actions (`focus`, `navigate`, `show`, `hide`, `toggle`) that the
framework can verify.

## Framing: browser actions, not arbitrary JavaScript

Fractal already has the main interactivity model: declare `events:` on a page,
render `fx/2` or `trigger/3`, POST to `/fractal/event`, return HTML. Keyboard
shortcuts should extend that model, not create a second application framework in
the browser.

The primitive is therefore:

```elixir
use Fractal.Page,
  path: "/posts",
  title: "Posts",
  events: ["older", "newer"],
  keys: [
    "j": {:event, "older"},
    "k": {:event, "newer"},
    "/": {:focus, "#search"},
    "?": {:toggle, "#keyboard-help"},
    "Escape": {:hide, "#keyboard-help"},
    "n": {:navigate, "/posts/new"}
  ]
```

`"j": {:event, "older"}` travels through the normal `handle_event/2` path.
The other actions are local browser conveniences owned by Fractal's injected
runtime:

- `{:focus, "#search"}` focuses an element.
- `{:navigate, "/posts/new"}` navigates to an app path.
- `{:show, "#help"}` clears the standard `hidden` attribute.
- `{:hide, "#help"}` sets the standard `hidden` attribute.
- `{:toggle, "#help"}` toggles the standard `hidden` attribute.

This is intentionally much smaller than `Phoenix.LiveView.JS`. It is not a DOM
mutation language. It is a named, bounded vocabulary for common keyboard UX:
search focus, help panels, modal dismissal, navigation accelerators, and event
accelerators.

## Scope

### Page declaration

`Fractal.Page` gains a `:keys` option. It returns a normalized list through a
new callback such as `keys/0`, defaulting to `[]`.

Valid declarations in v1:

```elixir
keys: [
  "j": {:event, "older"},
  "k": {:event, "newer"},
  "/": {:focus, "#search"},
  "?": {:toggle, "#keyboard-help"},
  "Escape": {:hide, "#keyboard-help"},
  "n": {:navigate, "/posts/new"}
]
```

The public documentation lives in `Fractal.Interactive`, because this remains
part of Fractal's no-user-JavaScript interactivity story. The implementation
uses an internal helper module:

```elixir
defmodule Fractal.Interactive.BrowserAction do
  @moduledoc false
end
```

That module owns action/key normalization, validation, encoding for the runtime,
and shared error messages used by compile-time checks and verification.

### Key grammar

Keep the v1 grammar deliberately small and explainable:

- Printable single-key shortcuts: `"j"`, `"k"`, `"/"`, `"?"`.
- Named keys that browsers expose consistently: `"Escape"`, `"Enter"`,
  `"ArrowUp"`, `"ArrowDown"`, `"ArrowLeft"`, `"ArrowRight"`.
- Modifier chords: `"Mod+k"`, `"Ctrl+k"`, `"Alt+k"`, `"Shift+?"`, where
  `Mod` means Command on macOS and Control elsewhere.

Rejected in v1: multi-key sequences (`"g n"`), arbitrary `KeyboardEvent.code`,
per-locale key maps, and browser-reserved/system shortcuts. Duplicate keys on a
page are invalid.

Runtime rule: shortcuts do not fire while focus is inside `input`, `textarea`,
`select`, or `[contenteditable]`, so `/` types `/` when the user is already
editing text. `Escape` may be considered for an exception later, but v1 should
stay predictable unless the implementation plan explicitly justifies the
exception.

### Browser action grammar

Actions supported in v1:

```elixir
{:event, name}
{:focus, id_selector}
{:navigate, path}
{:show, id_selector}
{:hide, id_selector}
{:toggle, id_selector}
```

Constraints:

- Event names are non-empty strings and must be declared in `events:`.
- Navigation targets are app paths beginning with `/`; external URLs and
  `javascript:`-style targets are invalid.
- DOM-targeting actions accept **id selectors only** in v1: `"#search"`,
  `"#keyboard-help"`. Full CSS selectors are deliberately rejected so verify can
  be strong without adding a selector engine dependency.
- `show`/`hide`/`toggle` manipulate the standard `hidden` property/attribute,
  not arbitrary classes.

### Runtime

`Fractal.Interactive.runtime_js/0` grows a small keyboard listener and a browser
action executor.

- The document carries the current page's encoded key bindings, likely on the
  page's `<main>` element or in a small JSON script/data attribute the framework
  owns.
- `{:event, name}` posts to `/fractal/event`, reusing the same CSRF handling,
  redirect handling, and fragment swap path as `fx/2`.
- Local actions run in the browser:
  - focus: `document.getElementById(id).focus()` when present;
  - navigate: `window.location.href = path`;
  - show/hide/toggle: update `el.hidden`.
- Missing DOM targets at runtime are safe no-ops, but verification should catch
  normal mistakes before they ship.

### Verification

`mix fractal.verify` must make keyboard shortcuts agent-correctable:

- `keys:` is well-formed and has no duplicate key combinations.
- Every `{:event, name}` references a declared `events:` name.
- Existing event checks still ensure `handle_event/2` exists when events are
  declared.
- Every DOM-targeting action uses a simple id selector.
- Every DOM-targeting action's target id appears in the page's baseline rendered
  HTML. The target may be rendered directly by the page or by a component; the
  only requirement is that the assembled output of `render/1` contains the id.
- `{:focus, "#id"}` additionally requires the target to be focusable: an
  `input`, `textarea`, `select`, `button`, an anchor with `href`, or any element
  with `tabindex`.

This means the following should fail verification with a precise message:

```elixir
keys: ["/": {:focus, "#serach"}]
```

when the page renders:

```elixir
tag(:input, [id: "search", type: "search"])
```

The error should say which page, which key, which action, and which missing id
caused the failure.

Selectors are verified against the page's normal smoke render — the same model
used for existing render checks. A page-level shortcut implies page-level
availability: if a modal/help panel is controlled by a page-level key, it should
exist in the baseline HTML, often hidden with `hidden: true`. It may live in a
component; it just needs to be present in the rendered page.

### Testing helpers

`Fractal.Test` should gain a helper that exercises the server-backed branch of
keyboard shortcuts without a browser, for example:

```elixir
fire_key("/posts", "j")
```

For event actions, this should resolve the key through the page declaration and
dispatch exactly as `/fractal/event` would. For local-only browser actions,
there is no server behavior to fire; the helper can return/assert the resolved
action or provide a focused helper such as:

```elixir
assert_key_action(MyApp.Pages.Posts, "/", {:focus, "#search"})
```

The exact API can be refined during implementation, but the test story must let
apps assert that important keyboard event paths are covered without introducing
a browser test dependency.

### Docs and generators

- Update `priv/guides/interactivity.md` with a keyboard shortcuts / browser
  actions section.
- Update `Fractal.Page` and `Fractal.Interactive` docs.
- Consider whether `mix fractal.gen.page --events ...` should mention `keys:` in
  comments/examples, but do not force every generated interactive page to have
  shortcuts.
- Add a small example to `examples/blog`, preferably on a page where shortcuts
  are natural: `/` focuses search, `?` toggles keyboard help, `Escape` hides it,
  and one key triggers an existing page event if appropriate.

## Non-goals

- No user-authored JavaScript callbacks.
- No arbitrary `keydown`/`keyup` hooks.
- No full CSS selector support in v1.
- No multi-key sequences like `g n`.
- No class manipulation (`add_class`, `remove_class`, `toggle_class`) in v1.
- No transitions, dispatching custom DOM events, focus stacks, or command
  composition like `Phoenix.LiveView.JS`.
- No global app-wide shortcut registry. Shortcuts are page declarations.
- No component-owned independent behavior. Components may render targets, but
  pages own keyboard shortcuts because events and routing belong to pages.
- Keyboard shortcuts must not be the only accessible path to an action; they are
  accelerators for behavior that remains reachable through rendered controls or
  links.

## Constraints

- Preserve one file per page: route, render, events, keys, handlers, and styles
  live together.
- Preserve the stateless server: keyboard event actions submit the same request
  data model as other events; local browser actions do not create server state.
- No new dependencies. Id-selector verification should be implemented with the
  rendered HTML Fractal already has, not a general CSS selector engine.
- Keep the framework-owned document boundary: apps declare data/actions; the
  framework injects and owns the runtime.
- All behavior must remain safe when JavaScript is unavailable: pages still
  render and normal links/forms/buttons still work; keyboard shortcuts are
  progressive enhancement.

## Files expected to change

New:

- `lib/fractal/interactive/browser_action.ex`
- tests for browser action normalization/validation

Modified:

- `lib/fractal/page.ex` — `:keys` option, callback/default, compile-time shape
  checks where appropriate, docs.
- `lib/fractal/interactive.ex` — docs, runtime JS key listener/action executor,
  event dispatch reuse.
- `lib/fractal/document.ex` — include the current page's encoded key bindings in
  the framework-owned document/page markup.
- `lib/fractal/verify.ex` — key/action checks, rendered target-id checks,
  focusability checks.
- `lib/fractal/test.ex` — keyboard helper(s) for server-backed shortcut paths.
- tests mirroring the above modules, plus fixture pages in
  `test/support/fixtures.ex`.
- `priv/guides/interactivity.md` — keyboard shortcuts and browser actions.
- `examples/blog` — small dogfood example and tests/verify updates.

Installer changes are probably unnecessary unless generated app docs or
comments need to mention the new primitive.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] Pages can declare `keys:` with event, focus, navigate, show, hide, and
  toggle actions.
- [ ] Keyboard event actions reuse `/fractal/event` and `handle_event/2`; local
  browser actions run without a server request.
- [ ] Shortcuts are ignored while the user is typing in form fields or editable
  content.
- [ ] `mix fractal.verify` catches malformed keys/actions, duplicate keys,
  undeclared event references, missing target ids, and non-focusable focus
  targets with precise page/key/action errors.
- [ ] DOM-targeting actions are id-selector-only in v1 and use the standard
  `hidden` attribute for visibility.
- [ ] The test helper story covers server-backed keyboard shortcuts without a
  browser dependency.
- [ ] Docs explain keyboard shortcuts as browser actions under Fractal
  interactivity, including accessibility guidance that shortcuts are
  accelerators, not the only path.
- [ ] Framework tests pass, `mix fractal.verify` passes, and the blog dogfood
  example verifies.
