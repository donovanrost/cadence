---
title: Telemetry Data Management — Design
tags: [design, telemetry, data-management, provenance, deduplication, tsdb, replay]
status: draft
created: 2026-06-16
updated: 2026-06-26
---

# Telemetry Data Management — Design

> Status: **draft / proposed.** This document captures telemetry data identity,
> provenance, duplicate handling, correction, late-arrival, quality, and storage
> semantics. Dashboards depend on these answers, but should not own them. The
> dashboard engine should surface data-management metadata and warnings; the
> telemetry data layer owns the rules.

## 1. Purpose

Define how Cadence manages telemetry observations across live ingest, archive,
replay, rehearsal, AI&T, simulation, and bring-your-own TSDB deployments.

The immediate pressure comes from dashboards and historical analysis: a chart
needs to know whether the value it is plotting is canonical, late, backfilled,
corrected, superseded, duplicated, degraded, simulated, replayed, or incomplete.
Those are data-management decisions, not widget decisions.

## 2. Problem

It is tempting to say "we deduplicate at the database." That is the wrong
abstraction.

A database uniqueness constraint can enforce an invariant after Cadence has
chosen one. It cannot decide the domain meaning of two records:

- exact duplicate of the same observation
- same packet received through two ground paths
- same packet replayed in a simulation run
- same value reprocessed under a new catalog/runtime binding
- corrected value that supersedes an earlier value
- conflicting values with the same apparent identity
- legitimate repeated samples with identical values and timestamps

The storage layer can reject, upsert, or index rows. It cannot decide which
observation is canonical for audit, which one feeds latest value, which one
belongs to replay, or which one dashboards should warn about.

## 3. Strategic Thesis

Cadence should treat telemetry data management as a domain policy layer:

> **Cadence defines observation identity, conflict policy, supersession policy,
> and projection semantics; the database enforces selected invariants and stores
> provenance.**

Storage uniqueness is a guardrail, not the policy. The data-management layer
should make duplicate and correction decisions explicit, auditable, and visible
to downstream projections.

## 4. Current State

Current telemetry samples already carry useful provenance:

- `sample_id`
- `mission_id`
- `spacecraft_id`
- `point_id` / `point_name`
- `packet_definition_id` / `packet_definition_version`
- `packet_id`
- `evidence_id`
- raw and engineering values
- `quality_state`
- `generation_time`
- `receipt_time`
- `provenance`

The current Postgres history store persists samples keyed by `sample_id`.
Historical range queries are receipt-time based. Latest/current projections use
the shared `Cadence.Telemetry.LatestProjectionOrder` policy:

```text
generation_time || receipt_time, then receipt_time, then sample_id
```

That policy is source-time-first: a late-arriving sample with an older
`generation_time` is still stored historically but does not replace the live
latest/current projection solely because its `receipt_time` is newer. This does
not yet define the durable domain model for duplicate observations, conflicting
observations, correction, supersession, source watermarks, backfills, or
multi-realm storage.

## 5. Core Concepts

### 5.1 Raw evidence

Raw evidence is the immutable ingress fact captured before interpretation:

```text
bytes arrived
  from source endpoint S
  at receipt time R
  with optional source time G
  carrying source metadata M
```

Raw evidence should remain immutable and provenance-rich. It is the audit anchor
for packet records, telemetry samples, replay inputs, and processing anomalies.

### 5.2 Observation

An observation is Cadence's domain interpretation of raw evidence into a value
for an observable at a time and scope.

For spacecraft telemetry:

```text
observable/point P
  for mission M and spacecraft S
  interpreted from packet/evidence E
  under runtime/catalog context C
  with raw value RV and engineering value EV
  at generation time G and receipt time R
```

The current `Telemetry.Sample` is the first implementation of this concept, but
the design should distinguish:

- **row identity** — the stored row id (`sample_id`)
- **observation identity** — what makes two samples candidates for "same
  observation"
- **version identity** — whether one observation supersedes another
- **provenance identity** — where/how the value was received or produced

### 5.3 Data realm

Realm separates corpora that must not silently mix:

- flight
- rehearsal
- AI&T
- simulation
- replay
- lab
- shadow ingest
- backfill/import

The same packet/point/time can exist in multiple realms. That is not a duplicate
unless a policy says those realms are comparable or mergeable.

### 5.4 Canonical projection

A canonical projection is the selected read model for an operational use:

- latest value
- historical value series
- limit evaluation source
- derived telemetry source
- dashboard frame
- replay comparison baseline

Projection policy decides what to do with duplicates, conflicts, late arrivals,
corrections, and quality states for that use.

## 6. Observation Identity And Idempotency

Cadence needs an explicit idempotency key before storage.

Candidate identity inputs:

- organization/mission
- data realm
- source endpoint
- spacecraft identity
- packet identity fields, such as APID and sequence count when available
- packet generation/source time
- packet bytes or content hash
- source evidence id
- runtime/catalog binding id
- point id
- packet entry path for repeated points or arrays

There may not be one universal identity key. The ingestion layer should allow
identity policies by protocol family and source type.

Example shape:

```elixir
%ObservationIdentity{
  identity_id: "obs_id_...",
  mission_id: "...",
  realm: :flight,
  observable_id: "tlm.hk.battery_voltage",
  spacecraft_id: "sc_001",
  source_endpoint_ref: "ksat_downlink",
  protocol_family: :space_packet,
  source_sequence: %{apid: 42, sequence_count: 1024},
  generation_time: ~U[2026-06-16 12:00:00Z],
  packet_hash: "sha256:...",
  entry_path: ["HK", "battery_voltage"]
}
```

The important design point: `sample_id` can remain a row id, but Cadence should
also compute a stable observation/idempotency key so retry, replay, alternate
path, and backfill handling is explicit.

### 6.1 Identity Contract

The long-term contract should separate three IDs that are easy to conflate:

| ID | Meaning | Stable across | Not stable across |
| --- | --- | --- | --- |
| `sample_id` | storage/read-model row identity | nothing except that row | retry, replay, correction, reprocessing |
| `observation_identity_id` | logical "same observation under same semantic context" key | retry, alternate path ingest, import/backfill, conflicting/corrected values for the same observation | semantic reprocessing, cross-realm copies |
| `idempotency_key` | write-attempt de-duplication key | retry of the same write from the same source/binding/run | alternate paths, corrections, new revisions |

For v0 spacecraft packet telemetry, `observation_identity_id` should be derived
from:

- organization and mission
- data realm
- spacecraft identity, when known
- observable identity (`observable_id` / `point_id`)
- protocol family
- source packet identity, such as APID and sequence count when available
- generation/source time when available
- packet content hash or evidence content hash
- packet entry path for repeated points or arrays
- semantic context key: catalog revision, packet definition id/version, and
  runtime/application binding identity

It should **not** include `sample_id`, `evidence_id`, `packet_id`,
`source_endpoint_ref`, `data_source_id`, raw value, or engineering value. Those
belong to provenance, write idempotency, and revision/conflict state. Excluding
source/data-source identity is what allows Cadence to recognize the same
observation received through two ground paths without discarding the provenance
of either path. Excluding value is what allows corrections and conflicts to
attach to the same observation identity instead of becoming unrelated rows.

The semantic context key is intentionally part of the observation identity for
v0. If the same packet bytes are interpreted under a different catalog/runtime
context, Cadence should treat the output as semantic reprocessing rather than an
in-place duplicate. A future `physical_observation_id` can group those semantic
versions for cross-context analysis.

### 6.2 Idempotency Key Contract

`idempotency_key` prevents accidental duplicate writes from the same producer.
It should include:

- organization, mission, realm
- data source and source binding
- source endpoint when present
- replay/import/backfill run id when present
- producer-supplied message id when available
- `sample_id` or source row id
- revision number

This makes retries cheap without hiding alternate-path duplicates, corrections,
or reprocessing. Database uniqueness can enforce this key, but it should not be
the only identity Cadence stores.

## 7. Duplicate And Conflict Classes

Cadence should classify duplicate candidates instead of treating them all as
one database collision.

| Class | Meaning | Default policy |
| --- | --- | --- |
| Exact duplicate | same evidence or same observation key and same value/provenance | idempotent no-op or coalesce |
| Alternate-path duplicate | same observation from different source endpoints/ground paths | preserve provenance; project one canonical candidate |
| Reprocessed duplicate | same raw evidence interpreted again under same semantic context | idempotent no-op if output matches |
| Semantic reprocessing | same raw evidence interpreted under new catalog/runtime context | preserve as new semantic version or analysis output |
| Correction | new value intentionally supersedes prior value | persist both; mark supersession |
| Conflict | same observation identity, incompatible values, no correction authority | persist conflict state; do not silently pick |
| Cross-realm echo | same apparent observation in flight/replay/simulation/AI&T | preserve separately; never dedup across realms by default |

This classification can happen before insertion, during ingest reconciliation,
or asynchronously through a data-management projector, but it should be modeled
as domain state.

Default v0 actions:

| Class | Persist row? | Feeds canonical history? | Feeds latest/current? | Emits durable event? |
| --- | --- | --- | --- | --- |
| Exact duplicate | optional/no-op | no new value | no | no, unless diagnostic threshold exceeded |
| Alternate-path duplicate | yes | one selected canonical value | only selected canonical value | optional source-quality/provenance event |
| Reprocessed duplicate | optional/no-op | no new value if identical | no | no |
| Semantic reprocessing | yes | only in requested semantic view | no by default | yes, for reprocess run summary |
| Correction | yes | yes, as canonical revision | yes, if selected by latest policy | yes |
| Conflict | yes | no default canonical value until resolved | no | yes |
| Cross-realm echo | yes | only in that realm | only in that realm | run/event dependent |

When Cadence cannot confidently classify a duplicate candidate, it should prefer
preserving the row as `:conflict` or `:advisory` over silently selecting a
canonical value.

## 8. Supersession And Correction

Telemetry observations should be append-friendly. Corrections should not mutate
historical facts in place unless the fact is purely a cache/projection.

Proposed model:

```elixir
%ObservationRevision{
  revision_id: "obs_rev_...",
  observation_identity_id: "obs_id_...",
  sample_id: "sample_...",
  revision_kind:
    :initial | :duplicate | :alternate_path | :correction |
    :semantic_reprocessing | :conflict,
  supersedes_sample_id: "sample_..." | nil,
  canonical?: true | false,
  reason: :higher_quality | :operator_correction | :runtime_reprocess | nil,
  decided_by: %{kind: :system | :user | :import, id: "..."},
  decided_at: DateTime.t(),
  provenance: %{...}
}
```

Only projections mutate:

- latest value changes to the selected canonical revision
- historical default queries hide superseded values unless requested
- audit queries can show all revisions
- dashboards can warn when a range includes corrections or conflicts

### 8.1 Revision State Semantics

`validity_state` is the consumer-facing state. `revision_kind` explains why the
state exists.

| `validity_state` | Meaning | Default query behavior |
| --- | --- | --- |
| `:canonical` | selected operational value for its observation identity | included |
| `:duplicate` | equivalent value already represented by another row | hidden unless audit/all-revisions |
| `:superseded` | once-canonical value replaced by an authorized correction | hidden from canonical, visible in as-recorded/all-revisions |
| `:conflict` | incompatible candidate with no resolution authority yet | hidden from canonical, warning surfaced |
| `:advisory` | imported/backfilled/comparison data not authorized for canonical use | hidden unless explicitly requested |
| `:recomputed` | derived by analysis/reprocessing under alternate semantics | only in recomputed views |

Correction authority must be explicit. A corrected row becomes `:canonical` only
when the write context or a correction workflow carries authority to supersede
the prior canonical row. Otherwise the row is `:conflict` or `:advisory`.

Supersession should be represented in both directions when the backing store can
support it:

- new row: `supersedes_observation_id` / `supersedes_sample_id`
- old row or projection: `superseded_by_observation_id`
- durable event: `correction_applied` or `correction_reverted`

Append-only TSDBs may not support updating the old row directly. In that case,
Cadence should maintain a companion revision/projection table that maps
supersession state while leaving original observations immutable.

### 8.2 Observation Identity State Projection

The first implementation uses a Postgres current-state projection,
`telemetry_observation_identity_states`, written after the physical observation
writer succeeds. QuestDB remains the append-oriented observation log; Postgres
answers the operational question "what does Cadence currently believe about this
logical observation identity?"

The projection is keyed by `observation_identity_id` and stores:

- tenant and scope: organization, mission, realm, observable, point, spacecraft
- current canonical row: `canonical_observation_id`, `canonical_sample_id`,
  `canonical_revision`
- latest seen row for audit/debug: `latest_observation_id`,
  `latest_sample_id`, `latest_revision`
- aggregate revision state: `validity_state`, canonical/duplicate/conflict/
  superseded/advisory counts
- decision metadata: `decided_at`, `decision_reason`, payload with latest
  evidence/packet/source references

V0 policy is deliberately conservative:

- `:canonical` revision 1 initializes canonical state
- higher canonical revisions promote the canonical row
- `:duplicate`, `:advisory`, and `:superseded` rows are counted but do not
  promote canonical state
- `:conflict` rows are counted and mark the identity state as conflict without
  replacing the canonical row

This is not the full correction-authority workflow. It is the projection layer
that future correction and conflict-resolution workflows will update or rebuild.

Consumers should treat the projection table as private persistence. The public
read boundary is `Cadence.Telemetry.Storage.fetch_observation_identity_state/1`
for a single identity and
`Cadence.Telemetry.Storage.list_observation_identity_states/2` for mission-
scoped queries filtered by realm, source, binding, point, observable,
spacecraft, or validity state. Dashboards should consume this domain read model
when surfacing revision/conflict badges instead of coupling widgets to raw
projection rows.

Bulk identity-state reads must also be context bounded:
`Cadence.Telemetry.Storage.fetch_observation_identity_states/2` accepts identity
ids plus organization, mission, realm, data-source, and binding filters. This
keeps dashboard frame enrichment tied to the same tenant/source context that
produced the samples rather than relying on observation identity ids as the only
isolation boundary.

Identity-state projection changes are cache-affecting data-management events.
Dashboard telemetry frames that use identity-state enrichment must carry a
revision dependency fingerprint derived from the relevant identity ids,
canonical/latest observation ids, revisions, validity state, counts, and
decision timestamps. Telemetry write/projection paths must invalidate live and
snapshot dashboard source/frame artifacts for the affected source identity and
time range so cached conflict/correction warnings cannot outlive the current
projection state.

The runtime invalidation boundary is
`Cadence.Dashboards.RuntimeInvalidation.telemetry_revision_state_changed/2`.
Projection writers and future correction/conflict-resolution workflows should
call it with organization, mission, data source, source binding, realm,
observable, and `observation_identity_id` context. Workflows that already have a
computed `telemetry_revision_dependency` should pass it as an additional filter.

V0 exposes a bounded projection command,
`Cadence.Telemetry.Storage.apply_observation_identity_decision/3`, for explicit
current-state decisions such as marking an identity canonical, conflicting,
superseded, or advisory. The command requires tenant/mission context, updates
decision metadata (`decision_reason`, `decided_at`, payload decision evidence),
records an append-only `telemetry_observation_identity_decision_events` audit
event, and emits telemetry revision-state invalidation. The projection update
and audit event commit in one transaction; if the event cannot be recorded, the
current-state projection must not change. The scoped read boundary for audit
history is
`Cadence.Telemetry.Storage.list_observation_identity_decision_events/2`.

This is still not the full correction-authority workflow. It gives Cadence a
durable event surface for operator/system decisions while leaving richer
approval, replay, and rollback semantics for the future correction workflow.

## 9. Latest-Value Semantics

"Latest" needs an explicit policy. It is not just "highest inserted row" or
"highest receipt time."

Candidate ordering dimensions:

- generation/source time
- receipt time
- processing/evaluation time
- canonical revision decision time
- quality ranking
- source priority
- realm

Working default for flight telemetry:

1. choose only canonical, non-superseded observations in the selected realm
2. order by `generation_time || receipt_time`
3. break ties by receipt time
4. break remaining ties by stable observation/sample id
5. surface a warning if a later receipt supersedes what operators previously saw

Late-arriving data makes this explicit: a sample received now with an old
generation time may affect historical charts but does not become "latest" for
the live console under the default projection policy. Backfill/correction
authority can still introduce explicit supersession rules later; those rules
must be auditable rather than implicit receipt-time side effects.

The first read-side contract is `Cadence.Telemetry.SelectionPolicy`. It
normalizes dashboard/read options into a data-management view:

- `:canonical` (default) applies `validity_state: :canonical`; missing legacy
  validity metadata is treated as canonical-compatible for local projections.
- `:as_recorded` and `:all_revisions` remove the validity-state filter so
  investigation surfaces can inspect duplicates, conflicts, superseded rows, and
  advisory data.
- an explicit `validity_state` filter takes precedence over the view.

Current-value projections must not let unresolved conflicts replace canonical
latest state. History and range readers should apply the same selection contract
so live value tiles, bounded charts, freshness probes, and latest-as-of queries
do not drift into different interpretations of "the telemetry value."

The current/latest projection write path must consume samples enriched from
`ObservationEnvelope` metadata, not raw decom output. The envelope is the point
where Cadence attaches observation id, observation identity id, validity state,
realm, source binding, data source, source endpoint, revision, and supersession
metadata. Writing current values before that enrichment would let unresolved
conflicts, advisory imports, or duplicate rows bypass the read-side
`SelectionPolicy`.

Latest/current rebuilds must use the same contract as live writes. A rebuild
from durable sample history should apply the identity-state projection and
`SelectionPolicy` to storage-enriched sample provenance before selecting the
newest row per point. Missing storage provenance is tolerated as legacy
canonical-compatible data, but rows marked as conflict, advisory, superseded, or
duplicate must not become operational latest unless a correction/decision
workflow promotes them into canonical state first.

Operator/system decisions must propagate to latest/current immediately for the
affected mission/scope/point. The durable sample row keeps its original physical
provenance, but the latest projection overlays
`telemetry_observation_identity_states` so a promoted conflict can become the
canonical latest value without mutating history. Conversely, an explicit
non-canonical decision such as `mark_conflict`, `mark_superseded`, or
`mark_advisory` removes that identity from the canonical latest view until a
later decision promotes a canonical sample again.

Canonical history reads must use the same effective-selection contract. A
dashboard chart and a latest-value tile should not disagree about which sample
is canonical after an operator decision. Investigation views such as
`:all_revisions` still return physical rows as recorded so operators can inspect
the original conflict/advisory/superseded state. Managed QuestDB raw sample
history follows this rule by reading candidate rows and applying effective
selection after row materialization. For effective-canonical raw history,
caller `limit` is a logical result limit, not the physical SQL candidate limit;
adapters may overfetch a bounded candidate window before applying selection.
If the physical candidate window is full and effective selection returns fewer
rows than requested, the adapter should report diagnostics such as physical
candidate count, logical selected count, requested logical limit, physical
candidate limit, and `candidate_window_exhausted?`. Dashboard frames should
surface this as a `:candidate_window_exhausted` warning because "no selected
rows" may mean "candidate window too shallow," not "no canonical data exists."
Native TSDB aggregates, watermarks, and BYOTSDB adapters must either implement
the same identity overlay or explicitly declare the result as a
physical/as-recorded aggregate.

Until effective aggregate materialization exists, native decimated telemetry
frames and source watermarks should declare `canonical_mode: :physical` and emit
a `:physical_aggregate_semantics` informational warning. This prevents a
dashboard from silently presenting raw effective-canonical history and native
physical aggregates as if they had identical semantics. The future target is
either post-read effective aggregation from selected samples or a TSDB-side join
or materialized projection over observation identity state. Decimated history
readers should expose both a bucket-only compatibility API and a richer result
API shaped like `{buckets, diagnostics}` so dashboards can attach aggregate
semantics, bucket counts, bucket widths, and future completeness warnings without
renaming the public contract again.

### 9.1 Backfill And Correction Interaction

Default latest/current behavior:

- authoritative correction can replace latest/current if it supersedes the
  selected canonical observation
- authoritative backfill participates in latest/current only through the normal
  latest ordering policy; an old generation time does not become current because
  import time is newer
- advisory backfill never updates latest/current
- comparison/replay/simulation backfill never updates flight latest/current
- conflict rows never update latest/current until resolved
- duplicate rows never update latest/current unless they are promoted by an
  explicit source-priority/correction decision

This gives dashboards a stable live-console rule while still allowing explicit
operator/system correction workflows to change current truth.

## 10. Historical Query Semantics

Historical queries should declare their view:

- **canonical** — default operational history; hide superseded rows, include
  canonical corrections.
- **as-recorded** — what Cadence knew at the time, before later corrections.
- **all-revisions** — audit/debug view showing duplicate/conflict/correction
  records.
- **recomputed** — analysis output from reprocessing under different
  runtime/catalog/limit context.

Dashboards should default to canonical observed history, with badges/warnings
when a range includes late arrivals, corrections, conflicts, mixed semantic
context, or incomplete source watermarks.

## 11. Backfill And Late Arrival

Backfill is not merely inserting old rows. It changes the knowledge state of the
system.

Backfill ingestion should record:

- import/backfill run id
- source corpus and realm
- source time range
- receipt/import time range
- semantic context used for interpretation
- whether backfilled observations are authoritative, advisory, or comparison
  only
- whether they may update latest/current projections

Late-arriving live data should record:

- observed generation time
- receipt time
- lateness duration
- source endpoint
- whether it updates canonical history
- whether it updates current/latest projections

These facts likely belong in the operational event model as coarse events:
backfill started/completed, late data accepted, late data rejected, correction
applied, conflict detected. Individual samples remain telemetry facts.

Current implementation note: telemetry observation identity decision events and
telemetry backfill/import lifecycle events are durable subsystem events and can
be queried by mission/source/observable or affected source-time window for
dashboard overlays. They also persist canonical `:telemetry` operational events
in the shared `operational_events` store, using source-record refs back to the
subsystem rows. The canonical telemetry storage write path now emits backfill/
import/late-data lifecycle events when writes carry a run id or explicit
lifecycle flag, including failed write attempts. A workflow-facing backfill/
import lifecycle API records request, approval, rejection, start, completion,
and failure events against the same durable event table, and a narrow workflow
runner can wrap a write operation with that event sequence.
Product-level sample backfill/import entrypoints now derive lifecycle scope
from the samples, call that runner, and persist through the canonical telemetry
storage path. Historical workflow start transitions can now enqueue a durable
background job through the existing `Cadence.Jobs` runner. The job executor
reads the selected point's source window from the configured history store,
writes the matching samples back through canonical telemetry storage with
duplicate write-outcome lifecycle rows suppressed, then records completed or
failed workflow lifecycle state with job/source diagnostics. The dashboard
lifecycle inspector can resolve the associated durable job id, status, attempt
count, and failure reason for the inspected run, and duplicate start submissions
are blocked once a job exists for that run. Failed jobs can be requeued from the
dashboard inspector without creating a second job for the run, preserving the
durable attempt count for the next execution. Failed job lifecycle events now
carry structured failure diagnostics: failure code/detail, retryability, retry
blockers, recovery action, source selector, and requested source window. The
dashboard inspector exposes those diagnostics and suppresses retry when the
request must be corrected first. Lifecycle inspectors should explain these
chains as workflows, not isolated events: current state, source identity/window,
group progress, job status, retry/correction requirements, and late-data policy
source events need to be visible together so an operator can understand why a
dashboard region changed. Non-retryable failures can now record a corrected
request as a new durable `requested` lifecycle event with a new run id,
corrected source identity/window/point fields, and evidence linking back to the
failed run/event/job. Correction request creation validates that source event in
the caller's organization/mission context, requires a correction-required failed
backfill/import event, rejects workflow mismatches, and requires the durable
telemetry historical-data workflow job for that source run to exist, match any
job id carried by the failed event payload, and still be failed. Accepted
correction requests inherit group/item/job provenance into the new requested
event. Group lifecycle summaries treat a
completed correction as the point where the original failed item is explicitly
superseded, separate from the earlier requested/started correction states.
Correction lifecycle stage transitions now use a guarded product API that
validates the correction event and its failed source before recording later
stages, instead of requiring dashboard callers to copy correction payload fields
by convention. Those transitions also re-use the ordered lifecycle stage policy
and reject stale correction requests once another correction has completed the
same failed source event. Historical workflow action eligibility is also exposed through a
data-management product API for stage transitions, group stage transitions,
retry, failed-group retry, and correction requests; dashboards decorate those
decisions for presentation instead of owning the rule vocabulary. Selected-event
single-stage transitions also use a guarded product API that fetches the source
lifecycle event, checks workflow/stage ordering through the same action policy,
and records source-event provenance on the new lifecycle event. Retry commands
are likewise product-guarded: a single retry must target the telemetry workflow
job for the selected source event's run, non-failed jobs are rejected by the same
action-policy reason vocabulary, and failed-group retry returns a blocked result
when the group has no retryable failures instead of accepting a no-op command.
Workflow
explanation summaries expose the same kind of product-owned semantic contract:
state, severity, badge, and reason are chosen by telemetry data management for
late-data policy events, retry/correction relationships, failure, completion,
and default recorded states, while dashboards render display text and detail
rows. The dashboard request path supports multi-point/bulk
source-window requests, revision decision event inspectors can submit an initial
correction-authority decision against the same observation identity, and
lifecycle event inspectors can record explicit `late_data_accepted` /
`late_data_rejected` policy events against the same source identity and
source/receipt windows. Late-data policy execution mode is a product decision:
complete point/source-window context executes against selected samples, while
incomplete context records an auditable event-only policy decision. Dashboard
commands submit that mode explicitly and do not fall back from a failed sample
execution into event-only recording. Late-data policy decisions also expose executable write
semantics: accepted late data writes as canonical, current/latest-projection-
eligible history, while rejected late data writes as advisory history and
suppresses current/latest projection refresh. Product-level late-data policy
execution can now select matching source samples by source identity and
source/receipt window, persist them through that policy contract, and record the
resulting policy lifecycle event with selected sample count and source
diagnostics. Dashboard lifecycle/event projections carry the same execution
summary as first-class fields (`selected_sample_count`, `projection_effect`,
`write_validity_state`, `record_current_values`, and `refresh_latest_value`) so
   operators can see whether a late-data decision changed canonical/current
   history directly from chart markers and event rows. The dashboard late-data
   policy control previews accept/reject projection effects before submission and
   labels whether the action can execute against selected samples or will only
   record an auditable event. Revision decision controls similarly preview whether
   an operator action will mark an identity canonical, conflict, superseded, or
   advisory before applying the correction-authority decision. Correction
   authority is also exposed as a bulk product boundary: a caller can submit
   multiple observation identities under one workflow context, while individual
   decision events retain per-item canonical candidate ids, evidence, placement
   context, and shared workflow/item metadata; invalid items return in a
	   partial-failure summary instead of forcing dashboards to hide batch outcomes.
	   Dashboard comparison-review activity can now submit those bulk decisions for
	   eligible open findings, and rendered browser coverage proves both all-success
	   and degraded partial-failure outcomes with requested/applied/failed counts;
	   richer approval, automation, and recovery workflows are still future work.

## 12. Quality And Validity

`quality_state: :good | :suspect | :bad` is a useful start, but the long-term
model needs to separate:

- source-reported quality
- transport/protocol quality
- decom/interpretation quality
- calibration quality
- staleness
- data completeness
- conflict/correction state
- operator or system validity override

Proposed frame-level vocabulary for consumers:

```text
quality_state: good | suspect | bad | unknown
validity_state: canonical | superseded | conflict | duplicate | recomputed
freshness_state: fresh | stale | gap | late | partial
source_state: nominal | degraded | recovered | unavailable
```

The exact stored schema can evolve, but downstream surfaces need stable
semantics.

Current implementation note: `ObservationEnvelope` carries
`observation_identity_id`, `observation_id`, `idempotency_key`,
`validity_state`, `revision`, and `supersedes_observation_id`, but the current
state set is still a v0 subset (`canonical`, `duplicate`, `conflict`,
`superseded`, `advisory`). Reverse supersession indexes, correction authority,
and `recomputed` views remain target-contract work.

## 13. Source Watermarks And Completeness

Dashboards and APIs need to know whether the absence of data means:

- no sample was generated
- Cadence has not received it yet
- the source is down
- the archive is still backfilling
- retention has dropped the data
- the BYO source cannot answer completeness

Each data source/binding should expose watermarks when possible:

```elixir
%SourceWatermark{
  data_source_id: "ds_...",
  realm: :flight,
  logical_source: :telemetry,
  scope: %{spacecraft_id: "sc_001"},
  complete_through: ~U[2026-06-16 12:00:00Z] | nil,
  latest_receipt_time: ~U[2026-06-16 12:00:05Z] | nil,
  retention_starts_at: ~U[2026-01-01 00:00:00Z] | nil,
  confidence: :authoritative | :best_effort | :unknown
}
```

Watermarks should travel into dashboard frames as warnings and completeness
metadata.

## 14. Storage Contract

The storage contract should separate domain policy from physical storage.

The first implementation contract should be:

```text
Telemetry.Sample
  + WriteContext        # organization, mission, realm, data source, binding
  -> ObservationEnvelope
  -> configured writer  # QuestDB managed history first
```

The envelope is the handoff point between Cadence domain policy and database
serialization. It carries:

- authoritative tenant and mission context
- data realm
- logical/source binding identity
- physical data source identity
- source endpoint / replay-run identity when applicable
- sample row identity
- observation/idempotency key
- validity/revision/supersession metadata
- provenance copied from the sample

The envelope should be produced before a TSDB write. Physical stores can then
enforce uniqueness or indexes, but they do not invent observation identity.

`Cadence.Telemetry.Storage` is the router for this write path. It groups samples
by mission, builds `WriteContext`, creates `ObservationEnvelope` records, and
dispatches them through a configured `Storage.Writer`. Storage failures are
returned to the persistence caller; they are not silently best-effort.

### 14.1 Managed store

Cadence-managed storage can enforce richer invariants:

- immutable raw evidence
- immutable observation rows
- observation identity indexes
- revision/supersession rows
- canonical projection tables
- source watermarks
- query-time decimation metadata

### 14.2 Bring-your-own TSDB

BYO storage may only provide bytes and range scans. Cadence should still own
meaning:

- query adapters map BYO rows into Cadence observation frames
- Cadence-side metadata records data source, realm, binding, and semantic
  context
- capabilities declare whether the source can expose dedup keys, watermarks,
  quality flags, correction state, and retention
- missing capabilities produce explicit warnings, not silent assumptions

BYO does not remove the need for Cadence data-management policy. It changes how
much of the policy can be enforced at ingest time versus read time.

### 14.3 Tenant and mission isolation topology

The first implementation can attach `organization_id` and `mission_id` to write
contexts, observation envelopes, source requests, and query filters. That is a
reasonable early contract because it keeps the dashboard and telemetry source
adapter explicit about tenant/mission scope.

The longer-term storage topology should not assume every tenant and mission
shares one physical TSDB. For high assurance, noisy-neighbor isolation, customer
data residency, and BYO deployments, Cadence should support stronger physical
isolation options:

- database/schema per organization
- database/schema per mission for high-value or high-volume missions
- dedicated managed TSDB instance per organization or mission
- customer-owned TSDB selected through source bindings

This does not remove tenant and mission identifiers from the domain model.
Cadence should continue carrying them in metadata for auditing, routing,
provenance, and defense in depth. The difference is that physical topology
becomes another layer of isolation rather than relying only on `WHERE
organization_id = ... AND mission_id = ...` filters.

The data source registry should therefore represent both semantic scope and
physical isolation:

- owner organization
- optional mission binding
- physical backend or customer connection
- isolation level (`shared`, `org_isolated`, `mission_isolated`, `customer_owned`)
- indirect `credentials_ref` for customer-owned/BYO sources
- realm/dataset binding policy
- capability and watermark support

The current enforceable source contract is:

- `shared` sources may be global or scoped, but every read still carries
  tenant/mission filters for defense in depth.
- `org_isolated` sources require `organization_id`; the physical backend is
  selected for that organization, even when a binding later narrows to a
  mission.
- `mission_isolated` sources require both `organization_id` and `mission_id`;
  the physical backend is selected for that mission.
- `customer_owned` sources require a customer owner, an organization, and an
  indirect credential reference; BYO TSDB sources must use this isolation level.
- source-health and connection-profile evidence include a redacted physical
  isolation profile so operators can distinguish shared-filtered reads from
  organization, mission, and customer-owned physical boundaries.

`Cadence.Control.DataSources.ManagedQuestDBProvisioning` is the first concrete operation
for managed isolated TSDB sources. It plans an organization- or mission-isolated
QuestDB data source, applies pending versioned QuestDB SQL migrations through
`SchemaMigrator`, persists the data-source projection/event, and records
redacted provisioning evidence such as isolation boundary, endpoint/topology
refs, and applied migration versions. The operation deliberately keeps raw
connection credentials and executable migration callbacks out of public plan,
event, and data-source evidence.
`Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs` is the durable execution
boundary for that operation. It enqueues a `managed_questdb_provisioning`
background job with a redacted request payload, executes provisioning through
the shared `Cadence.Jobs` runner, gets runtime-only migration credentials or
callbacks from deployment config, and uses existing job failure/retry state
instead of storing secret material in the job row.

Dashboard source adapters should remain topology-agnostic. They ask the source
registry for the binding that satisfies an org/mission/realm request; the
binding decides whether that request becomes a filtered query against a shared
store or a connection to an isolated database.

Provisioning the physical databases, schemas, or dedicated TSDB instances is a
deployment/platform concern. The dashboard contract only depends on the resolved
data source, binding, credential reference, and isolation profile; adapters must
not infer tenancy by hard-coding database names.

The current binding row should be treated as a projection, not the full audit
source. The first implementation records `data_source_binding_events` when a
source binding is registered, changed, enabled, disabled, or superseded. Those
events capture previous/current data source, dataset, realm, priority, active
interval, status, version, actor, and payload. This is the minimum provenance
needed to explain managed-vs-BYO TSDB selection during rehearsals, AI&T,
replay, and operational review without requiring the final global event spine.
Historical dashboard reads reconstruct effective source-binding intervals from
those events. Source results and frames carry the selected binding version,
event id, and interval metadata. Telemetry bounded-history reads now segment a
historical range by source-binding interval, dispatch each segment to its
resolved TSDB/dataset, and concatenate compatible frames with
`source_binding_segments` provenance. The same segmented binding provenance is
included in source facts and source-result cache keys so snapshot preflight can
reuse cached historical results only when the interval-to-source mapping still
matches. Runtime cache metadata indexes every segment's binding id, binding
event id, TSDB/data source id, realm, and dataset so source changes and historical
backfills can evict affected segmented artifacts. Requests or frame shapes that
cannot be segmented safely still return structured warnings instead of silently
merging different TSDBs or datasets.

The first implementation should fail closed for customer-owned TSDB sources.
`kind: :byo_tsdb` requires a customer owner, `customer_owned` isolation,
organization scope, and a non-empty credential reference. Source metadata may
reference non-secret connection descriptors such as `endpoint_ref`, but must not
embed passwords, API keys, tokens, or raw secret payloads. The credential
reference must resolve to an active non-secret row in the dashboard source
credential registry before the data source is persisted. The registry records
scope, owner, provider, status, version, and append-only registration/rotation
events; it does not store secret material. The first material backend is an
env-profile resolver: the credential row can point to a non-secret profile name,
and runtime configuration maps that profile to environment variable names for
endpoint/auth/header material. That gives Cadence a deployable BYO path without
persisting secrets, but it is not the final isolation story. A dedicated secrets
subsystem should eventually use the same credential reference under audit and
authorization controls to retrieve the actual connection material from Vault,
KMS, or another operator-owned backend.

### 14.4 First concrete managed TSDB: QuestDB

QuestDB is the first concrete managed TSDB target for local development and
adapter design. The initial repo-level `docker-compose.yml` provides a single
QuestDB service with:

- Web Console / REST on `9000`
- InfluxDB Line Protocol ingestion on `9009`
- Postgres wire protocol on `8812`
- minimal health server on `9003`
- persistent local data under `./var/questdb`

Cadence-managed QuestDB schema is defined with versioned SQL files under
`apps/cadence/priv/questdb/migrations`, not Ecto migrations. The local migration
entry point is:

```bash
mix cadence.questdb.migrate --plan
mix cadence.questdb.migrate
mix cadence.questdb.smoke
mix cadence.data_sources.managed_questdb_provision --plan --organization-id ORG --mission-id MISSION --data-source-id SOURCE
mix cadence.data_sources.managed_questdb_provision --apply --organization-id ORG --mission-id MISSION --data-source-id SOURCE
```

The migration task connects to QuestDB through the REST `/exec` API on port
`9000` and records applied SQL versions in a QuestDB-local
`cadence_schema_migrations` table. We use REST instead of Postgrex/PGWire for
now because Postgrex issues PostgreSQL catalog/type queries that QuestDB's
PGWire parser does not support. The smoke task applies pending migrations,
writes a synthetic telemetry observation, reads it back through
`HistoryStore.QuestDB`'s underlying reader, and fails if the round trip is not
visible.

For org/mission-isolated managed sources, the provisioning API uses the same
migrator instead of duplicating schema logic. It can be run with injected
migration executors in tests or deployment automation, then persists the
dashboard data-source row with `storage: :questdb`, redacted topology refs, and
source-isolation metadata. The durable provisioning job can wrap the same
operation when schema work should run asynchronously, while preserving a
redacted request payload and standard background-job retry/failure state. A
future ops workflow can add approval, admin UI, and provider-specific database
allocation around that job boundary. The current Mix task is the
operator/automation surface for direct plan/apply execution: it
requires an explicit `--plan` or `--apply` mode, accepts organization/mission/
source/isolation inputs plus non-secret endpoint/topology refs, never prints
password material, and exits nonzero through `Mix.raise/1` when planning,
migration, or persistence fails.

The first Cadence integration should still avoid coupling the telemetry domain
model to QuestDB-specific SQL or line protocol. QuestDB should receive
`ObservationEnvelope` rows through an adapter that declares capabilities:

- write protocol: ILP, Postgres wire, or both
- timestamp column used for primary history queries
- supported value types
- dedup/idempotency enforcement strategy
- retention support
- watermark support
- downsampling/aggregation support

The first adapter shape is split into two layers:

- `QuestDB.ObservationRow` serializes an `ObservationEnvelope` into a stable
  `telemetry_observations` insert shape.
- `QuestDB.ObservationWriter` owns the physical Postgres-wire connection and
  insert execution.
- `Storage.Writers.QuestDB` is the configured canonical managed history writer.

This keeps timestamp selection, typed value placement, and metadata JSON
encoding testable without requiring a running QuestDB instance.

The existing Postgres telemetry sample table is now a read-model/test adapter,
not the long-term history store. It remains useful until the QuestDB read source
is implemented, but the write contract is already envelope-first.

`HistoryStore.QuestDB` bridges the existing telemetry history API to the
QuestDB observations table. It uses `QuestDB.ObservationReader` to query
canonical rows by default (`validity_state = "canonical"`), filter by mission,
point, tenant, realm, data source, spacecraft, and time window, and map rows back
to `Telemetry.Sample` for compatibility. Rich dashboard reads should eventually
move to a frame/observation source that can expose validity, watermark, and
source metadata without collapsing everything into `Telemetry.Sample`.

For the first adapter, Cadence should prefer an append-oriented write path:

```text
ObservationEnvelope
  -> QuestDB serializer
  -> observations table
  -> optional projection/watermark tables
```

The open schema decision is whether one wide observations table is sufficient
for v0 or whether typed value tables are needed immediately. The domain
contract should not depend on that answer.

## 15. Relationship To Dashboards

Dashboards should consume, not own, data-management semantics.

Frames should carry enough metadata for widgets to render honestly:

- `quality_state`
- `validity_state`
- `freshness_state`
- `source_state`
- `data_realm`
- `data_source_id`
- `observation_identity_id`
- `sample_id`
- `superseded_by`
- `revision_kind`
- `watermark`
- warnings

Dashboard examples:

- show a gap when source watermarks prove data is missing
- show "partial" when completeness is unknown
- mark a chart range that contains corrected values
- keep observed history distinct from recomputed analysis
- label replay/simulation/AI&T data rather than merging it with flight

## 16. Relationship To Events

Do not emit a canonical operational event for every sample.

The operational event model should capture coarse data-management transitions:

- backfill started/completed/failed
- late data accepted/rejected
- conflict detected/resolved
- correction applied/reverted
- source watermark advanced/regressed
- data source degraded/recovered
- canonical projection rebuilt

Individual observations, revisions, and sample values remain telemetry data
facts. Timeline projections can summarize the operationally meaningful changes.

Dashboard runtime invalidations are the immediate cache/refresh consequence of
these data-management transitions. Telemetry storage writes emit
`source_watermark_changed` for live cache entries and `historical_data_changed`
for snapshot/archive cache entries through
`Cadence.Dashboards.RuntimeInvalidation.Event`. Those runtime invalidation
events are typed and observable through runtime health, but they are not a
replacement for durable operational events such as backfill completion,
correction applied, or source watermark advanced/regressed. Current backfill/
import/late-data lifecycle events and observation identity decisions now write
both the subsystem fact and the canonical operational-event envelope in one
transaction; sample-level observations remain outside the operational-event
spine.

## 17. Initial Scope

Start with the canonical write path and keep read-model replacement separate.

Recommended first slice:

1. Add the write-path envelope contract (`WriteContext` + `ObservationEnvelope`)
   and route telemetry history writes through `Cadence.Telemetry.Storage`.
2. Provide local QuestDB development plumbing through Docker Compose and
   versioned QuestDB SQL migrations.
3. Make QuestDB the configured managed history writer.
4. Keep existing Postgres reads as a temporary read-model adapter until the
   QuestDB read source exists.
5. Implement `observation_identity_id`, revision terminology, and revision
   projections in the write path.
6. Add dashboard/API vocabulary for `validity_state`, `freshness_state`, and
   source watermarks.
7. Document latest/current projection policy explicitly.
8. Keep `sample_id` as row identity and add separate observation/idempotency
   keys.
9. Implement backfill/correction authority flags and latest/current projection
   effects.

That slice gives dashboards honest metadata while moving telemetry history writes
to the intended TSDB contract.

## 18. Open Questions

1. **Identity policy plug-in shape** — how protocol/source-specific identity
   policies are registered and versioned.
2. **Latest policy exceptions** — whether any non-flight mode should override
   the default generation-time-first projection order.
3. **Correction authority source** — which systems/users/import runs can carry
   supersession authority and how that authority is audited.
4. **Conflict resolution workflow** — how conflicts move from unresolved to
   canonical/superseded, and whether operator adjudication is required.
5. **Backfill authority defaults** — which import classes are authoritative,
   advisory, or comparison-only by default.
6. **Quality vocabulary** — expand `quality_state` or add separate validity /
   freshness / source-state fields?
7. **Watermarks** — which stores can provide authoritative completeness, and how
   should BYO sources declare unknown completeness?
8. **Retention** — how do projections behave when raw observations age out but
   aggregated history remains?
9. **Reprocessing** — where do recomputed samples live, and how do they link
   back to raw evidence and original samples?
10. **Event boundary** — which data-management state changes become canonical
   operational events versus telemetry subsystem facts?

## 19. Cadence Modules Referenced

`Cadence.Ingress.RawEvidence` · `Cadence.Protocol.PacketRecord` ·
`Cadence.Telemetry.Sample` · `Cadence.Telemetry.{CurrentValueStore,HistoryStore}` ·
`Cadence.Persistence.Schemas.TelemetrySampleRow` ·
`Cadence.Projections.TelemetryLatestValues` ·
`Cadence.Limits.Event` · `Cadence.DerivedTelemetry.Sample` ·
`Cadence.Replay`.
