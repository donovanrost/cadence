# Day plan lifecycle and the 'no approved plan' Now item (domain, 11-15; ux U61)

Status: **the source is built** (`Cadence.Reads.PlanCoverageAttention`, branch
`domain/plan-coverage`, landing after api's 901cd1e0d), with lead's stalled-booking rule (11-16).
The lifecycle guards below are on `domain/day-plan-lifecycle`. It's an attention source like U47/U54.
**Readers: the shape is the one under "Fields (as built)"; it supersedes the 11-15 proposal.**

## Why

On 11-16 there were 40 requirements and zero bookings. The day's only plan (planned 11-10, rejected
in a QA test, resubmitted 11-11) sat in `pending_approval` for four days, and nothing told anyone.
Planning is manual today (below), so this item is the safety net.

## Answers to fe-setup's questions (from the code)

**(a) Does a pending plan lapse once its day starts? Yes: at its first selected pass, not at
midnight.**

- Approving re-validates that **every** selected opportunity snapshot is unexpired
  (`ContactPlanApprovals.maybe_revalidate/7` → `unexpired/2`), and it's all-or-nothing.
- On dev a snapshot's `expires_at` is its pass's start (11-16's plan: 36 snapshots, `expires_at =
  starts_at`, the first at 00:28:49Z).
- So from the first selected pass's AOS, the plan can no longer be approved
  (`contact_plan_opportunity_expired`).
- Execution also skips any item whose snapshot has expired (`ContactPlanExecutions.unexpired/2`).

Mid-day, what can still be approved and booked is a **new** plan for the rest of the day (a fresh
draft only sees future opportunities). So once the first window has opened, the item's action is
"Plan the rest of 11-16", not "Review".

**(b) Is there an automatic daily planning run? No.**

- `FleetPlanningRun` has a `:scheduled` trigger kind, and `ContactPlanning.FleetAutomation`
  implements the unattended, exact-grant workflow (plan, then reserve, under an
  `AutomationGrant`).
- But nothing invokes it: no scheduler, and no caller of `FleetAutomation.plan/5`.
- Every run on dev is `manual` or `repair`. 11-16's coverage was one manual run on 11-10.

A daily scheduled run (e.g. plan day D at D − 48 h under an automation grant) is a product decision
for the user. Until then, this item is how a missed day gets noticed.

**Re-planning 11-16 (fe-setup and qa).**

- `POST …/contact-plans/drafts {day}` succeeds while another plan for the day is pending: there's no
  check.
- Nothing supersedes the pending plan, either at draft or at submit. No code writes `:superseded`,
  and `PlanSupersession` only reads requirement and template changes.
- The old plan lapses at its first pass (a).
- **Don't approve both** until the guard below is built: two approved plans for one day would both
  book the same requirements.

## Day plan lifecycle (director's ruling, 11-15)

The 11-16 re-plan showed two gaps.

**1. One approved plan per day, and an explicit supersession.**

- **Approval guard.** Under the plan lock, `ContactPlanApprovals` refuses approval when any
  requirement this plan covers is already covered by **another** plan in `approved`, `executing`,
  `partially_reserved` or `reserved`: `{:error, {:contact_plan_day_already_planned, %{plan_id,
  revision, state, requirements: n}}}`. The overlap is by requirement, read from both plans'
  `requirement_refs_document`, not by horizon alone. That covers a fleet day (the run's horizon) and a
  per-requirement plan with one rule.
- **Supersession on draft.** When a new candidate plan is created for day D (a fleet run whose
  horizon is D, from `Scheduling.create_draft` or any run), every other plan for D in `draft` or
  `pending_approval` becomes **`:superseded`**. It's the first writer of that state.
  - It's written in the run's transaction, with `lifecycle_reason` "Superseded by <new plan>
    (planned <at>)".
  - A pending approval on it is withdrawn.
  - A ScheduledReads update (`:contact_planning_changed`) is published.
  - Approving or submitting a superseded plan is refused: `{:error,
    {:contact_plan_superseded_by, new_plan_id}}`.
- **ux words** both refusals.

**2. Approve what's still valid.**

- Approval no longer fails whole when a selected snapshot has expired. It splits the selection into
  `valid` and `expired`:
  - **valid not empty:** the version is approved as planned (its `content_sha256` and policy
    snapshot still match exactly, so the policy check runs on the full selection, the one that was
    reviewed). The decision records `expired: [%{snapshot_id, requirement_id, starts_at}]`, and
    execution books `valid` only (it already skips expired items).
  - **valid empty:** refused, `{:error, {:contact_plan_all_opportunities_expired, count}}`.
- The approval result returns `%{reservable: n, expired: [...]}`, so the console can say what will
  and won't be booked. **ux words the partial result.**

**Tests:**
- two approvals for one day: the second is refused with the first plan's id;
- a per-requirement plan overlapping an approved fleet day is refused;
- a new draft for D supersedes D's pending plan, and approving the superseded plan is refused;
- a partial-expiry approval books the unexpired items and lists the expired ones;
- all expired is refused with the count;
- the 11-16 shape: v2 pending, a new draft supersedes it, the new plan's approval books.

## The source: `plan_coverage` (as built, 11-16)

One item per UTC day **D**, from today to today + 2, id `YYYY-MM-DD`. It's raised when D has needs
and **nothing is being booked** for them.

**What counts:**

- **D's needs and first window:** `Reads.ContactPlanDays` (the K1 strip's read, so the strip and Now
  agree). `requirements_count` is the day's contacts needed (requirements and template occurrences).
  `first_window_at` is the earliest window that **starts** in D. A requirement carried over from the
  day before doesn't start D's countdown, so a day with only carried-over needs has no item.
- **D's plan:** the strip's own rule (the newest plan that isn't superseded or canceled), with its
  **derived** state (`Control.Contacts.plan_state/5`).
- **Covered (no item):** the derived state is `executing`, `unconfirmed`, `partially_reserved`,
  `reserved` or `failed` (unbooked passes have their own items), or `approved` within **2 minutes**
  of `approved_at` (booking normally starts in well under a second).
- **Open:** no plan, `draft` (sent back or not), `pending_approval`, `approved` past the grace
  (booking never started), and `interrupted` (the run stopped with passes never placed, its lock
  free). A `partially_reserved` plan whose run stopped also reads `interrupted` (lead 11-16: the
  execution projection writes `partially_reserved` after the first reserved item).
- No heartbeat or job: the execution lock is a Postgres session lock, so a free lock means no run.

**Priority:**

| When | Priority |
|---|---|
| `now ≥ first_window_at − 24 h` | P2, caution |
| `now ≥ first_window_at − 6 h` | P1, caution |
| `now ≥ first_window_at` | P1, `severity: "crit"` |

**Fields (as built):**

```
%{
  id: "2026-11-16", source: "plan_coverage", state: "open",
  day: "2026-11-16",
  first_window_at: DateTime, due_at: DateTime,     # the countdown target
  severity: "caution" | "crit",
  requirements_count: 1512,
  raised_at: DateTime,      # first window − 24 h, or later: approved_at + 2 min / last progress
  plan: nil | %{
    id, revision,                                 # contact_plan_id, version (R41)
    state: "pending_approval" | "draft" | "approved" | "interrupted",
                                                  # sent back = "draft" with sent_back set
    author: %{id, name} | nil,
    submitted_at: DateTime | nil,                 # pending_approval only
    sent_back: nil | %{by: %{id, name}, at, comment},
    approved_at: DateTime | nil,                  # approved / interrupted only
    booking: nil | %{reserved, total, last_progress_at}   # interrupted only
  },
  approvers: [%{id, name}]                        # organization admins, never the author
}
```

`last_progress_at` is the latest item start or finish: the last progress seen, **not** when the run
stopped. The console adds the per-viewer fields: `viewer_can_approve`, and `viewer_can_book`
(`:operate_mission`, what `POST …/execute` authorizes; true → Start booking / Continue booking,
false → Open plan).

**Resolutions** (`resolved_since/3`, from durable times):

```
%{id, source, day, action, from_state, plan_revision, booking, resolved_by, resolved_at}
```

| `action` | When | `from_state` | `booking` |
|---|---|---|---|
| `approved` | the plan was approved and booking started within the grace; by the approver | nil | nil |
| `booking_started` | booking began after the grace (`"approved"`), or resumed after a gap longer than it (`"interrupted"`); by `system` | `"approved"` / `"interrupted"` | nil |
| `day_ended` | D ended still open; by `system` | the plan's state then, or nil | `%{reserved, total}` when interrupted |

**`nothing_left` is NOT emitted (yet).** Nothing durable records when a day's needs drop to zero, so
such a day just leaves the list with no resolved line. ux's words ("Nothing is left to plan for
11-16.") stay specified for when a durable time exists; **readers shouldn't build a line for it now.**

**Cost:** `Reads.Attention` wraps each load (and `/counts`) in `ReadMemo.with_memo/1`, so the source
reads the days once per load, not three times. That read is the strip's: the plan list (one
selected-opportunities query per plan, up to 100; 18 plans on dev) plus the demand. `approvers` is
one member query per item.

## Tests (built: `contact_plan_executions_test.exs`, U61 describe; lifecycle tests on its branch)

- No item for a day with an approved or reserved plan.
- One per day for a pending plan, sent back with its comment, draft, and no plan.
- The priority steps at T−24 h, T−6 h and the first window (injected now).
- Crit with a pending plan whose first snapshot has expired says "Plan the rest of D".
- Resolutions: approved, nothing left, day ended.
- `viewer_can_approve` is false for the author.
- The 11-16 shape from dev: pending since 11-11, 40 requirements.
