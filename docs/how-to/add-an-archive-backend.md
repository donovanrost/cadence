---
title: Add an Archive Backend
tags: [how-to, developer, storage, archive, replay]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Add an Archive Backend

This guide describes how to add a new archive backend for high-rate append-only
data in Cadence.

Use this when you need a new backing store for:

- raw ingress evidence
- protocol packet records
- protocol transfer-frame records

The current runtime defaults are filesystem-backed archives with lightweight
Postgres indexes. Tests use Postgres compatibility backends.

## 1. Choose the correct archive boundary

Cadence currently has two archive behaviors:

- [`Cadence.IngressArchive`](../../apps/cadence/lib/cadence/ingress_archive.ex)
- [`Cadence.Protocol.RecordArchive`](../../apps/cadence/lib/cadence/protocol/record_archive.ex)

Use `Cadence.IngressArchive` when the unit of retention is raw ingress
evidence.

Use `Cadence.Protocol.RecordArchive` when the unit of retention is decoded
packet or transfer-frame record data.

Do not create a new archive abstraction unless the existing ones are a poor fit
for the data shape.

## 2. Decide whether you are building a runtime backend or a compatibility backend

Cadence currently has two backend styles:

- runtime archive backends
- compatibility backends for tests or transitional flows

Examples:

- [`Cadence.IngressArchive.FileSystem`](../../apps/cadence/lib/cadence/ingress_archive/filesystem.ex)
- [`Cadence.IngressArchive.Postgres`](../../apps/cadence/lib/cadence/ingress_archive/postgres.ex)
- [`Cadence.Protocol.RecordArchive.FileSystem`](../../apps/cadence/lib/cadence/protocol/record_archive/filesystem.ex)

Use a runtime backend when the goal is scalable retention outside OLTP
Postgres.

Use a compatibility backend when you need simple deterministic test behavior or
transaction-friendly compatibility with older code paths.

## 3. Implement the behavior, not just the write path

Archive backends are not just "write here" abstractions. They are also replay
and observability seams.

For ingress archives, implement:

- `child_spec/1`
- `persist_raw_evidence_multi/2`
- `persist_raw_evidence/1`
- `fetch_raw_evidences/2`
- `flush/1`
- `reset/0`
- `stats/1`
- `reset_stats/1`

For protocol record archives, implement:

- `child_spec/1`
- `persist_records_multi/4`
- `persist_records/3`
- `fetch_packet_records/2`
- `fetch_transfer_frame_records/2`
- `flush/1`
- `reset/0`
- `stats/1`
- `reset_stats/1`

If your backend supports efficient batch writes, also implement the optional
batch helpers used by the boundary modules.

## 4. Keep replay in mind from the beginning

Archive backends are part of the replay model, not just retention.

That means a backend should normally provide:

- durable segment or object storage
- lightweight discovery/index rows or another efficient lookup mechanism
- scope filtering by mission and time
- filtering by evidence id, source ref, or realized contact when applicable

The current filesystem backends do this by:

- writing segment files
- storing lightweight Postgres index rows
- reading back through replay scopes

That is a good default shape for object-store-backed designs too.

## 5. Keep the hot path async

Runtime archive backends should not drag heavy storage work back onto the
ordered ingress lane.

The current design is:

- executor emits processed batches
- projector performs async archive writes
- archive backend buffers and flushes on its own worker

That means the backend should prefer:

- batched writes
- flush intervals or flush-count thresholds
- explicit `stats/1` for backlog visibility

Avoid designs that require one synchronous remote write per ingress message.

## 6. Provide real stats

Archive backends are operational infrastructure. They need first-class stats.

The current archive stats shape includes:

- `queue_depth`
- `oldest_buffered_age_ms`
- `flush_count`
- `flush_failure_count`
- `last_flush_error`
- `flushed_count`
- `segment_count`
- `flush_total_us`
- `avg_flush_us`
- `flushed_bytes_total`
- `avg_segment_bytes`

If a backend cannot provide something meaningful, return the empty/default
value. Do not omit the field shape.

## 7. Add the backend to config

Backends are selected through application config.

Current defaults in [`config/config.exs`](../../config/config.exs):

- `:ingress_archive` -> filesystem
- `:protocol_record_archive` -> filesystem
- `:telemetry_current_value_store` -> ETS
- `:telemetry_history_store` -> Noop

That means a new backend should be selectable with the same config pattern:

```elixir
config :cadence,
  ingress_archive: [
    module: MyArchiveBackend,
    ...
  ]
```

or:

```elixir
config :cadence,
  protocol_record_archive: [
    module: MyProtocolArchiveBackend,
    ...
  ]
```

## 8. Make sure the application supervisor can start it

`Cadence.Application` starts archive children through the behavior modules:

- `Cadence.IngressArchive.child_spec()`
- `Cadence.Protocol.RecordArchive.child_spec()`

If your backend needs a worker process, return a real child spec.

If it is stateless, return `nil`.

That keeps the application startup path uniform.

## 9. Test four things

At minimum, cover:

- enqueue or persist behavior
- flush behavior
- replay fetch behavior
- stats and reset behavior

Reference tests:

- [`ingress archive filesystem tests`](../../apps/cadence/test/cadence/ingress_archive/filesystem_test.exs)
- [`protocol archive filesystem tests`](../../apps/cadence/test/cadence/protocol/record_archive/filesystem_test.exs)

## 10. Prefer archive + index over large OLTP tables

If you are unsure about backend shape, prefer:

- durable archive object or segment
- lightweight discovery index

over:

- a large always-on OLTP rowset in Postgres

That is the storage direction the current architecture is moving toward.

## Checklist

- correct archive behavior chosen
- runtime vs compatibility goal is explicit
- write, fetch, flush, reset, and stats implemented
- replay scope works
- hot path remains async
- backend is selectable through config
- child spec integrates with `Cadence.Application`
- tests cover write, flush, fetch, and stats
