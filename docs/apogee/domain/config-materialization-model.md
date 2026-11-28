# Spacecraft configuration: what is materialized per craft, and should it be

domain, 2026-11-15. Read-only review requested by the director for the user ("is step 4's query cost
really a data modeling issue?"). Written independently of the parallel reviewer. Set-based writes
are on hold until this is answered.

All figures are from `cadence_apogee_dev` (mission-earendil-demo, 500 spacecraft, one profile,
catalog with 10 packets), read with catalog statistics, index lookups, TABLESAMPLE and two scans of
tables under 2 MB. The query counts come from the dev-sized 500-craft apply test
(`profile_rollout_preview_test.exs`, commits 67e87cdfd and 851b03f9e).

**Short answer: yes.** The expensive part is the binding set. It is stored as the full cross product
craft × packet, and every generation stores a complete new copy for the whole mission, even when one
spacecraft changes. On dev, 500 spacecraft have **2 distinct configurations**, yet each generation
writes 10,000 rows (about 14 MB). Set-based writes would make that wrong shape faster; they wouldn't
fix it.

## 1. What a generation materializes per spacecraft today

| Store | Per craft, per generation | Size on dev | What it's for |
|---|---|---|---|
| `governed_capability_instances` | 10 rows (one per handled packet) | ~600 B/row; 17 MB for 3 versions | One decom instance per (mission-model revision, packet, **source endpoint**) |
| `governed_binding_rules` | 10 rows | ~770 B/row; 26 MB for 3 versions | Routes (endpoint, APID) to that instance |
| `spacecraft_configuration_revisions` | 1 row (a derived revision) | ~550 B document; 1.6 MB for 1,001 rows | Per-craft history: what this craft was configured with at version N |
| `spacecraft_application_bindings` | 1 row, updated in place | 500 rows, 0.8 MB | Per-craft "applied" state (catalog, APIDs, endpoint, applied binding-set version) |
| Apply-time reads and locks | 2 `Drafts.fetch` + 1 advisory lock | - | Read the current draft, serialize per craft |

**Binding-set versions are full copies.** There are 3 versions on dev, each with exactly 5,000
instances and 5,000 rules. Version 3 was written by revision 9, "#65 canary: EARENDIL-001 catalog
rev 4", **a one-spacecraft change that wrote 10,000 rows.** The two binding tables total 43 MB for
three generations, about 29 KB per craft per generation, and none of it is ever pruned.

Not part of this problem:
- The mission ledger (`mission_config_revisions` and `_entries`) records the change, not the craft:
  1 to 6 entries per change.
- `contact_transport_profiles` (2 per craft, uplink routes) is genuinely per craft (SCID, VCID,
  provider binding) and a catalog move doesn't touch it.

In the 500-craft apply, 31 statements per craft remain. 20 are the instance and rule inserts; the
rest are the derived revision, the two draft reads, the application-binding update and the lock.

## 2. How much of it is identical

- **Per-craft documents.** Take each craft's latest configuration document and remove
  `telemetry_source_endpoint_id`. The 500 documents then reduce to **2 distinct configurations**:
  - **499 identical** (catalog m6rblb);
  - **1 different**: 001, whose only override is `catalog_revision_id`, the canary.

  The removed field is always `spacecraft_runtime:<spacecraft_id>`, derived from the craft's id
  (checked for all 500). The 1,001 revisions have 1,001 distinct `content_sha256` only because each
  document embeds that derived id. Content addressing dedupes nothing today.
- **Binding rows.** An instance's whole configuration is `{mission_id, packet_definition_id,
  version}`, and a rule's is `{apid, packet_kind}` plus the endpoint scope. **The only per-craft value
  in 10,000 rows is the source endpoint reference**, and the instance id embeds that same endpoint
  string.
- **The runtime already noticed.** `Runtime.BindingSetIndex` interns identical configurations in
  memory and `select/2` slices the set back out per partition by `source_endpoint_ref`. Cadence
  stores the cross product, then de-duplicates it again on every load.

What is genuinely per craft:
- its id, and the source endpoint derived from it;
- overrides (on dev, one);
- enable flags;
- uplink routes (transport profiles);
- the history of which configuration it was on, when, and under which change.

## 3. Who reads the per-craft copies

| Reader | Reads | Could it read shared + per-craft instead? |
|---|---|---|
| Runtime reconciler (`mission_runtime_reconciler.ex`), then `BindingSetIndex.select/2` per partition | The whole active version: 10,000 rows hydrated per activation | Yes. Expand the shared template with `partition.value` at `select/2`. That's what the index does after load already. |
| Activations (`activations.ex`, `management/activations.ex`, `control/activations.ex`), `SpacecraftConfiguration.Active`, `ConfigurationGeneration` (previous set) | A full version by (id, version) | Yes, behind `Governance.fetch_binding_set`, if it keeps returning the same `BindingSet` struct |
| Evidence and replay (`cadence.ex:82`, `operational_events.ex:260`, `replay.ex:152`) | A full historical version, for one event's explanation | Yes. Better: an explanation needs one craft's slice, not 10,000 rows. |
| Ops point catalog (`ops/point_catalog.ex`) | The active version | Yes; it needs the packet definitions, which are per artifact anyway |
| Capability records (`transport_`/`managed_capability_records`) | Store `capability_instance_id`, which embeds the endpoint, plus `partition_value` | Yes, if expansion produces the same deterministic ids |
| `Drafts` and `Review` | Per-craft revision documents | Yes: artifact ⊕ overrides resolves the same document |
| History and rollback (per craft) | Revision versions | Yes, from assignment history (section 4) |
| `spacecraft_application_bindings` readers | Applied state per craft | It should be a projection of the head. **On dev, 001's row says catalog m6rblb while 001 runs ieeplt** (revision 3, binding set v3 on model 732618). Either that column means something else or it is a drifted copy. To check; it's an example of what three copies of one fact allow. |

## 4. An alternative model: shared, content-addressed configuration

**Configuration artifact** (immutable, content-addressed):
- Holds the resolved configuration that affects compilation (catalog revision, protocol, handled
  APIDs, enables) and its compiled binding **template**: instances and rules with the endpoint as a
  parameter.
- Addressed by `sha256(resolved content without spacecraft identity)`.
- Each artifact is compiled and validated once.
- On dev this is 2 artifacts of about 10 instances and 10 rules each.

**Spacecraft head**: one row per craft holding:
- `artifact_sha`;
- its identity parameters (endpoint, which is derived anyway);
- an `overrides` reference;
- `version` and `generation`.

**Two kinds of override**, kept separate:
- A **compile-affecting** override (catalog, APIDs, protocol) selects a different artifact: the
  artifact is `f(profile ⊕ overrides)`. Craft with the same overrides share it, so 001 points at
  artifact B.
- An **identity** override (SCID, endpoint) is a parameter bound at expansion.

**Assignment history** (append-only, per craft): `(spacecraft_id, version, artifact_sha,
overrides_sha, generation, change_set, revision)`, about 150 B per row. Per-craft audit is kept as
rows. A document "as of version N" is resolved, not stored.

**Binding-set version**: `{generation, [(artifact_sha, [spacecraft…])]}`, a membership list.
`Governance.fetch_binding_set` expands it to today's `BindingSet` struct, with the same
deterministic instance ids (model revision + endpoint + packet), so capability records, evidence and
replay keep joining.

**What a fleet catalog move costs in this model:**
- compile the new artifact once (already true after 67e87cdfd);
- insert 1 artifact;
- `insert_all` 499 assignment rows;
- one `UPDATE … FROM` of the heads;
- one membership row;
- one mission lock.

That is **about 10 statements and a few hundred KB**. Today it is about 15,500 statements, 14 MB of
binding rows and 0.5 MB of documents. A one-craft canary costs the same handful of statements, not
10,000 rows.

**What it breaks, and how to keep it:**
- **Per-craft audit.** Kept as assignment rows. The history and Drafts readers resolve the document
  instead of reading it; the API shape is unchanged if they resolve server-side.
- **Rollback.** Simpler: a reference flip. Artifacts referenced by any assignment are never deleted;
  only unreferenced ones are collected.
- **Mixed fleets during a rollout.** Native: a membership lists several artifacts, and dev is exactly
  that today (2).
- **#38 (a command releases only over its own spacecraft).**
  - Uplink is unaffected: routes stay per craft.
  - For telemetry, endpoint scoping moves from stored rows to expansion. The risk is a template rule
    expanded without its endpoint, which would match across craft.
  - Mitigation: expansion is the only constructor, a template can't be admitted without the endpoint
    parameter, and a test proves a frame on X never selects an instance of Y.
- **Content hashes.** `binding_set_content_sha256` on activations changes meaning for new
  versions. Old versions keep theirs. Hash the membership plus the artifact hashes.
- **Validation.** Done once per artifact, plus endpoint existence for the membership (one query,
  as in 851b03f9e).
- **Drift.** The three per-craft copies of "which catalog is this craft on" (revision document,
  application-binding row, binding rows) become one head. That removes the class of the 001
  inconsistency above.

**Migration**, smallest-risk order:
1. **Storage only.** Add artifacts and membership. `persist_binding_set` writes the membership form,
   and `fetch_binding_set` expands to the identical struct. Test `expand(compress(v)) == v` for
   every existing version (a one-off check on dev in a slot). The runtime and readers are unchanged,
   old versions stay readable as they are, and no backfill is needed.
2. **Configuration.** Assignments and heads replace derived revision documents for new changes. The
   old revisions stay as history. Drafts and Review resolve.
3. **`spacecraft_application_bindings`** becomes a projection of the head or is deleted, after an
   inventory of its readers.
4. **Later.** `BindingSetIndex` builds from the membership directly, skipping the 10,000 structs.
   Old versions can optionally be compressed to recover the 43 MB.

## 5. Recommendation

1. **Treat it as a modeling fix, not a write-speed fix.** Don't do set-based writes of the current
   shape: `insert_all` of 10,000 cross-product rows per generation makes the wrong model fast and
   leaves 14 MB per generation, every one kept.
2. **Do step 1 first** (binding-set storage behind `Governance.fetch_binding_set`). It removes 20 of
   the 31 statements per craft and about all of the bytes, without changing a reader. It is provable
   by equivalence against every stored version.
3. **Then step 2** (artifacts, heads, assignments). It removes the rest of the per-craft work (draft
   reads, document inserts, application-binding updates, per-craft locks), keeps per-craft audit as
   rows, and makes rollback and canaries a reference flip.
4. **Today's retry is unaffected.** The ~14:15Z step 4 retry runs on the current fixes (estimated
   30 to 50 s against the 120 s limit) under the director's stop rule. Nothing here is needed for
   it. If it trips the rule, step 1 replaces set-based writes as the next fix.

**Not measured yet:**
- the read side: reconciler hydration time for 10,000 rows, and evidence lookups that load a full
  version;
- what `spacecraft_application_bindings.catalog_revision_id` means for 001.

Both are read-only checks I can do next.

## 6. Step 1 landed (#447): measured

Binding-set versions are stored once per distinct configuration plus a membership list
(`Governance.BindingSetStorage`); `Governance.fetch_binding_set` expands them to the identical
`BindingSet` (same ids, same order, same `content_sha256`, #108). Old versions read as rows.

`Cadence.Governance.BindingSetStorageMeasureTest` (`mix test ... --include scale`, a catalog the
size of dev's: 10 packets a craft), laptop 2, develop before and after, rows and bytes added to the
binding tables and statements run by the review, which writes the version:

| | before | after |
|---|---|---|
| 500 craft, one generation | 10,001 rows, 16.1 MB, 15,691 statements | 502 rows, 0.11 MB, 5,698 statements |
| 500 craft, then a one-craft change | 10,001 rows, 12.3 MB, 10,087 statements | 501 rows, 0.12 MB, 94 statements |
| 1,000 craft, one generation | 20,001 rows, 32.7 MB, 31,191 statements | 1,002 rows, 0.25 MB, 11,198 statements |
| 1,000 craft, then a one-craft change | 20,001 rows, 6.1 MB, 20,087 statements | 1,001 rows, 0.23 MB, 94 statements |

The statements that remain in a generation's review are the per-craft ones (`prepare_drafts`,
#1000), not the binding set's. Wall times are noisy on a shared laptop and are in the PR, not here.
The apply's statements are unchanged (it reads the same set).

Equivalence is checked on every write and read in the test suites: `Cadence.TestSupport.
BindingSetEquivalence` reads every persisted version back and compares it with its rows-form
expansion, struct for struct and by hash, and a fallback to rows raises under test.
