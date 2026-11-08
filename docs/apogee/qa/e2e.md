# Console e2e suite

Location: `frontend/apps/console/e2e/` + `frontend/apps/console/playwright.config.ts` (qa owns
both; lead owns the app's `package.json` / tsconfig wiring). Runner: `@playwright/test` 1.62.1
(same version as the workspace `playwright` catalog entry), headless system Chrome.

## Run it

Needs the live dev server (see `runbook.md`); e2e is **not** in the workspace `test` script.

```sh
cd frontend
corepack pnpm --filter @cadence/console test:e2e            # whole suite
corepack pnpm --filter @cadence/console test:e2e shell     # one spec by name
BASE_URL=http://127.0.0.1:4001 corepack pnpm --filter @cadence/console test:e2e   # other server
```

Report: `frontend/apps/console/playwright-report/index.html`; traces and failure screenshots
in `test-results/` (both gitignored, as is `e2e/.auth/`).

## Layout

| File | Purpose |
| --- | --- |
| `e2e/auth.setup.ts` | Signs in once through the real `/sign-in` page; saves `e2e/.auth/admin.json` for the other tests |
| `e2e/support/env.ts` | `BASE_URL`, admin credentials (env, falling back to the `mise.toml` dev values), seeded demo ids |
| `e2e/support/fixtures.ts` | `test`/`expect` with an **auto fixture that fails the test** on page errors, console errors, or app requests that fail or return ≥400. Opt out per test with `test.use({ allowedDiagnostics: [/pattern/] })` |
| `e2e/support/console.ts` | `openConsole(page, path)`: goto + wait for `body[data-shell-ready]` (the boot screen also has an `h1`, so never assert before it) |
| `e2e/support/accessibility.ts` | `expectAccessible(page)`: axe WCAG 2.1 A/AA scan (contrast, names, roles) |
| `e2e/<journey>.e2e.ts` | One spec per journey (shell, J1 Now, J2 Investigate, …, S1–S5, C1–C3, K0–K3) |

Always import `test`/`expect` from `./support/fixtures.ts`, not `@playwright/test`, so the
diagnostics guard applies.

## Conventions

- Locate by role and accessible name (`getByRole("button", { name: "Approve" })`). If a
  control can't be found that way, that's an accessibility bug, so file it rather than adding a
  `data-testid`.
- Assert on seeded real data (Reflect Orbital / Earendil), never on design-canvas sample values.
- Each journey spec covers: happy path, empty state, error state (route the API to fail with
  `page.route`), keyboard-only completion of the primary action, and `expectAccessible`.
- Primary actions are checked for ≥44px targets (`boundingBox()`), and status is checked for
  a text equivalent (not color alone).
- Tests that mutate data use their own uniquely named records and clean up, because the dev DB is
  shared (see `runbook.md`).

## Shell contract (agreed with lead; see docs/apogee/ARCHITECTURE.md)

1. `/console` signed out → redirect to `/sign-in`.
2. Signed in, `/console` renders a `banner` landmark showing the current org **and** mission names.
3. A labelled `navigation`, one `main`, exactly one `h1` per screen.
4. Any `/console/*` path returns 200 + the SPA index on full reload.
5. No console errors and no app request ≥400 on load.
6. axe WCAG 2.1 AA clean.
