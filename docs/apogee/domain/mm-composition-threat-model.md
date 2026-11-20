# Threat model: mission composition and binding records (DRAFT, before design D)

Owner: mms-security. Status: a draft from domain's plan, ahead of design D. When D lands it gets
refined against D, and every question in §5 needs D's answer before D is approved.

Sources:
- `mission-model-build-plan.md` §2: phase 2 (composition), phase 4 (binding storage and heads);
- `config-materialization-model.md` §4: the content-addressed configuration model;
- DECISIONS #92 (the model gate) and #108 (stored hashes);
- #116 (append-only decision records);
- #280 (service accountability);
- #38 (a command releases only over its own spacecraft).

It folds in #293's earlier MM&S findings (§6). Severity follows the review checklist (C1–C5).

## 1. Scope

**In scope:**
- Phase 2 (D and E): the mission composition record, imports mounted under subtrees, authored
  layers, and the model gate re-keyed from catalog revision to composition.
- Phase 4 (F to I): binding-set versions as content-addressed artifacts plus membership, per-craft
  heads and append-only assignment history, `spacecraft_application_bindings` as a projection, and
  the runtime's index built from the membership.

**Out of scope here:** phase 1, runtime snapshots (api-ops reviews them); phase 3's monitoring lane,
except where it writes authored layers (CB-6); phases 5 and 6.

## 2. Assets

| Asset | Why it matters | Where |
|---|---|---|
| **Composition record** | What a profile runs. Replaces the catalog revision as the pinned unit. | D (new) |
| **Imported layer** | A catalog import mounted at a subtree. The catalog revision stays as provenance. | C, D |
| **Authored layer** | Mission-authored limits, derived telemetry and alarms (phase 3). | D, J |
| **Model gate state** | Approved or rejected per composition. Today it's keyed by the catalog revision (`:mission_model_revision_not_in_catalog`). | E |
| **Comparison baseline** | What a new composition is compared against. It's catalog-keyed today (`model_approval_gate.ex:75-88`). | E |
| **Profile pin** | Which composition a profile (and so its craft) runs. | D |
| **Configuration artifact** | Shared, content-addressed resolved configuration and binding template. | F, G |
| **Expansion** | Template plus a craft's identity parameters, giving the concrete instances and rules. | F, I |
| **Binding-set membership** | `{generation, [(artifact_sha, [spacecraft…])]}`. What's active. | F |
| **`binding_set_content_sha256`** | Activation evidence. Its meaning changes for new versions. | F |
| **Spacecraft head** | One row per craft: `artifact_sha`, identity parameters, overrides, version. | G |
| **Assignment history** | Append-only per-craft audit, replacing the per-change revision documents. | G |
| **`spacecraft_application_bindings`** | Becomes a projection of the head, or is deleted. | H |

## 3. Actors and trust boundaries

- **Importers:** a person, a service identity (counted as its accountable people, #280), or Cadence's
  seed actor (counts no one, MM-2). An import is untrusted input: its declarations and mount
  requests are parsed, never executed.
- **Authors of authored layers:** through change sets in the monitoring lane, with four-eyes (#92 (a),
  #280's accountability).
- **Approvers:** the model gate (org admin, person-only, separated from importers and authors), and
  the activation approver.
- **The runtime:** consumes expanded bindings. It trusts the expansion and must not have to.
- **Tenants:** organization, then mission. Every artifact, composition and head must be scoped to
  both, or proven safe to share (CB-7).
- **REST bearers:** always services, holding `:manage_mission` at most for setup writes (#293's
  correction). They must not reach composition or pin writes outside the change-set and gate path.

Boundaries the design must hold: import input → compiler; composition → gate; gate → profile pin;
pin → head and assignment; head plus artifact → expansion → runtime; tenant → tenant.

## 4. Threats (draft; each says what D must show; refined 11-20 from ca-security, domain and mms-engineer)

**Composition and the gate (phase 2)**

- **CB-1 (high; C5): an approved import plus an approved authored layer is approved as a whole.**
  - The addendum's rule makes the combination approved without anyone reviewing the combination.
  - An authored layer can shadow or rewrite imported values (a limit's bounds, a derived parameter's
    inputs), so two separately harmless approvals can compose into something nobody saw.
  - D must say:
    - whether the comparison report runs on the **composed** result before the composition is usable;
    - who approves a composition whose layers were each approved by different people;
    - whether separation holds across layers: the authored layer's author must not approve a
      composition that includes their own layer, with #280's accountability for services;
    - that the approval's digest (`DecisionRecord.subject.digest`) covers every layer's content hash
      plus the mount map, so approving one combination can't be replayed onto another
      (ca-security).
  - domain (11-20): D answers yes, the comparison on the composed result gates it.
- **CB-2 (high; C3): a content-addressed composition across tenants.**
  - If composition ids are content hashes, the address must include org and mission. Insert-or-get
    must re-read by key plus org plus mission and fail closed on a mismatch, as #119 had to
    (`:mission_model_scope_mismatch`). Otherwise one tenant can pre-create or observe another's record.
- **CB-3 (high; C1): who moves a profile's pin.**
  - Repointing a profile to another composition changes what every craft on it runs.
  - D must say:
    - whether a pin change is a change-set kind with four-eyes;
    - whether a pin to an unapproved composition is refused at write time **and** at activation (the
      gate re-checked under the activation lock, as today);
    - who may pin: an org admin, a mission admin, or a service with `:manage_mission`.
- **CB-4 (high; C2): a window where neither gate applies during the re-key.**
  - E moves the approval and baseline from catalog to composition. Through the migration and the
    code switch, a revision must never become usable because the old guard is gone and the new one
    isn't in force.
  - The one-to-one migration must carry approval state **exactly**: an unapproved catalog revision
    never becomes an approved composition, and a rejected one stays rejected.
  - D must name: the transaction order, the guard test (no approved composition without a gate
    decision row or a migrated equivalent), and the evidence for migrated approvals (the decision
    record's `subject.digest`).
- **CB-5 (medium; C4): mounting and shadowing.**
  - Imports are mounted under subtrees so a second import composes instead of being silently dropped
    (`MM_DUPLICATE_IDENTITY`).
  - A mount must not claim root, another import's subtree, or an authored layer's namespace, and a
    collision must be a loud refusal, never a silent drop or override.
  - D must give the mount-path grammar and the collision rule, and say who chooses the mount point:
    the importer or a reviewed config.
  - Built in C (mms-engineer): the grammar, no root mount, no authored mounts, and collisions as
    BLOCKING diagnostics. D must add that a composition with any blocking diagnostic is refused at
    the record's write and at pin.
- **CB-6 (medium; C5): authored layers and separation.**
  - Authored layers arrive by change set (phase 3). The change-set review's separation (#280:
    services count as their people) must cover them.
  - domain (11-20): an authored layer has no separate gate decision. The monitoring change set's
    review IS its approval (the addendum), with separation as for change sets. So the threat is that
    review's separation, plus CB-1's composed-result comparison. D shows both.

**Binding records (phase 4)**

- **CB-7 (high; C3): shared artifacts across tenants.**
  - Artifacts are addressed by `sha256(resolved content without spacecraft identity)`. If that
    address is global, two tenants with identical content share a row. That leaks existence and
    timing, and lets one tenant's insert-or-get trust a row another created.
  - D or F must scope artifacts to org and mission, or prove sharing is safe: the artifact holds
    nothing tenant-specific, and readers never treat its creator or its time as theirs. Either way,
    re-read and verify scope after an insert-or-get, as CB-2.
  - An artifact never holds a secret (credentials, keys, endpoint auth). Those stay per craft or per
    endpoint, referenced by id, never in shared content (ca-security).
  - **Status:** met by 4a as built (#475), per domain and mms-engineer: per-tenant artifacts, a write
    guard and a hash check on read. mms-security to verify against #475's code.
- **CB-8 (high; C3/#38): expansion without the endpoint.**
  - Telemetry endpoint scoping moves from stored rows to expansion. A template rule expanded without
    its endpoint parameter would match frames across craft. That's #38's class for telemetry, and
    data from one craft attributed to another.
  - The plan's mitigation must be in F's acceptance:
    - expansion is the only constructor;
    - a template can't be admitted without the endpoint parameter;
    - a test proves a frame on X never selects an instance of Y.
  - Add that the runtime index (I) is built only from expanded instances, never raw templates.
  - **Status:** met by #475, per domain and mms-engineer: a structural endpoint and the #38 test.
    mms-security to verify; I's index rule is still for I.
- **CB-9 (high; C2): membership integrity and activation evidence.**
  - Every spacecraft in a membership must belong to the mission, checked at write.
  - Membership is written only by the activation path, under the activation lock.
  - The activation evidence must still pin exactly what runs.
  - `expand(compress(v)) == v` for every stored version is the proof for 4a. Run it on dev in a qa
    slot, and keep it as a test over fixtures.
  - **Correction (domain and mms-engineer, 11-20):** 4a as built (#475) keeps
    `binding_set_content_sha256` as the expanded set's hash, unchanged from the rows form, with
    goldens at 6 and 500 craft. The evidence doesn't change, and #108 isn't triggered. Because it
    hashes the expanded result, it already pins exactly what expansion produced, which covers
    ca-security's 'pin the expansion version' point. A future change to expansion that alters the
    output changes the hash, and so the evidence, as it should.
  - **Condition (ca-security, 11-20):** whatever admits or runs a version (activation, the runtime
    index, replay) recomputes the expanded hash from the artifact plus the identity parameters with
    today's code, compares it to the approved evidence, and fails closed on a mismatch. It never
    trusts a stored expanded hash. So an expansion-code change shows up as a refused activation, never
    a silent change to what runs.
  - **Status (verified by mms-security on develop b4a646ef8, 11-20):** met for 4a, at three points,
    each with today's code and failing closed:
    - read: `governance.ex` `hydrate_binding_set/1` (membership form) recomputes and refuses with
      `:binding_set_expansion_mismatch`, and every reader goes through `fetch_binding_set`;
    - admit: `control/activations/preflight.ex` `exact_approved_content/2` against the approved
      activation's hash;
    - run: `runtime/mission_runtime_spec.ex` `validate_content_hash/2` before a runtime spec exists.
  - D carries the same three points for heads (G) and the index (I).
- **CB-10 (medium; C2): heads and assignment history.**
  - Assignment history replaces per-change revision documents as per-craft audit, so it must be
    append-only (#116's triggers, as #436 did for accountables).
  - The head moves only through the change-set apply path, and every head change writes its
    assignment row in the same transaction.
  - A head pointing to an artifact or composition that isn't approved and active must be
    unreachable (CB-3).
- **CB-11 (medium; C2): collecting unreferenced artifacts.**
  - "Artifacts referenced by any assignment are never deleted." Collection must lock against a
    concurrent new assignment (an artifact unreferenced at scan time, then referenced, then deleted).
  - Every historical activation's evidence must stay resolvable for replay and audit. D or G gives
    the lock or the reference check inside the delete.
- **CB-12 (medium; C4): retiring `spacecraft_application_bindings` (H).**
  - Some readers make decisions from it: #38's release check (a command releases only over its own
    spacecraft) and the console's "which catalog is this craft on".
  - The reader inventory must list each authorization-relevant reader, and none may read a stale
    projection. The projection is written in the head's transaction, or each reader moves to the head.
- **CB-14 (high; C1/C5): head overrides and identity parameters bypass the composition approval**
  (ca-security).
  - A compile-affecting override (catalog, APIDs, protocol) selects a different artifact, so it
    changes what a craft runs without the composition being re-approved. An identity override (SCID,
    endpoint) is bound at expansion, so a wrong one routes another craft's frames or commands (#38).
  - D or G must make every override change a change-set kind with four-eyes (#280's separation),
    re-run #38's checks at apply and at activation, and refuse an override that points to an
    unapproved artifact or composition.
- **CB-15 (medium; C2): an approval withdrawn while craft run it** (ca-security; #499's pattern).
  - If a composition's approval is revoked or superseded, D must say what happens to craft whose
    head pins it: suspended (as #499 suspends grants), kept until the next activation, or refused at
    the next generation.
  - Whatever happens is recorded, and the craft's state says why. Silent continued use of a revoked
    composition is the failure to rule out.
- **CB-13 (low; availability): unbounded composition or expansion.** Bounds on layer count, mount
  depth and expansion size, so one import or authored layer can't make compile or expansion
  unbounded. A refused oversize write records nothing. C has no layer or depth bounds
  (mms-engineer), so this is for D.

## 5. Questions design D must answer (for mms-security's review of D)

1. **Composition approval (CB-1, CB-6):** the composed-result comparison gates it (domain: yes). Who
   approves, which ids is the approver separated from (importers, authored-layer authors, their
   services' people), and does the approval digest cover every layer plus the mount map?
2. **Identity (CB-2):** is a composition content-addressed? Is the address scoped to org and
   mission? What's the re-read check?
3. **Pin (CB-3):** is a pin change a change-set kind? Who may make one? Is an unapproved pin refused
   at write and re-checked at activation?
4. **The gate re-key (CB-4):** the order of the migration and the code switch, how approval and
   rejection carry over one-to-one, the guard test, and the evidence for migrated approvals.
5. **Mounting (CB-5):** C's grammar and BLOCKING collisions, plus D's refusal of a composition with
   any blocking diagnostic at the record's write and at pin. Who picks the mount?
6. **Artifact scope (CB-7):** met by #475 (to verify); no secrets in artifacts.
7. **Expansion (CB-8):** F's acceptance includes the three #38 mitigations, and I builds only from
   expanded instances.
8. **Evidence (CB-9):** unchanged by 4a (the expanded set's hash; goldens in #475). D keeps it so
   for compositions. Every admit or run recomputes the expanded hash with today's code and fails
   closed against the approved evidence, never trusting a stored one.
9. **Audit (CB-10, CB-11):** assignment history append-only by trigger; head writes atomic with
   their assignment row; collection safe against a racing assignment.
10. **Projection (CB-12):** the reader inventory, with authorization readers called out.
11. **Bounds (CB-13):** layer, depth and expansion limits (none in C).
12. **Overrides (CB-14):** every compile-affecting and identity override is a change-set kind with
    four-eyes; #38 re-checked at apply and activation; no override to an unapproved artifact.
13. **Withdrawn approvals (CB-15):** what running craft do, and what's recorded.
14. **Old data (#112):** each migration reads old rows. The plan says phases 2 and 4 migrate rather
    than reset; each PR shows it, as #497 had to for grants (a one-to-one fill that keeps old rows
    readable and refused where they must be).

## 6. Carried from #293 (the MM&S gates threat model)

| Item | Status |
|---|---|
| MM-1 (service breaks importer/approver separation) | Fixed: #280 (#435), plus #283 (#497) for grants and #436 (#504) for append-only accountables. |
| MM-2 (`importer_recorded=false`; seed counts no one) | Open: #513 (the seed runner is recorded and counts as an importer). #435 made `importer_recorded` count services. |
| MM-3 (#119 content-addressed revisions across tenants) | Fixed by #119's scoped re-read. CB-2 and CB-7 apply the same rule to compositions and artifacts. |
| MM-4 (upload publishes a job inside a transaction) | Open, low. |
| MM-5 (`request_promotion` writes before it authorizes) | Open, low. |
| MM-6 (qualification cases have no second person) | Open, dormant. |
| SC-1 (client-set request metadata drives the approver's view) | Likely closed for spacecraft configuration by #329 (L10 derives what a request changes; ca-security). To verify when #235 closes. |
| SC-2, SC-3 (REST spacecraft create outside change sets) | Fixed: #328 (#332). |
| Actor naming (#146's rule) | Fixed across MM&S: #365, #366 (#474), #471 (#487); #511 (approved, landing). The other squads' reads are #462. |

#293's §3–5 (the actor audit, tenant boundaries, secrets) carry over as open sections here. They
get filled in when D's records exist, since composition and binding records are the new write paths.
