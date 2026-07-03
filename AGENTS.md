# Fractal

An AI-first web framework written in Elixir. Humans build it, but they do
so purely with AI — so this file is the contract for how agents work here.

## Orientation

- A **page** is one module in `lib/fractal/pages/` using `Fractal.Page`.
  Routes are auto-discovered; there is no router file to edit.
- HTML is built with `Fractal.HTML.tag/3` — escaped by default, `raw/1`
  is the only escape hatch.
- `mix fractal.verify` is the feedback loop. A change is not done until
  it passes.

## Agent workflow

When asked to create or change a page or feature:

1. **Read the docs first**: run `mix fractal.ai.docs` (or read
   `guides/*.md`). They define page anatomy, conventions, and testing
   expectations.
2. **Scaffold**: `mix fractal.gen.page Name --path /route --title "Title"`
   creates the page and its test. For non-trivial pages, edit `render/1`
   and make the test assert on the real content.
3. **Verify**: run `mix fractal.verify`. Fix anything it reports and
   re-run until green.
4. In development, `mix fractal.server` auto-recompiles and reloads the
   browser — no restarts needed to see the change.

## Commands

| Command | Purpose |
| --- | --- |
| `mix fractal.server` | Start the dev server on port 4000 (live reload on) |
| `mix fractal.gen.page Name` | Scaffold a page + test |
| `mix fractal.verify` | Compile (warnings-as-errors) + page checks + tests |
| `mix fractal.ai.docs` | Print the guides agents must read |
| `mix test` | Run the test suite directly |

## Conventions

- Elixir ~> 1.20. Format with `mix format` before finishing.
- Every module of framework code has test coverage under `test/`,
  mirroring the `lib/` layout.
- Keep pages self-contained; shared markup helpers belong in
  `Fractal.HTML` or a dedicated module, not copied between pages.
- Database access (when it arrives) will use Ecto — do not hand-roll
  persistence.

## Model routing (through July 7)

Default: Sonnet 5 for everyday work.

Use Fable 5 only for heavy, high-payoff tasks:
- large migrations (framework, language, dependency)
- codebase-wide refactors across many files
- complex multi-step builds
- hard bugs in tangled code (race conditions, subtle state)

Rule of thumb: weeks-by-hand → Fable 5, minutes-by-hand → Sonnet 5.
Protect the Fable 5 window. Don't spend it on small edits.

Note: some security-adjacent requests get rerouted to Opus 4.8
by the new safeguards. If quality drops on one call, check for a reroute.
