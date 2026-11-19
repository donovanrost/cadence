# Telemetry provenance storage: design (api-ops, 11-16)

Owner: **api-ops**. Reviewer: **domain** (reviewed 11-16; its changes are folded in: `binding_rule_id`
derived, `qualified_name` kept, the algorithm-row rule). Status: **option B approved
(user, via director, 11-16; DECISIONS #103); D later in a qa slot; C deferred. `CAPACITY` sized
before build (section 3, B); nothing is built yet.** This is the provenance row of the storage-growth design items (BACKLOG, "Design
items"): `provenance_json` on `telemetry_observations` is about two thirds of QuestDB's bytes.

`L` = `apps/cadence/lib/cadence`.

## Summary

- A stored observation is **3,006 bytes**; its `provenance_json` is **1,959** of them (65%).
- That JSON is **~974 characters**, and QuestDB's legacy `STRING` type stores it as UTF-16 (2 bytes
  per character), which is why it costs ~2 KB.
- **None of it is per observation.** Every field is a constant of the mission model revision, the
  point, the packet type, or the packet, and four fields repeat or rebuild other columns exactly.
- **Nothing on the read side needs it as JSON.** No QuestDB read path reads any of its fields for
  its value; one external API passes the map through whole, and one write-back path copies it.
- **Recommendation (option B):** promote the fields to their own columns (`SYMBOL`s for the
  constants, a small `VARCHAR` for the per-packet ref), drop the duplicates, rebuild the binding id
  from the model, keep the JSON only as a residual for other sample shapes, and rebuild the same map
  on read. **~63% less QuestDB growth** (3,006 → ~1,115 bytes per row), and **~74%** if the other text columns also move to `VARCHAR`
  (option D, a later step). No change to anything a user sees.

## 1. Measured on dev (read-only, sampled)

All reads were bounded: partition metadata (`table_partitions`), one 20,000-row sample from a single
5-minute window of a live contact (`observed_at in '2026-11-16T18:16;5m' limit 20000`), and counts
over the 8-minute 18:15:49Z contact window. No full-partition scans.

**Row size.** 11-14 (sealed): 2,643,696 rows, 7.4 GiB, so **3,006 bytes per row**. 11-15: 2,605,680
rows, 7.3 GiB (3,008).

**Rate.** In contact, a spacecraft writes **~145 observations per second**: EARENDIL-008 68,976 rows
in 478 s, EARENDIL-010 18,432 in 127 s. At ~14.4 observations per packet that is ~10 packets/s.

**Where the bytes are (per row, from the sample).** `STRING` = 2 bytes per character + a 4-byte
length + an 8-byte index entry; `VARCHAR` = UTF-8 with a 16-byte entry, values up to 9 bytes inline.

| Column | Avg chars | As `STRING` (today) | As `VARCHAR` |
|---|---:|---:|---:|
| `provenance_json` | 973.6 | **1,959** | 990 |
| `evidence_id` | 73 | 158 | 89 |
| `packet_id` | 71 | 154 | 87 |
| `sample_id` | 71 | 154 | 87 |
| `observation_id`, `observation_identity_id`, `idempotency_key` | 43 each | 98 each | 59 each |
| `metadata_json` | 29 | 70 | 45 |
| `point_name` | 20.9 | 54 | 37 |
| `raw_value_text` | 7.2 | 26 | 21 |

The fixed-width columns (4 timestamps, ~12 `SYMBOL`s, the typed values) are ~140 bytes.

**What `provenance_json` holds.** Every sampled row (100% of 87,408 in the contact window) is a
packet-derived observation with exactly these ten keys:

| Key | Avg chars | Distinct in sample | Scope | Notes |
|---|---:|---:|---|---|
| `binding_rule_id` | 245 | 10 | per spacecraft × packet type | **rebuildable**: `mission_model_telemetry:<revision>:spacecraft_runtime:<spacecraft_id>:<producer_id>:rule` (20,000/20,000) |
| `mission_model_revision_id` | 89 | 1 | per mission model revision | |
| `runtime_plan_id` | 85 | 1 | per runtime plan | |
| `producer_id` | 85 | 10 | per packet type (container) | |
| `semantic_id` | 85 | 144 | per point | |
| `evidence_id` | 75 | 139 | per frame | **duplicate** of the `evidence_id` column (20,000/20,000) |
| `packet_id` | 73 | 1,390 | per packet | **duplicate** of the `packet_id` column (20,000/20,000) |
| `qualified_name` | 35 | 144 | per point | equals `/parameters/` + `point_name` here (20,000/20,000) only because the simulator's model is flat; a nested XTCE import gives e.g. `/Sat/EPS/BusVoltage` with a short `point_name`. **Not derivable**; `semantic_id` is a hash of it |
| `identity_ref` | 14 | 1,390 | per packet | the v2 identity basis, e.g. `["seq",101,477]` |
| `producer_kind` | 11 | 1 | constant (`container`) | |

The key names and JSON punctuation alone are ~168 characters (~340 bytes as `STRING`) per row.

**Other shapes exist** but weren't in the window: algorithm-derived samples carry `source_update_ids`,
`trigger_sample_id` and the producer/revision/plan keys, with no binding rule or semantic id
(`L/runtime/partition_owner.ex:787-794`); smoke checks write `%{source: …}`. `source_update_ids` and
`trigger_sample_id` are genuinely per observation, and `source_update_ids` grows with the algorithm's
input count (~70 characters per id), so a many-input derived point is a heavier row.

**Caveat.** One mission model (the simulator's), whose `STRESS_TEST` packet type carries 64
parameters. The per-row provenance cost doesn't depend on packet size (every field is repeated per
row), so the percentage holds; the absolute rate (145/s) is mission-specific.

## 2. Who reads it

From a read-side survey of every QuestDB read path (file:line evidence in the review thread):

- **The one reader** is `ObservationReader.sample_from_row/1`
  (`L/telemetry/storage/questdb/observation_reader.ex:348-368`). It decodes the JSON into
  `%Sample{provenance: map}`, adds a `"storage"` sub-map **built from columns**, and leaves the
  matching struct fields (`semantic_id`, `qualified_name`, `producer_*`, `mission_model_revision_id`,
  `runtime_plan_id`) **nil**.
- **Investigate / Exploration** ("Record provenance" in Sample inspection) shows the `"storage"`
  sub-map and the `packet_id`, `evidence_id` and packet-definition **columns**. None of the ten keys.
- **Dashboards, limits recompute, point history, verifier series, point search, revision state and
  identity selection** read values, times, columns and `"storage"`. None of the ten keys.
- **External telemetry API** (`GET /api/organizations/:org/missions/:mission/telemetry/points/:id/
  {latest,history}`, `TelemetryJSON.telemetry_sample/1`) returns the whole map as
  `data[].provenance`. No frontend calls these routes; external clients might.
- **Historical backfill / import and late-data accept** read samples from QuestDB and write them
  back (`DataManagement.HistoricalSourceSamples` → `Storage.persist_samples`). The envelope copies
  `sample.provenance` verbatim (`L/telemetry/storage/observation_envelope.ex:117`), so the new row
  gets all ten keys **plus the reader's `"storage"` sub-map** (a growth bug of its own: fix it in
  any option). `to_sample` then reads six keys to fill the struct handed to the current-value store.
- **`identity_ref` is never decoded** on the read side; identity selection uses the
  `observation_identity_id` column.
- **The archives don't depend on it.** Replay re-derives samples from the **ingress** archive and
  never reads QuestDB; the protocol record archive stores packet-level provenance only.

## 3. Options

Bytes per row are computed from the measured columns above; the projection is in section 4.

### A. Same JSON, as `VARCHAR`

`ALTER TABLE telemetry_observations ALTER COLUMN provenance_json TYPE VARCHAR` (QuestDB documents the
STRING → VARCHAR conversion as lossless; `STRING` is its legacy type).

- **Saves** 969 of 1,959 bytes: row 3,006 → **2,036** (−32%).
- **Read side:** none; the column returns the same text.
- **Migration:** one statement, but it rewrites the column in every partition, so it's a slot
  operation. One community report has a WAL table going suspended after an in-place type change, so
  test it on a copy first. Alternatively, convert only once the old partitions have aged out.
- **Doesn't fix** the repetition; it halves it.

### B. Promote the fields to columns, rebuild the map on read (**recommended**)

- New columns:
  - `SYMBOL`s for `mission_model_revision_id`, `runtime_plan_id`, `producer_kind`, `producer_id`,
    `semantic_id` and `qualified_name`: 4 bytes each per row, with an explicit `CAPACITY` (see
    "Symbol cardinality" below);
  - `identity_ref VARCHAR`, about 30 bytes;
  - `binding_rule_derived BOOLEAN` (1 byte): the row's binding id is rebuilt from the model.
- Not written: the `packet_id` and `evidence_id` copies, whose columns are the source, and
  `binding_rule_id` (domain's review). Its id embeds the model revision, so as a `SYMBOL` its
  dictionary would accumulate revisions × spacecraft × packet types for the table's whole life (a
  symbol dictionary is per column and isn't pruned when partitions drop): past 500k values within a
  year of weekly revisions at 1,000 craft. It is rebuilt on read by domain's
  `Catalog.binding_rule_id(revision, spacecraft_id, producer_id)`, which owns the format and pins it
  with a test. The writer drops it only when it equals that function's result for the row, and sets
  `binding_rule_derived`; otherwise it stays in the residual JSON, so nothing is ever lost.
- **Columns are filled only from keys present in the provenance map**, never from `Sample` struct
  fields, and the reader rebuilds exactly those keys. An algorithm-derived sample has a struct
  `semantic_id` but none in its provenance, so its row gets no `semantic_id` and its API output gains
  none (pinned in the contract test with one algorithm row and one packet row).
- `provenance_json` keeps only the **residual**: keys that aren't promoted, such as algorithm
  `source_update_ids` and smoke `source`. For packet rows it is null.
- The reader rebuilds the same map from columns + residual, so the API output is byte-identical
  (pin it with a contract test). It also fills the `Sample` struct fields that are nil today.
- **Saves** ~1,890 bytes: 6 × 4 + ~30 + 1 + null residual (12) ≈ 67 bytes instead of 1,959. Row
  3,006 → **~1,115** (−63%).
- **Read side:** cheaper. Symbol reads replace a ~1 KB JSON decode per row on every history read,
  and Investigate can show the semantic id or producer without parsing.
- **Migration:**
  - `ALTER TABLE ADD COLUMN` is metadata-only and instant; existing partitions read null.
  - The writer writes both shapes from the cutover. The reader prefers the columns and falls back
    to decoding the full JSON when they're null (old rows).
  - On dev the old shape ages out under the keep-today+2 rule in three days. In a longer-retention
    deployment the fallback stays until the oldest retained partition postdates the cutover, then
    it's deleted.
  - The same migration file runs on bring-your-own QuestDB (the BYO smoke covers it).
  - Dedup is unaffected: the keys stay `(observed_at, idempotency_key)`, and `idempotency_key`'s
    digest doesn't include provenance.
- **Symbol cardinality.** Promoted values are bounded by the mission model, not by traffic, and
  size `CAPACITY` for points across ALL tenants in the table, not one mission:
  - `semantic_id` and `qualified_name`: one per distinct point name, ever. `semantic_id` is a hash
    of the kind and qualified name only (`Catalog.MissionModel.Canonical.semantic_id/2`), so it
    doesn't change with revisions and isn't mission-scoped.
  - `producer_id`'s values are container and algorithm semantic ids, equally stable; revision and
    plan grow with revisions.
  - Sized per tenant mix in "Symbol `CAPACITY`" below.

#### Symbol `CAPACITY` (sized 11-16, before build)

**Measured on dev** (Postgres catalog, exact counts on small tables; one bounded 5-minute QuestDB
window; QuestDB metadata only, no scans):

- 2 organizations, 2 missions, 5 mission model revisions in 8 days (4 + 1).
- 20 runtime plans: 4 targets per revision (command, monitoring, telemetry, algorithm). Samples
  carry the telemetry plan or the algorithm plan, so **≤ 2 plan values per revision**.
- 146 parameters and 10 containers in every revision. The two missions run the same model and
  share **all 146** semantic ids: the dictionary is keyed by name, not by tenant.
- The window has 144 distinct `point_id`s, `observable_id`s and `semantic_id`s, and 10 packet
  definitions, for 1 spacecraft. The existing per-point `SYMBOL`s are the same cardinality class as
  the new ones, and today they sit at QuestDB's default `CAPACITY` 256 with `CACHE`.

**Which tables hold which tenants:**

- **The platform-shared managed instance** (`isolation_level: :shared`, the default) holds every
  tenant's rows in one table. **This is the sizing case.**
- An org- or mission-isolated managed instance holds one tenant.
- **Bring-your-own instances must be isolated** (`customer_owned`, `org_isolated` or
  `mission_isolated`; `DataSource.require_byo_isolation_level`), so they also hold one tenant.

**What `CAPACITY` does on our QuestDB:**

- Managed instances run **9.4.3** (docker-compose, the qa runbook, CI and the chaos lab). Dev
  reports `cairo.auto.scale.symbol.capacity = true` with threshold 0.8 (`SHOW PARAMETERS`). From
  that setting's arrival in 9.1.0, a dictionary that passes 80% of its capacity is resized instead
  of slowing down. On managed instances `CAPACITY` is therefore a **starting size**: undersizing
  costs a resize, not a degraded map.
- A bring-your-own instance on QuestDB older than 9.1 has a **fixed** capacity. It holds one
  tenant, though, so the one-tenant row of the table below is its worst case.
- A dictionary is per column and is never pruned when partitions drop, so size for the table's
  life, not the retention window.

**Cardinality per column**, over the table's life:

| Column | Grows with |
|---|---|
| `semantic_id`, `qualified_name` | distinct point names across every model on the instance, plus names added or renamed by later revisions (tenants on the same model share values) |
| `producer_id` | distinct container and algorithm names, by the same rule |
| `mission_model_revision_id` | every revision ever written |
| `runtime_plan_id` | ≤ 2 × revisions |
| `producer_kind` | 2 today (`container`, `algorithm`) |

**Tenant mixes at the design's 1,000 spacecraft.** These are assumptions: no deployment measures
points per model yet, and dev's simulator has 146. Names churn by 10% a year.

| Mix | Tenants × spacecraft | Points / packet types per model | Distinct models | Revisions per model per year |
|---|---|---:|---:|---:|
| 1. One constellation | 1 × 1,000 | 20,000 / 500 | 1 | 52 |
| 2. Mid-size tenants | 20 × 50 | 5,000 / 200 | 20 | 52 |
| 3. Long tail | 200 × 5 | 1,500 / 50 | 200 | 12 |

**Year-3 dictionary sizes:**

| Mix | `semantic_id`, `qualified_name` | `producer_id` | revisions | plans |
|---|---:|---:|---:|---:|
| 1 | 26,000 | 650 | 156 | 312 |
| 2 | 130,000 | 5,200 | 3,120 | 6,240 |
| 3 | 390,000 | 13,000 | 7,200 | 14,400 |

**Chosen `CAPACITY`.** The rule is no resize through year 3 except for mix 3's per-point names,
since a resize is cheap on 9.1+ and a fixed-capacity bring-your-own instance holds one tenant:

| Column | `CAPACITY` | Cache | Year-3 headroom (resize at 0.8) |
|---|---:|---|---|
| `semantic_id` | 262,144 | `NOCACHE` | mixes 1–2 never resize (209,715 trigger); mix 3 resizes once, at ~210k names |
| `qualified_name` | 262,144 | `NOCACHE` | as `semantic_id` |
| `producer_id` | 16,384 | `CACHE` | 13,107 trigger ≥ mix 3's 13,000 |
| `mission_model_revision_id` | 16,384 | `CACHE` | 13,107 ≥ 7,200 |
| `runtime_plan_id` | 32,768 | `CACHE` | 26,214 ≥ 14,400 |
| `producer_kind` | 256 (default) | `CACHE` | — |

- **`NOCACHE` on the two per-point columns:** a cached dictionary of 10⁵ long strings lives on the
  Java heap. These columns are written per row but are never filter keys on the read paths in
  section 2.
- The other three are small and hot (one revision and plan per active model), so they stay
  cached.
- **Dictionary bytes** grow with the values, not the capacity: ~174 bytes per `semantic_id` (85
  characters, UTF-16) and ~74–124 per `qualified_name`. At 262,144 values that is ~46 MB and ≤33
  MB per instance, once, against ~214 GiB a day of rows at 1,000 spacecraft.
- **The capacity-sized hash index cost** is checked on the copy in the build's QuestDB test, not
  assumed. So is the write cost of `NOCACHE` (domain's review): ingest rows/s for `semantic_id`
  `CACHE` vs `NOCACHE` at a pass-like batch. If `NOCACHE` costs measurably, `semantic_id` goes
  `CACHE` (~46 MB of heap is acceptable on managed).
- **Past year 3** the shared dictionaries keep growing (mix 3 adds ~30k names a year from churn
  alone, plus new tenants) and are never pruned. Auto-scale covers that on managed; the real bound
  is the next table generation (D or later). B's reader keeps filtering by `point_id`, never by
  `semantic_id`, so `NOCACHE` stays off the read path.
- **Not in B (a note for D's slot):** the existing per-point `SYMBOL`s (`point_id`,
  `observable_id`, `packet_definition_id`) are still at capacity 256. Managed instances auto-scale.
  A bring-your-own instance on QuestDB before 9.1 with more than ~200 points is already past them,
  so `ALTER TABLE … ALTER COLUMN … SYMBOL CAPACITY` could ride with D.

### C. By reference (a provenance table keyed by hash)

The row keeps `identity_ref` and a `provenance_ref SYMBOL` (hash of the static part); a Cadence table
`telemetry_provenance_refs (ref, json)` holds the static part once per point × revision × spacecraft.

- **Saves** about the same as B: row ~1,080 bytes (−64%), 40 bytes per row better.
- **Read side:** every read that wants provenance needs a lookup, through an ETS cache in front of
  Postgres (a batch per distinct ref). Raw rows stop being self-describing:
  - an export or a bring-your-own reader can't interpret them without Cadence's table;
  - a missing ref means unknown provenance.
  It does fit "meaning stays in Cadence, bytes can live anywhere".
- **Migration:** as B, plus the new table and its lifecycle. Its rows must outlive every QuestDB
  partition that references them, so they're never deleted while a partition can still point at
  them.
- **Not recommended now:** the same saving as B, with a read dependency and a lifecycle to own.

### D. B plus `VARCHAR` for the other text columns (a later step)

Convert `packet_id`, `evidence_id`, `sample_id`, `observation_id`, `observation_identity_id`,
`point_name`, `metadata_json`, `raw_value_text`, `value_string` and `supersedes_observation_id` to
`VARCHAR`. `idempotency_key` stays as it is unless dedup on a `VARCHAR` key is verified.

- **Saves** another ~330 bytes: row ~1,115 → **~785** (−74% overall).
- **Read side:** none (same text).
- **Migration:** as A: a slot, after a test on a copy. Or adopt it for the next table generation.

### Considered and dropped

- **Per-packet table.** A packet table removes only the per-packet fields; the per-point fields
  (`semantic_id`, `qualified_name`) stay per row. B beats it.
- **Drop the fields outright.**
  - Dropping only the duplicates and the rebuildable `binding_rule_id` from today's JSON gives
    ~976 bytes per row.
  - Dropping the constants as well (revision, plan, producer) loses which model interpreted a value.
    That is the point of provenance, and the backfill path uses those keys.
  - Not worth it next to B, which keeps everything.

## 4. Projected growth

QuestDB only, at dev's duty cycle (the storage-growth unit: ~1,420 contact-seconds per spacecraft-day,
~24 min of contact) and ~145 rows per contact-second. This reproduces dev: 590 MiB × ~12.7
spacecraft-equivalents ≈ 7.3 GiB/day.

| | Bytes per row | Cut | Per spacecraft-day | 500 spacecraft | 1,000 spacecraft |
|---|---:|---:|---:|---:|---:|
| Today | 3,006 | — | 590 MiB | 288 GiB/day | 576 GiB/day |
| A (VARCHAR JSON) | 2,036 | 32% | 400 MiB | 195 GiB/day | 390 GiB/day |
| **B (columns, recommended)** | **~1,115** | **63%** | **~219 MiB** | **~107 GiB/day** | **~214 GiB/day** |
| C (by reference) | ~1,080 | 64% | ~212 MiB | ~104 GiB/day | ~207 GiB/day |
| D (B + VARCHAR text) | ~785 | 74% | ~154 MiB | ~75 GiB/day | ~151 GiB/day |

The table scales linearly with contact time: 2 h of contact a day is ~5×. Even after D, the row is
dominated by the hash-text ids (`packet_id`, `evidence_id`, `sample_id`, observation ids, ~430 bytes
as `VARCHAR`). Making those binary (32-byte digests) is a separate, larger identity design, not
this one.

## 5. Recommendation

1. **The write-back leak is fixed** (`91e154d0b`, landed 11-16): the backfill/late-data path no
   longer re-persists the reader's `"storage"` sub-map into `provenance_json`.
2. **Build option B**, additively, as above. It needs:
   - a QuestDB migration that adds the columns;
   - domain's `Catalog.binding_rule_id/3` and its test (the writer checks against it, the reader
     rebuilds with it);
   - writer and reader changes behind one module;
   - the backfill path writing the columns from the struct fields the reader now fills;
   - a contract test that the external API's `provenance` is unchanged, for a packet row AND an
     algorithm-derived row;
   - the reader fallback for old rows.
3. **Then D in a slot**, after a test on a copy, or with the next table generation. A on its own is
   unnecessary once B is in, because the residual JSON is null for packet rows.
4. Leave **C** for when bring-your-own storage needs Cadence-held meaning; B's columns can be turned
   into refs later without another row-shape change.

Owners if approved: api-ops (writer, reader, migration, backfill path), domain (review; the
provenance contract in the mission model), qa (the slot for D).

## DECISIONS draft (for the director; the user signs off)

> **Telemetry provenance storage.** Each stored observation's provenance (which mission model
> revision, runtime plan, packet type, point and binding produced it) is kept as typed columns
> instead of a per-row JSON document:
>
> - the model-bounded values are dictionary-encoded columns;
> - the per-packet identity ref is a small text column;
> - the copies of the packet and evidence ids are no longer stored twice, and binding ids are rebuilt
>   from the model, not stored;
> - the JSON keeps only values that have no column.
>
> Readers rebuild the same provenance, so APIs and screens are unchanged. Old rows stay readable
> until retention removes them. This cuts the time-series store's growth by about 63% (≈3.0 → 1.1 KB
> per observation, measured on dev). A later conversion of the remaining text columns to the compact
> text type (in a maintenance slot) brings it to about 74%.
>
> Already fixed separately (11-16): data re-written by backfill or late-data handling no longer
> copies read-side bookkeeping into the stored provenance.
>
> A provenance-by-reference table was considered and deferred: it saves about the same, but rows stop
> being self-describing and reads gain a lookup.
