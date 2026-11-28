# Mission change sets (DECISIONS #1)

Owner: **domain**. Status: **draft 2, P1 built** (2026-11-08). Reviewers: director, api, fe-setup, ux.
Decisions: DECISIONS #13 (freeze while in review), #14 (reviewer ≠ every author), #16 (build P1).
Facade contract: `docs/apogee/api/domain.md`.

## Draft 2: what P1 built and what changed since draft 1

**Built:**
- Migration `20261108100000`: heads, revisions, entries, change sets, changes, ops, reviews.
- `Cadence.Configuration.*` is the core.
- `Cadence.Control.Configuration` is the facade, a composition root.
- `Cadence.Platform.ConfigKind` is the contract.
- Kinds: `ground_station`, `transport` (comms) and `spacecraft`, `spacecraft_profile` (spacecraft).
- Tests: `test/cadence/configuration/` (20).

**Changed from draft 1:**
1. **Review records live with the change set in P1** (`mission_config_reviews`), not in
   `activation_requests`. The approval *policy* is still ADR-004's: `ActivationPolicy.evidence`
   is captured at submit and re-validated at apply, and `activation_policy_changed` reopens the
   set. `activation_requests` can't carry a change set, because its `binding_set_*` columns are
   NOT NULL. P1 kinds produce no binding set. When P2 kinds change the runtime generation, the
   apply will create the activation request **pre-approved with the change set's review
   evidence**. That needs a small `Management.Activations` extension, and it keeps one
   decision per change.
2. **`config.stage` = `operate_mission`** (active members), not `manage_mission`. That matches
   who can save configuration today. `config.discard_any` = `manage_mission` (org admins).
3. **Staging validates fields only.** Cross-entity checks (SCID taken, pin exists, profile in
   use) run in preview. A set can therefore hold, say, a spacecraft pinned to a profile created
   earlier in the same set.
4. **Op `options`** carry per-op settings that aren't fields: a profile edit's `rollout`
   (`all` | `none` | `{spacecraft: [ids]}`). Moved spacecraft enter the revision as their own
   entries.
5. **Runtime impact in P1:** `transport` → contact scheduler notified after commit (booked and
   running contacts keep their route). `ground_station`, `spacecraft` and `spacecraft_profile`
   have no direct runtime effect; spacecraft configuration still reaches the runtime through
   activation (profile-routing.md §4, P2).

**Director review notes (`review-director-1.md`):**
1. *Sandbox side effects.* The rule is in the `ConfigKind` moduledoc: `validate/6` and
   `write/7` only use `Repo`. `ScopedReadUpdates` already skips publishing inside a transaction.
   The test `preview … publishes nothing` subscribes to `:configuration_changed` and
   `:spacecraft_configuration_changed` while previewing a station and a spacecraft. Because
   stores skip invalidations inside the apply transaction too, the facade re-publishes
   `:spacecraft_configuration_changed` after commit.
2. *Preview locks.* Preview takes no head lock and no advisory lock. It runs under
   `SET LOCAL statement_timeout = 15000`.
3. *Fleet snapshot cap.* P1 composes no fleet snapshot, so the cap doesn't affect P1. **But
   the existing per-spacecraft activation path is capped at 500 spacecraft / 4 MiB today**
   (`L/catalog/spacecraft_model_bindings.ex:5-6`), so a 550-spacecraft mission can't be
   activated through today's review either. P2 prerequisite: move per-spacecraft entries out of
   the activation `metadata` blob into a child table keyed by `activation_id` (one row per
   spacecraft, content hash in metadata), and compose by streaming. I'll do that before the
   first P2 kind that produces a generation.
4. *Outside changes.* A conflict reports `changed_in: :outside` when no revision after the base
   touched the path. The UI wording is "changed outside a change set" (api/domain.md, Preview).
5. *Rollback across legacy activations.* P2 rollback will **refuse a range that contains a
   `legacy_activation` revision**. Its entries are derived from activation snapshot diffs, and
   reversing them means re-activating an old configuration, which isn't a ledger inverse. The
   error names the newest legacy revision; you can roll back to it, not past it. Values changed
   outside change sets since the target are shown in the rollback preview and overwritten only
   with an explicit HOLD acknowledgement.
6. *Facade.* `docs/apogee/api/domain.md`.

**New finding (DECISIONS #15 follow-up, director):** profile `frame_parameters` are **not read
by the decode path today.** Downlink frame size comes from the transport's tcp_socket
configuration (`L/comms/transport_kinds/tcp_socket.ex:263-267`, `ingress_metadata`), and the
profile values only feed the spacecraft configuration document. Strictly, "framing fields only
appear if the pipeline uses them" leaves the Framing section empty. I recommend fixing the model
in P2 instead: the profile is the byte-interpretation owner (wire/bytes split), so the
materialized spacecraft configuration should supply framing to ingress. Until then, show the
Framing section read-only with "applied through spacecraft configuration".

UX contract: `docs/apogee/ux/screens/Changes.md`. Companion: `profile-routing.md` (routing rules and
overrides are change-set kinds). `L` = `apps/cadence/lib/cadence`.

## 0. Summary (the decisions I'm asking you to accept)

1. **One revision ledger per mission.** `rN` is a new per-mission counter on
   `mission_config_revisions`. Every applied change set writes exactly one revision, and the
   revision records what changed per entity (before/after documents). The ledger drives history,
   diff, compare and rollback.
2. **Wrap the entity stores; don't replace them.** Spacecraft profiles, transports, spacecraft,
   routing rules, stations and catalog pins keep their own tables, which stay the "current state"
   that runtime and reads already consume. A change set holds *proposed* content and writes it into
   those tables only on apply. Each entity kind plugs in through one behaviour (`ConfigKind`).
3. **Apply is an activation.** It reuses the ADR-004 governance pipeline that exists today
   (`activation_requests` → `activation_decisions` → `activation_executions` →
   `mission_binding_set_activations.generation`). There is no parallel approval system. Direct vs
   independent approval keeps coming from `Governance.ActivationPolicy`.
4. **`rN` ≠ activation generation.** A revision that changes runtime-relevant config also produces
   a new generation and records it. A revision that only touches routes or stations doesn't churn
   the runtime. Today's legacy activation path also writes a revision, so `rN` never lies.
5. **Rollback is a new revision.** It stages the inverse of the revisions after the target, then
   applies normally (review, checks, audit). History is never rewritten.
6. **Checks run on a sandboxed apply.** The real apply pipeline runs inside a transaction that is
   rolled back. Effect counts ("changes 499 · keeps 1"), readiness-after, conflicts and
   compatibility all come from the real code, not a second, hand-written predictor.

## 1. What exists (and why it is not enough)

| Entity | Versioning today | Audit | Reaches runtime via |
| --- | --- | --- | --- |
| Spacecraft Profile (`mission_spacecraft_types`) | append-only `(type_id, version)`, latest wins; **no v+1 path in prod** | none | pinned on spacecraft during admission only (`L/activations/spacecraft_configuration.ex:98-150`) |
| Transport (`comms_transports`) | append-only, latest wins, `version_transport` unlocked | none | read at contact scheduling (`L/contacts/provider_scheduling.ex:88`) |
| Spacecraft (`mission_spacecraft`) | mutable row, pins `{type_id, version}` | none | identity + activation snapshot |
| Spacecraft configuration (artifact, assignment history, head) | Per-spacecraft drafts point to immutable shared artifacts. Review resolves the assignments and builds a binding set and activation request with a fleet snapshot. | Assignment `created_by`; decisions have actor + reason | **the only governed path**: activation → generation → `MissionRuntimeReconciler.apply_generation` |
| Routing rule (`comms_routing_rules`) | mutable, no PK; per-rule event log (actor never passed) | partial | read at scheduling; snapshotted into contacts |
| Catalog revision (`catalog_revisions`) | immutable imports | `created_by` | via spacecraft configuration `catalog_revision_id` |
| Ground station (`comms_ground_stations`) | mutable | none | not linked to routing at all |

The activation generation is already a mission-wide counter, but it only covers spacecraft
configuration. Everything else is written directly, unaudited, with silent `on_conflict: :nothing`
collisions. The execution tail (runtime apply, `TelemetryDecom.activation_applied`) runs after the
activation transaction commits (`L/control/activations.ex:82-142`). No rollback exists anywhere.
The only rollback-as-new-version precedent is per entity, in dashboards (`revert_document`).

## 2. Concepts

- **Mission configuration**: the governed setup state of one mission, i.e. the union of every
  `ConfigKind`'s current rows.
- **Revision `rN`**: an immutable, applied step of the mission configuration. It has a number, a
  kind (`change_set | rollback | legacy_activation | baseline`), who applied it and when, why,
  approver(s), a summary, the activation it produced (if any), and its **entries**.
- **Revision entry**: one entity changed in a revision: `{kind, entity_id, op, before, after,
  paths}`. `before`/`after` are the kind's canonical documents (`nil` for create/delete).
- **Change set**: the mission's open staging area. There is at most one `open` set per mission,
  shared by every author. It has a `base_revision`.
- **Change**: one staged unit, as a user sees it ("50 new spacecraft (Block 2)"). It has an author,
  time, summary, `source` (surface link) and state. It owns one or more **ops**.
- **Op**: one entity operation: `{kind, entity_ref, action, payload, base}`.
  - `action`: `create | update | delete | reset`.
  - `payload`: the proposed document (create) or a list of `{path, value}` (update).
  - `base`: the entity's document hash at staging time + the base values of touched paths.
  - `entity_ref` is an existing id, or a staging-local ref (`new:<uuid>`) so ops in the same change
    can refer to a spacecraft created in that change.
- **ConfigKind** (behaviour, one per entity kind, owned by the entity's context):
  `load(scope, ids) → documents`, `validate(scope, post_state_docs)`, `apply(multi, op)`,
  `diff(before, after) → [path change]`, `effect(scope, op) → affected spacecraft`,
  `summary(op)`, `inverse(entry) → op`, `runtime_impact(op) → :generation | :contacts | :none`.

**v1 kinds:** `spacecraft_profile`, `spacecraft` (identity + profile pin), `spacecraft_override`,
`profile_routing_rule`, `transport`, `ground_station`, `catalog_assignment` (catalog revision for a
profile or a set of spacecraft). Later: `data_source`, `application_installation`,
`limit_definition`, `mission_model_promotion`. Catalog *imports* stay outside change sets: an
import produces an immutable artifact. *Rolling it out* is the config change.

## 3. Tables (new, all mission-scoped with the usual org/mission FK + trigger)

```
mission_config_change_sets
  change_set_id PK, org, mission, state, base_revision_number, opened_at, opened_by,
  content_sha256, activation_request_id NULL, submitted_by, submitted_at, reason NULL,
  failure_document NULL, closed_at
  partial unique index (mission_id) WHERE state IN ('open','in_review','applying')

mission_config_changes
  change_id PK, change_set_id FK, author_actor (doc), staged_at, summary, source (map),
  state (staged | withdrawn | discarded | applied), position

mission_config_ops
  op_id PK, change_id FK, kind, entity_ref, action, payload (map), base (map),
  touched_paths (text[]), position
  -- lookup index (change_set_id via change, kind, entity_ref) for in-set overlap checks

mission_config_revisions
  revision_id PK, org, mission, revision_number, kind, change_set_id NULL,
  rolls_back_to NULL, applied_by (doc), applied_at, reason, approvals (list of docs),
  summary, entry_count, activation_id NULL, generation NULL, content_sha256
  unique (mission_id, revision_number)

mission_config_revision_entries
  entry_id PK, revision_id FK, kind, entity_id, op, before (map), after (map), paths text[]
  index (mission_id, kind, entity_id, revision_number)   -- per-entity history, "since rN"

mission_config_heads
  mission_id PK, revision_number, revision_id, updated_at   -- current rN, row-locked on apply
```

Change-set states: `open → in_review → applying → applied`. From `in_review`: `sent_back → open`.
From `applying`: `failed → open` (ops kept). From `open`: `discarded`. The open set is created
lazily on the first stage.

## 4. Staging

`stage(scope, change_attrs, ops)` runs under the mission configuration lock
(`L/applications/configuration_lock.ex`):
1. Find or create the open set. Return `{:error, :change_set_in_review}` while a set is in review
   (one shared set per mission; staging resumes when it is approved or sent back).
2. Load the current documents for each op, resolve `base`, and run the kind's field validation
   (types, ranges, references). Invalid → `{:error, {:invalid, [%{path, message}]}}`, nothing
   staged.
3. **In-set overlap:** another *author's* staged op touches the same `(kind, entity, path)` →
   `{:error, {:staged_by_other, change_id, author, value}}` (UX: "Mira K. staged 1,200"). The same
   author re-staging the same path replaces their earlier value.
4. Insert the change + ops, and recompute `content_sha256`. Publish
   `read-updates:config_staged:<org>:<mission>`.

Returns `%{change_set_id, change_id, staged_count, base_revision}`. Errors stay distinct so the UI
can map each one to its own state:
- `{:error, :change_set_in_review}`
- `{:error, {:staged_by_other, %{change_id, author, value}}}`
- `{:error, {:invalid, [%{path, message}]}}`
- `{:error, :forbidden}`

- `withdraw(scope, change_id)`: the author (or `config.discard_any`) sets it to `withdrawn`. Ops
  are kept so the surface can rehydrate the author's edits
  (`list_withdrawn(scope, author, kind, entity)`).
- `discard(scope, change_set_id)`: discards the changes the caller may discard. The set closes when
  none are left.
- Editing during review is blocked. `send_back` reopens the set with the reviewer's comment
  attached.

## 5. Diff, conflicts, rebase

- **Change diff** = `kind.diff(current_doc, proposed_doc)` → `[%{path, before, after}]`. Creates
  list the new documents.
- **Revision diff** = its entries. **Compare rA…rB** folds the entries in (A, B] per entity:
  earliest `before`, latest `after`.
- **Conflict against live** (base revision moved or the entity changed outside the set): for each op,
  compare the current values of `touched_paths` with `base`.
  - Equal → clean. If only *other* paths moved, the op is **auto-rebased** (base updated, no user
    action).
  - Different → `conflict` with `{path, base, live, staged, changed_in: rK | :outside}`.
    `rebase(op_id, :keep_mine)` sets `base := live`. `:take_live` withdraws the path.
  - An entity deleted live → conflict that can't be rebased; the op must be removed.
- Because conflicts compare *values*, direct writes from legacy LiveView pages are caught too, even
  though they bypass the ledger.

## 6. Checks and dry run (K2 GO / HOLD / NO-GO)

`preview(scope, change_set_id | ops)` runs **the apply pipeline (§7 steps 2–5) inside
`Repo.transaction` and ends with `Repo.rollback`**. Nothing commits. The after-commit tail never
runs. Inside the sandbox, the real readers produce:

| Check | How | Verdict |
| --- | --- | --- |
| Validation | each kind's `validate` on the post-state + cross-entity rules (unique names/SCIDs, pins exist, routes materialize) | error → NO-GO |
| Conflicts | §5 | unresolved → NO-GO |
| Effect | `kind.effect(op)` → `%{changes: n, keeps: [%{spacecraft, reason}]}` per op (profile field: pinned spacecraft minus those with an override on the path) | info |
| Readiness after | the mission readiness read (api's `/readiness` source) evaluated in-sandbox, before vs after | new blocker → NO-GO |
| In flight | queued/staged commands whose command basis changes (they will fail closed at release with `command_release_basis_changed`, `L/commanding/request_queue_store.ex:313`); booked contacts on routes that change (they keep their snapshot) | HOLD |
| Compatibility | kind-declared requirements (e.g. frame size vs catalog) | HOLD |

The result is cached by `(content_sha256, head revision)`, so re-opening the review page is cheap.
fe-setup's P4 aside calls `preview` with *unstaged* ops (the same function, no change set) to get
"changes N · keeps M" before staging.

## 7. Apply (and what the runtime sees)

`submit(scope, change_set_id, reason)` (reason required, ≥ 10 chars):
1. Freeze: `open → in_review`, lock the content hash, run `preview`. Any NO-GO → back to `open`
   with the checks. HOLDs need `acknowledged_holds: true`.
2. **Compose:** compute the post-state, build the fleet's spacecraft configuration entries from the
   effective profile + overrides (`profile-routing.md` §4), and compose the next binding set
   (reuse `MissionBindingComposer` / `Review.replace_contributions`).
3. **Request:** `Management.Activations.request(change_class: max(kinds), metadata:
   %{"change_set" => %{id, content_sha256, base_revision}, "spacecraft_configurations" => …})`.
   The policy decides between:
   - `approved` (direct): continue at step 4;
   - `approval_pending` (independent): the set waits. The reviewer must be distinct from **every
     author** in the set, not just the submitter. That is stricter than today's
     `distinct_approver`, and the domain adds it in the decision step.
4. **Execute, in one transaction** (mission advisory lock + `mission_config_heads` `FOR UPDATE`):
   1. Re-admit: head revision == `base_revision` (after auto-rebase) and content hash unchanged,
      else `:change_set_stale` → back to `open`.
   2. Apply every op through `kind.apply(multi, op)` (insert profile version, update spacecraft,
      materialize routes, …).
   3. Write the revision + entries, then bump the head.
   4. **If any op has runtime impact `:generation`:** `Governance.persist_binding_set` +
      `Activations.persist_activation` *in the same transaction* (it already handles the advisory
      lock, generation, admission, active row and OperationalEvent). Store `activation_id`
      and `generation` on the revision.
   5. Mark the set `applied`.
5. **After commit**, the existing tail: `Control.Missions.ensure_started` →
   `MissionRuntimeReconciler.apply_generation` → `TelemetryDecom.activation_applied` → execution
   completion. If routes/transports changed: `Contacts.Scheduler.notify_contact_changed`. Then
   publish `read-updates:config_applied`, and a timeline event `Config r6 applied · 2 changes ·
   actor`.
6. **Runtime settle signal:** the domain publishes
   `{:config_runtime, %{revision, activation_id, generation, runtime, degraded_partitions}}` on
   PubSub topic `config:<org>:<mission>`, once when apply returns and again when the reconciler
   reports `GenerationApplied` (or gives up into degraded). `runtime` is one of
   `converging | applied | degraded`, and `not_applicable` for revisions with no generation. api
   relays it on the console channel. `current/1` also returns the latest runtime state, so a page
   that loads late doesn't depend on the event.

**Atomicity, stated honestly.** Steps 4.1–4.5 are all-or-nothing: a failure there means
**nothing changed** and the set returns to `open`. Step 5 runs after commit. If the runtime fails
to converge, r6 *is* applied and the runtime keeps retrying (30 s safety reconcile). The UI must
say "r6 applied · runtime converging / degraded on N partitions", **not** "nothing changed". The
UX step list maps to: validate = 1; write config = 4.2–4.3; materialize routes = 4.2
(routing kind); notify runtime = 5; verify = execution `succeeded` + `GenerationApplied`.

**When a revision reaches the fleet (ux Q5):**
- **Telemetry decode / framing / apps:** from the moment each partition applies the new
  generation (normally seconds). Future traffic only (ADR-004 §2); stored frames are never
  reinterpreted.
- **Routes:** new bookings and plans use the new routes immediately. Contacts already booked or
  running keep the route they were booked with (path templates are version-pinned).
- **Commands:** commands authored against the old command basis are refused at release (fail
  closed). That is the "In flight" HOLD.

## 8. Rollback

`stage_rollback(scope, target_revision_number)`: allowed only when the open set is empty. For every
entity with entries in (target, head], the state at the target is the `before` of its earliest entry
after the target. It stages one change `Roll back to r4 (reverts r5, r6)` whose ops are
`kind.inverse(...)` against the *current* state (base = head). It then goes through checks, review
and apply like any set, and the revision gets `kind: rollback, rolls_back_to: 4`.
- A create is reverted by delete. For a spacecraft that has received traffic, the kind turns that
  into `archive` and reports it as a HOLD ("archives EARENDIL-501, keeps its history").
- Catalog revisions are immutable artifacts: rollback moves pins, never deletes imports.
- Rolling back past `r1` (the baseline) is impossible: there is no ledger before it.

## 9. Audit and history

The revision row *is* the audit record: who applied it, approvals (actor + reason, from
`activation_decisions`), why, when, summary, entries. Read APIs:
- `list_revisions(scope, page)`
- `get_revision(scope, n)` (entries + diff)
- `compare(scope, a, b)`
- `entity_history(scope, kind, id)`: also gives "since rN" for overrides.

Withdrawn and discarded changes stay queryable on the set for audit (the who/when of staging).

## 10. Migration of current data

1. **Baseline:** a migration writes `r1` (`kind: baseline`, summary "Configuration as of
   2026-11-xx", no entries) and `mission_config_heads` for every mission.
2. **Legacy writers keep working while the SPA ships.** They bypass staging but still produce
   revisions:
   - The legacy activation path (`Control.SpacecraftConfiguration.submit`) writes a revision
     `kind: legacy_activation` with entries derived from the snapshot diff, inside
     `persist_activation`.
   - Direct writers (profile creation, transport/rule forms) go through
     `Configuration.apply_now(scope, ops, reason)`: a one-change set, applied immediately when
     policy allows, or left in review.
3. **Cutover (phase 2):** spacecraft configuration drafts become `spacecraft` /
   `spacecraft_override` ops. `Drafts.save` stops writing desired-state app rows
   (`L/applications/spacecraft_configuration/application_inputs.ex:59-90`); that moves into
   `kind.apply`. The per-spacecraft review UI is retired in favour of the change-set review.
4. **Synthetic profiles** (`spacecraft_configuration_profile_<rev>`, created when a spacecraft's
   protocol differed from its profile) are converted to overrides. See `profile-routing.md` §6.

## 11. Placement (architecture check)

- `L/configuration/`: new context `:configuration`, management plane. Schemas, staging, diff,
  ledger, the `ConfigKind` behaviour. It depends on `identity` and `platform` only. I add it to
  `@context_paths`, `@domain_plane_paths` and the policy doc.
- Kind implementations live in their owning context (`L/comms/config_kinds/…`,
  `L/spacecraft/config_kinds/…`). They depend only on the behaviour, which lives in
  `L/platform/config_kind.ex`, so they need no new context edges.
- `L/control/configuration.ex`: `:composition` (like `control/missions.ex`). It wires kinds,
  preview, submit and execute, and calls Activations, the reconciler and the scheduler.
- Facade: `Cadence.Configuration` functions exposed through `Cadence`; api wraps them. The full
  list is in `docs/apogee/api/domain.md` once agreed.

## 12. Facade sketch (for api)

```
stage(scope, %{summary, source}, [op])          → {:ok, %{change_set_id, change_id, staged_count, base_revision}}
preview(scope, change_set_id | [op])            → {:ok, %{checks: [check], effects: [effect], diff: [change_diff]}}
current(scope)                                  → {:ok, %{head: rN, change_set: set | nil}}   # bar + CONFIG r5 · 2 STAGED
withdraw(scope, change_id) / discard(scope, set_id)
rebase(scope, op_id, :keep_mine | :take_live)
submit(scope, set_id, %{reason, acknowledged_holds}) → {:ok, %{state: :applied, revision: 6, staged_count: 2,
                                                          activation_id, generation,
                                                          runtime: :converging | :applied | :degraded | :not_applicable,
                                                          degraded_partitions: []}}
                                                    | {:ok, %{state: :in_review, activation_request_id}}
review(scope, set_id, :approve | :send_back, comment) → same shapes
stage_rollback(scope, n)                         → like stage
list_revisions / get_revision / compare / entity_history
```

Capabilities for the bootstrap (DECISIONS #2, mapped to today's policy actions until Cedar):
- `config.stage` (`manage_mission`)
- `config.apply` (`request_activation`)
- `config.review` (`approve_activation`)
- `config.rollback` (`request_activation`)
- `config.discard_any` (`organization_admin`)

## 13. Answers to ux (Changes.md questions)

1. **One open set per mission, shared?** Yes. It is frozen while in review.
2. **Remove one change and return it as a draft?** Yes: `withdraw`. The ops are kept and the
   surface rehydrates them for the author.
3. **Base revision + field paths, conflicts, rebase?** Yes: per op `base` values + `touched_paths`.
   Non-overlapping changes auto-rebase. Overlaps are conflicts with `keep_mine` / `take_live`.
   Same-path staging by two authors is refused at stage time.
4. **Effect dry run + readiness-after?** Yes, server-side, via a sandboxed apply (§6). It also
   works for unstaged ops (P4 aside).
5. **When does it reach in-flight spacecraft?** See §7: decode at the next generation apply
   (seconds), routes for new bookings only, old-basis commands refused at release.
6. **Rollback = new revision?** Yes (§8). History is append-only.

Wording correction for ux: "Apply failed · nothing changed" is only true before commit. After
commit, a runtime convergence problem is "applied, runtime degraded" (§7).

## 14. Phasing

- **P1 (model) — built:** tables, staging, ledger, baseline r1, kinds `spacecraft_profile`,
  `spacecraft`, `transport`, `ground_station`; submit/execute with direct + independent policy;
  revisions read; preview with validation + conflicts + effect.
- **P2:** `profile_routing_rule` + `spacecraft_override` + `catalog_assignment` (profile-routing.md),
  readiness-after and in-flight checks, rollback, legacy-activation revisions, synthetic-profile
  migration.
- **P3:** retire per-spacecraft review, `apply_now` for legacy writers, more kinds.

## 15. Open questions

- **director:** Is "frozen while in review" acceptable, or do you want staging into a *next* set
  while one is in review? (That is more complex: two sets and a rebase chain.)
- **director:** Should the reviewer have to be distinct from every author (my proposal) or only
  from the submitter (today's rule)?
- **api:** Does readiness live in a domain read I can call in-sandbox? I'd like your readiness
  endpoint to be backed by `Cadence.Reads.Readiness.mission/2`, which I'd write.
- **fe-setup:** `source` on a change (surface route + entity) is free-form for the UI. Is a
  `{surface, entity_kind, entity_id}` map enough?
