# Threat model: Mission Model & Spacecraft gates (DRAFT)

mms-security, 2026-11-19. Reviewers: fe-setup (squad lead), ca-security (security lead).
Status: DRAFT, audit in progress. Read from develop `a48743995`. Line numbers are as of this write;
re-grep before acting on them. One page per feature, in the format of ca-security's E1 model once
it lands. Until ca-security's checklist lands, reviews use ca-security's six points (C1-C6):

- **C1** the actor comes only from the authenticated scope; a body naming one is `422 actor_not_assignable`.
- **C2** fail closed when a rule can't be evaluated; mark gaps `# todo(authz):`.
- **C3** refuse before writing, including publishes from inside a transaction that can still roll back.
- **C4** org and mission scoping is server-side on every read and write, idempotency and dedup keys included.
- **C5** author separation covers every author since the last approved version (the #236 rule). A
  service identity's act counts as the act of every person accountable for it (its issuer and every
  credential rotation's actor). If that set isn't recorded, the author is unknown, and under
  'independent' an unknown author fails closed.
- **C6** nothing secret on GitHub, and no exploit steps in public issues.

## 1. The mission-model approval gate (E2 #208)

### Assets and actors

- **Asset:** an approved mission-model revision. Once approved, a catalog generation may introduce it
  and a promotion activation may roll it out to the data plane (`MissionModels.request_promotion`).
- **Importers:** whoever brings content in.
  - People: `operate_mission`, which is any active org member today (`policy.ex:125`).
  - Service identities bound to the mission: `operate_mission` via `authorize_service_mission`.
  - Seeds: `Catalog.Actor.system/2`.
- **Approvers:** organization admins only, never a service (`Policy :approve_mission_model`, `policy.ex:92-99`).

### Entry points that import (all record `requested_by`)

| Path | Authorizes | Actor from |
|---|---|---|
| Console upload, `console/catalog_import_controller.ex` → `Catalog.Upload.import_revision` | `operate_mission` | `Actor.from_scope` |
| Console reimport, `console/catalog_controller.ex:58` → `Catalog.Reimport.execute` | `operate_mission` | `Actor.from_scope` |
| Host page and mission-catalog action (`host_page_live.ex:445`, `mission_catalog/action_provider.ex:125`) → `Reimport.execute` | `operate_mission` | `Actor.from_scope` |
| REST `POST …/catalog_import_runs` (`catalog_import_run_controller.ex:28`) → `Catalog.start_import_run` | `manage_mission` (= operate) | `ControlPlaneAccess.actor_document` |
| Seed (`dev/reflect_orbital/configuration.exs:104`) | n/a | `Actor.system("seed:…")` |

`Catalog.start_import_run`/`start_revision_import` refuse a run with no recorded actor (`Actor.recorded/1`).

### Separation (DECISIONS #92 (a))

Under 'independent', `RevisionDecisions.independent/5` refuses an approver who is in
`Catalog.model_importers/3`. That set is the union of `created_by` on catalog revisions naming the model
revision and the person requester of every completed run whose result names it, scoped by org + mission.
Services, the system actor and failed runs count no one. A run still in progress doesn't count until it
completes; that's harmless, since it's the same as approving before importing.

### Findings

- **MM-1 (high; C5): a service identity breaks importer/approver separation.**
  - How: a mission-bound service identity can import. Its run counts no one as an importer, and a revision
    with no recorded importer "can be approved by any administrator" (`revision_decisions.ex:10-12`).
  - `service_identities` records no issuer or rotation actor (`auth/service_identity_row.ex`), so the admin
    who issued the identity can import through it and approve the same content alone. Same class as
    approval-sweep Ruling C.
  - Fix (agreed with ca-security): (b) now: under 'independent', a revision whose importers include a
    service with no accountable person on record can't be approved until a person imports it or the set
    is known. Then (a): record the issuer and every rotation's actor on the service identity, and count
    them. Not (c): refusing service imports breaks real automation.
  - Applies across kinds. Director approved 11-19; filed as **#280** under #207, placed right after #233.
#### MM-1 impact list per approval kind (director 11-19: impact first, then build)

Merged with ca-security's notes (11-19); one list.

**Rule (ca-security, 11-19):**
- The accountable set (issuer + every rotator, transitively) REPLACES "self" wherever a kind ALREADY
  refuses self-approval, whatever the mode. It never adds a separation the kind doesn't have; it only
  widens who counts as self.
  - So under 'independent' it applies where the setting creates the separation (model revisions, contact
    plans, change sets).
  - Under every mode it applies where the kind always refuses self-approval (activations; commands
    wherever a second GO is required).
- An approver in the set is refused; an unknown set fails closed.
- Today every check below compares **person ids only**, so a service author is invisible to all of them.

**Who can be a service, and with what:** only `organization_admin` and `mission_admin` can be granted to a
service (`ParamParser.normalize_capability`, the console's `@capabilities`); `platform_admin` can't.
`:manage_service_identities` is `organization_admin` via `authorize_organization_capability`, which doesn't
check `actor_kind`. So a service with `organization_admin` can issue and rotate other services, and the
set must be transitive.

**Where accountability is recorded today (the input every kind needs):**

| Path | Issue / rotate recorded? |
|---|---|
| Platform-admin console (`console/admin_controller.ex` → `ConsoleAdmin.issue_service_identity`/`rotate_service_identity`, `console_admin.ex:77-110`) | Admin audit event (`service_identity_issued`/`_rotated`, actor = admin), written AFTER the change, outside its transaction |
| Org console (`console/service_identity_controller.ex` → `ServiceIdentityAdministration.create/rotate`; the platform-admin path also creates through it) | Create: `metadata["created_by"]` from the scope, in the same insert (`service_identity_administration.ex:29`); `%{"kind" => "unknown"}` when the caller is a service. A free-form map, not a column. Rotate: nothing |
| REST `POST /api/…/service_identities` (`service_identity_controller.ex:29`) → `Auth.issue_service_identity/1` | Nothing server-built. **Client `metadata` is copied verbatim** (`api/identity_params.ex:53`), so a caller can write any `created_by` (C1, DECISIONS #30/#32). `service_identity_id` is client-assignable too |
| Rotation core (`auth/service_identity_keys.ex:16`) | Only `key_rotated_at` in metadata; no actor |

- **Never read accountability from `metadata`:** it's client-writable on REST. Use server-built columns, and
  REST refuses `metadata.created_by` (and any accountability key) with `422 actor_not_assignable`.

- **Build:** record the issuer and each rotator ON the identity, in the same transaction as the issue or
  rotate, on all three paths (`Auth.issue_service_identity/1` and `ServiceIdentityKeys.rotate/2` take the
  acting scope). An audit event alone isn't enough: it's written outside the transaction and isn't
  keyed for a separation check.
- **Recursion:** a service with `organization_admin` capability can create identities over REST. Its
  accountable set is then the creating service's set, resolved recursively. A cycle or an unknown link
  makes the whole set unknown, which fails closed.

**Per kind** (who a service can author as; where the check is; what changes):

| Kind | Can a service author it today? | Check today | Change |
|---|---|---|---|
| Mission-model revisions | Yes: REST `catalog_import_runs`, console upload/reimport with a service scope | `RevisionDecisions.independent/5` ← `ModelImporters` (people only; services dropped) | `ModelImporters` returns service importers too. Expand them to their accountable set; unknown → `approval_authors_unknown`. Also closes MM-2 source 2 |
| Activations (incl. spacecraft-configuration reviews) | Yes: REST `POST /activations` (`authorize_mission`; `actor/1` accepts a service). Approving is human-only (`human_activation_approver_required`) | `distinct_approver/2` (`management/activations.ex:549`) compares only when `requester_actor_kind == :user`; applies in every mode | Service requester → its set, **in every mode, 'direct' included** (rule above) |
| Configuration change sets | No: only the console session API (users) writes changes | `Submission.independent/2` (`configuration/submission.ex:436`): reviewer not in `[submitted_by \| change authors]` | None now. A guard test that a service author fails closed, so a future REST path can't open it |
| Contact plans | Yes: planning runs author as a service (planner / fleet planning runs); a service submits with an automation grant (`contact_plans.ex:1208`) and **approves** with one (`contact_plan_approvals` `authorize_actor` `:service`/`:approved`) | `ContactPlanApprovals.separate_approver/5` (`:560`) checks a user actor only, so a service approver skips separation | Service author → its set. A service APPROVER's set is its accountable people plus the grant's approver; refused when it meets the author set. The planner proceeds when an approver outside the set approves. Open: who approves a grant (`grant.approved_by`), and is that person in the set? (yes by the rule above) |
| Fleet planning policies | Author check matches `user_id` only (`FleetPlanningPolicies.not_author/2`, `:354`); approving is user-only (`fleet_planning_policies.ex:584`) | Always refuses the author | Service author → its set (it already refuses self, in every mode) |
| Command requests | Yes: REST `command_requests`, `command_stages/…/submit` (queue submission: to confirm). Review/approve is user-only (`management/commanding/review_access.ex`) | `LifecyclePolicy.ensure_not_self_approval/2` (`commanding/lifecycle_policy.ex:59`): user_id only. Not governed by the setting (Ruling A) | Service requester → its set **wherever a second GO is required**, whatever the setting (rule above) |
| Command groups | Via the console only? (group submission; to confirm) | `group_decision.ex:85`: `requested_by["user_id"] == actor["user_id"]` | As command requests |
| Provider changes | To confirm whether a service can author one (REST `provider_profiles` writes are direct, not change requests). Approving is user-only (`provider_change_approvals.ex:111`) | `:approve_provider_changes` (org admins) | If a service can author one and the kind refuses self, as above (ca-security confirms after #233) |
| Qualification cases | Human-only approver (`comparison.ex:504`) | To confirm the author check | ca-security confirms after #233 |

**Shared pieces:** one function, `Accountability.authors(org, actor_documents) :: {:ok, [user_id]} |
{:error, :unknown}`, used by every kind; one refusal, `approval_authors_unknown` (409, `details.kind`), like
#236's `activation_approver_authors_unknown`. The org admin's "record who is accountable" action is
audited, and that admin joins the set.

**Out of scope:** seed (system-actor) authorship (MM-2 source 3); grandfathering legacy identities (the
dev reset recreates them, DECISIONS #112).

- **MM-2 (medium; C2): `importer_recorded=false` lets any admin approve.** Three sources:
  1. pre-11-17 runs that stored `%{}` (legacy; gone at the dev reset, DECISIONS #112);
  2. service imports (MM-1);
  3. seed imports under the system actor, which DECISIONS #113(4) relies on: "a second admin approves".
     A person runs the seed and nothing records who.
  - Proposal (pending ca-security): fail closed for 1 and 2. For 3, the seed run records who ran it and
    that person counts as an importer; until then #113(4) stays a procedure rule.
- **MM-3 (#119, in progress, mms-engineer): content-addressed revisions across tenants.**
  `mission_model_revisions` and `mission_model_layers` have global primary keys and are inserted
  `on_conflict: :nothing` (`mission_models.ex:280-290`). Today ids carry per-run provenance, so they never
  collide. Once #119 makes them content digests, the agreed conditions apply:
  - org + mission in both bases;
  - re-read after insert, keyed on PK + org + mission, failing closed on a mismatch;
  - the digest covers every compiled input;
  - `matched_existing` reported with its status;
  - decided revisions never reopen;
  - lands in or after the dev reset slot.
  `persist_layer/1` already re-reads by its own org + mission (`mission_models.ex:79-85`), so a foreign
  row reads as not found.
- **MM-4 (low; C3): an upload publishes a job inside a transaction.** `Upload.import_revision` wraps
  `start_revision_import` in `Repo.transaction`. `start_import_run` calls `Jobs.enqueue`, which publishes
  `Jobs.Available` at once instead of `Jobs.enqueue_in_transaction` + publish after commit
  (`jobs.ex:14-27`). Nothing fails after the enqueue today, so a rollback can't strand a published job,
  but the order is fragile.
- **MM-5 (low; hardening): `request_promotion` writes before it authorizes.** `MissionModels.request_promotion`
  runs `Comparison.run` (which inserts a comparison report) before `ManagementActivations.request`
  authorizes. Both callers (`activation_controller.ex:33`, `telemetry_decom.ex`) authorize first, so it's
  not reachable, but the domain function relies on its callers. Authorize at the top.

### Checked, fine

- Catalog store functions take org + mission and filter on both. `MissionModels` reads that take a nil org
  match only rows with a nil org (`organization_filter/2`, `mission_models.ex:365`), never another tenant's.
- Approve and reject take the revision row lock; approving an approved revision is a no-op, and the first
  approver stays on record.

## 2. Spacecraft configuration activation (#150, #235, #152)

### Findings

- **SC-1 (medium; C1/C4-adjacent; #235): request metadata a client sets drives what the approver sees.**
  - `Control.Activations.Description.describe/1` builds the activation row's kind, summary and spacecraft
    list (`activation_requests/rows.ex:44,70`), the apply attention item and the refusal details from
    request metadata.
  - REST `POST …/activations` (`activation_controller.ex:28`) accepts client `metadata` with only five
    reserved keys (`activation_params.ex:7`). `composition`, `application`, `change_set`,
    `triggering_spacecraft_id`, `contributors`, `reviewed_configuration_basis` and
    `mission_model_comparison` are not reserved. So a requester can label a model promotion as a decom
    change on chosen spacecraft.
  - Display only: what applies is the binding set, `named/3` is org + mission scoped, and no check reads
    these ids for a decision.
  - Fix: the description reads only server-built keys, and the REST route reserves every key the server
    builds (better: an allowlist of client keys).

_(Audit in progress: drafts and reviews, the forced approval on a legacy conversion batch, the same-SCID
HOLD, change-set authorship.)_

## 3. Actor on every write path (audit table)

_(In progress: `spacecraft_store*`, `spacecraft_type_store*`, `activations*`, `applications*`.)_

## 4. Tenant boundaries

_(In progress.)_

## 5. Secrets

_(In progress.)_

## Issues to file (once gh works on laptop 2)

- ~~Bug under #207~~ FILED as **#280** (fe-setup, 11-19): "An admin can approve their own work when it was done
  through a service identity they issued" (MM-1; impact list above).
- Bug under #208 (domain:mission-model; component:api): "Activation request metadata a client sends
  changes what the approver is shown" (SC-1). Note: no exploit steps in the public text (C6).
- Task under #208: MM-4 and MM-5 hardening.
