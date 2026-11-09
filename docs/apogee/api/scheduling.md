# Scheduling endpoints (S2–S6, S8)

Owner: **api** (DECISIONS #26). Consumer: **lead** (K1 Plan, K2 Re-plan). S1 passes and S10 push
are api-ops'. Base: `/api/console/v1/missions/:mission_id`. Conventions: [README.md](README.md).

Status: decisions agreed (DECISIONS #27, #28). **Implemented:** S6 list, plan detail with S2 demand,
S3 drafts (start/read/continue) and S5 submit/execute with acknowledged exceptions. Planning setup, day demand,
S4 edits/alternatives and S8 re-plan (K2 v1: after provider changes) are also in.

## 1. What the domain actually does (survey)

| Need | Domain today | Consequence |
| --- | --- | --- |
| Draft a day (S3) | `FleetPlanningStarts.preview/create` (evidence pattern) creates a *queued* fleet run; `FleetPlanner.run` executes it **synchronously**: provider searches per requirement (slow, real I/O), optimize, then materialize a candidate `ContactPlan` (draft). | Must run outside the request; no progress events exist. |
| Edit the draft (S4) | No add/remove inside a run. The only edit is `version_plan(plan, expected_version, selected_snapshot_ids/locked_snapshot_ids)` on the **candidate plan**. Only snapshots found by the run's searches are eligible. Coverage, conflicts and unsatisfied are recomputed and **persisted** as a new plan version (no dry run). | "Add a pass" = pick from the run's unselected opportunities. Each edit is a plan version (gives r41 → r42 for free). |
| Alternatives + effect (S4) | Nothing. Pure building block: `RequirementEvaluator.evaluate_selection/3`. | I compute effects in the read, with no persistence. |
| Demand (S2) | Pure evaluator per **requirement version** (spacecraft + window); persisted coverage on plan versions and run results. | Group by spacecraft for the "2 / 3" view. |
| Submit (S5) | `submit_plan` (draft → pending_approval), then `approve` (**organization_admin only**; requires **no conflicts, no unsatisfied requirements**, ≥ 1 selection), then `execute_approved_plan` (books with providers **synchronously**; idempotent per item). | A partial plan can't be submitted; members can only request approval. |
| Plans list (S6) | `list_plans` is unbounded. | Filter by day/state in the read and cap at 100. |
| Re-plan (S8) | A repair creates a **successor run** with a **new candidate plan** (not a version), locking committed passes. There is no diff and no apply. | I compute moved/dropped by diffing selections; apply = submit → approve → execute on the new plan. |

## 2. Decisions needed (lead + director)

1. **Async execution for S3 (draft) and S5/S8 (execute).** Proposal: run them under a supervised
   task (`Task.Supervisor`) in the web node. Return `202` with the run or plan id, and push
   `scheduling_progress {kind: draft|execute, id, phase, state, at}` on `mission:<id>`. The run and
   plan rows are the durable state, so a client that reconnects reads them. If the node dies
   mid-run, the run stays `running`/the plan stays `executing`. "Continue" recovers a run
   (`FleetRunActions :continue`), and execution items are idempotent, so re-execute is safe.
   **No new tables or migrations.** The alternative (a durable job type + journal table like
   the workspace's) is more robust, but it needs domain work and a migration. *Recommend the
   supervised task for v1.*
2. **Idempotency (`operation_id`).** Draft creation is already guarded by the evidence pattern
   (preview → create with the same evidence sha), and execution is idempotent per item. Proposal:
   accept `operation_id` and keep an in-memory node-local map (operation → result) for replays
   within 15 min. No durable journal in v1. *Recommend.*
3. **Approval (ux Q9).** The domain requires an org admin to approve, and approval requires a
   fully satisfied, conflict-free plan. Proposal for "Submit N requests": an org admin's submit
   does submit + approve + execute in one action; a member's submit moves the plan to
   `pending_approval` and returns `state: pending_approval` (the UI shows "waiting for an admin").
   Unsatisfied or conflicting drafts return `422 plan_not_ready` with the coverage, so K1 can show
   what blocks submit. Relaxing either rule is a domain/director call.
4. **Policy prerequisite.** Drafting needs an active fleet planning policy and at least one active
   requirement in the window. Missing either → `422 planning_not_set_up` (`details.missing`), and
   readiness should surface it. There's no console setup for policies yet. Is that a Setup gap
   to schedule?

## 3. Proposed endpoints

- **S6** `GET /contact-plans?day=YYYY-MM-DD&state=` → `{plans: [{id, version, state, day_start, day_end,
  author, counts: {selected, conflicts, unsatisfied}, updated_at}]}` (≤ 100, newest first).
- **S3** `POST /contact-plans/drafts {day, operation_id}` → `202 {run_id, state: queued}`. It runs
  preview + create + run in the task. `GET /contact-plans/drafts/:run_id` → `{run: {id, state, phase,
  horizon, failure}, plan: {id, version, state} | null, totals: {passes, minutes, rule_met, rule_total,
  conflicts}, passes: [{snapshot_id, spacecraft_id, station, starts_at, ends_at, disposition, score}]}`.
- **S2** `GET /demand?plan_id=&version=` (or `?run_id=`) → per spacecraft `{spacecraft_id, rule_met,
  contacts: {have, need}, reasons: [...]}` + `rules: [{requirement_id, version, text, source}]`. The
  `day=` form reads the latest plan for that day.
- **S4** `POST /contact-plans/:plan_id/versions {expected_version, add: [snapshot_id], remove:
  [snapshot_id]}` → the new version + totals + per-spacecraft effect.
  `GET /contact-plans/:plan_id/alternatives?spacecraft_id=` → unselected opportunities of the
  plan's runs for that spacecraft, each with `effect: {rule_met_after, contacts_after,
  clashes_with: [snapshot_id]}`.
- **S5** `POST /contact-plans/:plan_id/submit {expected_version, reason, operation_id}` → as in
  §2.3; when executing, `202 {state: executing}` and the per-item state arrives via S1/S10.
- **S8** `POST /contact-plans/:plan_id/repairs {from, to, operation_id}` → `202 {run_id}`;
  `GET /contact-plans/repairs/:run_id` → `{source_plan, plan (new), moved: [...], dropped: [...],
  added: [...], totals}`; apply = S5 submit on the new plan.

## 4. Implemented contracts

### Live: `scheduling_progress` on `mission:<id>`

`{kind: "draft" | "execute", id, state: "running" | "finished" | "failed", reason, at}`, sent when
off-request work starts and ends. It also emits `invalidate` with `contacts`. Treat it as a hint and
refetch the read. The read is the truth.

### `GET /contact-plans?day=YYYY-MM-DD&state=` (S6)

`{plans: [{id, version, state, window: {from, to}, author, counts: {passes, minutes, conflicts,
unsatisfied}, ready_to_approve, updated_at}]}`, newest first, capped at 100. `window` spans the
selected passes (`null` for an empty plan); `day` matches the window's start date (UTC). `state` is
one of `draft, pending_approval, approved, executing, partially_reserved, reserved, failed,
canceled, superseded`.

### `GET /contact-plans/:plan_id[?version=n]`

The list row, plus:
- `passes: [{snapshot_id, spacecraft_id, station, starts_at, ends_at, synthetic, locked}]`
- `demand: {rule_met, rule_total, spacecraft: [{spacecraft_id, rule_met, contacts: {have, need},
  reasons: [code]}], rules: [{requirement_id, version, spacecraft_id, text, source: "requirement",
  window}]}` (S2, from the version's persisted coverage)
- `unmet: [{requirement_id, requirement_version, spacecraft_id, why: [code]}]`: what an approver
  must acknowledge (DECISIONS #28)
- `conflicts`: always block approval and submit (`422 plan_not_ready` carries them in
  `details.conflicts`). Two codes:
  - `{code: "selected_contacts_overlap", spacecraft_id, snapshot_ids}`: overlapping passes for one
    spacecraft;
  - `{code: "station_unavailable", ground_station_id, window_id, kind: "outage" | "maintenance",
    snapshot_ids}`: passes inside an active outage or maintenance window on their station (U26),
    grouped per window. These carry no `spacecraft_id` key at all (not `null`); decode per-code
    fields as optional.
- `at_risk: [{code: "station_degraded", ground_station_id, window_id, kind: "degraded",
  snapshot_ids}]`: passes inside a degraded window. A warning; it doesn't block. Booked passes are
  K2's (repairs). `counts.conflicts` and `ready_to_approve` include station conflicts on the detail
  read; the list rows count only overlaps.

**Times:** `created_at` is when the plan was first drafted, `version_created_at` when the shown
version was made, and `updated_at` its last change.

**Author** (`author` on rows and detail): `{kind: "user", id, name}` for a person (a repair
proposal's author is whoever started the repair), `{kind: "system", name: "Cadence"}` for an
automatic run, or `null` when it isn't known.

**Counts** describe the whole plan the Gantt shows: `counts.passes` and `minutes` include kept
(locked) passes, and `counts.locked` says how many are locked. A repair proposal of 40 with 4
moves reads `passes: 40, locked: 36`; the diff counts the moves.

**Repair proposals** (U28): a plan that a repair run proposed carries `repair_of: {plan: {id,
version}, run_id}`, where `plan` is the plan being repaired; every other plan has `repair_of:
null`. This is on the plan detail and on list rows. `GET /contact-plans` returns them apart:
`{plans: [...], repair_proposals: [...]}`. `plans` holds base plans only, so K1 picks the day's
plan from `plans` and points to its open repair from `repair_proposals`. Applying a repair is K2's
(Re-plan).

**Superseded drafts** (K1, ux ScheduleFlow): a `draft` or `pending_approval` plan whose
requirements were overtaken reads as `state: "superseded"` (in the list rows and the detail), with
`superseded: {at, by: {name} | null, reason, changes: [{kind: "requirement" | "template", id, name,
from_version, to_version}]}`. Otherwise `superseded` is `null`. It is computed **on read** against
the current versions (U27), so bumping a template or requirement supersedes the draft at once.
Reasons, strongest first: `template_changed` (a requirement's template has a newer version, or no
longer targets its spacecraft), `requirement_changed` (a newer requirement version than the plan
used), and `requirement_closed`. A requirement that another plan (pending approval or later)
has taken up is never stale, because supersession keeps it, so a repair plan built on a booked
plan's requirements isn't superseded. **Submit refuses a superseded draft** with `409 plan_superseded`
and `details.superseded`. The plan itself isn't changed, so its detail stays readable, and
`ready_to_approve` is `false`. `?state=draft` filters on the stored state, so a superseded draft
still comes back, as `superseded`. Re-draft the day to plan against the new versions.

`station` is `{ref, id, code, name}`: `ref` is the provider's ground-station ref, matched to a
Cadence ground station by id, `metadata.code` or `metadata.provider_station_ref` (the same join as
the passes read, `Reads.StationRefs`). `id`, `code` and `name` are `null` when nothing matches.
The same shape is used on draft passes, alternatives and repair-diff passes. Errors:
`404 plan_not_found`.

### `POST /contact-plans/drafts` (S3)

Body `{day: "YYYY-MM-DD", operation_id}`. It plans 00:00–24:00 UTC of that day with the mission's
active fleet planning policy and the active requirements (including recurring templates), then
runs the plan **off the request**.

- `202 {run_id, outcome: "created" | "replayed", state}`. The same `operation_id` returns the same
  run (persisted, so it works on any node).
- `422 planning_not_set_up` with `details.missing`: `["fleet_planning_policy"]` or
  `["contact_requirements"]`. `422 horizon_exceeds_policy`. `409 inputs_changed` (retry).

The review evidence pins its instant (`evidence.as_of`, G1): which requirements count as still in
the future (and so are superseded by a template) is decided at that instant, and the start reloads
its inputs at the same one, so a requirement starting between review and start doesn't change the
hash. Later review pages pass `as_of` back; a review older than 15 minutes asks for a fresh one.

### `GET /contact-plans/drafts/:run_id`

`{run: {id, state, phase, horizon: {from, to}, failure, started_at, updated_at}, plan: <plan detail>
| null}`.

- `state`: `queued | running | completed | partial | failed | canceled | interrupted`.
  **`interrupted`** means the run is queued/running but nothing is executing it (no session holds
  its lock, checked cluster-wide), so offer Continue. A queued run gets 60 s to start before it
  counts as interrupted.
- `plan` is the candidate plan (draft) once the run materializes it.
- `404 draft_not_found`.

### `POST /contact-plans/drafts/:run_id/continue`

Resumes an interrupted run off the request and returns `202 {run_id, state: "running"}`.
`409 draft_not_interrupted` otherwise.

### `POST /contact-plans/:plan_id/submit` (S5)

Body `{expected_version, operation_id, reason?, acknowledgements?: [{requirement_id,
requirement_version?, reason}]}`. `reason` defaults to a console note; acknowledgement reasons are
10–2000 characters. `requirement_version` is accepted and ignored, because the server pins the
version from the plan.

| Caller | What happens | Response |
| --- | --- | --- |
| member | draft → `pending_approval` (an admin reviews it) | `200 {plan_id, state: "pending_approval", outcome: "pending_approval"}` |
| org admin | submit (if draft) → approve with the acknowledgements → execute **off the request** | `202 {plan_id, state: "executing", outcome: "executing"}`, then `scheduling_progress {kind: "execute"}` |
| replay (same `operation_id` on this plan) | nothing | `200 {plan_id, state, outcome: "replayed"}` |

An admin calling submit on a member's `pending_approval` plan is the review: it approves and
executes. Per-item booking states show up in S1 passes and the plan detail.

Errors:
- `422 plan_not_ready`: unmet requirements without acknowledgements, any conflict, or an empty plan.
  `details: {unmet, conflicts}`, as in the plan detail.
- `422 acknowledgements_required` (`details.missing: [requirement_id]`): some, not all, unmet
  requirements were acknowledged.
- `422 invalid_params`: body shape, a reason outside 10–2000, or an acknowledgement for a
  requirement that isn't unmet.
- `409 plan_changed` (stale `expected_version`), `409 plan_not_submittable`,
  `409 operation_conflict` (operation id used on another plan), `404 plan_not_found`.

Acknowledgements are stored on the approval (`approval.exceptions`) with its actor and time
(DECISIONS #28).

### `POST /contact-plans/:plan_id/execute`

Re-executes an approved plan whose execution was **interrupted**, or that was approved and never
started. Items are idempotent, so booked passes aren't rebooked. Returns `202 {plan_id, state:
"executing"}`, or `409 plan_not_resumable`.

### Plan states `interrupted` and `unconfirmed` (DECISIONS #52)

A plan whose lifecycle is `executing` while no session holds its execution lock (cluster-wide)
reads by its unfinished execution items. List rows, plan detail and the draft/repair reads all
report it the same way:

- `interrupted`: some item was never placed with the provider. Offer Execute: it places those and
  re-reads (never re-sends) the rest.
- `executing`: every unfinished item was placed and the provider hasn't answered yet, within the
  confirmation window (`:provider_confirmation_window_ms`, default 10 min, from when the item was
  placed). No Execute. The plan settles by itself when the provider confirms, rejects or fails the
  bookings (`reserved`, `partially_reserved` or `failed`).
- `unconfirmed`: a placed booking is still unanswered past the window. The operator resolves it
  by checking that reservation with the provider. Execute answers `409 plan_not_resumable`.

Plan detail (`GET /contact-plans/:id`, and the S4 edit response) carries `unconfirmed` (U30):
`{window_ms, booked, passes: [{snapshot_id, provider: {id, name}, sent_at}]} | null`. It's non-null
whenever a placed booking is unanswered past the window. `booked` counts reserved passes; `passes`
are the unconfirmed ones, soonest first (join `snapshot_id` to `passes[]` for spacecraft, station
and times); `sent_at` is when the booking was placed.

### `GET /contact-plans/setup`

`{setup: {ready, missing: ["fleet_planning_policy" | "contact_requirements"], policy: {id, version} |
null, requirements: n, templates: n}}`. `ready` means drafting can start (an active policy plus at
least one active requirement or template). Readiness reports the same condition as finding
`planning_not_set_up` (fix kind `contact_planning`, which has no area tile).

### `GET /contact-plans/demand?day=YYYY-MM-DD` (S2, no plan needed)

`{day, spacecraft_with_rules, contacts_needed, without_rule, spacecraft_total}`. It counts active
requirements whose window overlaps the UTC day, plus template occurrences due that day (previewed;
nothing is materialized). Each one contributes its `contact_count`.

### `POST /contact-plans/:plan_id/versions` (S4 edit)

Body `{expected_version, add?: [snapshot_id], remove?: [snapshot_id]}`. Creates the next plan
version with the selection changed, and the domain recomputes coverage, conflicts and unmet. It
returns the new plan detail. Only passes the plan's planning runs found can be added (pick them
from alternatives). Editing a plan in review returns it to draft (the domain's rule). Errors:
`409 plan_changed`, `404 plan_not_found`, `422 plan_not_editable` (`details.reason` is the domain
code, e.g. a snapshot that doesn't belong to the plan's runs), `422 invalid_params`.

### `GET /contact-plans/:plan_id/alternatives?spacecraft_id=` (S4)

`{plan_id, version, spacecraft_id, rule_met, contacts: {have, need}, alternatives: [{snapshot_id,
requirement_id, station: {ref, id, code, name}, starts_at, ends_at, synthetic, effect: {rule_met_after, contacts_after:
{have, need}, clashes_with: [snapshot_id]}}]}`: eligible opportunities the plan's runs found for that
spacecraft but didn't select, oldest first. Effects come from the same requirement evaluator the
plan uses, and nothing is written. The "closes gap to 6h10" phrasing isn't computed (the rules
have no gap measure); `rule_met_after` and `clashes_with` are.

### `POST /contact-plans/:plan_id/repairs` (S8, K2 v1 "Re-plan after provider changes")

Body `{operation_id, from?, to?}` (ISO-8601; default: now until the end of the source run's
horizon). `plan_id` is any plan of the day's **repair chain** (the root plan plus every applied
repair in its `repair_of` chain, qa #30); the repair starts from the chain **head** (the latest
applied repair, else the root). The day is repairable while the chain has lost bookings,
whatever the head reads, or when the head is `executing`, `partially_reserved` or `failed`. This
starts a **repair run** that keeps the day's current bookings (reserved, uncertain or requesting,
across the whole chain) locked and re-plans the rest, **off the request**. Bookings an earlier
repair made are therefore never re-sent. `202 {run_id, outcome, state}`;
progress arrives as `scheduling_progress {kind: "draft"}`. Errors: `409 plan_not_repairable`,
`422 invalid_params`, `422 planning_not_set_up`.

There is no `station_id`: a repair run plans through the same Planner as a draft, which treats
windows at stations that are down or in maintenance (`StationAvailability`, S7) as ineligible.
To start from a station outage, take the plan ids from the station impact read (`plans`, see
contacts.md S7).

The operation id is recorded on the repair run right after creation, because the reviewed repair
flow has no transactional option for it yet. A crash between the two can leave an unrecorded run,
and a replay then starts another repair. (Drafts don't have this gap.)

### `GET /contact-plans/repairs/:run_id`

The draft read (`run`, `plan` = the **new** candidate plan), plus `source_plan: {id, version}` and
`diff: {kept, moved: [{spacecraft_id, from, to, offset_s}], dropped, added, totals}` (each pass is
`{snapshot_id, spacecraft_id, station: {ref, id, code, name}, starts_at, ends_at}`). `diff` is `null` until the run has
produced a plan. The diff compares the bookings the repair started from (the chain's live
bookings plus its lost ones that no other repair replaced) with the candidate, by the candidate's
**locked** passes: `kept` is exactly the locked passes. Every other candidate pass is a new
booking, including one on the same freed opportunity as a lost pass, so `moved` + `added` is
exactly what Apply sends. "Moved" pairs a spacecraft's lost and new passes in time order, and
that pairing is persisted as what the repair *replaces* (see contacts.md `replaced_by`). The
diff stays the same after Apply.

**Apply** = `POST /contact-plans/<new plan id>/submit` (S5), with acknowledgements for any gaps.
The repair yields a new plan; the source plan isn't superseded automatically (domain behavior).
Not yet: station-outage entry (S7), provider billing terms, and the uplink impact read.

## Contact planning setup (CP, Setup screen; DECISIONS #27)

Base: `/api/console/v1/missions/:mission_id/contact-planning`.

### `GET /policy` (CP2)

`{policy_id, version, active_version, document, pending: {version, requested_by, requested_at,
document} | null, schema: [field], defaults, permissions: ["planning.edit", "planning.approve"]}`.
`document` groups the six policy sections: `horizon, scoring, resources, budgets, redundancy,
automation`.

- `document` is the **active** version's document (the latest one while nothing is active yet).
  It is `null` (and so is `version`) when the mission has no policy.
- `version` is the latest version (pending, active or rejected): send it as `expected_version` on
  the next save.
- `pending` is the latest version while it awaits review (not active, no decision). A rejected
  version is never pending. `pending.document` is what's under review, for the diff.
  `requested_by` is an actor `{kind: "user", id, name}`. `schema` fields use the
kind-schema shape plus `group` and `advanced`; paths are `<group>.<field>`. `defaults` is what
the server fills in for omitted fields. Permissions are organization-admin today.

### `POST /policy`

Body `{document, expected_version?, reason?}`. It saves the next version (or the first) and returns
`201 {version, state: "pending_approval"}`. A version becomes active only after another admin
approves it. Errors: `422 invalid_params` (details keyed by `<group>.<field>`),
`409 version_conflict` (`details.expected_version` = current), `403 forbidden`.

### `POST /policy/:version/decision`

Body `{decision: "approve" | "reject", comment}`; `comment` is **required** for both decisions
(`422 invalid_params`, `details.comment`). Returns `{version, state: "active" | "rejected"}`.
`409 reviewer_is_author` if you saved that version (a single-admin organization can't activate
its own edits; that's by design per ux).

### `GET /` (CP1 summary)

`{policy: {version, mode} | null, coverage: {spacecraft_total, covered, contacts_per_day,
uplink_passes_per_day}, templates: [template row], not_covered: [{group: "profile" | "none", label,
count, suggested_target: target | null}], permissions}`. `policy: null` means no active policy.
Coverage counts the next 24 h of the **active** templates: `covered` is how many spacecraft at
least one of them targets now, and `contacts_per_day` counts occurrences × targeted spacecraft ×
`contact_count`. `not_covered` groups the rest by profile, largest first, and suggests a profile
target. Permissions are the CP2 ones (`planning.edit` is what template writes need).

### Templates (CP3; design: [`domain/contact-templates.md`](../domain/contact-templates.md))

A **target** is one of:

- `{kind: "profile", spacecraft_type_id, exclude_spacecraft_ids?}`: every spacecraft pinned to that
  profile;
- `{kind: "plane", plane: n, exclude_spacecraft_ids?}`: spacecraft whose `metadata.plane` is the
  integer `n`. This is interim: plane is free-form metadata until it's first-class, so a string or
  missing plane never matches;
- `{kind: "spacecraft_ids", spacecraft_ids: [id]}` (1 to 10,000, unique).

Membership resolves when requirements are generated, so a target follows profile pins, metadata and
new spacecraft. The **document** is `{schedule, requirement, catch_up_policy}`: the template's
schedule, the requirement content each occurrence generates, and the catch-up bounds.

- `GET /templates` → `{templates: [{id, name, state, version, target, applies_to, applies_to_count,
  rule_summary, priority}]}` (closed ones are left out). `applies_to` ("plane 1", "profile Block 1",
  "12 spacecraft", "…, except 2") and `rule_summary` ("1 downlink ≥ 5 min each · every 6h00") are
  server-made; don't re-derive them. `applies_to_count` is resolved now.
- `GET /templates/schema` → `{fields, defaults}` for the template form, in the policy schema's
  field shape (`path, label, type, unit, enum, range, default, required, help, visible_when,
  group, advanced`) over `schedule.*`, `requirement.*`, `catch_up_policy.*`. Types add `datetime`,
  `time` and `list` (ids). `visible_when` ties `interval_seconds` / `time_utc` to `schedule.type`
  and the duration / volume fields to `requirement.success_measure`. Units are `s` and `bytes`.
- `GET /templates/:id` → the row plus `document` and `versions: [{version, created_at, actor:
  {kind, id, name}}]` (newest first). `404 template_not_found`.
- `POST /templates` `{name, target, document}` → `201 {id, version: 1}`. The template is active
  at once.
- `POST /templates/:id` `{name?, target?, document?, expected_version}` → `201 {id, version}`.
  Omitted parts carry over. `409 version_conflict` on a stale `expected_version`.
- `POST /templates/preview` `{name?, target, document, days?}` (days 1–31, default 1) → `{spacecraft_count,
  occurrences, contacts, contacts_per_day, warnings: [{code}]}`, writing nothing. Warnings:
  `applies_to_nobody` (count 0) and `excluded_outside_target` (with `spacecraft_ids`: excluded ids
  the target wouldn't include anyway).
- Errors: `422 invalid_params` (`details.document` with the reason; `details.target` +
  `spacecraft_ids` for unknown spacecraft; `details.target: "unknown profile"`), `403 forbidden`
  (writes need organization admin).
- When a template's **new version** generates requirements, the older version's future requirements
  that no plan has taken up (pending approval or later) are canceled with reason
  `template_versioned: …`. So are those for spacecraft that **left the target**
  (`left_template_target: …`). Requirements already started or planned are left alone.
- **Dry run before saving** (ux ContactPlanning.md): `GET /templates/:id/supersedes` and
  `GET /requirements/:id/supersedes` → `{drafts: [{plan: {id, version}, day, author, state}]}`,
  writing nothing. They list the open drafts a new version would supersede, by the same rule as
  the on-read `superseded` state:
  - a template's new version supersedes drafts holding its future requirements that no plan has
    taken up;
  - a requirement's new version supersedes every draft that references it.

  Plans past draft are K2's and aren't listed. A **policy** version doesn't supersede drafts:
  each draft keeps the policy snapshot it was made with.
- Templates aren't change sets: edits are versioned and audited on the template (planning policy,
  not mission configuration).
