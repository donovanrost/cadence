# ux view on fe-ops' §11c(C) parity audit (planning design calls and the "by design" list)

For lead and the director, answering `docs/apogee/plans/parity-ops-c.md` (16196255e). These cover the items that
need a design call: A14, A15, A17, and section C. The rest of the audit is fe-ops' and lead's to sort.

## Planning design calls

**A14a. Planning horizon (a chosen multi-day window): different design. Keep the day as the unit.**
A fleet plan in the console is one UTC day. That choice holds up the rest of the model:
- one approved plan per day;
- a new draft supersedes the pending one for the same day;
- U61's coverage item is per day;
- the requirement view's "Plan 11-14" goes to a day (DECISIONS #89, #91).

A free horizon would let two plans overlap on one day, which those guards don't allow. The real need behind the
horizon is "get the next few days planned without hunting". Meet it with the days: the Plan screen's day picker
shows the next 7 days, each with its state (`Booked`, `Waiting for an admin`, `Draft`, `No plan`). Drafting four
days is then four quick drafts, each reviewed on its own, and each one still small enough to review. Build that
strip if it isn't there; don't build a horizon input.

**A14b. "Include recurring demand" toggle: drop.**
A draft covers every active requirement plus every active template (#89). A plan built without the templates would
look complete on the screen, while U61's coverage item and "Rule met" count it as short. To leave a template's
demand out, the operator pauses or ends the template, where the change is versioned and visible to everyone. A
per-draft switch nobody else can see is the wrong place for it.

**A14c. Reviewing pinned inputs before creating: covered; no build.**
The `no_draft` state already lists the day's demand (its requirements and templates) before `Draft the day`.
Drafting is cheap and can be redone, since a new draft supersedes the old one. The input fingerprint goes into
Technical details with the other evidence fields (B).

**A14d. Choosing the repair window: drop the free input. Show where the window comes from.**
Re-plan (K2) takes its window from the cause: the outage or provider change, plus the policy's
`repair_horizon_seconds`, and it locks every committed pass in it (#56, S8). A hand-typed window could leave a
lost pass outside the repair, or open booked passes to change. Instead, the Re-plan header says why the window is
what it is: "02:45–10:45Z: the Svalbard outage and the policy's 8 h repair horizon". Widening it is a policy
change, in Setup › Contact planning › Policy. The attempt count `attempt 2 of 3` goes next to it, because it tells
the operator whether another re-plan is still possible.

**A15. Approve without booking: drop. Add an optional note to Submit and Approve.**
In the console, approving books: `Approve and book 1,512 passes`. An approved but unbooked plan would be one more
waiting state, while offers expire on a countdown (`NEXT OFFER EXPIRES T−15:15`). That's the failure behind 11-16:
a plan sat in pending_approval, and the day had zero bookings (#91). If booking stops partway, the existing
`Continue booking` and the refusal table already cover the recovery. The other half of A15 is worth building: an
**optional** note on Submit and on Approve ("Note for the record"). It's recorded with the actor and time (U29) and
shown in the plan's history. Send back keeps its required comment.

**A17. Fleet run directory: drop as a directory. Fold run history into the day (with A10).**
Runs are an engine detail; the operator works with days and plans. Each part of the legacy directory has a place
in the console instead:
- **Run history:** a day's runs (drafts, re-plans, booking runs, failures, with who and when) belong in that day's
  plan history, which A10 builds anyway: one "History" section on the Plan screen, newest first.
- **A failed run's code:** it shows on the day, the way U30 and the refusal table already work.
- **Optimizer rationale:** it stays per pass ("why this pass", the alternatives list).
- **Resource pressure and fingerprints:** they go into Technical details (B).
- **Automation history:** drop it. Nothing runs automatically (#91), so a fleet-wide run directory comes back to
  the table with the automation feature.

## Section C: "gone by design"

**C1. Command stages: confirmed.** A command group is the batch, and Compose's autosaved draft is the private
workspace. Stages were a second batching layer on top of the same idea, with their own lifecycle to learn. What's
lost is a draft shared between operators. If that's needed, it becomes a feature of command groups, not a return of
stages.

**C2. The separate queue step: confirmed, with one condition.** GO and Arm queue the request directly. A
second "Review for queueing" page adds a click and no new decision. The condition: the queue page was where an
operator saw the **server-resolved arguments** (defaults filled in, units converted). That's safety information,
not just evidence. Where a resolved value differs from what was entered, the Approve and Arm sheets show it next to
the entered value (`Sent as 2.50 V (entered 2.5)`, or `Default used: 30 s`). The rest of the queue page's
fields (approval id, queue entry, content sha) go into Technical details (B).

**C3. "I reviewed…" checkboxes: confirmed.** A checkbox in front of a button only proves a second click. The
console makes the decision itself the attestation:
- GO is recorded with the actor and time;
- the reviewer can't be the author;
- the second GO must come from someone else;
- failing checks block the action.

Where the stakes justify extra friction, the console uses type-to-confirm (U53), not a checkbox.

**C4. The ops landing's cards and the frame's context rail: confirmed, with one sub-item to build.** Now is the
landing, and the rail counts carry the posture. Of the open sub-items:
- **Always-visible posture in the top bar: build.** The empty slot (`App.vue:50-51`) takes the cockpit status
  cluster that dashboards already has (`◆ 2 crit · ▲ 1 caution · 3 stale` chips linking to Alarms or Fleet, plus
  UTC). It's the same component, so posture reads the same on every screen.
- **Latest alarm transition time:** fold it into A6 as Alarms' header meta ("Last change 02:51Z on
  EARENDIL-047").
- **In-flight and failed command counts:** not separately. Failures already reach Now as items, and the Commands
  tabs count what needs you.
- **"Following" a command:** drop. Now surfaces what needs you, and Investigate holds the history.
- **A positive "Connected" indicator:** drop. Status is quiet when nominal; the console shows loss (offline,
  stale) and the ticking UTC clock shows it's live.

The rest of C5 (workspace panes, rail collapse, starred dashboards in the rail) is confirmed as gone.

## One wording ruling from section D
**D4:** a command's end reason `expired` reads **"Expired"**, never "Canceled". In a sentence: "Expired at 02:30Z
before it was released." (U68)
