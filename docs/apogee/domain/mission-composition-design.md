# Mission composition and the model gate (design D #445, E #446; overhaul phase 2)

domain (technical lead), 2026-11-20. Status: **design for review.** Reviewers:
- api-ops: runtime and plan ids;
- mms-security: the threat model, #512 §5;
- ca-security: approval paths;
- fe-setup / mms-ux: the read shapes;
- mms-engineer: builds.

Sources:
- the ADR-020 addendum (DECISIONS #92, #93);
- `mission-model-build-plan.md` §2;
- `mm-composition-threat-model.md` (#512, CB-1…CB-15);
- #456 (C, import mounts; approved, not yet merged; D1 needs it);
- #483 (provenance B: derived `binding_rule_id`);
- #534 (packet definition identity).

## 0. The short version

- **The gated unit stays the mission model revision.** The model gate already keys on
  revision ids: `ModelApprovalGate.introduced/2` and `check/5` work per fleet entry's revision.
  Only two things in it are catalog-keyed:
  - `RevisionDecisions.approve`'s requirement for a catalog row (`:mission_model_revision_not_in_catalog`);
  - `default_baseline` (`Catalog.previous_model_revision`).

  E re-keys those two, and nothing else moves. So there's never a window where no gate
  applies (CB-4).
- **A composition** is a new, small, immutable record: which imported layers, at which mounts,
  in one mission.
- **An effective revision** is a model revision compiled from a composition's imported layers
  plus the mission's authored layers at one head. It's the same table as today:
  `mission_model_revisions` and `_revision_layers`.
- **Profiles and per-craft overrides pin a composition.** The catalog revision stays as import
  provenance.
- **Migration is one-to-one, with no recompile.** Each existing catalog revision's model
  revision is already a one-import compile at mount '/', which #456 keeps byte-identical. So each
  becomes a one-layer composition whose effective revision IS the existing revision row, with
  the same id and the same approval row. No reset.

## 1. Records

### `mission_model_compositions` (new)

| column | |
|---|---|
| `organization_id`, `mission_id` | Tenant scope. Part of the key and of every foreign key (CB-2). |
| `composition_id` | `mission_model_composition:` + sha256 of the canonical term `{org, mission, sorted [{layer_id, mount}]}`. Content-addressed **within the tenant**. |
| `imported_layers` | `[{layer_id, mount}]`, sorted by mount. Imported layers only. |
| `created_by`, `created_at` | Who made it (a person, or a service counted through #280). |

- **Immutable.** UPDATE and DELETE are refused by trigger (#116's pattern).
- **Insert-or-get** re-reads by `(org, mission, composition_id)` and fails closed on any scope or
  content mismatch, as #119 did (CB-2).
- **Mounts** follow #456:
  - a plain absolute path;
  - '/' only when it's the composition's single imported layer;
  - no two equal or nested mounts (`MM_MOUNT_COLLISION`).

  The **record decides the mount**. The importer only suggests one (import-run metadata,
  CB-5).
- **Bounds (CB-13):** at most 8 imported layers, mount depth at most 4 segments.

### `mission_model_effective_revisions` (new, link)

`(org, mission, composition_id, authored_head, revision_id)`, unique on the first four.

- `authored_head` is the mission's authored-layer lineage head (phase 3; `nil` until then).
- `revision_id` references `mission_model_revisions`.
- It's how "this composition at this authored head" finds its compiled revision without
  recompiling. Same immutability and scope rules.

### The authored-layer head (phase 3, named here so D doesn't need changing later)

- The monitoring lane's apply advances one per-mission head (`authored_head`), recorded in the
  mission ledger.
- Phase 3 (J, #451) owns it. D only names the column.

## 2. Compiling an effective revision

`MissionModels.effective_revision(org, mission, composition_id, authored_head)`:
- an existing link is returned as-is;
- otherwise it calls `compose/4` with the composition's imported layers (mounts from the
  record, #456) plus the authored layers at the head, writes the revision as today (plans and
  diagnostics), and writes the link;
- blocking diagnostics (`MM_*` errors) mean no link and no revision usable (`valid?` false).

With **one imported layer at '/' and no authored layers**, `compose/4` gives the
byte-identical revision a catalog import makes today. #456's goldens pin that, so the
migration reuses the existing rows.

**Binding ids (#483 constraint).**
- Decom instance and rule ids embed the revision id
  (`TelemetryBinding.binding_rule_id(revision, spacecraft, producer)`).
- Each effective revision has its own id, exactly as each catalog revision's model revision
  does today. Stored observations keep their `mission_model_revision_id`, and the derived
  `binding_rule_id` rebuilds from it.
- So the format is unchanged, and existing rows read as before. No migration of derived rows.

## 3. Pins (CB-3, CB-14)

- **What's pinned:**
  - profiles gain `composition_id` beside `catalog_revision_id`;
  - per-craft overrides gain the path `composition_id`;
  - the effective revision a craft runs is `effective_revision(pinned composition, mission's authored head)`.
- **Pins change only by change set** (configuration lane), with four-eyes under 'independent'
  and #280's separation. That covers the kinds `spacecraft_profile` (`composition_id`) and the
  per-craft override. No other writer; REST bearers can't reach it outside the change-set path.
- **A pin to a composition that isn't approved is refused:**
  - at staging, as a validation NO-GO;
  - again at activation, under the activation lock: the gate's existing per-revision check on
    the effective revision.
- **Identity overrides** (SCID, endpoint) stay change-set kinds, and #38's checks re-run at apply
  and at activation (CB-14), as today.
- **`catalog_revision_id` on profiles and overrides**:
  - it becomes read-only provenance, derived from the composition's (single) imported layer
    while there is one;
  - new writes set `composition_id`;
  - a change set that sets only `catalog_revision_id` (old clients) is translated to the
    one-layer composition of that revision, so the console keeps working while readers
    move (§6).

## 4. The gate re-key (E, CB-1, CB-4, CB-6)

- **The gated unit is unchanged:** the effective revision, via the existing `ModelApprovalGate`.
- **Approving a composition = approving its base effective revision** (authored head `nil`).
  It's the same `RevisionDecisions.approve` flow, with three changes:
  - the catalog-row requirement is replaced by "a composition names this revision";
  - **importers** become the union of the importers of every imported layer's catalog revision
    (`Catalog.model_importers` per layer), so separation covers every imported layer;
  - the comparison runs on the composed revision.
- **An effective revision with authored layers** (phase 3) is approved by the monitoring set's
  own change-set review (the addendum; CB-6: no second gate decision). It's usable only when:
  - its composition's base is approved;
  - the comparison report on the COMPOSED revision has passed, or the change-set reviewer
    acknowledged it as today (CB-1: the combination is compared, not only its parts);
  - the change set's separation held. The reviewer is distinct from every author (DECISIONS
    #14), with #280 for services.

  The four-eyes record (#117) names the change set and the comparison report.
- **Baseline (`default_baseline`):** the previous effective revision of the same composition
  lineage, else the revision most craft run (today's fallback). `Catalog.previous_model_revision`
  stays only for a one-layer composition, where it's the same thing.
- **Migration order (CB-4):**
  - The migration creates compositions and links for existing revisions **in one transaction**.
  - It writes nothing to `mission_model_revisions`: the approval columns are the same rows,
    carried exactly, so an unapproved revision stays unapproved and a rejected one rejected.
  - The code switch (approve's composition check) lands in the same release as the migration.
    The gate's per-revision check is unchanged throughout, so there's no gap.
  - Guard test: after migration, every approved revision has its approval decision row and a
    composition that names it, and no composition has an approved base without one.
  - The migrated approvals keep their decision records' `subject.digest`.

## 5. A withdrawn approval (CB-15)

- If a composition's base approval is withdrawn or superseded, the **next generation is
  refused** for every craft pinned to it, at staging and again at activation.
- Craft keep running their last activated generation until then, and their state reads
  "pinned composition no longer approved", with the reason and the decision record.
- It's never used silently.
- Suspending sooner (stopping running craft, as #499 does for grants) is a question for
  mms-security and ca-security. **Recommendation:** no. Stopping telemetry and commanding on an
  approval change is an operational decision for a person, not an automatic consequence. Show
  it on the craft and in the attention queue instead.

## 6. Readers first (fe-setup's ask)

**Order:**
1. Reads gain `composition_id` and `{imported_layers: [{layer_id, catalog_revision_id, mount}]}`
   beside today's `catalog_revision_id`, on the profile, spacecraft configuration, catalog and
   activation (L10) reads. fe-setup / mms-ux name E's read shape (approval per composition).
2. The console moves its reads.
3. Then the writes switch to `composition_id`.

The console rows are U-entries from ux.

**The breaking base for composed revisions:**
- A composed revision has no single catalog revision.
- `catalog_revision_id` on its pin reads as `null`, and the reads give `imported_layers`.
- A client that still needs one catalog revision shows "Composed" and the layer list. ux
  gives the words.

## 7. Old data (#112)

- **The migration is one-to-one:**
  - every catalog revision with a model revision gets a one-layer composition (mount '/') and
    a link to that same revision;
  - every profile and override with `catalog_revision_id` gets the matching `composition_id`.
- No recompile, no new revision ids, no reset.
- Old activations and fleet entries keep naming revision ids, which are unchanged.
- Old rows stay readable, so this is an ordinary landing with a restart.

## 8. Answers to #512 §5 (mms-security)

| # | Question | Answer |
|---|---|---|
| 1 | Composition approval (CB-1, CB-6) | §4: compared on the composed revision; base approved by the gate with union importers; authored layers by their change-set review, no second decision |
| 2 | Identity (CB-2) | §1: content-addressed within (org, mission); insert-or-get re-reads scoped and fails closed |
| 3 | Pin (CB-3) | §3: change-set kinds only, four-eyes; unapproved refused at staging and at activation |
| 4 | Gate re-key (CB-4) | §4: the gated unit is unchanged; one-transaction migration with no approval writes; guard test; digests kept |
| 5 | Mounting (CB-5) | §1: the record decides; #456's grammar and collision rule |
| 6 | Artifact scope (CB-7) | Met by 4a's design (scoped to org and mission); re-lands after #534 |
| 7 | Expansion (CB-8) | Met by 4a; I (#450) builds from membership, with #450's CB-9 hardening |
| 8 | Evidence (CB-9) | Unchanged hash meaning (the expanded set); three checks (read, admit, run); #450 removes the computed default |
| 9 | Audit (CB-10, CB-11) | G and H (later slices): append-only by trigger, the head written with its assignment row; collection locks against new assignments |
| 10 | Projection (CB-12) | H: the reader inventory first, authorization readers named |
| 11 | Bounds (CB-13) | §1: 8 imported layers, depth 4; compile and expansion bounds in C/F |
| 12 | Overrides (CB-14) | §3 |
| 13 | Withdrawn approvals (CB-15) | §5 |
| 14 | Old data | §7 |

## 9. Slices (issues)

| Slice | What | Owner | Reviewers |
|---|---|---|---|
| D1 | Composition and link tables with triggers; `effective_revision/4`; the one-to-one migration with its guard test | mms-engineer | domain, mms-security, api-ops |
| D2 | Reads first (§6) | api / mms-engineer | fe-setup, mms-ux |
| D3 | Pins via change sets (`composition_id`); translating old writes; staging NO-GO | mms-engineer | domain, ca-security |
| E1 | Approve and baseline re-keyed; union importers; composed comparison | domain | ca-security, api-ops |
| E2 | Withdrawn-approval state on craft and in attention (§5) | domain | mms-security, ux |

**Order:**
1. #534 (P1);
2. #456 (C) merges; then D1 and E1 together (one release, with the migration);
3. then D2;
4. then D3;
5. then E2.

4a (#447) re-lands after #534, independently of D.
