# Console e2e suite

Location: `frontend/apps/console/e2e/` + `frontend/apps/console/playwright.config.ts` (qa owns
both; lead owns the app's `package.json` / tsconfig wiring). Runner: `@playwright/test` 1.62.1
(same version as the workspace `playwright` catalog entry), headless system Chrome.

## Run it

Needs the live dev stack (see `runbook.md`); e2e is **not** in the workspace `test` script.
Check `uptime` first: above a 1-minute load of 16, run single specs, not the whole suite
(TEAM.md, Git).

```sh
cd frontend
corepack pnpm --filter @cadence/console test:e2e                 # whole suite (2 workers)
corepack pnpm --filter @cadence/console test:e2e now            # one spec by name
corepack pnpm --filter @cadence/console test:e2e now -g "phone"  # one test
E2E_MUTATE=1 corepack pnpm --filter @cadence/console test:e2e changes catalog-import  # writes
E2E_WORKERS=4 …                                                   # when the laptop is idle
```

**When (user, 2026-11-11).** Browser tests are not part of agents' routine validation: no runs
after a server restart, before a commit, or inside another agent's iterate-and-check loop. The
suite runs in CI (devops; `docs/apogee/qa/ci-handoff.md`), which is what catches regressions such
as qa #43 (a Readiness 500 that sat for two days). Run specs locally only while developing or
debugging the suite itself (qa), or to reproduce a specific reported bug.

Report: `frontend/apps/console/playwright-report/index.html`; traces and failure screenshots in
`test-results/` (both gitignored, as is `e2e/.auth/`).

**Writes.** By default the suite writes nothing permanent. Staged changes it creates carry the
`QA-E2E` marker and are discarded after each test, and specs skip when someone else has changes
staged. `E2E_MUTATE=1` enables the tests that create permanent records: the change-set apply
round-trip (rename EARENDIL-499 and back, r2/r3), a catalog re-import of `demo_spacecraft.yaml`,
planning-policy versions, and the K1 submit race (a template version plus, if needed, a draft).

## Personas

Sessions are saved per persona by `e2e/auth.setup.ts` (users seeded by `dev/apogee_qa_personas.exs`).
The default is `admin`; switch with `test.use({ storageState: storageStateFor("operator") })`.

| Key | User | Use for |
| --- | --- | --- |
| `admin` | env administrator (platform admin mode) | default |
| `operator` | `qa-operator@example.com`, member | capability gating (no admin actions) |
| `second` | `qa-second@example.com`, member | second operator / approver |
| `orgAdmin` | `qa-org-admin@example.com`, organization admin | admin UI without platform admin (default) |
| `orgAdmin2` | `qa-org-admin-2@example.com`, organization admin | approvals the author can't give (#38, policy versions) |

## Layout

| File | Purpose |
| --- | --- |
| `support/fixtures.ts` | `test`/`expect` with an **auto fixture that fails the test** on page errors, console errors, or app requests that fail or return ≥400. Allow expected ones with `test.use({ allowedDiagnostics: allow(/…/, /…/) })` (one RegExp: Playwright reads arrays as `[value, options]`) |
| `support/console.ts` | `openConsole(page, path)` (waits for `body[data-shell-ready]`), `missionPath`, `missionApi` (route globs), `jsonData` / `jsonProblem` |
| `support/sign-in.ts` | Real `/sign-in`; waits for LiveView to connect and reloads up to 3× (the socket can miss its 2.5 s WebSocket window on the loaded laptop) |
| `support/env.ts` | `BASE_URL`, personas, seeded demo ids/slugs |
| `support/accessibility.ts` | `expectAccessible(page, { exclude })`: axe WCAG 2.1 A/AA |
| `support/fleet.ts` | `routeDegradedNow`: real `/fleet` rows with synthetic states, plus a contract-shaped `/action-queue` from the same fleet |
| `support/alarms.ts` | `/alarms` fixture with server-side filtering (Investigate B1/B4) |
| `support/episodes.ts` | Stateful alarm-episode fixture (acknowledge/assign, injectable failures) and a read-only list fixture |
| `support/config.ts` | Change-set API helpers: stage a rename, QA-only discard, foreign-staged guard |
| `support/planning.ts` | Contact-planning helpers: `utcDay`, `plansForDay`, `bumpTemplate` (a rule change "from another tab") |

## Coverage

| Spec | Screen / journey | Data |
| --- | --- | --- |
| `shell` | Shell contract, capability-gated nav | real |
| `now` | J1 Now | fixture over real fleet + action queue |
| `investigate`, `investigate-lifecycle` | J2 Investigate, alarm lifecycle (decision 6) | real history; alarm + episode fixtures |
| `alarms` | Ops › Alarms (episodes) | episode fixture |
| `palette` | J5 ⌘K query line, chords | real |
| `telemetry` | Telemetry explore | real history |
| `setup-readiness` | S1 Readiness | real + fixtures |
| `setup-spacecraft`, `setup-detail`, `setup-add-spacecraft` | S2 directory, detail, wizard; profiles; catalog index | real |
| `catalog-import` | S3 import | real (upload opt-in) |
| `changes`, `setup-stations` | Change sets (decision 1), stations edit/add | real, staged then discarded (apply opt-in) |
| `planning-requirements`, `planning-policy` | CP1 contact rules, CP2 planning policy | real (policy versions opt-in) |
| `planning-submit-race` | K1 submit loses a race with a template change: 409 `plan_superseded`, nothing booked | real, opt-in (saves a template version, which supersedes every open draft, so it skips while another day has a live draft; drafts today+4 if needed) |

## Conventions

- Import `test`/`expect` from `./support/fixtures.ts`, not `@playwright/test`, so the
  diagnostics guard applies.
- Locate by role and accessible name. If a control can't be found that way, that's an accessibility
  bug: file it rather than adding a `data-testid`.
- Assert on seeded real data (Reflect Orbital / Earendil), never on canvas sample values.
- Each journey spec covers: happy path, empty state, error state (`page.route` → 4xx/5xx),
  keyboard completion of the primary action, and `expectAccessible`.
- A known defect is a `test.fail(true, "qa issue #N: …")` test; it flips (and fails loudly) when
  fixed, which is the signal to remove the marker and close the issue.

## Shell contract (agreed with lead; see docs/apogee/ARCHITECTURE.md)

1. `/console` signed out → redirect to `/sign-in`.
2. Signed in, `/console` renders a `banner` landmark showing the current org **and** mission names
   (takeover routes show them in the takeover header instead, ux U19).
3. A labelled `navigation`, one `main`, exactly one `h1` per screen.
4. Any `/console/*` path returns 200 + the SPA index on full reload.
5. No console errors and no app request ≥400 on load.
6. axe WCAG 2.1 AA clean.
