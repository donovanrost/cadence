# First-seen identity states

Owner: domain. Status: built, measurement pending (11-17). Lead's design OK 11-17 with conditions (1)–(5); dashboards OK'd the shape diff.

## The rule

`telemetry_observation_identity_states` holds a row only for an identity something has been said about:

- **a decision** (`apply_decision`), or
- **a non-canonical sighting** (today: late data rejected as `:advisory`).

A canonical sighting of an identity with no row writes nothing. Before this change every envelope wrote or touched a row. That was about 3.6 GB a day and about 57% of Postgres growth on dev, almost all of it canonical first sightings nobody decided anything about.

An identity that has a row tracks every later sighting as before: counts, canonical promotion, latest pointers and last seen.

## Who reads the rows, and what changes for them

| Reader | Uses | Change |
|---|---|---|
| `EffectiveSelection` (history, latest values, observation reader) | rows with an explicit decision only | none |
| Dashboards `RevisionState` summary | counts, validity, warnings | counts are over rows only. Warnings are unchanged: they come only from non-canonical rows, which are still written. A frame whose identities all lack a row has no `meta.revision_state`. |
| Dashboards revision dependency (RuntimeCache invalidation) | the identity ids on the frame | Same set as before: built from the samples' identity ids, with a bare entry for an identity with no row. Fingerprint values change, so there is **one cache miss per entry after the restart**. |
| Frontend | none read `revision_state` | none |

## Write path (`ObservationIdentityStates.EnvelopeWrites`)

One `SELECT … FOR UPDATE` of the batch's existing rows, in identity order. Then, per envelope:

- **row exists:** update it as before. A row an operator decided (`decision_event_id` set) is the
  exception (#369; lead's ruling: a revision never clears a decision). The update changes only
  the counts, `latest_*` and the seen times. It keeps `canonical_*`, `validity_state`,
  `decision_reason`, `decided_at` and the payload's `decision`, which `EffectiveSelection` reads.
  A decision stands until an operator changes it. `latest_revision` > `canonical_revision` then
  shows that a newer revision arrived (U106). Tests: `observation_identity_decision_survives_test.exs`
  (each decision kind: decide, then re-sight, then a revision);
- **no row, canonical:** nothing;
- **no row, non-canonical:** `INSERT … ON CONFLICT DO NOTHING`. If another batch or a decision committed the row first, this sighting updates that row under its lock. The unique key never raises.

The per-identity `ObservationIdentityStateChanged` facts are published as before.

## Decisions on an identity with no row (`Decisions`, `DecisionSeed`)

`apply_decision` creates the row from the stored observation, then applies the decision, its decision event and its operational event. They all run in one transaction.

- **The read** is `HistoryStore.fetch_sample(PhysicalSampleQuery)`, the backend-neutral exact lookup. It runs **before** the Postgres transaction opens, and it is refused inside one.
- **The scope** is the decision context (organization, mission, realm, data source, binding, replay run) plus the item's `point_id`, `sample_id` (else `canonical_sample_id`) and `observed_at`. With `from = to = observed_at`, the QuestDB read touches one day partition. QuestDB's `observation_identity_id` is an unindexed STRING; a lookup by identity alone would scan every partition.
- **Checks:**
  - the fetched row must carry the decided identity;
  - its revision comes from the row (the storage provenance `"revision"`, which QuestDB's physical reader now selects, as ETS and Postgres already carried it);
  - the `observation_id` digest must agree with that revision. Since #161 the digest is (identity, sample, packet, revision): the evidence that carried the sample isn't part of it, so a re-batched replay is the same observation (no legacy form, DECISIONS #112).
- **Facts not stored anywhere:** `observable_id` is taken as `point_id`. No write path passes another one, and a tripwire test fails if one starts to.
- **Any error writes nothing:** a missing field, store unreachable, not found, identity or revision mismatch.

### Caller contract (API note)

Decision items should **always** send `point_id`, `sample_id` and `observed_at`: the sample's generation time, else its receipt time, ISO 8601 or a DateTime. A client can't know whether the identity already has a row. These fields are read only when it doesn't, and a decision without them on such an identity returns `{:error, {:missing_field, f}}`. There is no production caller of decisions yet (11-17).

## What is no longer kept (DECISIONS wording for lead)

> First-seen identity states (11-17, domain; lead's design OK): telemetry_observation_identity_states keeps a row only for an identity with a decision or a non-canonical sighting. A canonical sighting of an identity with no row writes nothing, so we no longer keep a per-identity row (counts, first/last seen, latest pointers) for undecided canonical sightings. For an identity whose row is created later, by a non-canonical sighting or by a decision, first_seen_at is that row's creation time, not the first sighting. Readers: EffectiveSelection is unaffected (it uses decided rows only). Dashboards revision summaries count rows only, warnings are unchanged, and the cache dependency still covers every identity on the frame. A decision on an identity without a row reads the observation (exact physical lookup, one partition, before the transaction) and creates the row; any error writes nothing.

## Tests

- `observation_identity_first_seen_test.exs`: each write branch; one locking read per batch of first sightings; decision seed (facts, revision from the row, read outside the transaction, refused inside one); nothing written on an unreachable store, mismatch or missing field; data-management items.
- `observation_identity_states_race_test.exs` (real transactions): two batches for the same new identity; a decision racing a batch.
- `runtime_cache_test.exs`: a decision on a first-seen identity invalidates the cached source result and frame.
- `physical_sample_reader_test.exs`: the row's revision is carried; a NULL revision gets no key.
- `observation_envelope_observable_tripwire_test.exs`: no envelope write path passes `observable_id`.

## Measured, A/B

Method: base 75cfd29b8 vs built b77a79f6f, in the order built, base, built. Each phase is one gated job: forced compile, then
3 runs of 1,000 timed frames after 10 warm-up frames, through the real ingest and persistence path (the #99 e2e setup, two
telemetry samples per frame). Partition 12, test DB. WAL by relfilenode from pg_waldump over each run's LSN window.

| Per 1,000 frames | Base (3 runs) | Built (6 runs) |
|---|---|---|
| Identity-state rows written | 2,000 (2,020 incl. warm-up) | 0 |
| WAL on the table (heap + 4 indexes) | 3.08–3.10 MB | 0 B |
| Statements on the table | 1,000 (one insert_all per frame) | 1,000 (one locking read per frame) |
| Time in those statements | 206–220 ms | 85–93 ms |
| All statements | 45,000 | 45,000 |
| Decode-to-commit p50 / p95 | 12.3–16.3 / 19.6–23.7 ms | 12.1–17.1 / 19.1–27.0 ms (within run-to-run noise) |

Not covered: the dev saving in bytes per day. That needs a TABLESAMPLE read of the share of undecided canonical rows (outside
slots, or by qa); the bench shows the mechanism: every canonical first sighting's row and its WAL are gone.
