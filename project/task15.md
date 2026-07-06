# Task 15: live reload v2 — push, CSS hot-swap, compile-error overlay

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

This task closes the three concrete gaps a comparison with
`phoenix_live_reload` surfaced, without importing its machinery (no
WebSocket, no iframe, no `patterns:` config, no per-request lazy
compiler). Live reload is the loop the agent workflow runs inside —
agent edits, browser shows — so its latency and failure behavior are
product, not plumbing.

## Framing: keep the ordering, fix the delivery

What we already do *better* than Phoenix and must preserve:

- **Compile-then-reload.** The watcher compiles eagerly on change and
  bumps only on success, so the browser refresh always lands on ready
  code. (Phoenix reloads first and compiles lazily on the next request
  — you wait in the browser.)
- **Failed compiles never blank the page.** Old code keeps serving.
- **Zero configuration.** Watch `lib/` and `assets/`; no patterns file.

What we do worse, and fix here:

1. **Polling.** The client asks every 500ms — ~250ms average latency,
   2 requests/sec/tab of log and telemetry noise. We now have SSE
   machinery (task 13); the reload signal becomes a push.
2. **CSS-only changes cause a full reload.** Scroll position, form
   input, and open panels are lost to a stylesheet tweak — exactly the
   workflow the dev bar encourages. Phoenix hot-swaps assets; so
   should we.
3. **Compile errors are invisible in the browser.** The page silently
   stays stale while the error sits in the terminal. The error should
   appear where your eyes are.

## Scope

### One dev event stream instead of polling

- `GET /fractal/reload` becomes a dev-only SSE stream (the framework
  owns both ends of this endpoint — no compatibility shim; in prod it
  404s, hardening what is today an always-on JSON endpoint). The
  injected script becomes an `EventSource` listener; `EventSource`'s
  native reconnect replaces hand-rolled retry, and the 500ms poll loop
  is deleted.
- Internally the reloader notifies the stream over the existing bus
  (an internal `Fractal.Bus.broadcast` on a reserved topic — not
  `publish/1`, so the verify topology scan and user `watch:` space are
  untouched).
- Restart self-heal: on connect the server sends the current token;
  the client remembers its first token and full-reloads when a
  reconnect reports a different one (covers server restarts, exactly
  like the old poll comparison did).

### Event kinds: reload, css, error

`Fractal.LiveReload` grows from a bare integer to `{token, event}`:

- **`reload`** — a successful recompile of code changes: the client
  calls `location.reload()`, unchanged.
- **`css`** — the debounce batch touched *only* `assets/` files: skip
  the no-op compile, recompute the fingerprinted bundle path, and send
  it as the event payload. The client swaps the stylesheet `<link>`
  href in place — no reload, page state preserved. (The reloader must
  start tracking *which* paths were in the debounce batch, not just
  that one arrived.)
- **`error`** — a failed compile: send the formatted compiler output.
  The client renders a dismissible overlay (dev-bar-style isolated
  DOM, built and styled from JS, no `<style>` tags, ignored by the
  picker) on top of the still-working page. The next successful event
  clears it. A tab opened *while* the build is broken receives the
  active error on connect — the stream's initial state, not just its
  deltas.

### Watcher fallback

When the native watcher can't start (missing inotify, NFS,
containers), retry with the `:fs_poll` backend and warn, instead of
disabling live reload outright as today.

### Docs and dogfood

- Update the dev-loop section of the building_pages guide (CSS
  hot-swap, error overlay).
- Demonstrate live in `examples/blog` over real HTTP: a CSS-only
  change streams a `css` event with a new bundle href; a code change
  streams `reload`; a deliberate syntax error streams `error` with the
  compiler message, and the fix streams `reload`.

### Non-goals

- No WebSockets, no iframe, no `patterns:`/dirs configuration, no
  per-request lazy compilation — the simplicity and the
  compile-then-reload ordering are the point.
- No web-console log streaming, no open-in-editor jumps (`PLUG_EDITOR`
  style). The editor-jump idea pairs naturally with the dev bar's
  provenance annotations — worth its own discussion later, not a rider
  here.
- No JS hot-module reloading; there is no user JS to hot-swap.

## Constraints

- Everything remains dev-gated (the `:live_reload` flag); prod
  documents already carry no script, and the endpoint now 404s in
  prod — asserted by tests.
- The stream is a dumb pipe like the watch streams: no state beyond
  the current `{token, event}`; killing every connection loses nothing
  (reconnect + initial state self-heal).
- Test strategy mirrors task 13: Plug.Test covers the prod-404 and
  the endpoint's non-streaming paths; the streaming happy path runs
  over real HTTP in `server_test` (short keepalive in the test env
  already bounds shutdown); the overlay/swap JS is asserted
  structurally like the dev bar's. `response_headers_test` must stop
  using `/fractal/reload` as its sample endpoint.
- Reloader tests must cover the batch classification (assets-only vs
  code) and the error → clear lifecycle without depending on timing
  sleeps more than the existing reloader tests do.
- No new deps.

## Files expected to change

Modified: `lib/fractal/live_reload.ex` (token → `{token, event}`,
bus notification), `lib/fractal/reloader.ex` (batch path tracking,
css/error classification, `:fs_poll` fallback), `lib/fractal/router.ex`
(`/fractal/reload` → dev-only SSE), `lib/fractal/document.ex` (the
injected script: EventSource, link swap, error overlay),
`priv/guides/building_pages.md`, tests mirroring each
(`live_reload_test`, `reloader_test`, `router_test`,
`response_headers_test`, `server_test`, `document_test`). No installer
changes — every app gets it on upgrade.

## Plan first

Before changing anything, map the full plan and list the files you'll
touch. Wait for my go-ahead, then execute in one pass.

## Definition of done

- [x] No polling: dev pages hold one SSE connection to
  `/fractal/reload`; the 500ms loop is gone; prod serves 404 there.
- [x] A CSS-only change swaps the fingerprinted bundle link in place —
  no page reload — and a code change still full-reloads onto
  already-compiled code; demonstrated live in `examples/blog` over
  real HTTP.
- [x] A compile error appears as a browser overlay with the compiler
  output while old code keeps serving; the next good compile clears
  it and reloads; a tab opened during the broken state shows the
  error immediately — demonstrated live.
- [x] Server restarts and dropped connections self-heal via the
  initial-token comparison.
- [x] The watcher falls back to `:fs_poll` with a warning instead of
  disabling.
- [x] Framework suite, blog suite + verify, and the born-green
  integration test stay green; guide updated.
