# Historical data operations: assessment notes (parked)

**Status: PARKED, 2026-11-18 (user decision, DECISIONS #110).** The assessment of the legacy historical
data-operations page (team shorthand L16; board issue #144) stopped here, unfinished. The legacy page
stays. These are the notes as they stood, kept so the work can resume if the rest of the console shows
it's still needed. Items marked VERIFIED were checked against the code; the rest are leads from a
read-only sweep, to verify before relying on them.

## What the feature is, in code

- One owned table: `telemetry_backfill_lifecycle_events`, an append-only event log (23 event types). There
  are no group or workflow tables: a group is a `request_group_id` inside the JSON payload, looked up
  without an index (`backfill_lifecycle_events.ex:65-106`).
- Each event is mirrored into `operational_events` in the same transaction. The work runs as background jobs
  (`telemetry_historical_data_workflow`), keyed by run id.
- Item stages: requested / approved / rejected / started / completed / failed / retried
  (`backfill_lifecycle_group.ex:290-300`). A group's state is derived (`:399-445`); there's no 'rejected'
  group state.
- Start writes the stage event and then enqueues the job, NOT in one transaction (`data_management.ex:650-652`).
- The only production writer is the legacy page (`HistoricalWorkflowActions`, six actions). About 28
  `Cadence.*` facade wrappers are used only by tests; identity decisions, single retry, replacement
  recovery, `backfill_samples` and `import_samples` are test-only.
- Size: domain about 4,050 lines, storage about 1,530, facades about 520, app and web about 1,240,
  dashboard coupling about 1,120, frontend about 2,000; about 7,800 test lines in 105 tests.

## VERIFIED: a "backfill" or "import" never fetches anything external

`WorkflowJobs.execute_job` -> `HistoricalSourceSamples.fetch` -> `HistoryStore.sample_history_result`.
The history store backends are only ets, noop, postgres and questdb (`lib/cadence/telemetry/history_store/`),
all Cadence's own stores, and the `source_*` override keys fall back to the request's own data source,
binding, realm and window (production never sets them; `workflow_jobs.ex:63-118`, `config.exs:119-129`).
So a backfill or import re-reads Cadence's stored samples for the same binding and window and writes them
back (with the request's authority, validity, revision and supersedes options).

Late-data accept and reject do the same fetch and write; reject still rewrites the data as advisory
(`late_data_policy.ex:21-34`). There's no console path for either.

## VERIFIED: a written-back row gets a new observation identity

Found in the typed-provenance round trip (api-ops, 33735faa3), confirmed by reading: the QuestDB reader never
restores `Sample.frame_ref`, and `ObservationEnvelope` (`:121-122`, `:235-259`) derives the v2 identity only
from `frame_ref`, otherwise v1. The identity reference survives only in `provenance["identity_ref"]`. So a
backfill, late-data accept or reject creates a SECOND identity (v1) beside the original v2 one: it neither
supersedes nor decides on the original observation, and it adds identity-state rows. Reachable only from the
legacy page. Fix candidate (its own change, board issue #168): restore `frame_ref` from the provenance
`identity_ref` on read (`Sample.decode_frame_ref` exists).

## Director's ruling on any rebuilt write-back (verbatim, 11-17)

"any write-back goes through B's writer, which promotes from the rebuilt provenance map; nothing writes
provenance_json directly or bypasses that writer". Pinned by the round-trip contract test (read, write back,
read: the same provenance and the same columns). This supersedes an earlier wording ('write the columns from
the struct'); the tension that wording raised (B's reader doesn't fill the Sample struct's fields) is moot.

## Leads not yet verified

- A manual 'complete' or 'failed' doesn't check the job's status, and the job then writes a second terminal
  event (no stage check in execute).
- Now's `job_outcome_unknown` Retry writes `job_outcome_resolutions`, with no lifecycle event.

## Still to read, had it continued

`docs/telemetry-data-management-design.md` §11 (the original intent); `plans/parity-ops-d.md` D3-D5 and its
parity table (`:110-131`); DECISIONS #75, #105; `ux/reviews/2026-11-16-parity-ops-d.md`;
`ux/information-architecture.md:182,205`; the late-data accept-versus-reject behaviour; api-ops on the
write-back side.
