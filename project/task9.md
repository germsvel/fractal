# Task 9: extensible verification — test coverage contracts and invariants

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

## Framing: the verification pyramid, and why pages don't verify themselves

Verification has three layers, each with a distinct owner and failure meaning:

1. **Compile time** — structural/pairing errors (`post:` without
   `handle_post/1`). Owner: the framework. "This page is malformed."
2. **`Fractal.Verify`** — universal invariants the framework can assert about
   every page *without knowing what the page is for* (unique routes, CSRF in
   forms, no CDNs, expectations honored, renders don't crash). Owner: the
   framework. Green means one thing for the whole app.
3. **The page's test file** — the behavioral specification of *this* page,
   with real data, through the real router. Owner: the page author (the
   agent). **The test file IS the per-page verify function** — written in a
   language with data setup, sandboxing, and real failure output.

We considered and rejected a per-page `verify/0` callback:

- It's a strictly weaker assertion language for the test file's job (no data
  setup, no scenarios, no failure diffs), creating a fuzzy where-does-this-
  check-go boundary — and fuzzy boundaries are where agents make bad choices.
- **Self-verification isn't verification.** Verify's authority comes from the
  checker being defined outside the checked file. A page carrying its own
  verification can weaken its own gate (a vacuous `verify/0`), and "green"
  stops meaning anything uniform. Same reasoning as guards failing closed and
  expectations living in the checkpoint, not the pages they constrain.
- The escape-hatch lesson: an optional hook collects whatever gets pasted
  into it, drifts from behavior, and produces false confidence.

Also rejected (for now): per-page `example/0` for richer smoke-renders.
Components get examples *because they're pure*; page examples would need DB
state to mean anything, making them flaky in exactly the way sandboxed tests
aren't. Components get examples, pages get tests — that asymmetry is
load-bearing.

What survives from the idea are two real gaps, both filled in the framework's
existing shapes:

## Scope

### 1. Test coverage as a verification contract

Nothing currently enforces that a hand-written page *has* tests — the
generators scaffold them, but a page added by hand can skip them silently.
Same move as `expect/2`: make coverage mechanical.

`mix fractal.verify` checks, for every discovered page (and component):

- a corresponding test file exists at the conventional path
  (`test/fractal/pages/<name>_test.exs`, `test/fractal/components/<name>_test.exs`)
- the test file references the module (a content check, so an empty stub
  named correctly doesn't pass)

Failure names the page and the expected path, and suggests the generator or
the documented test conventions. This can't judge test *quality* — it
converts "forgot entirely" from silent to loud, which is the failure mode
that matters. (Escape consideration: sample/demo pages are pages like any
other; they already have tests. No opt-out.)

### 2. Invariants: the app extends the contract, not the page

Apps have app-specific rules that must hold for every page ("every title
under 60 chars", "every page renders a breadcrumb"). The right granularity
is app-wide, not per-page — invariants are defined **once, in one
well-known place**, and run by verify against **all pages uniformly** (the
checkpoint pattern applied to verification):

```elixir
# lib/fractal/invariants.ex — the app's additions to the verification contract
defmodule Fractal.Invariants do
  use Fractal.Invariant

  invariant "title fits in a search result", %{page: page} do
    if String.length(page.title()) <= 60,
      do: :ok,
      else: {:error, "title is #{String.length(page.title())} chars — keep it under 60"}
  end

  invariant "every page links home", %{rendered: rendered} do
    if rendered =~ ~s(href="/"), do: :ok, else: {:error, "add a link back to /"}
  end
end
```

**Naming**: an *invariant* is a property that must be guaranteed — which is
exactly what these are: universally quantified statements over all pages.
Rejected names: `Checks` (collides with `Checkpoint`/`Checkpoints` — a
near-prefix in module and file names, and the checkpoint guide already
calls guards "named checks"); `Properties` (invites confusion with
property-based testing and its generators — StreamData's `property` macro
looks identical but means something else); `PageProperties` (the only
compound module name in the framework, and wrong the moment invariants
apply to components too).

**Honest usefulness assessment** (this feature has a null alternative): a
plain ExUnit test looping `Router.pages()` can express any of these
invariants today. Expressiveness is NOT the differentiator. Two properties
are, and they're what the feature must earn its keep on:

1. **Proactive surfacing**: invariants are house rules, printed by
   `mix fractal.ai.docs` — an agent learns "titles under 60" *before*
   writing page #21, not by failing afterward. This is the built-in-docs
   pillar doing real work, and the main justification.
2. **Verify-pass reporting**: invariants run in the fast structural pass
   (before the test suite, even with `--no-tests`) and report per page
   with the invariant's own message, instead of one loop assertion failing
   somewhere.

If neither property proves valuable in practice, remove the feature and
document the ExUnit-loop pattern instead.

Why not literal ExUnit syntax: ExUnit tests are anonymous functions
registered with a runner in the test env — they can't be enumerated for
the ai.docs inventory, named per page in verify output, or run in the
structural pass. So: ExUnit *conventions*, custom *mechanism*. The
`invariant "name", %{page: page} do` shape deliberately mirrors
`test "name", %{conn: conn} do` — the context is an explicit,
pattern-matched argument, not magic variables injected into the block.
Omit the pattern when the invariant needs no context.

- `Fractal.Invariant` behaviour + `invariant/3` macro: the context map is
  `%{page: module, rendered: html}` (`rendered` from the same
  empty-assigns smoke render as the framework's render check); the block
  returns `:ok` or `{:error, message}`.
- Discovered like the checkpoint: at most one invariants module, optional.
- Runs inside `Fractal.Verify.run/1` after the framework checks, per page,
  named `"<Page> satisfies invariant '<name>'"`. A crashing invariant is a
  failing one (fail closed).
- Invariants are read-only observations — they cannot mutate anything, and
  they must tolerate pages rendering with empty assigns (same rule as
  everywhere).
- `mix fractal.ai.docs` prints the invariant inventory so agents know the
  house rules before writing a page.

### Consistency: migrate the checkpoint's `guard` macro to the same shape

`guard :signed_in do ... end` currently injects a magic `assigns` variable
(`var!`). Adopt the explicit-context style there too, so the framework has
exactly one pattern for block-macros receiving context:

    guard :signed_in, %{context: context} do
      if context["user_name"], do: :ok, else: {:redirect, "/login", ...}
    end

Only `Fractal.Checkpoints` uses it; the migration is mechanical. Agents
learn the pattern once.

### Verification of the verifier

- Verify errors if more than one invariants module exists.
- A crashing invariant surfaces as that page's failure with the exception
  message; the invariant author sees it immediately.
- Invariant names must be unique (compile-time, like guards).

### Deliberate rejections (record the why)

- **No per-page `verify/0`** — see framing. The test file is the per-page
  contract; verification stays outside the verified file.
- **No per-page `example/0`** — pure components get examples; DB-backed
  pages get tests.
- **No literal ExUnit syntax for invariants** — tests can't be enumerated
  for the inventory or run in the structural pass; we borrow ExUnit's
  *shape* (`invariant "name", %{page: page} do`) without its runner.
- **No magic variables in invariant/guard blocks** — context arrives as an
  explicit pattern-matched argument, ExUnit-style.
- **No per-invariant page filtering** (e.g. `invariant ..., only: "/admin"`)
  in v1 — universal invariants keep green meaning one thing; an invariant
  can trivially no-op (`:ok`) for pages it doesn't apply to, keeping the
  judgment visible in its body. Revisit only with evidence.

## Constraints

- Keep the 1-file per page structure: pages gain no verification API at all.
- Invariants live in exactly one module (`lib/fractal/invariants.ex`),
  optional, discovered by behaviour — mirroring `Fractal.Checkpoint`.
- Invariants receive data (`page`, `rendered`); they cannot reach into
  conns, sessions, or the response path.

## Files expected to change

New: `lib/fractal/invariant.ex` (behaviour + `invariant/3` macro + runner +
discovery), optional starter `lib/fractal/invariants.ex` (with one real,
useful invariant for this app), `guides/verification.md` gains an
"invariants" section (or a new `guides/invariants.md`), tests. Modified:
`lib/fractal/verify.ex` (test-coverage check + invariant execution +
at-most-one enforcement), `lib/fractal/checkpoint.ex` +
`lib/fractal/checkpoints.ex` (migrate `guard` to explicit-context
arguments), `lib/mix/tasks/fractal.verify.ex`,
`lib/mix/tasks/fractal.ai.docs.ex` (invariant inventory), `AGENTS.md`
(orientation bullet: where invariants live; never add page-level verify
functions), `guides/building_pages.md` + `guides/checkpoint.md`
touch-ups.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] A hand-written page without a test file fails `mix fractal.verify`,
naming the page and the expected test path — demonstrated by adding one.
- [ ] An invariant defined in `lib/fractal/invariants.ex` runs against every
page; a violating page fails verify with the invariant's message —
demonstrated live (add an invariant the current app violates, watch it
fail, fix the page).
- [ ] Invariants appear in `mix fractal.ai.docs`; an agent prompted to add
a page respects the house invariants without being told about them in the
prompt.
- [ ] Verify fails on duplicate invariants modules and on duplicate
invariant names (compile-time).
- [ ] The checkpoint's `guard` macro uses explicit context arguments
(`guard :signed_in, %{context: context} do`) and all existing guard tests
still pass.
- [ ] I can run all the tests with `mix test` and they pass.
