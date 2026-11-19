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
   *Superseded 2026-11-19 (#257, director): submit only submits for everyone, and approving is
   its own action, `POST .../approve` (§4).*
4. **Policy prerequisite.** Drafting needs an active fleet planning policy and at least one active
   requirement in the window. Missing either → `422 planning_not_set_up` (`details.missing`), and
   readiness should surface it. There's no console setup for policies yet. Is that a Setup gap
   to schedule?

## 3. Proposed endpoints

> **Superseded by §4** (drift sweep 2026-11-13): this was the first proposal. §4 is the contract;
> the shapes below (`day_start/day_end`, `counts.selected`, a flat repair read, `GET /demand`
> with `plan_id`/`run_id`) aren't what the server answers.

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
off-request work starts and ends. It also emits `invalidate` with `contacts` and `contact_plans`. Treat it as a hint and
refetch the read. The read is the truth.

### `GET /contact-plans?day=YYYY-MM-DD&state=` (S6)

`{plans: [{id, version, state, window: {from, to}, author, counts: {passes, minutes, conflicts,
unsatisfied}, ready_to_approve, updated_at}]}`, newest first, capped at 100. `window` spans the
selected passes (`null` for an empty plan); `day` matches the window's start date (UTC). `state` is
one of `draft, pending_approval, approved, executing, partially_reserved, reserved, failed,
canceled, superseded`, or the derived `interrupted` / `unconfirmed` (§Plan states). The `state`
filter takes any of them; a stored state filters as stored (an `executing` plan shown as
`interrupted` still matches `executing`), a derived one by the derived state.

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

**Author** (`author` on rows and detail): `{kind: "user", id, name}` for a person (`id` can be
missing on older plans that recorded only a name) (a repair
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
  Other planning refusals answer `422 <code>`, among them `fleet_planning_requirement_not_active`
  and `fleet_repair_horizon_exceeded`.
- `422 fleet_planning_occurrence_limit_exceeded` (U52), `details {count, limit}`: the day's
  template fan-out (each active template's occurrences in the day, capped at its
  `maximum_occurrences_per_run`, times its targets, existing days included) is over the limit
  (50,000). Nothing is created. `count` is the whole count. The setup read's
  `template_requirements_estimate` shows the same number beforehand.

The review evidence pins its instant (`evidence.as_of`, G1): which requirements count as still in
the future (and so are superseded by a template) is decided at that instant, and the start reloads
its inputs at the same one, so a requirement starting between review and start doesn't change the
hash. Later review pages pass `as_of` back; a review older than 15 minutes asks for a fresh one.

### `GET /contact-plans/drafts/:run_id`

`{run: {id, state, phase, horizon: {from, to}, failure, started_at, updated_at, stopped_at}, plan:
<plan> | null}`. `plan` is the plan read with its derived state, not the full plan detail: it has
no `passes[].booking`, `unconfirmed`, `execution`, `chain` or `chain_head` (a draft has none; read
`GET /contact-plans/:id` for them). `stopped_at` is `null` while the run is queued or running. For a
finished run (`completed | partial | failed | canceled`) it's the completion time. For an
`interrupted` run it's the last time the run recorded progress: nothing records the moment a
node stops, so say "stopped at or after".

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

**Since 2026-11-19 (#257, director): submit only submits**, for members and admins alike, under
either approval setting. Approving is its own action, `POST .../approve` (below). Under 'direct'
an admin's submit used to approve and book in one step (`202`); it now answers `200` like
everyone's. ux's one act for a 'direct' admin ("Approve and book N passes") is the console
calling submit, then approve, and both are recorded.

Body `{expected_version, operation_id, note?, acknowledgements?: [{requirement_id,
requirement_version?, reason}]}`. `operation_id` is 1–120 bytes. `note` is optional (at most
2,000 characters after trimming; blank is none). Acknowledgement reasons are 10–2000 characters;
`requirement_version` is accepted and ignored, because the server pins the version from the plan.
The submitter's acknowledgements are recorded on their submission round. `decision_note` is
refused here (`422 invalid_params`): it belongs to approve.

| Request | What happens | Response |
| --- | --- | --- |
| a draft (or a sent-back draft) | → `pending_approval` | `200 {plan_id, version, state: "pending_approval", outcome: "pending_approval", replayed: false}`. `version` is the version put up for approval: a sent-back draft cuts the next one (below), so approve with this `version` |
| a plan already `pending_approval` | nothing | `409 plan_already_submitted`, `details: {submitted_by: {id, name}, submitted_at}` (both or neither) |
| the same request again (same `operation_id`, actor and normalized body) | nothing new | the **original** status and body with `replayed: true` |

Errors:
- `409 plan_already_submitted` (above). Was a silent `200` before #257.
- `409 duplicate_operation` (`details.plan_id`): this `operation_id` was used on this plan by a
  different request (another actor, another body, or the other action). Nothing changed.
- `409 operation_conflict`: the operation id was used on another plan.
- `409 plan_changed` (stale `expected_version`), `409 plan_not_submittable`, `404 plan_not_found`.
- `422 invalid_params`: body shape, `decision_note`, a note over 2,000 characters.

Submitting doesn't check coverage: approve does (`plan_not_ready`, `acknowledgements_required`).

**Replays (both submit and approve).** Each request records its operation in the same
transaction as the submit or the decision, after the plan row lock: (organization, mission,
`operation_id`) → the action, the plan, the actor, a SHA-256 of the normalized body
(`expected_version`; the note trimmed, blank as none; acknowledgements sorted by
`requirement_id`, reasons trimmed) and the original answer. A request whose operation id is
known gets the original answer with `replayed: true` when the action, plan, actor and body digest
match; otherwise `409 duplicate_operation` (`409 operation_conflict` for another plan). A replay
starts nothing again. A rolled-back request records no operation, so its retry runs for real.
Since #273 the approve's digest also covers `expected_expired_digest`. A replay returns the
ORIGINAL answer, including the `expired` set it carried, even if more booking windows have closed
since.

### `POST /contact-plans/:plan_id/approve` (#257)

The approver's decision on a plan waiting for approval: the only console path that approves.
Org admins (`approve_contact_plans`). Body `{expected_version, operation_id, decision_note?,
acknowledgements?, expected_expired_digest?}`:
- `expected_version`: the version the approver saw (after a submit, the `version` it returned).
- `decision_note`: optional, at most 2,000 characters after trimming; recorded as the approval's
  reason, `NULL` when blank or absent (U76).
- `acknowledgements`: the **approver's** acknowledgements of unmet requirements, recorded on the
  approval (`approval.exceptions`). Required when the version has unmet requirements.
- `expected_expired_digest` (#273): the plan read's `expired_digest`, sent back unchanged. It's an
  opaque string; clients never compute it. Absent means "saw none" (the empty set), so an older
  client is refused whenever a pass's booking window has closed.

`202 {plan_id, version, state: "executing", outcome: "approved", replayed: false, expired}` once
the approval is committed, then booking runs **off the request** (`scheduling_progress {kind:
"execute"}`). The approval records the approval policy in force, from the same read as the
separation check (#226(b)).

**Closed booking windows (#273).** A selected pass whose provider offer has expired (the
domain's one rule, `ContactPlanApprovals.expired_set/5`, which applies a 60 s lookahead) can't be
booked. The approval leaves those passes out and records them as **skipped** on the decision;
execution books the approved passes minus the skipped. The set is computed once per decision,
under the plan row lock:
- `expired` on the 202 is exactly the set the decision recorded: `null` | `{count,
  reservable_count, items: [{snapshot_id, spacecraft: {id, name, scid} | null, station: {id,
  code, name} | null, aos, expires_at | null, reason: "opportunity_expired" |
  "no_booking_window"}]}`. Items are in AOS order and capped at 5,000; `count` isn't capped.
  `no_booking_window`: the provider gave no window, so the pass fails closed and counts as closed.
- `409 contact_plan_all_opportunities_expired` (checked first): every selected pass has closed,
  so nothing can be booked. `details: {expired, expired_digest}`. Nothing is recorded.
- `409 contact_plan_expired_passes_changed`: the closed set differs from the one the approver saw
  (`expected_expired_digest`). `details: {expired, expired_digest}` (the current set). Nothing is
  recorded. Show the new list; the approver approves again with the new digest (never an
  automatic retry).
- The plan detail shows the set before anyone decides; see "Closed booking windows on the plan
  read" below.

Errors:
- `403 contact_plan_self_approval_forbidden`, `details: {because: "submitted" | "edited"}`: under
  'independent' approval, the approver submitted this version (`submitted`, which wins when both
  apply) or authored it (`edited`: the version's `created_by`; for a drafted plan, the drafter).
  Nothing is recorded or booked.
- `403 forbidden`: not an org admin.
- `409 plan_not_pending`, `details: {state, decided_by: {id, name}, decided_at}` (the decision
  pair both or neither): the plan isn't waiting for approval (already approved or sent back, or a
  draft). A second, concurrent approve of the same plan gets this (the plan row lock serialises
  them), unless it is the same request, which replays.
- `409 plan_changed`: `expected_version` isn't current, or the content changed.
- `409 duplicate_operation`, `409 operation_conflict`: as for submit.
- `422 plan_not_ready` (`details: {unmet, conflicts}`), `422 acknowledgements_required`
  (`details.missing`), `409 plan_superseded`, `422 invalid_params`, `404 plan_not_found`.

**Closed booking windows on the plan read (#273).** The plan detail (`GET /contact-plans/:id`,
so Re-plan's proposal too) carries:
- `expired`: the shape above, from the domain's rule at read time.
- `expired_digest`: send it back unchanged as `expected_expired_digest`. It's opaque, and the
  domain's `expired_set/5` and its golden test are its only definition.
- `next_expiry_at`: when the set next changes, with the margin already applied, or `null`. When now
  passes it, say a window has closed since the page loaded and offer a reload; never edit the
  list.
- `expiry_margin_seconds`: `60`.

**`approval_setting`** (#257): the plan detail and each plans-list row carry the mission's
approval setting at read time, `"direct"` or `"independent"`, so the console offers the right
act. `"independent"`: a second person approves (the submitter and the version's author can't).
Approve's `403` stays the backstop, because the setting can change between the read and the
click.

Acknowledgements are stored on the approval (`approval.exceptions`) with its actor and time
(DECISIONS #28). Plan detail carries the latest decision on the shown version as `approval`:
`{decision: "approved" | "rejected", actor: {kind, id, name}, at, reason, exceptions:
[{requirement_id, requirement_version, reason}]} | null` (`null` until someone decides; a sent-back
plan shows the rejection and its reason). Join `requirement_id` with `unmet[]` to describe the
requirement.

### Resubmitting after a send back (U36, qa #40)

Submitting a draft whose current version was sent back (its latest decision is `rejected`) is
allowed as is: the server cuts the next version with the same selected and locked passes
(`rationale: "Resubmitted after send back"`) and submits that. The rejection stays on the old
version. Send the `expected_version` you were shown (the sent-back one); the reply's `version`
is the new one (#257), so approve with it. Undecided drafts submit as before.

The lock, the operation check, the version check, the cut, the submit, the round record and the
operation record are one transaction: a second click with a new operation id finds the plan
pending and gets `409 plan_already_submitted`; it never cuts another version.

Submit takes an optional `note` (at most 2,000 characters: what changed, for the reviewer). Plan detail carries the review rounds:

- `submission`: `{round, actor: {kind, id, name}, at, note, unchanged} | null`, the round that
  submitted the shown version. `unchanged`: the selected and locked passes equal the previous
  version's (a resubmission without edits). Header: "v2 · resubmitted"; "Resubmitted unchanged"
  when `unchanged`.
- `previous_round`: `{round, version, approval: <approval shape>, acknowledgements:
  [{requirement_id, reason}]} | null`: the round before, with its decision (who sent it back and
  why) and the gap reasons the author gave then (prefill the gaps sheet).

Plan detail also carries `latest_version` (U69 A10): the plan's newest version, so a
`?version=N` read of an older one can show the historical-version banner and "Review current
version" (open it without `version`).

### `GET /contact-plans/days?from=YYYY-MM-DD&to=YYYY-MM-DD` (DECISIONS #100 day strip, owner: api)

K1's day strip in one read: at most 14 UTC days, `from` ≤ `to`, both inclusive (otherwise `422
invalid_params`). `{"data": {"days": [{day, plan: {id, version, state} | null, sent_back,
requirements_count, booked_count, unconfirmed_count, requested_count, first_window_at}]}}`, one
entry per day in order, days without a plan included.

- `plan`: the day's plan by K1's own rule (repair proposals aside, the newest plan that isn't
  superseded or canceled, else the newest if it's a superseded draft); `state` is the list's and
  detail's word, derived states included (`interrupted`, `unconfirmed`). Plans are grouped by their
  window's UTC day from the newest 100.
- `sent_back`: a draft whose latest decision is a rejection.
- `requirements_count`: the day's contacts needed, as `GET /contact-plans/demand` (`contacts_needed`);
  0 when there's nothing to plan, never null.
- `booked_count` / `unconfirmed_count` / `requested_count`: the plan's `execution` `confirmed` /
  `uncertain` / `requested` (passes); null without a plan, or before it has bookings.
- `first_window_at`: `null` for now; it takes U61's `plan_coverage` rule when that source lands, so
  the strip and Now agree.

### `GET /contact-plans/:plan_id/history` (U69 A10, owner: api)

`{"data": {"plan_id", "latest_version", "versions": [...], "decisions": [...], "truncated"}}`:

- `versions`, newest first: `{version, created_at, created_by: {kind: user | service_identity |
  system, id, name} | null (an automatic run reads `{kind: "system", name: "Cadence"}`, as detail), rationale | null, content_sha256, selected, locked, rejected,
  decision: approved | rejected | null (that version's latest decision), submitted: bool}`.
  Open one with plan detail's `?version=`.
- `decisions`, newest first, one per act across all rounds: `{kind: submitted | approved |
  rejected, version, round | null, actor: {kind, id, name}, at, text | null (a submit's note or a
  decision's reason), unchanged: bool | null (submits only), acknowledgements: [{requirement_id,
  requirement_label, spacecraft: {id, name} | null, requirement_window: {from, to} | null, reason}]
  (submits), exceptions: [{requirement_id, requirement_version, requirement_label, spacecraft,
  requirement_window, reason}] (decisions),
  automation_grant_id | null (a decision made under an automation approval policy), skipped}`.
  The words match detail's `submission` / `approval`.
- `skipped` (#273): on an approval, the passes it left out because their booking window had
  closed, exactly as the decision recorded them, in the `expired` shape (approve, above). `null`
  when none were skipped, for every decision made before #273, and for submits and send-backs.
- `requirement_label` (ux U73): a requirement has no name of its own, so it's its template's name
  when a template generated it ("Block 1 daily"), else its rule in words ("2 downlink contacts of
  at least 10 min", as `demand.rules[].text`); `null` only when the requirement can't be read.
  Acknowledgements name the requirement's current version.
- At most 200 versions and 500 decisions, newest kept; `truncated: true` past either.
  `404 plan_not_found`.

`422 contact_plan_version_already_decided` now only means someone decided the version at the same
moment; `details.decided_by: {kind, id, name} | null` names them ("already decided by Mira K.").

### `POST /contact-plans/:plan_id/reject` (send back)

Body `{expected_version, reason}`. For a plan in `pending_approval`: an approver
(`approve_contact_plans`) sends it back. The plan returns to `draft` (its author can edit and
resubmit), and the decision is recorded as a rejected approval with the reason. Approving is
`POST .../approve` (#257). Returns `200` plan detail (`state: "draft"`). Errors: `422 invalid_params`
(`expected_version`, `reason` is required), `409 plan_changed` (another version is current),
`409 plan_not_pending`, `404 plan_not_found`, `403 forbidden`.

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
`{window_ms, booked, passes: [{snapshot_id, provider: {id, name | null} | null, sent_at}]} | null`.
`provider` is `null` when Cadence holds no reservation for the booking (nothing came back to
name the provider), and `name` is `null` for a provider the mission no longer lists. It's non-null
whenever a placed booking is unanswered past the window. `booked` counts reserved passes; `passes`
are the unconfirmed ones, soonest first (join `snapshot_id` to `passes[]` for spacecraft, station
and times); `sent_at` is when the booking was placed.
Each pass also carries `item_id` (the execution item).

Plan detail also carries `execution` (lead: K1/K2 headers, bookingStopped, K2's applied
footer): `{requested, sent, never_sent, confirmed, uncertain, rejected, failed}`, counts of the
approved version's bookings, or `null` before the plan has any (drafts, pending approval).
`requested` is every pass the plan books; `requested = sent + never_sent`; `sent = confirmed +
uncertain + rejected + failed`. `never_sent` is still waiting, was interrupted before the
provider call, or failed before it (an expired opportunity); `failed` counts only bookings the
provider failed or lost after they were placed. Header example: "booking · `confirmed` of
`requested`"; bookingStopped: "`sent` requests went out; `never_sent` didn't". It changes with
`contact_plans` invalidations (contacts.md S10).

Each of plan detail's `passes[]` carries `booking` (lead, K1 8e): `{state, reason, at}`, or `null`
when the approved version doesn't book that pass (and for every pass before approval). It is
joined on `snapshot_id` within the approved version only. `state` is `confirmed | uncertain |
rejected | failed | never_sent`, and per-pass states add up to `execution`'s counts (there's no
`sent` state: `sent` is the umbrella of the first four). `failed` = the provider failed or lost a
placed booking; `never_sent` = waiting, sending, or failed before the provider call. `reason` is
`sending` while the provider call is in flight, else a short code from the last error
(`provider_timeout`, `rejected`, `snapshot_expired`, …), or `null`. `at` is when the booking last
changed. K1 draws Requested → Confirmed / Rejected per bar from it; rejected passes become Demand
rows.

`booking` also carries (ux ScheduleFlow f05d68e9 'K1 booking reasons'): `detail` (the provider's
own words, e.g. "Station full", or `null`), `retryable` (`true | false`, `null` when the provider
didn't say), `retry_after_seconds` (or `null`), and `resolved: {by {kind, id, name}, at} | null`
for an operator's resolution (U29: not booked, rejected or not sent, and "Mark booked" on a
confirmed pass). Older resolutions predate `resolved` and read `null`. Provider categories
(`reason`): `no_capacity`, `conflict`, `invalid_request` (rejected); `provider_unavailable`
(failed); `authentication_failed`, `authorization_failed`, `unsupported_capability`,
`not_found`, `provider_not_ready`, `rate_limited`, `known_timeout`, `ambiguous_outcome`,
`malformed_response`, `provider_error` (uncertain). A status-path rejection carries the
provider's status reason, else the raw status (`rejected`, `terminated_early`).

Plan detail also carries the day's **repair chain** (qa #30): `chain: [{id, version}]` (the root
plan first, then each applied repair in order; versions are the approved ones) and
`chain_head`: the **plan id as a bare string** (not `{id, version}`), naming the plan a new
Re-plan starts from; its version is the matching `chain` entry's. Example:
`"chain": [{"id": "contact_plan_fleet_6e74…", "version": 1}, {"id": "contact_plan_fleet_8ae6…",
"version": 1}], "chain_head": "contact_plan_fleet_8ae6…"`. On an unknown chain: `chain: []`,
`chain_head: null`. A draft or a proposal that isn't applied reads the chain
it belongs to; it isn't in `chain` itself.

### `POST /contact-plans/:plan_id/unconfirmed/:snapshot_id/resolve` (#53, U32)

Body `{action: "booked" | "not_booked", note, provider_reference?}` (`provider_reference` only
for `booked`). Admins only (`approve_contact_plans`); the pass must be one of `unconfirmed.passes`.
Cadence re-reads the provider first. Reply `200 {outcome, provider_answer, resolution: {actor:
{kind, id, name}, at, note, provider_reference}}`:

- `outcome: "provider_answered"`: the provider answered on the re-read, so its answer settled the
  booking. The resolution recorded says so (it's no operator claim about the booking). `provider_answer` is `"booked" | "not_booked"`.
- `outcome: "attested"` (Mark booked) or `"not_booked"` (Cadence cancels first, then fails the
  item; repair treats it as lost). `provider_answer` is `null`.

Errors: `422 invalid_params` (`action`, `note`, `provider_reference`), `404 booking_not_found`,
`409 booking_not_unconfirmed`, `409 booking_already_resolved` with `details.actor` (who
resolved it, or `null`), `403 forbidden`.

### `GET /contact-plans/setup`

`{setup: {ready, missing: ["fleet_planning_policy" | "contact_requirements"], policy: {id, version} |
null, requirements: n, templates: n}}`. `ready` means drafting can start (an active policy plus at
least one active requirement or template). Readiness reports the same condition as finding
`planning_not_set_up` (fix kind `contact_planning`, which has no area tile).

`?day=YYYY-MM-DD` (U52; UTC, default today; a bad day is `422 invalid_params {day}`) adds
`template_requirements_estimate: {count, limit, capped: [{template: {id, name}, limit, last_at}]}
| null` for the day Start would draft. `count` is the template fan-out Start counts toward `limit`
(50,000), the same number as its `fleet_planning_occurrence_limit_exceeded`, including days that
already exist (so it can read higher than what a start creates). `capped` lists the templates whose
occurrences that day pass their per-run cap: `limit` is the cap and `last_at` the last occurrence it
keeps; later ones that day aren't generated by that start. `null` when no active template counts
anything.

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
plan uses, and nothing is written. The top level also carries `longest_gap` (as in plan detail's
demand, below), and each effect `longest_gap_after_seconds`: the same measure with that pass
added (clashing passes stay in), so D can say "6h10 → 3h05". A plan with nothing selected takes
its day from the candidates. With a gap limit (DECISIONS #74), it's the limited requirement's
number, as below.

### Plan detail measures (K1 C panel, lead; `GET /contact-plans/:id`)

Additive, optional fields:

- `demand.spacecraft[].longest_gap`: `{seconds, limit_seconds, from, to} | null`. The longest
  stretch of the plan's UTC day (00:00Z–24:00Z of the earliest pass's date) without one of this
  spacecraft's selected passes. A gap runs LOS → next AOS; the day's edges count (00:00Z → first
  AOS, last LOS → 24:00Z). Only this plan's passes count (not earlier chain bookings or the
  previous day's last pass). No pass all day reads 86400; `null` when the plan has no passes.
  `from`/`to` are ISO timestamps (whole seconds), `null` only when the day is fully covered
  (`seconds: 0`). **With a gap limit (DECISIONS #74):** when any of the spacecraft's
  requirements has `max_gap_seconds`, `longest_gap` is the evaluator's number for the limited
  requirement with the largest excess (`seconds - limit_seconds`): over that requirement's window,
  its own eligible selected passes, and `limit_seconds` is its limit. Over the limit, the
  requirement is unmet with reason `max_gap_exceeded` (facts `{longest_gap_seconds, from, to,
  max_gap_seconds}`). Without a limit, `limit_seconds` is `null` and this is the plan-day measure.
- `demand.spacecraft[].uplink_passes`: `{have, need}`. `have` counts selected passes whose
  booking will **request** an uplink leg (the spacecraft's primary uplink route lands at that
  station on the same provider); confirmation shows later as the passes read's
  `uplink_confirmed`. `need` is `null` (no rule carries an uplink count, and uplink requirements
  aren't plannable yet).
- `provider_freeze`: `{at, provider: {id, name}, snapshot_id, by_provider: [{provider, at}]} |
  null`. The earliest offer `expires_at` (the last moment the provider honours that offer) among
  passes **not yet sent** to a provider: every selected pass for a draft, review or an approved
  plan not yet executed; once executing, only the unplaced (`pending`/`requesting`) items. It may
  be in the past (an expired offer, which approval refuses). `null` when nothing is left to send.
  Providers publish no day-level cutoff, so this is the honest freeze. The simulator's offers
  expire at AOS.
- `passes[].expires_at`: that offer's expiry (ux: "3 more offers expire in the next hour").

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

**Covered by a single booking** (DECISIONS #56): a repair also holds the mission's live single
bookings (no plan) in its horizon and pairs them with lost bookings by the same rules (same
spacecraft, nearest start, the rest unpaired). The diff lists those lost passes under `covered`
(each pass plus `covered_by`: the single booking's `provider_reservation_id`), not under `kept`,
and `totals.covered` counts them; Apply sends nothing for them. Known limit: a lost booking can
only be held when the plan the repair starts from selected it (true when it was lost after the
latest repair). An older lost booking that a single booking covers is still recorded as covered,
but the planner may propose a pass for it, which then shows under `added`.

**Apply** = `POST /contact-plans/<new plan id>/submit` (S5), with acknowledgements for any gaps.
The repair yields a new plan; the source plan isn't superseded automatically (domain behavior).
Station-outage entry works through the station impact read's `plans` (above). Not yet: provider
billing terms (no provider supplies them), and an uplink impact read (which queued uplinks a
repair's moves affect). Ask if a screen needs either.

## Contact planning setup (CP, Setup screen; DECISIONS #27)

Base: `/api/console/v1/missions/:mission_id/contact-planning`.

### `GET /policy` (CP2)

`{policy_id, version, active_version, document, pending: {version, requested_by, requested_at,
document, reason} | null, schema: [field], defaults, permissions: ["planning.edit", "planning.approve"]}`.
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
`201 {version, state: "pending_approval"}`. `reason` (trimmed, at most 500 characters; empty is
none) is stored on that version: `pending.reason`, and the audit's "Proposed planning policy vN"
entry. Earlier versions have none. A version becomes active only after another admin
approves it. Errors: `422 invalid_params` (details keyed by `<group>.<field>`),
`409 version_conflict` (`details.expected_version` = current), `403 forbidden`. A `reason` over
500 characters is `422 invalid_params` (`details.reason`).

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
- `POST /templates` `{name, target, document, operation_id?}` → `201 {id, version: 1}`. The
  template is active at once. Optional `operation_id` (client idempotency key, 1–200 characters, the same contract as
  command groups): a replay answers `409 duplicate_operation` with `details.template_id` (the one
  it made) and creates nothing. Without it, every create is new.
- **L2** `POST /templates/:id/pause | /activate | /close` `{expected_version, reason}` → `200 {id,
  state: "active" | "paused" | "closed", version}`. Moves: active ↔ paused, active | paused → closed
  (final). The version doesn't change; requirements the template already made stay (only active
  templates make new ones). `409 version_conflict` (`details.expected_version` = current),
  `409 template_transition_not_allowed` (`details.state` = current), `422 details.reason` (required,
  ≤ 2000), `403 forbidden` (the same check as template writes: `planning.edit`). The template detail
  carries `state_changed: {state, at, actor {kind, id, name}, reason} | null`, the last move a person
  made (`null` while it's active since create).
- `POST /templates/:id` `{name?, target?, document?, expected_version}` → `201 {id, version}`.
  Omitted parts carry over. `409 version_conflict` on a stale `expected_version`
  (`details.expected_version` = current).
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
- **Days an edit won't regenerate** (U48, DECISIONS #86): the template's `supersedes` read also
  returns `decided: {planned_or_started, closed, canceled}`, each a list of `{occurrence_at, date
  (YYYY-MM-DD, UTC), spacecraft_ids}` (one per occurrence instant, oldest first; spacecraft sorted).
  - `planned_or_started`: a plan past draft holds the day's requirement, or its window has begun.
    The edit keeps that requirement (no second one for the day).
  - `closed` / `canceled`: an operator closed or canceled it; the edit doesn't bring it back.
    Days canceled by supersession or by leaving the target regenerate, so they aren't listed.
  - The days looked at are the template's generated occurrences from the current version's
    catch-up lookback onward, classified as the next version would (domain's `TemplateDays`, the
    rule materialize and the fleet start use). A day's count is the number of distinct `date`s;
    its requirements are the sum of `spacecraft_ids` lengths (ux words both).
  - Not on `requirements/:id/supersedes`.
- Templates aren't change sets: edits are versioned and audited on the template (planning policy,
  not mission configuration).

### Automation grants (§11 L3)

A grant lets a service identity act without a person (plan, repair, execute, submit, approve)
within the active fleet planning policy. Under `/contact-planning`:

- `GET /grants` (mission operators) → `{grants: [grant], service_identities: [{id, name, state:
  active | disabled}] (this mission's), policy_version: <active policy version> | null, limits:
  {maximum_horizon_seconds, maximum_contacts, maximum_execution_concurrency} (the active policy's
  ceilings, for hints; each `null` without a policy, the object itself is always present), permissions: ["grants.manage"] | []}`. A grant is
  `{id, service_identity {id, name}, policy_version, allowed_actions: [plan | repair | execute |
  submit | approve], maximum_horizon_seconds, maximum_contacts, maximum_execution_concurrency,
  maximum_estimated_cost_micros, currency, valid_from, valid_until, state: active | revoked | expired,
  approved_by {id, name}, approved_at, reason, revoked_by {id, name} | null, revoked_at | null,
  revocation_reason | null, sha256}`. `service_identity.name`, `currency` and
  `maximum_estimated_cost_micros` can be `null`. `expired` is computed (active past `valid_until`). Cost stays
  hidden in the console (#63).
- `POST /grants` (organization admins) `{service_identity_id, maximum_horizon_seconds,
  maximum_contacts, maximum_execution_concurrency, valid_days (1–365), reason, policy_version}` →
  `201 {grant}`. `allowed_actions` and the cost limit come from the active policy. `409
  policy_changed` with `details.active_version` when `policy_version` isn't the active one; `422
  invalid_params` on the field for limits beyond the policy (`maximum_horizon_seconds`,
  `maximum_contacts`, `maximum_execution_concurrency`), a disabled or other-mission identity
  (`service_identity_id`), or missing input.
- `POST /grants/:id/revoke` (organization admins) `{reason, sha256}` → `200 {grant}` (state
  `revoked`). `409 grant_changed` when `sha256` no longer matches; `404 grant_not_found`;
  `422 invalid_params` (`details.sha256`) when it's missing.

### Requirements (one-off; BACKLOG §8 8g)

A one-off **contact requirement** is one spacecraft's need in one window. Templates generate them
too; these endpoints list both and write the one-off kind. The wire **content** uses the
requirement's own field names: `spacecraft_id, earliest_start, latest_end, service_direction,
contact_intent, success_measure, minimum_duration_seconds, preferred_duration_seconds,
minimum_data_volume_bytes, contact_count, minimum_separation_seconds, max_gap_seconds, priority,
rationale, provider_constraints_document {allowed, excluded}, station_constraints_document
{allowed, excluded}`.

- `GET /requirements/schema` → `{fields, defaults}` in the template schema's field shape: the
  template's `requirement.*` fields without the prefix, plus `spacecraft_id` (`reference`,
  required), `earliest_start` / `latest_end` (`datetime`, required) and `max_gap_seconds`
  (DECISIONS #74: `integer | null`, unit `s`, 600–604800, optional, `advanced`; "Longest time
  without a contact"). `group` is `window` or `requirement`. `rationale` is required (a one-off
  must say why).
- `GET /requirements?spacecraft_id=&state=&source=&page=&limit=` → `{requirements: [row], page,
  next_page}`. Each row is a requirement at its **current version**, most recently changed first.
  `state` is `active | closed | canceled`; `source` is `one_off | template`; `limit` 1–200
  (default 50); `next_page` is `null` on the last page. A row is `{id, state, version, spacecraft
  {id, name}, template_id | null, template_version | null, content, rule_summary, updated_at}`.
  `template_version` (U48) is the template version that generated it (Source "Block 1 daily ·
  v2"), `null` for a one-off. `updated_at` is the current version's time. `rule_summary` is the templates' sentence without a cadence, plus the gap limit
  when set: "2 downlinks ≥ 5 min each", "1 downlink ≥ 2.0 GB each · gaps ≤ 6h00".
- `GET /requirements/by-template?day=YYYY-MM-DD` (UTC day, default today) → `{day, templates:
  [{template {id, name, state}, count, active_count}]}` by name: per template, the requirements it
  generated whose window opens that day (any state), and how many of those are still active.
  Templates with none that day are left out. One grouped query; `422 details.day` for a bad
  date.
- `GET /requirements/:id` → the row plus `versions: [{version, created_at, actor {kind, id,
  name}}]` (newest first). `kind` is `user`, `service` (a service identity, named) or `system`
  (`name` null). `404 requirement_not_found`.
  - `held_by: {plan_id, revision, state, day} | null` (ux P4): the plan past draft
    (pending_approval or later) that holds the requirement, the most recently changed if several
    do; `revision` is its current version; `day` is the plan's UTC day as the plans list files it
    (its first pass; null without passes), which is how the console opens it. A draft doesn't hold
    it. Show "Open plan R<revision>" instead of "Plan <day>".
- `POST /requirements` `{content, operation_id?}` → `201 {id, version: 1}`. Omitted fields take
  the schema's `defaults`. Optional `operation_id` (client idempotency key, 1–200 characters, the same contract as
  command groups): a replay answers `409 duplicate_operation` with `details.requirement_id` (the one
  it made) and creates nothing. Without it, every create is new.
- `POST /requirements/:id` `{content, expected_version}` → `201 {id, version}`. An **omitted** key
  carries over from the current version; an explicit **`null` clears** a nullable field
  (`max_gap_seconds: null` = no limit). `409 version_conflict` with `details.expected_version` =
  the current version. `409 requirement_not_active` for a closed or canceled requirement. Run
  `GET /requirements/:id/supersedes` first for the drafts a new version supersedes.
- Errors: `422 invalid_params` keyed by field (`details.latest_end`, `details.max_gap_seconds` =
  "must be between 600 and 604800 seconds" or "must not be longer than the window",
  `details.spacecraft_id` = "unknown spacecraft", `details["content.<key>"]` = "unknown field",
  `details.constraints`, `details.expected_version`); `403 forbidden`; anything else the domain
  refuses is `422 requirement_rejected`. Writes publish the `contact_plans` invalidation.
- `POST /requirements/:id/close` and `POST /requirements/:id/cancel` `{expected_version, reason}` →
  `200 {id, state: "closed" | "canceled", version}`. Close = the need is over or met; cancel =
  withdrawn. Both are **final** (nothing reopens a requirement; declare a new one). `reason` is
  required, at most 2000 characters (`422 details.reason`). `409 version_conflict`
  (`details.expected_version` = current), `409 requirement_not_active` with `details {state,
  state_changed}` when it already ended (also on a new version), `404 requirement_not_found`.
  Drafts that reference it go superseded (`requirement_closed`); `GET /requirements/:id/supersedes`
  lists them first, in the same row shape as the templates' supersedes read.
- List and show rows carry `state_changed: {at, by {kind, id, name}, reason}`, `null` while
  active.
