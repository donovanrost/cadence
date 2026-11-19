# Review: contact-plan Submit and Approve against U97 (#257)

Reviewer: ca-ux (Commanding & Approvals UX). Checked from code on develop `a48743995` (PR #267 merged), against
U97, U20, U95, U36, U61 and a11y-checklist B6. Owner of the screens: fe-ops (Ground & Comms); ux copied.
No local browser run; findings are from the code paths.

Files: `frontend/apps/console/src/features/scheduling/` `review-run.ts`, `review-words.ts`, `plan-primary.ts`,
`SubmitSheet.vue`, `PlanScreen.vue`, `PlanFooter.vue`, `lifecycle.ts`, `errors.ts`; kit `ApCallout.vue`.

## What holds

- Success only from the answer (U20): `Approved.` only on `outcome: "approved"` (`review-run.ts:85-89`); `Sent for
  approval.` only on `pending_approval` (`review-run.ts:121-123`); anything else gets U97's "didn't record" /
  "didn't confirm" lines (`review-words.ts:190-194`). Outcomes decode with `knownText`, so an unknown outcome falls to
  the cautious line.
- The one act stops when submit's outcome isn't `pending_approval`, with no approve call (`review-run.ts:121`, #264).
- The note goes only as `decision_note` in the one act (`review-run.ts:111-117`, #264); a refused approve keeps it for
  the retry (`keepNote`, `SubmitSheet.vue:133`).
- Self-approval refusals: both `because` lines match U97 word for word; Approve then shows disabled with the A6
  reason (`plan-primary.ts:104-105`), Send back stays (`PlanFooter.vue:111`).
- The submitter up front under `independent` gets no Approve, only "You submitted this plan, so another org admin
  approves it." (`plan-primary.ts:108-110`); under `direct` Approve shows.
- `plan_not_pending` (all four forms), `plan_changed`, `forbidden`, unknown code with Technical details, submit's
  `plan_already_submitted` (three forms): match U97.
- A 422 on the note shows the server's words under the note, not in the callout (`SubmitSheet.vue:164-171`).
- The one act's labels, confirm body and muted line (`DIRECT_NOTE`) match U97, gaps included.

## Findings, ranked (wrong claim > wrong words > a11y > nits)

### 1. Wrong claim: "Booking 40 passes" when some passes expired

`review-run.ts:87` builds the success line from `plan.counts.passes`. When the approve answer carries `expired`
(passes whose window had started, U61), only `expired.reservable_count` are booked. The screen then shows two lines
that disagree: the result callout "Approved. Booking 40 passes." (`PlanScreen.vue:313`) and U61's info callout
"Approved. Booking 37 passes; …" (`lifecycle.ts:132`, `PlanLifecycleCallouts.vue:41`). Breaks U20 (claim only what's
known). Fix: count from `expired.reservable_count` when `expired` is present, or let the U61 callout carry the line and
drop the duplicate. Which of the two shows is ux's call (gap A below).

### 2. Wrong words: `plan_superseded` on approve says "can't be submitted"

`review-words.ts:145-148` prefixes U36's submit-side sentence: "Not approved: contact rules changed since this draft,
so it's superseded and can't be submitted. Draft the day again." The act was an approve, and the line doesn't end
"Your approval wasn't recorded." (U95, U97's preamble). In practice `PlanScreen.vue:143` closes the sheet on
superseded and the superseded state shows, so this line is reachable only in the one act's partial line ("R41 was
sent for approval, but not approved: contact rules changed since this draft, so it's superseded and can't be
submitted.") — which contradicts its own "was sent". Needs ux's line (gap B).

### 3. Wrong words: `plan_not_ready` / `acknowledgements_required` show the server's message

U97 says "U36's lines, opening 'Not approved:'", but U36 has no lines for these codes, so `review-words.ts:150-157`
shows `Not approved: ` + the server message: "Not approved: The plan has unmet requirements or conflicts." (capital
after the colon, no what-to-do, no "Your approval wasn't recorded."). Not fe-ops' fault; needs ux's lines (gap B).

### 4. Wrong words: submit's `plan_changed` doesn't open "Not sent:"

`SubmitSheet.vue:179-183`: "The plan changed since you opened this. Close it and review again." Every other submit
refusal opens "Not sent:" (U97, designers.md §3). Suggested, matching U97's approve line: "Not sent: R41 changed after
you opened it, so nothing changed. Reload to review it again." For ux to confirm.

### 5. a11y: the sheet's refusal is announced politely, not as an alert

The sheet's refusal is `<ApCallout tone="caution">` (`SubmitSheet.vue:294`); `ApCallout` gives `role="status"` to
every tone but `crit` (`packages/apogee-ui/src/ApCallout.vue:10`). B6 wants `role="alert"` for refusals and failures.
The screen-level partial line and self refusal are `crit` (alert, fine); the "didn't record" / "didn't confirm" lines
are `caution` (status), which reads as a result and may be right. Kit-level question for ux: should `ApCallout` take
an explicit `announce` / role rather than inferring it from tone? Every caution-toned refusal across squads has the
same issue.

### 6. Nit / gap: the one act's unclear approve hides that the submit landed

`review-run.ts:129-130`: submit returned `pending_approval`, then approve got no clear answer (5xx, dropped
connection). The screen shows the generic UNCLEAR line ("this may or may not have gone through"), though the submit
is known to have gone through. U97 has no line for this case (gap C).

## Gaps for ux to word (not to improvise)

- **A.** The approve success line when `expired` is present: which line shows, and with which count (finding 1).
- **B.** Approve refusals `plan_superseded`, `plan_not_ready`, `acknowledgements_required` with U95's ending, plus their
  one-act "it" reasons (findings 2, 3).
- **C.** One act: submit landed, approve unclear. Suggested: "R41 was sent for approval, but Cadence didn't get a clear
  answer to the approval, so it may or may not have been recorded. Reload to see the plan before trying again."
- **D.** U97 internal: `plan_not_found` and `duplicate_operation` on approve don't end "Your approval wasn't recorded."
  as U97's preamble says every approve refusal does, and `duplicate_operation` opens "Not sent:" on an approve. The
  built code matches U97's literal lines, so this is a U97 question, not a build bug.

## Rulings (ux, 11-19)

ux ruled on every gap the same day and adds the words to U97 and a11y B6 in one docs PR. The fixes go to fe-ops'
follow-up PR. #273 tracks finding 1.

- A: with `expired` present the success line is U61's partial line, with the count from the answer ("Approved.
  Booking 37 passes; 3 had already started, so they weren't booked."); the U61 callout keeps only its list.
- B, C, D: the approve lines for `plan_superseded`, `acknowledgements_required`, `plan_not_ready` (three forms),
  `plan_not_found` and `duplicate_operation`, all ending "Your approval wasn't recorded."; the unclear approve (one
  act and single); submit's `plan_changed` opening "Not sent:". Exact words: U97 after ux's PR.
- Kit: a refusal of the person's own act is `role="alert"` whatever its tone; `ApCallout` gets an explicit role that
  wins over its tone default. That's Platform card #276 (dashboards builds it); the outcome-role rules are a11y B6
  (#274).
- Finding 4's final line is U97's, not the suggestion above: "Not sent: R41 changed after you opened it. Reload to
  see it, then send it again."
- The fixes for A-D, #273 and finding 4 are fe-ops' commit 3998afed1 on `fe-ops/257-words`, in U97's words as merged
  in #274.
