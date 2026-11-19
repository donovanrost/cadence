# Fleet snapshot: moving per-spacecraft entries out of activation metadata (DECISIONS #19)

Owner: **domain**. Status: **built** (`ddc72c2e`, DECISIONS #23). Reviewer: director.

**As built, and how it differs from the draft below:**
- **Fleets are keyed by their own hash, not by request.** Metadata v2 is
  `%{"spacecraft_configuration_version" => 2, "fleet" => %{"mission_id", "sha256", "count"},
  "configuration_review" => …}`. The tables are `activation_fleets`,
  `activation_fleet_entries` (per mission, by entry hash) and `activation_fleet_members`
  (GIN on `source_endpoint_ids`). Requests, approvals and activations all resolve the same way,
  from metadata alone.
- **No backfill.** v1 rows stay readable through `Cadence.Catalog.FleetSnapshot`, and a mission
  moves to v2 on its next activation. The review evidence still lives in metadata (about 100 KB
  for a 500-spacecraft batch); the command-basis size filter accepts v1 and v2.
- **The data plane never reads the tables.** `Control.Activations` hands `TelemetryDecom` the
  resolved entries. Runtime partitions don't need the snapshot (`PartitionMetadata.project` is a
  pass-through for v2).
- **Activation transactions get a 120 s timeout,** like review. The 15 s default was too short
  for fleet admission under load.
- **Measured:** 500 + 550 fleet tests went from 274 s (one failing) to 133 s (all passing) on a
  loaded machine.
`L` = `apps/cadence/lib/cadence`.

## Where we are

**Interim fix shipped** (`740bc19c`). The fleet snapshot is now bounded separately from one
review batch:
- fleet: 2,000 spacecraft, 8,000 sources, 16 MiB;
- review batch: still 500.

A 550-spacecraft fleet activates in two batches (new test in
`test/cadence/spacecraft/fleet_configuration_activation_test.exs`). That unblocks Block 2. It is
not constellation scale.

**Why it isn't enough** (measured on `mission-earendil-demo`: 500 entries, about 4.3 KB each,
2.3 MB as text):
- **The full fleet snapshot is copied 4× per activation:** request → activation history → active
  row → operational event. It is also carried in memory in facts, the runtime spec and every
  partition context.
- **Every review rewrites the whole fleet,** even for one spacecraft (`review.ex:55` merges the
  active fleet in).
- **Every reader decodes and validates the whole map,** even when it needs one source
  (`SpacecraftModelBindings.entries/1` runs `ConfigurationInput.decode` per entry on every call;
  `entry_for_source` is a linear scan). Command authoring does this on every request.
- Admission compares the whole map twice: `approval_admission.ex:14` and
  `activations/spacecraft_configuration.ex:26`.
- The command-authoring token hashes the whole activation struct, metadata included
  (`reads/mission_models/active_basis.ex:34`).

## Proposal

**Content-addressed entries plus a small membership table per request.**

```
activation_spacecraft_entries          -- one row per distinct entry content, shared across requests
  entry_sha256 PK, organization_id, mission_id, entry jsonb, inserted_at

activation_fleet_members               -- the fleet of one activation request
  activation_request_id FK, spacecraft_id, entry_sha256 FK,
  source_endpoint_ids text[], commanding_enabled bool, catalog_revision_id,
  mission_model_revision_id, mission_model_sha256, configuration_revision_id
  PK (activation_request_id, spacecraft_id)
  GIN index on source_endpoint_ids; index (activation_request_id, commanding_enabled, mission_model_sha256)
```

- An unchanged spacecraft re-uses its entry row, so a 50-spacecraft review writes 50 new entries
  plus ~2,000 small membership rows (~0.4 MB), instead of 2,000 full entries copied 4×.
- Activation **metadata v2** keeps only:
  `%{"spacecraft_configuration_version" => 2, "fleet" => %{"count", "sha256"},
  "configuration_review" => …}`.
  `fleet.sha256` hashes the sorted `(spacecraft_id, entry_sha256)` pairs. Admission compares it
  (plus the reviewed entries) instead of deep-comparing maps. The command-authoring token covers
  it through the metadata, as today.
- Activations already point at their request (`activation_request_id`), so the active fleet is
  `members WHERE activation_request_id = active.activation_request_id`. Nothing is copied to
  activations, the active row or operational events.

**One read API**, `Cadence.Activations.Fleet` (catalog context), replaces direct metadata access:

| Function | Replaces | Query |
| --- | --- | --- |
| `entry(activation, spacecraft_id)` | `metadata["spacecraft_configurations"][id]` | PK |
| `entry_for_source(activation, source_id)` | `SpacecraftModelBindings.entry_for_source` | GIN on sources |
| `entries(activation)` / `stream(activation)` | `entries/1` (whole fleet: validation, `runtime_basis/1`, `TelemetryDecom.activation_applied`) | batched |
| `commanding_groups(activation)` | `Management.Commanding.SpacecraftCatalogs` | group by `mission_model_sha256` |
| `catalog_usage(mission)` | `reads/catalog/spacecraft_usage.ex` | members only, no entry jsonb |
| `fleet_sha256/1`, `count/1` | deep map equality | metadata |

Validation (`valid_entry?`, unique sources) runs **once, at request time**, not on every read.
Uniqueness of sources becomes a query over the members of one request.

## Migration

1. Create the tables. Backfill every request that has v1 `spacecraft_configurations`: entries
   deduplicated by content, members per request. Rewrite those requests' metadata to v2 along
   with the matching activation history rows, active rows and operational events (strip the
   snapshot, keep `fleet`). One migration, in batches.
2. Readers go through `Fleet`. For one release it still accepts v1 metadata, for rows written
   during deploy, then that path is removed.
3. **Effect on commanding:** the command-authoring token changes once, because the metadata
   shrinks, so drafts authored before the deploy must be re-validated (they fail closed with
   `command_authoring_basis_changed`). Deploy outside a commanding window.

## Cost and placement

About 20 call sites:
- `review.ex`, `active.ex`
- admission (2 modules)
- `mission_model_promotion.ex`, `control/spacecraft_model_bindings.ex`, `telemetry_decom.ex`
- `active_basis.ex`, `spacecraft_catalogs.ex`
- `reads/spacecraft/configuration.ex`, `reads/catalog/spacecraft_usage.ex`
- `management/activations.ex` (`latest_spacecraft_request` becomes a members query)
- `activation_json.ex` (serializes `fleet` instead of the snapshot)
- the runtime spec and partition metadata. Partitions only need their own source; they get it
  from `entry_for_source`.

Roughly 2–3 days with tests. The existing 500-spacecraft tests become 2,000-spacecraft tests.

## Recommendation on timing (your call)

The interim fix covers fleets up to 2,000. Change-set P2 is the first new writer of fleet
snapshots: profile and framing changes reach the runtime through activation. So I recommend doing
this **at the start of profile-routing P2, before any change-set kind produces a generation**.
That way the new writer only ever writes v2, and we don't build P2 on the v1 blob and migrate it
again later. If you'd rather have it now, as its own milestone, I'll do it next.
