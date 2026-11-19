# Mission-model overhaul: phased build plan (DECISIONS #92, ADR-020 phases 1-6)

domain (technical lead), 2026-11-19, for the director, cc lead. The overhaul is the top build
priority as of 11-19 ~20:2xZ (the user, via the director).

The director's questions and the short answers:

| Question | Answer |
|---|---|
| (a) Which phase removes the most DB load soonest? | **Phase 1**, built as DECISIONS #94/#96 (one semantic snapshot per partition every 60 s, no per-commit log). It removes about **1.25 GB/day** of writes on dev, about 99% of that stream. **Phase 4 step 1** comes next: about 14 MB and ~15,500 statements per generation, in bursts. Phases 2, 3, 5 and 6 remove almost no load on dev today. |
| (b) Before figures on dev | Section 1. Measured 11-19 20:32-20:33Z: catalog reads plus sampled reads, qa's OK. |
| (c) Dependencies; does phase 2 need #99? | **Phase 2 doesn't need #99**; it builds on develop. **Phase 1 does need #99** (board #155): replaying from a 60 s snapshot repeats monitoring effects, which is what #99's deterministic ids are for. Phase 1 builds on `domain/replay-ids` now and merges after #155. Section 3. |
| (d) Issue breakdown | Section 5, under E2 #208, Squad = Mission Model & Spacecraft. |
| Breaks old dev data? Group the storage-breaking parts? | **No phase needs the dev reset.** Each one either keeps old rows readable or migrates them one-to-one. None of them can merge by ~11-22 anyway, so the reset goes ahead with #155, #171, #161/#162 and whatever has merged. Section 4. |

## 1. Before figures (dev, `cadence_apogee_dev`, 11-19)

Statistics accumulated since **2026-11-14 21:22Z**, about 4.96 days and 189 realized contacts. All
reads were read-only with a 60 s statement timeout; the slowest took 0.29 s. Scripts and raw output:
domain's scratch `mm-before/` (catalog.sh, sample1.sh, sample2.sh).

### Steady writes (per pass and per day)

| Table | Inserts since reset | Per day | Per realized contact | Row size | What it is | Overhaul phase |
|---|---|---|---|---|---|---|
| `semantic_runtime_commits` | 88,873 (+497,665 deletes) | ~17,900 | ~470 | **~70 KB**: input 17.8 + result 28.4 + state 24.0 KB (newest 500, 2 partitions, ~70 commits/min) | one row per runtime commit, holding the full partition state each time | **1** (#94) |
| `semantic_runtime_checkpoints` | 88,863 updates on 48 rows | ~17,900 | ~470 | small, but each update hashes the full 24 KB state | a per-commit checkpoint pointer | **1** (#94) |
| `telemetry_observation_identity_states` | 12,951,936 | ~2.6 M | ~68,500 | ~1.08 KB → ~0.6 KB | per observation | not the overhaul: #359 (built; retention dry → live) |
| `protocol_archive_record_entries` | 2,068,712 | ~417 k | ~10,900 | ~2.3 KB | the archive | no |
| `operational_events` | 98,568 | ~19,900 | ~520 | **~2.5 KB** for `source_watermark_advanced` since 11-16 (newest 500); 24 KB before f3bebae6b | watermark events | no (see below) |
| `data_source_watermark_events` | 88,530 | ~17,800 | ~470 | ~0.7 KB since 11-16 (newest 500) | watermark history | no (see below) |

**About 1.25 GB/day** of `semantic_runtime_commits` writes (88,873 × ~70 KB over 4.96 days),
retired later, so it is written and deleted rather than kept. DECISIONS #96's own estimate was
~99 MB per craft-day today against ~0.55 MB per craft-day with snapshots.

### Per generation (bursts)

| Store | Per generation at 500 craft | On dev now | Overhaul phase |
|---|---|---|---|
| `governed_capability_instances` + `governed_binding_rules` | **10,000 rows, ~14 MB** (craft × packet) | 4 versions, 20,000 + 20,000 rows, 60 MB, never pruned; 1 generation since 11-14 | **4** step 1 |
| statements in the apply transaction | **~15,500** (31 per craft; 20 are the rows above) | the 11-15 step-4 apply hit the 120 s limit twice | **4** steps 1-2 |
| `spacecraft_configuration_revisions` | 500 rows (~550 B documents) | 1,500 rows | **4** step 2 |
| `spacecraft_application_bindings` | 500 updates | 501 rows, 1,000 updates | **4** step 3 |
| activation fleet entries and members | content-addressed, deduplicated already | 1,506 + 3,500 rows | unchanged |
| runtime reconciler | hydrates all 10,000 rows per activation | - | **4** step 4 |

At 2,000 craft, which the fleet snapshot allows (DECISIONS #23), that is 40,000 rows and ~56 MB per
generation.

### The side stores (phase 3)

`governed_limit_definitions`, `governed_derived_telemetry_definitions`, their lifecycle, latest-value
and evaluation-run tables, `derived_telemetry_samples` and `alarm_episodes` all hold **0 rows** on
dev. `Limits.start_evaluate` and `DerivedTelemetry.start_evaluate` have **no product caller**, only
tests (`limits.ex:229`, `derived_telemetry.ex:31`). Retiring them removes no DB load on dev. Its
value is correctness: one evaluator, compile-time reference checks, and ux's monitoring lane.

### Outside the overhaul

- **Watermark events (corrected 11-19 ~21:00Z).** The first version of this plan said these were
  ~345 MB/day and that DECISIONS #101's trim wasn't built. Both were wrong.
  - The trim landed 11-16 (f3bebae6b; fe-ops found it). My whole-table sample mixed 24 KB rows from
    before it with 2.5 KB rows from after.
  - Measured on post-trim rows only (newest 500 of each, 11-19 19:36-19:43Z, ~18.5k events/day):
    - `source_watermark_advanced` events are 2,477 B, about 46 MB/day;
    - `data_source_watermark_events` rows are 680 B, about 12 MB/day.
  - qa's own post-trim sample came to ~45 MB/day.
  - The rest of #101's trim would save ~13 MB/day, under lead's 50 MB/day bar, so #441 is parked
    behind #243 (lead, fe-ops).
- **The identity states** are #359: built, dry on dev, live after qa's comparison.

## 2. The phases, in build order

Each phase ships in slices. Each slice is a PR with failing-first tests and the usual reviews.
api-ops reviews every runtime and plan-id change; mms-security threat-models the composition and
binding records.

### Phase 1: runtime identity and persistence (the biggest load win)

**1a. Semantic snapshots (DECISIONS #94/#96).** Decided 11-15, not built.
- A `semantic_runtime_snapshots` row per partition, written every 60 s, at end of pass and at
  shutdown. It holds `latest`, algorithm memory, monitoring state, timers and the input position.
- Recovery restores the snapshot and replays the journal from its position. #99's deterministic ids
  make the repeated effects insert-or-get.
- No per-commit log: `semantic_runtime_commits` stops being written. The retention job and
  `CommitRetirement` go, and the table is dropped once nothing reads it.
- The idempotent-retry and timer-projection uses of `result_term` (`store.ex:348-356`, `:517-546`)
  move to the snapshot and the effect ids. The divergence check (`verify_replay`) becomes #99's
  tripwire on replayed effects.
- The live UI's ETS current-value store is seeded from the snapshot's `latest` (#96).
- **Load:** ~470 × 70 KB per pass becomes one ~24 KB snapshot per active partition per minute.
  About 99% less (1.25 GB/day → ~15 MB/day on dev's pattern), plus the per-commit checkpoint upsert
  and its full-state hash.

**1b. Plan ids and runtime identity independent of the revision id.**
- Today `plan_id = content_id({target, …, revision_id, …})` (`runtime_plan.ex:41-54`), and the
  runtime basis hashes the revision id (`mission_runtime_spec.ex:283-301`). So every model change
  starts each partition's state empty (`monitoring_seed.ex:3-5`).
- With plan ids from the plan's content (and the snapshot keyed by the partition, not the basis,
  `recovery-from-archive.md:166-174`), state carries across a revision when parameter and policy
  identities survive.
- That matters for phase 3: a limit change would otherwise reset every partition's state.
- **Load:** none directly. It removes the empty restart after every activation.

**Depends on:** #155 (#99) merged, for 1a's replay safety. 1a builds on `domain/replay-ids` now.
1b after 1a.
**Who:** domain builds 1a and 1b; api-ops reviews; qa runs a crash-and-restart post-check in a slot.

### Phase 2: composition (the enabler)
- `MissionModels.compose/4` (`mission_models.ex:69-76`, no product caller today) wired into revision
  building: effective revision = the mission's imported layers + its authored layers.
- Imports mounted under subtrees. Today both importers emit a root `"/"` `:add`, so the second import
  hits `MM_DUPLICATE_IDENTITY` and is silently dropped (`compiler.ex:95-114, 395-399`).
- A **mission composition record** that profiles pin, in place of a catalog revision. The catalog
  revision stays as import provenance.
- **The model gate re-keyed.** `RevisionDecisions.approve` requires a catalog row naming the revision
  (`:mission_model_revision_not_in_catalog`), and the comparison baseline is catalog-keyed
  (`model_approval_gate.ex:75-88`). Both move to the composition. Composed revisions get the
  addendum's rule: an imported composition already approved, plus an approved authored layer, is
  approved.
- **Load:** none; it unblocks phases 3 and 4b.
- **Depends on:** nothing unlanded. **Who:** domain designs the record and the gate change;
  mms-engineer builds the import mounting and the profile pin; mms-security threat-models the
  composition record; api for the profile and catalog API.

### Phase 3: limits, derived telemetry and alarms as authored layers
- Change-set kinds in a **monitoring lane** (the addendum's lanes; ux's U108, PR #438).
- Applying a set recompiles one effective revision per imported composition in use (2 on dev) and
  activates them in one generation.
- One live evaluator (the model's monitoring and algorithm plans).
- The side stores migrate once with no dual-write. They're empty on dev, so this is a code
  migration only. Then the stores, the evaluators and the two #77 kinds are retired.
- Acceptance: a dangling reference after a rename is a compile-time error.
- **Depends on:** phase 2 (authored layers), and 1b (so a monitoring change doesn't empty partition
  state). **Who:** domain plus mms-engineer; ux (U108); fe-setup (editors); api (the monitoring-lane
  API).

### Phase 4: stop per-craft materialization (`config-materialization-model.md`)
- **4a, storage only:** binding-set versions stored as content-addressed artifacts plus membership,
  behind `Governance.fetch_binding_set`, which expands to the identical struct. Proof:
  `expand(compress(v)) == v` for every stored version (a dev check in a slot). Readers don't change.
  It removes ~14 MB and ~10,000 inserts per generation, 20 of the 31 statements per craft.
  **Depends on: nothing.** It can start now, in parallel with phase 1.
- **4b:** per-craft heads and append-only assignment history in place of derived revision documents.
  Drafts and Review resolve. **After phase 2**, so the head pins the composition, not a catalog
  revision, and isn't built twice.
- **4c:** `spacecraft_application_bindings` becomes a projection of the head, or is deleted after a
  reader inventory. That removes the drift class behind 001's 11-15 inconsistency.
- **4d:** `BindingSetIndex` builds from the membership directly, without hydrating 10,000 rows.
- **Who:** domain builds 4a; mms-engineer builds 4b-4c with domain; api-ops reviews the runtime side
  (4a's expansion is on the activation path; 4d is runtime).

### Phases 5 and 6 (after 2-4; no load win)
- **5:** SpaceSystem binding. Spacecraft bind to one or more SpaceSystems; per-computer models.
- **6:** calibrations (board #21, M7: calibrators declared but not executed), context and change
  alarms, export.
- Calibrations stay pulled forward as the addendum's correctness item (#21). They don't wait for
  phase 6.

## 3. Dependencies

```
#155 (#99) ──> 1a snapshots ──> 1b plan ids ─┐
                                             ├──> 3 monitoring lane
2 composition ──────────────────────────────┤
     └──> 4b heads/assignments ──> 4c ──> 4d │
4a binding storage (now) ────────────────────┘ (independent)
5, 6 after 2-4
```

- **Phase 2 and #99:** phase 2 touches the model, the catalog and profiles, not runtime effect ids.
  It doesn't need #99 and builds on develop.
- **Phase 1 and #99:** 1a replays up to 60 s after a crash, so it needs #99's insert-or-get ids. It
  builds on `domain/replay-ids` (pushed 11-19, ba4943476) and merges after #155.
- **#99 and phase 1:** #99 doesn't need phase 1. Its stream ordinals key on `(mission,
  partition_id)`, and `PartitionKey.identifier` (`affinity:value`) is already revision-free.
- **#171** (QuestDB provenance) waits on #155, not on the overhaul.
- Parallel tracks: **1a (domain) ‖ 2 (domain design + mms-engineer) ‖ 4a (domain, or mms-engineer
  once 2 is designed)**.

## 4. Old dev data, earliest merge, and the reset

| Phase / slice | Breaks reading old dev data? | Earliest merge (est.) |
|---|---|---|
| #155 (#99) | **Not shown to.** Old inputs carry no frame and read as `effect_source: nil`, the no-frame path. I verify it with a restart onto dev data in qa's slot before the reset, and say so in the PR. | PR 11-20 ~13:00Z; merge on review |
| 1a snapshots | **No.** A partition with no snapshot starts empty once, which today happens on every activation (`monitoring_seed.ex`). Alarm state reseeds as today. Old commit rows are dropped later, not read. Lands in a qa restart outside a pass. | ~11-24 (after #155) |
| 1b plan ids | **No.** New plans get new ids; existing plan and evaluation rows keep theirs. | ~11-26 |
| 2 composition | **No, with a one-to-one migration:** each catalog revision's model revision is already a one-import composition, so profiles and overrides get the matching record in SQL. That is a data migration, not a compatibility shim (#112). | ~11-27 |
| 3 monitoring lane | **No.** The side stores are empty on dev. | ~12-03 |
| 4a binding storage | **No.** `fetch_binding_set` reads both forms; old versions stay as they are. | ~11-23 |
| 4b-4d | **No.** Old revision documents stay as history; heads and assignments start from the current state. | after 2: ~12-01 |

**For lead's reset pick list:** no overhaul phase must ride the reset, and none merges within
~2 days of 11-20. So the reset doesn't wait: it goes with #155, #171, #161/#162 and what has
merged. Grouping isn't needed, because phases 2-4 are designed to migrate instead of reset. If a
review finds a phase can't keep old data readable, it gets its own reset (lead's rule).

## 5. Issue breakdown (E2 #208, Squad = Mission Model & Spacecraft)

New issues, filed after the director's OK. Owners are proposals for fe-setup (squad lead) to
confirm.

| # | Issue | Phase | Owner | Reviewers |
|---|---|---|---|---|
| A | A partition's semantic state is kept in one snapshot per minute, not in a commit per input (#94/#96) | 1a | domain | api-ops, qa |
| B | Runtime plan ids and partition state survive a model revision that keeps the same parameters | 1b | domain | api-ops |
| C | Imports are mounted under their own subtree, so a second import composes instead of being dropped | 2 | mms-engineer | domain |
| D | A mission composition record is what a profile pins; the catalog revision is provenance | 2 | domain (design), mms-engineer | api, mms-security |
| E | The model gate approves compositions (approval, baseline, qualification re-keyed) | 2 | domain | ca-security, api-ops |
| F | Binding-set versions are stored once per configuration, not per craft × packet | 4a | domain | api-ops |
| G | A spacecraft's configuration is a head plus assignment history, not a derived document per change | 4b | mms-engineer | domain |
| H | `spacecraft_application_bindings` becomes a projection of the head (reader inventory first) | 4c | mms-engineer | domain |
| I | The runtime builds its binding index from the membership | 4d | domain | api-ops |
| J | Limits, alarm rules and derived parameters change through the monitoring lane (U108) | 3 | domain + mms-engineer | ux, api |
| K | Retire the limit and derived-telemetry side stores, evaluators and #77 kinds | 3 | mms-engineer | domain |

Existing issues it absorbs or links:
- #28 and epic #216 (phase 3), #26 and #22 (phase 3's one live evaluator surfaces model alarms);
- #21 (calibrators, the correctness item);
- #119 (re-import identity, a phase 2 input);
- #367 (CatalogDiff on a missing revision, near E).

## 6. Order of work from 11-20

1. **domain:**
   - (i) this plan to the director;
   - (ii) #155's PR (~13:00Z);
   - (iii) 1a's design delta: the snapshot schema and recovery, against `recovery-from-archive.md`,
     reviewed by api-ops;
   - (iv) 4a, failing-first, in parallel;
   - (v) phase 2's design (D, E) for mms-engineer and mms-security.
2. **mms-engineer:** C now (independent), then D's build once designed.
3. **mms-security:** the composition and binding records' threat model, from D's design.
4. **ux:** U108 (PR #438); domain answers its six questions in review by 11-20 10:00Z.
5. **What slips (lead re-orders):**
   - domain's #273 PR opens (machine time only), then #355 and #369 wait behind 1a and 4a;
   - the #359 live switch is qa's and isn't affected.
