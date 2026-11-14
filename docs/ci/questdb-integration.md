# CI proposal: QuestDB integration job

Status: **P0 built** (`questdb-integration` in `ci.yml`, outside ci-ok for its first clean week).
P1 is approved in principle; lead schedules it after api-ops' and domain's current fixes (BACKLOG).
Director, 2026-11-14. Owner: devops.

## Why

Production writes and reads telemetry through QuestDB, but the test env swaps every telemetry
store for Postgres (`apps/cadence/config/test.exs`): `Writers.PostgresReadModel`,
`HistoryStore.Postgres`, `CurrentValueStore.Postgres`, and the Postgres ingress and
protocol archives. No test opens a socket to a real QuestDB; the QuestDB-flavoured tests stub
`exec_fun`/`write_fun` (docs/ci/plan.md, "QuestDB: not needed for phases 1–3"). So anything that
behaves differently in QuestDB reaches qa's live `:4011` or production first. The director counts
two incidents so far. The gaps include:

- **Constraints:** Postgres enforces unique keys and NOT NULL. QuestDB has none; the only "uniqueness"
  is `DEDUP UPSERT KEYS(observed_at, idempotency_key)` on a WAL table
  (`priv/questdb/migrations/20260617…`, `…20260627…`), which *replaces* a row instead of failing.
- **Visibility:** WAL writes become readable asynchronously. Postgres reads its own write
  immediately, so a read-after-write that passes in tests can miss in production (the existing
  smoke already polls for this: `Smoke.read_back/3`).
- **SQL dialect and functions:** decimation (`SAMPLE BY`), watermarks, timestamp precision,
  and the `/exec` REST shape. These are covered today only by stubs.

## Proposal

One new job, `questdb-integration`, in `ci.yml`, in two phases.

| | P0: smoke (devops alone) | P1: tagged suite (with owners) |
| --- | --- | --- |
| Service | `questdb/questdb:9.4.3` (same pin as `docker-compose.yml`), health on :9003 | same |
| Runs | `mix cadence.questdb.migrate`, then `mix cadence.questdb.smoke` (migrations via `/exec`; write one observation; read history, native decimation and watermark; fails if not visible) | P0 + `mix test --only questdb` |
| Covers | Schema and migrations, writer, history reader, decimation, watermark | **Ingest:** journal → processing → `Writers.QuestDB`. **History and plot reads:** `HistoryStore.QuestDB` and the dashboard reads behind it. **Constraint check:** today it reads Postgres samples, which are empty in prod-like setups; duplicate and retried writes (DEDUP upsert vs a Postgres unique error), out-of-order samples, NULLs. (Command verifiers read in-process samples, not QuestDB: domain's analysis, via lead.) |
| Who writes it | devops: ~½ day | Tests: api-ops (ingest) and domain (reads, constraint check), who know the two incidents; ~1–2 days of owner time. devops: job and flake tracking |

**How the P1 suite runs:** `@moduletag :questdb` (the job's grep gate looks for exactly
`@moduletag :questdb` or `@tag :questdb`). `apps/cadence/test/test_helper.exs` excludes it by
default, so tagged tests skip `test-core` and run in this job with no workflow change. The job sets
`CADENCE_QUESTDB_HTTP_ENDPOINT`/`_HOST`/`_PORT` and has a Postgres service.
It's `async: false` and points `telemetry_storage`/`telemetry_history_store` at the QuestDB
modules in setup, restoring them on exit. Postgres stays on the sandbox. QuestDB has no
transactions, so tests isolate with unique org, mission and point ids per test. The container is
thrown away after each run, so there's no cleanup. Every read-after-write uses bounded polling
(like `Smoke.read_back/3`), never a fixed sleep.

## Cost and time

- **Money: $0.** The repo is public, so standard GitHub-hosted runners are free.
- **Wall clock: about +0 minutes.** It runs in parallel, and the critical path is still the
  browser shards (~4–5 min).
  - The job itself takes ~2½–3½ min: warm `setup-cadence` ~60–90 s (core shards take 116–173 s
    in total today), QuestDB pull and health check ~15–25 s, migrate + smoke ~10 s, P1 suite an
    estimated 30–90 s.
- **Concurrency is the real cost.** A full PR run already has 17 jobs (core×4, web×2,
  browser×2 and the rest). This makes 18. GitHub's Free plan caps an account at 20 concurrent
  jobs, so two overlapping PR runs already queue, and this adds a little to that. (I haven't
  confirmed which plan the account is on; on Pro the cap is 40.)
- **Flake risk: medium, from WAL visibility.** It's mitigated by polling, and the job stays
  **outside ci-ok** for its first clean week, tracked like the browser shards, then joins.

## Decision (director, 2026-11-14)

P0 is built now, outside ci-ok for a clean week. P1 waits for the owners. Concurrency is fine at 18
jobs; if runs ever queue behind the 20-job cap, devops reports it and we merge jobs.

## Related: item (1), ingest suite with the journal on and off

Separate from this job. The test env runs `ingress_journal: [enabled?: true]` and prod's default
is `false`. api-ops' planned shape (names final when it lands, after their ingest fix):
`@moduletag :ingest_journal_matrix`, with the journal toggled at boot by
`CADENCE_TEST_INGRESS_JOURNAL=off|on` (default on) in `apps/cadence/config/test.exs`. Then CI adds a
parallel rerun: `CADENCE_TEST_INGRESS_JOURNAL=off mix test --only ingest_journal_matrix`. About 100 of the 506 core test
files touch ingest, so expect ~1–2 min of job time and no added wall clock.
