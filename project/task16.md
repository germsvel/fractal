# Task 16: the route table — compile-time speed without compile time

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

Routing currently rediscovers the world on every request:
`Router.pages/0` globs the host app's `ebin/*.beam` off the filesystem,
runs `Page.page?/1` reflection (ensure_loaded + attribute walks) over
every module in the app, sorts, and `find_route/2` re-sorts and
linearly matches. Measured in `examples/blog`: **~308µs per call with
only 19 modules**, scaling with the app's *total module count* — a
1,000-module app would burn tens of milliseconds of filesystem and
reflection work per request. This task removes that cost without
changing a single contract.

## Framing: why not literal compile time

- **No compile unit can see all pages.** The framework compiles before
  the host app exists, and each page compiles independently. The only
  ways to get a compile-time table are a central router module the app
  maintains (the exact coordination artifact one-file-per-page exists
  to eliminate) or a generated module with its own
  regenerate-and-recompile build-graph problem.
- **Runtime discovery is load-bearing for the dev loop.** Agent writes
  a page → watcher recompiles → the route exists, no restart. That
  stays.

The route set changes at exactly two moments, both framework-owned:
boot, and the dev reloader's recompile. So: build the table once at
runtime, cache it, and keep the dev path live. Compile-time
performance, delivered at runtime — the same policy
`Fractal.Assets.css_bundle/0` already applies to the CSS bundle.

## Scope

### The table

An internal route-table module (`@moduledoc false` — not a new
primitive, an implementation detail of the router):

- Built from one discovery pass: the sorted page list (what `pages/0`
  returns today), plus per method (GET/POST/PUT/DELETE) the routes
  **pre-split into segment lists** and **partitioned**:
  - a map of fully-static routes for O(1) exact lookup
    (`%{["posts", "new"] => page}`),
  - a list of dynamic patterns for the linear match, sorted by param
    count (then path, for determinism).
- **Identical match semantics to today**, including the subtlety that
  ordering is by param *count*, not merely static-before-dynamic
  (`/posts/:id` beats `/:section/:page`). The existing router tests are
  the contract; no behavior change is acceptable.
- `Router.pages/0` keeps its exact contract (verify, the gallery,
  ai.docs, the 404 page all consume it) — it just reads the table.
- The same term also carries the discovered **checkpoint and layout
  modules** — the other two discovery products consumed on every
  request (`Checkpoint.context/1` in assigns, `Layout.site/chrome` in
  the document). Leaving them out would have left two ebin scans per
  request in place; folding them in is the "terms updated together
  live in one term" rule. Their plural `modules/0` discovery functions
  (verify's at-most-one checks) stay live.

### The cache: persistent_term, used the way its docs demand

The best-practices analysis (from the OTP docs) is part of this task's
record, because the design follows from it:

- **One key, one large term**: everything under `{Fractal.Router,
  :routes}` — page list, static maps, dynamic lists in a single map.
  Never per-method or per-page keys ("prefer a few large persistent
  terms"; "terms updated together should be collected into one").
- **Prod writes exactly once, then never.** A first `put` of a new key
  is not an update — no old value, no global GC. The route set cannot
  change after boot in prod. This is the canonical
  write-once-read-forever workload; reads are copy-free and
  contention-free.
- **Dev and test never write at all** — both stay on today's live
  discovery path. The gate is
  `Application.get_env(:fractal, :cache_discovery, true) and not live_reload`:
  dev is live via the live-reload flag (instant pick-up of new pages,
  `--no-watch` correctness, modules-compiled-in-iex), and test envs are
  live via `config :fractal, cache_discovery: false` — set in the
  framework's own `config/test.exs`, in `examples/blog`'s, and in the
  installer's generated `config/test.exs` (with a comment), so host-app
  test suites behave exactly like ours. The flag doubles as an explicit
  diagnostic lever: any environment can turn caching off with one line
  if a stale-discovery bug is ever suspected — something an env sniff
  could never offer. No invalidation machinery exists because no
  cached context can ever need it. `Fractal.Assets` adopts the shared
  gate, so its test-env caching goes away for the same reason.
- **No long-lived holder of the term**: request processes use the
  table transiently and die; the SSE loops (watch, reload) must not
  capture it in loop state. Comment at the read site so this doesn't
  drift — it's moot while prod never updates, but it keeps the
  fallback (below) safe.

### Considered and rejected (recorded)

- **Compile-time codegen / central router macro** — see Framing.
- **ETS** — copies the term out on every read; trades a one-time prod
  write we don't have for per-request copy churn we'd feel forever,
  plus an owner process and its lifecycle.
- **A GenServer holding the table** — serializes all routing through
  one mailbox.
- **Application env** — ETS-backed with per-read copying; semantically
  config, not cache.
- **Dev cache + invalidate-on-reloader-bump** — viable fallback if a
  huge app ever makes *dev* routing feel slow (the same-value `put`
  optimization and a dev machine's small process count keep the GC
  cost trivial there), but not built now: the uncached dev path is
  simpler and cannot be stale.
- **Trie/radix matching** — unnecessary; after the table, matching is
  a map hit or a scan over a handful of dynamic routes.

### Non-goals

- No API or behavior change anywhere: same routes, same precedence,
  same `pages/0`, same dev loop.
- No routing configuration. The one addition is
  `config :fractal, :cache_discovery` (default `true`) — an off-switch
  for the cache, not a tuning surface; it takes no values besides
  false.

## Constraints

- Tests are never cached, by design — see the gate above. This deletes
  (rather than manages) the poisoning hazard: tests that mutate
  discovery config (`:otp_app` overrides) or toggle dev mode mid-suite
  cannot interact with a cache that is never populated in a test env.
  Rejected alternatives for the test gate, for the record: detecting
  `mix test` via `Mix.env()` when Mix is loaded (knobless, but bakes a
  runtime dependency on the build tool's presence into cache behavior
  and offers no lever to reproduce or rule out cache bugs elsewhere),
  and skipping the cache whenever `:otp_app` is overridden (the
  override is legitimate, documented prod config — real apps would
  silently lose the cache).
- Benchmark honestly, same method as the measurement that motivated
  this: `pages()`/route lookup timed in `examples/blog`, before and
  after, cached and uncached paths both reported.
- No new deps. Framework suite stays DB-less.

## Files expected to change

New: the internal table module (e.g. `lib/fractal/routes.ex`,
`@moduledoc false`) and its test. Modified: `lib/fractal/router.ex`
(`pages/0` and `find_route/2` read the table),
`lib/fractal/assets.ex` (adopt the shared `cache?/0` gate),
`config/test.exs` (framework), `examples/blog/config/test.exs`, and
`installer/templates/config/test.exs.eex` (all three set
`cache_discovery: false`, the template with a comment). Docs: the
router moduledoc's discovery paragraph gains a sentence on caching and
the flag; the installer change means the born-green integration test
must be re-run.

## Plan first

Before changing anything, map the full plan and list the files you'll
touch. Wait for my go-ahead, then execute in one pass.

## Definition of done

- [x] Routing no longer touches the filesystem or module reflection
  per request when cached: table built once, read from
  `{Fractal.Router, :routes}`.
- [x] Benchmark in `examples/blog` shows per-request routing cost
  dropping from hundreds of µs to single-digit µs on the cached path,
  with the uncached (dev) path unchanged.
- [x] Match semantics are provably identical: all existing router,
  verify, and blog tests pass unmodified.
- [x] The dev loop still picks up new pages without restart
  (uncached path), demonstrated in `examples/blog`.
- [x] persistent_term usage follows the recorded constraints: single
  key, single term, no writes outside the cache-eligible path, no
  long-lived holders.
- [x] Framework suite, blog suite + verify, and the born-green
  integration test stay green.
