# CI proposal: QuestDB integration job

Status: **proposal only**, nothing built (director via lead, 2026-11-14). Owner: devops.

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
| Covers | Schema and migrations, writer, history reader, decimation, watermark | **Ingest:** journal → processing → `Writers.QuestDB` → `HistoryStore.QuestDB`. **Verifier:** command verifiers reading samples from QuestDB (semantic-id matching #88, target-spacecraft filter #38). **Constraints:** duplicate and retried writes (DEDUP upsert vs Postgres unique error), out-of-order samples, NULLs |
| Who writes it | devops: ~½ day | Tests: api-ops (ingest) and domain (verifier, constraints), who know the two incidents; ~1–2 days of owner time. devops: config switch, job and flake tracking |

**How the P1 suite runs:** `@moduletag :questdb`, excluded by default (like `:browser`).
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

## Recommendation

Build P0 now: it's half a day, catches migration, dialect and decimation breakage on every PR,
and needs nobody else. Start P1 when api-ops and domain can write the ingest, verifier and
constraint tests. Each phase gets its own small PR.

## Related: item (1), ingest suite with the journal on and off

Separate from this job. The test env runs `ingress_journal: [enabled?: true]` and prod's default
is `false`. Once api-ops' tag or parameter lands, I'll add one parallel job (or a step in a core
shard) that reruns the tagged ingest tests with the journal off. About 100 of the 506 core test
files touch ingest, so expect ~1–2 min of job time and no added wall clock.
