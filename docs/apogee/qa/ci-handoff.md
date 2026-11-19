# Console e2e in CI: handoff to devops

Owner: qa. Source of truth for running the suite locally: [e2e.md](e2e.md); for the stack:
[runbook.md](runbook.md). User rule (2026-11-11): browser tests run in CI, not in agents' routine
validation.

## Timings (2026-11-11 21:40Z, 2 workers, loaded laptop, ui/apogee-spa at 291744b7)

Wall time **203.5 s** for 90 tests (82 passed, 4 failed, 4 skipped). The 4 failures were stale
assertions, fixed in 31af6c78. `sum_s` is the per-spec sum of test durations (serial cost); `max_s`
is the slowest test.

| Spec | Tests | sum_s | max_s | Data | Shared-state writes |
| --- | ---: | ---: | ---: | --- | --- |
| auth.setup.ts | 5 | 29.0 | 9.7 | real sign-in | session files only |
| setup-spacecraft | 7 | 50.2 | 12.2 | real | none |
| investigate | 7 | 43.6 | 9.4 | real history + fixtures | none |
| setup-readiness | 6 | 34.3 | 17.0 | real + fixtures | none |
| now | 9 | 32.0 | 20.0 | fixtures over real fleet | none |
| setup-detail | 6 | 26.3 | 17.8 | real | none |
| telemetry | 5 | 25.3 | 7.0 | real history | none |
| setup-stations | 4 | 22.7 | 9.0 | real | **stages + discards** a change set |
| shell | 6 | 20.5 | 4.5 | real | none |
| investigate-lifecycle | 5 | 19.1 | 4.8 | fixtures | none |
| alarms | 4 | 17.4 | 6.1 | fixtures | none |
| palette | 7 | 15.3 | 3.2 | real | none (opens Compose; drafts may autosave) |
| setup-add-spacecraft | 5 | 14.2 | 4.3 | real | **stages + discards** a change set |
| catalog-import | 4 | 13.0 | 5.5 | real | upload only with `E2E_MUTATE=1` |
| planning-requirements | 4 | 10.5 | 3.2 | real | none |
| changes | 2 | 7.3 | 5.9 | real | **stages + discards**; apply only with `E2E_MUTATE=1` |
| planning-policy | 3 | 5.7 | 2.9 | real | policy versions only with `E2E_MUTATE=1` |
| planning-submit-race | 1 | 0.6 | 0.6 | real | template version only with `E2E_MUTATE=1` |

Total serial cost is ~392 s, so with an idle CI runner at 4 workers expect roughly 1.5–2 min
after the stack is up. Raise workers with `E2E_WORKERS`.

**Fast real-server subset** (~1 min serial): `shell`, `planning-requirements`, `palette`, and
`setup-readiness -g "real server"`. Together they cover sign-in, the shell contract, a real
catalog read, the ⌘K query against the real fleet, and the Readiness endpoint (qa #43 would have
failed here). Run it as `playwright test shell planning-requirements palette setup-readiness`.

## (1) Specs that touch shared state

- **Never in CI:** run without `E2E_MUTATE`. With it unset, `changes` (apply), `catalog-import`
  (upload), `planning-policy` and `planning-submit-race` skip their permanent writes.
- **Staged change sets:** `changes`, `setup-stations` and `setup-add-spacecraft` stage a change
  set marked `QA-E2E` and discard it after each test. Each skips when someone else has changes
  staged, so they must not run concurrently against one server. Put the three in one serial
  project (`fullyParallel: false`, `workers: 1`) or on one shard.
- Everything else is read-only or uses `page.route` fixtures and can run fully parallel.

## (2) Booting the stack

Follow runbook.md "Start everything from scratch". In order:

1. **Postgres** (any 16+) with a fresh database: `CADENCE_DEV_DATABASE=<db>`,
   `mix ecto.create -r Cadence.Repo && mix ecto.migrate -r Cadence.Repo`.
2. **QuestDB** `questdb/questdb:9.4.3` with ports mapped, then `mix cadence.questdb.migrate`, with
   `CADENCE_QUESTDB_HTTP_ENDPOINT`, `CADENCE_QUESTDB_HOST` and `CADENCE_QUESTDB_PORT` set.
3. **Simulator:** `EARENDIL_SIMULATOR_PORT=4111 mix run --no-start --no-halt
   ../../dev/reflect_orbital_simulator.exs` (from `apps/cadence_simulator`). It keeps its store in
   DETS under `var/reflect_orbital/`, so start CI with a clean one.
4. **Phoenix:** `mix phx.server` from `apps/cadence_web` with the same DB and QuestDB variables,
   plus `EARENDIL_PROVIDER_URL=http://127.0.0.1:4111`, `OTEL_EXPORTER_OTLP_ENDPOINT=` (empty) and
   `PORT=4011`. It needs `apps/cadence_web/node_modules` (`npm ci`) for the LiveView sign-in page.
   Boot creates the environment admin from `CADENCE_ADMIN_EMAIL` and `CADENCE_ADMIN_PASSWORD`
   (mise.toml: `admin@example.com` / `change-me`).
5. **Console SPA:** in dev, Phoenix fetches the console `index.html` from the Vite dev server
   (:5181). For CI, ask lead whether to serve a production console build instead, which is faster
   and has no HMR. That's the one open question.
6. **Seed** (from `apps/cadence_web`, Phoenix running, all rerunnable):
   `dev/reflect_orbital_demo.exs` (500 spacecraft; needs `EARENDIL_PROVIDER_URL`), then
   `dev/apogee_qa_personas.exs`, then `dev/reflect_orbital_planning.exs`. Then
   `dev/reflect_orbital_activate.exs --single-operator` against the node (runbook step 6).
7. **Browsers:** system Chrome (`channel: "chrome"`); on CI use `npx playwright install chrome`.

Point the suite elsewhere with `BASE_URL` (default `http://127.0.0.1:4011`). `CI=1` only sets
`forbidOnly`.

## (3) Sign-in and storageState

`playwright.config.ts` has two projects. `setup` (`e2e/auth.setup.ts`) signs in each persona
through the real `/sign-in` LiveView page and saves `e2e/.auth/<persona>.json` (gitignored).
`desktop` depends on it and defaults to the admin session. The personas are `admin` (env admin)
plus `operator`, `second`, `orgAdmin` and `orgAdmin2`, all with password `apogee-qa-password`
(override with `E2E_PERSONA_PASSWORD`; admin credentials come from `CADENCE_ADMIN_*`).
`support/sign-in.ts` waits for the LiveView socket and reloads up to 3 times; `setup` retries once.
Sessions are server-side, so a Phoenix restart invalidates them: re-run `setup` after any restart.
With Playwright `--shard`, every shard runs `setup` itself (it's a dependency), which is fine.

Every test also has an auto fixture (`support/fixtures.ts`) that fails it on page errors,
console errors or app requests ≥ 400, unless the spec allows them.
