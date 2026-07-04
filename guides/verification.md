# Verification

Fractal ships a verification loop so that AI-generated code is checked by
machinery, not by hope. The single entry point:

```
mix fractal.verify
```

It performs, in order:

1. **Compile with warnings as errors.** Undefined functions, unused
   variables, pattern-match issues — anything the compiler flags fails
   verification.
2. **Page checks** (`Fractal.Verify`):
   - at least one page module exists
   - no two pages claim the same route
   - every page's path is a string starting with `/` with no stray
     whitespace
   - every page's title is a non-empty string
   - every page's `render/1` runs without raising (with
     `%{params: %{}, path: ..., conn: nil}`) and returns renderable
     content (`Fractal.HTML` safe content, a string, or a list)
3. **The test suite** (`mix test`). Skip with `--no-tests` when iterating,
   but a change is only done when the full run passes.

The task exits non-zero on any failure, so it can gate CI and agent loops.

Some checks also run earlier, at compile time: `use Fractal.Page` refuses
to compile a page with a missing or malformed `path:`.

## Workflow for agents

1. Make the change (e.g. generate a page with `mix fractal.gen.page`).
2. Run `mix fractal.verify`.
3. If it fails, read the check names and details — they name the module
   and the exact problem — fix, and re-run.
4. Only report the work as done when verification passes.

## Testing conventions

- Every page has a test file at `test/fractal/pages/<name>_test.exs`.
- Page tests assert three things: the page passes `Fractal.Verify.run/1`,
  declares the expected route, and its rendered HTML contains the real
  content (not just the scaffold placeholder).
- Render pages in tests via
  `page.render(%{params: %{}, path: page.path(), conn: nil})` and turn the
  result into a string with `Fractal.HTML.to_safe/1` +
  `Fractal.HTML.safe_to_string/1`.

## Invariants: the app's additions to the contract

An **invariant** is a property that must be guaranteed for every page —
current and future. They are defined once, in `lib/fractal/invariants.ex`,
and `mix fractal.verify` runs them against all pages uniformly:

```elixir
defmodule Fractal.Invariants do
  use Fractal.Invariant

  invariant "title fits in a search result", %{page: page} do
    if String.length(page.title()) <= 60,
      do: :ok,
      else: {:error, "title is #{String.length(page.title())} chars — keep it under 60"}
  end
end
```

- The context (`%{page: module, rendered: html}`) arrives as an explicit
  pattern-matched argument — the same shape as ExUnit's
  `test "name", %{conn: conn}`. Omit the pattern when unneeded.
- Blocks return `:ok` or `{:error, message}`; a crashing invariant fails.
- Invariants apply to **all** pages — there is no filtering option. One
  that doesn't apply to a page can return `:ok` for it, keeping the
  judgment visible in its body.
- The current inventory is printed by `mix fractal.ai.docs` — **read it
  before writing a page**; these are the house rules.

Invariants are NOT per-page verification. A page's behavioral spec is its
test file — pages have no verification API of their own, deliberately:
verification stays outside the file it verifies.

## Test coverage is enforced

Every page and component must be referenced by at least one test file —
`mix fractal.verify` fails otherwise, naming the module and the
conventional test path. The generators scaffold test files; a hand-written
page must bring its own. This check enforces existence, not quality — the
testing conventions above describe what good page tests cover.
