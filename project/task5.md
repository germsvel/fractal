# Task 5: sessions and CSRF protection

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

Two implicit principles established in prior tasks also apply: the server stays
stateless (state travels with the request — params, DOM values, the DB), and we
don't reimplement battle-tested plumbing (Ecto for data; here, Plug for
sessions/CSRF crypto).

## Scope

Add sessions and CSRF protection (deferred since task 2 — the guides currently
say "no CSRF token until sessions exist").

### Sessions: encrypted cookies, read as data, written as data

- **Storage**: encrypted cookie store (`Plug.Session`, `:cookie` — plug_crypto
  is already a dep). No server-side session store: the session rides with the
  request, the server holds nothing. This is "state travels with the request"
  applied to identity.
- **Reading**: `assigns.session`, a string-keyed map exactly like
  `assigns.params`. Same rule as params: pages must tolerate an empty session
  (verify's smoke-render passes `session: %{}`).
- **Writing**: a declarative directive on handler results, NOT conn mutation.
  Extend the existing return vocabulary with an optional trailing keyword:

      {:redirect, "/dashboard", session: %{"user_id" => user.id}}
      {:redirect, "/", clear_session: true}   # logout

  Two directives only: `session:` (merge map) and `clear_session: true`. They
  compose with every return type, including `{:fragment, ...}`, so interactive
  pages get sessions for free. A grep for `session:` finds every place session
  state changes (same greppability argument as `raw/1`).
- **Secrets**: `secret_key_base` in config (dev/test committed, prod from env,
  matching the existing config layout); a `mix fractal.gen.secret` task; a
  verify check that the secret exists and has real entropy (>= 64 bytes, not a
  scaffold placeholder). Misconfiguration is a red ✗ with instructions, not a
  runtime crypto error.
- **Documented boundary**: sessions are for identity and flash-scale data
  (~4KB cookie limit). App state keeps living in the DB or the DOM — the guide
  must say this so agents don't treat the session as a cache.

### CSRF: invisible, framework-owned at both ends, verify-enforced

Key insight: Fractal owns both the producer and the consumer of every
state-changing request (all forms go through `form_for`/`button_to`, all
events go through the injected runtime), so CSRF can have **zero page-level
API** — the correct amount of security API to hand an agent.

- `form_for` and `button_to` silently append a hidden `_csrf_token`
  (session-bound masked tokens via `Plug.CSRFProtection` — no hand-rolled
  crypto).
- The layout emits `<meta name="fractal-csrf-token">`; the fx runtime reads it
  and includes the token in every `/fractal/event` POST.
- Router pipeline: parsers → method override → session fetch → CSRF verify
  (POST/PUT/PATCH/DELETE and events) → dispatch. `SameSite=Lax` on the session
  cookie as belt-and-braces (PUT/DELETE tunnel through POST, so Lax covers
  everything uniformly).
- **The 403 is a corrective instruction, not a wall**: "CSRF token missing.
  Build forms with `Fractal.Form.form_for/4` and interactions with `trigger/3`
  or `fx/2` — hand-written `<form>` tags and `fetch` calls are not supported.
  See `mix fractal.ai.docs`." Runtime failures teach the agent the convention,
  like the 404 that suggests the page-creation prompt.
- **Verify catches hand-rolled forms**: extend the smoke-render so any page
  output containing `<form` without a `_csrf_token` fails verification,
  naming the module. Bypassing `form_for` is caught at `mix fractal.verify`,
  not in a security review.
- **The protection itself is tested, not assumed**: a framework test posts
  token-less and asserts the 403.

### Testing story

Token round-trips would make page tests miserable. Use Plug's own escape
hatch — the `:plug_skip_csrf_protection` conn private (the same mechanism
Phoenix tests use) — wrapped in a new `Fractal.Test` module: `get_page/1`,
`post_page/2`, `put_page/2`, `delete_page/1`, `fire_event/3`, plus
`with_session/2` for logged-in scenarios. Generated tests import it, replacing
the ad-hoc `defp get_page` helpers currently templated into every generated
test file.

### Deliberate non-goals

- **No server-side session store** — breaks statelessness for no current need.
  Known tradeoff to document: encrypted cookies can't be force-expired
  individually, only by key rotation. Revisit only if server-side revocation
  becomes a requirement.
- **No per-page CSRF opt-out** (`csrf: false`) — an option that exists will
  eventually be pasted by an agent into the wrong file. If API endpoints ever
  need exemption, that's a separate routing concept, not a page flag.
- **No conn exposure in the session API** — the day pages return conns, the
  1-file declarative model starts eroding.

### Optional (cheap, same directive vocabulary)

Flash messages: `{:redirect, to, flash: %{info: "Post created"}}`, rendered by
the layout, cleared after display. Sessions make these nearly free.

## Constraints

- Keep the 1-file per page structure.
- Session writes stay declarative (result directives); no `put_session`-style
  conn plumbing in pages.
- Use `Plug.Session` / `Plug.CSRFProtection` / `plug_crypto` — do not
  hand-roll session encoding or token crypto.

## Files expected to change

`lib/fractal/router.ex` (session + CSRF plugs in the pipeline),
`lib/fractal/page.ex` (assigns docs, result-directive parsing),
`lib/fractal/form.ex` (token injection), `lib/fractal/interactive.ex` (meta
tag + runtime token), `lib/fractal/layout.ex`, `lib/fractal/verify.ex` (secret
check, form-without-token check), new `lib/fractal/test.ex`, new
`lib/mix/tasks/fractal.gen.secret.ex`, `config/*.exs`, generated-test
templates in both generators, new `guides/sessions.md` plus guide/AGENTS.md
touch-ups.

## Plan first

Before changing anything, map the full plan and list the files you'll touch.
Wait for my go-ahead, then execute in one pass.

## Definition of done

- [ ] I can log in on a demo page (session persists across requests, shown in
the layout as the current user) and log out (session cleared).
- [ ] Every form and interactive event carries a CSRF token automatically; a
forged token-less POST gets a 403 whose body tells the agent how to fix it.
- [ ] `mix fractal.verify` fails on a weak/missing secret and on any page that
renders a `<form>` without a CSRF token.
- [ ] I can prompt an agent to build a page that uses the session, and it does
so using `assigns.session` and the `session:` directive without touching a
conn.
- [ ] I can run all the tests with `mix test` and they pass, using the new
`Fractal.Test` helpers.
