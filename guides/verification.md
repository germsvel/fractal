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
