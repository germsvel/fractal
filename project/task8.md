# Task 8: cross-cutting behavior — guards, context, and the middleware rejection

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

## Framing: middleware is the antithesis of the one-file promise

Fractal's legibility story is "read one page file, understand everything about
that route." A middleware stack (Plug pipelines, Rack, Django) is precisely
invisible behavior nobody can see from the page — ordered lists of opaque
functions acting at a distance. Ordering bugs, silent request mutation, and
forgotten route coverage are bad for humans and worse for agents.

So we do NOT build "middleware" as a mechanism. We decompose the real needs
into named, declarative, verifiable primitives — and refuse the generic slot.
The meta-principle running through every task applies: fx instead of scripts,
directives instead of conn mutation, components instead of ad-hoc markup,
**guards instead of middleware**. Cross-cutting behavior in Fractal means:
declared where it applies, defined in one well-known place, guaranteed by
verify.

## Scope

### 1. Guards (auth and friends) — declare on the page, define in one place

```elixir
# the page says it — visible in the one file that matters
use Fractal.Page, path: "/admin/posts", title: "Admin", require: :admin

# lib/fractal/guards.ex — ONE well-known module defines what names mean
defmodule Fractal.Guards do
  use Fractal.Guards

  @impl true
  def check(:signed_in, assigns) do
    if assigns.session["user_id"],
      do: :ok,
      else: {:redirect, "/login", flash: %{"error" => "Please log in."}}
  end

  def check(:admin, assigns), do: # ...
end
```

- `require:` takes one guard name or a list; guards run in declared order
  before `render/1`, every `handle_*/1`, **and interactive events** (events
  dispatch to a page, so they cannot bypass auth — a classic middleware
  hole closed by construction).
- Guards return the vocabulary pages already speak: `:ok` or
  `{:redirect, to, directives}` (session/flash directives included). They
  cannot mutate assigns — allow or redirect, nothing else. Guards MAY query
  the database (unlike components); they are behavior.
- No stack, no ordering semantics beyond the page's own list, no hidden
  request rewriting.

### 2. Expectations: middleware as a verification contract

The reason frameworks reach for path-scoped pipelines is forgettability
("admin page #12 shipped without the guard"). Instead of moving *runtime*
behavior into a hidden scope, move the *guarantee* into verify. The Guards
module declares expectations:

```elixir
expect "/admin", :admin   # any page under /admin must declare require: :admin
```

Runtime behavior stays 100% visible in each page file; `mix fractal.verify`
fails any page whose path matches an expectation but lacks the declaration,
naming the page and the fix. Coverage is guaranteed mechanically; legibility
stays intact.

### 3. Shared request context — narrowly

One optional module, `Fractal.Context`: a pure function of
session/params/path whose result lands under **`assigns.context`** —
namespaced so provenance is self-evident (anything on `context.*` came from
exactly one greppable file; the same "one well-known place" bargain as
`app.css` and Guards). Guards receive the context too, so `:admin` can check
`context["user"]` without re-querying.

Rules: identity-scale derivation only (current user, locale, tenant); must
tolerate an empty session; never business logic.

### 4. Response headers: defaults and config, not code

The framework sets sane security headers by default (x-content-type-options,
x-frame-options, referrer-policy) — zero API, the CSRF precedent. Custom
headers via `config :fractal, :response_headers` (a map — data, not code).
No user code runs in the response path.

### 5. Observability: telemetry, not middleware

Emit standard `:telemetry` events from the router (request dispatch +
duration, guard denials). Ecto and Bandit already speak telemetry; users
attach handlers in their own application code. Keep the event set small.

### Verification additions

- Every `require:` name resolves to a defined guard (fail, naming the page).
- Every `expect/2` path prefix is honored by every matching page (fail,
  naming the page and the missing guard).
- Each guard is smoke-run with empty assigns — must return `:ok` or a
  redirect, not crash (same "must tolerate empty session" rule as pages).
- `Fractal.Context` (when defined) is smoke-run with empty assigns.
- Informational: guards no page requires (like unused components).
- `mix fractal.ai.docs` prints the guard inventory and expectations.

### Deliberate rejections (record the why)

- **No generic middleware slot, ever** — no `config :fractal, plugs: [...]`,
  no `def middleware`. Invisible action at a distance breaks the one-file
  promise; ordered stacks are the canonical agent failure mode; an open hook
  collects whatever agents paste into it. New cross-cutting needs become new
  named primitives with verification — the framework grows vocabulary, not
  hooks.
- **No assigns mutation from guards** — guards allow or redirect; derivation
  belongs to `Fractal.Context`, in its namespaced key.
- **Rate limiting deferred** — infrastructure (reverse proxy) until proven
  otherwise.
- **Rewrites/redirect rules deferred** — mostly can't arise with exact-match
  routing; deployment-layer concerns stay there.

## Constraints

- Keep the 1-file per page structure: a page's guards are declared in the
  page file; nothing invisible runs for a page beyond what `require:` and
  the framework itself (session/CSRF) do.
- Guards and expectations live in exactly one module (`lib/fractal/guards.ex`),
  context in exactly one module (`lib/fractal/context.ex`); both optional.
- Use the existing result-directive vocabulary; no conn exposure.

## Files expected to change

New: `lib/fractal/guard.ex` (behaviour + `expect/2` + runner),
`lib/fractal/guards.ex` (the app's guards — created with a `:signed_in`
starter), `lib/fractal/context.ex` (optional starter), `guides/guards.md`,
demo admin page(s), tests. Modified: `lib/fractal/page.ex` (`require:`
option + validation), `lib/fractal/router.ex` (run guards before
render/handlers/events; default security headers; telemetry),
`lib/fractal/verify.ex` (+ `lib/mix/tasks/fractal.verify.ex`),
`lib/mix/tasks/fractal.ai.docs.ex` (guard inventory),
`lib/mix/tasks/fractal.gen.page.ex` (`--require` option), `config/*.exs`
(response_headers example), `guides/sessions.md`/`building_pages.md`
touch-ups, `AGENTS.md`, `Fractal.Test` docs (guards respect the `session:`
opt naturally).

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] I can protect a page with `require:` and a guard defined in
`lib/fractal/guards.ex`; unauthenticated requests (including interactive
events) redirect with a flash, authenticated ones pass — demonstrated over
real HTTP with the login demo.
- [ ] An `expect "/admin", :admin` declaration makes `mix fractal.verify`
fail on any `/admin` page missing `require: :admin`, naming the page —
demonstrated by adding an unguarded admin page.
- [ ] `assigns.context` carries derivations from `Fractal.Context` (e.g. the
current user), available to pages and guards.
- [ ] Responses carry the default security headers; a custom header can be
added via config alone.
- [ ] I can prompt an agent to protect a new page, and it uses `require:` +
the existing guard instead of inventing auth logic in the page.
- [ ] I can run all the tests with `mix test` and they pass.
