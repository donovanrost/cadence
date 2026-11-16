# Setup and admin screens: ux a11y checklist audit (dashboards, 11-16, for fe-setup and qa)

Lead asked dashboards to run ux's checklist (`ux/a11y-checklist.md`) over fe-setup's screens ahead of qa's §6 pass.
This was an audit only. Kit-level causes are fixed by dashboards (lead reviews). Everything else is for fe-setup.

**Method**
- **Code read:** every screen, every sheet, dialog and in-place confirm, against A1–A7, B1–B5 and D.
- **Headless pass on :4011:** 60 page runs at 1440 and 390, as org admin, plus platform admin for Data sources
  and Admin › Audit. It was load-gated and read-only: each "…" sheet was opened, then Tabbed, Esc'd and checked
  for focus return. Nothing was confirmed, typed or saved.

**What the headless pass found**
- No page scrolls sideways at 390.
- Every page has one h1, except Admin › Audit (see Shell).
- Every sheet it could open passed A2–A5.
- Register source fails A1 (confirmed live).

**Not reached live:** the Admin › Audit content and the #90 platform switch need admin mode, a step-up the read-only
pass didn't do. Both were audited in code only.

**Since ApSheet 8d7a6a07e:** a sheet whose opener is gone *at close* now returns focus to the page h1, not `<body>`.
The A5 items below are the other kind: the control disappears in place, or after a later refetch.

`V` marks a finding confirmed against the code by dashboards (re-read) or live; the rest are from the code read and
are high-confidence unless they say "(medium)".

## Kit (dashboards, lead's review)
- **K1 [A6]** ApSelect has no `required` prop, so required selects can't carry `aria-required`. Affected: Grant
  mission, Platform switch "Read from", Register source selects, Override spacecraft. Fix: add `required`, which
  sets `aria-required`. `V`
- **K2 [A1/A4]** An ApSheet without a footer has no close control at ≥768 (its ✕ shows on phones only) and no
  initial-focus target, for example Data sources › binding History. Fix: show the ✕ at every width when the sheet
  has no footer, and make it the focus fallback. `V`
- **Proposal, lead's call:** about ten screens hand-roll an in-place confirm (Remove account, Reset to inherited,
  invitation Revoke, Rotate/Revoke key, requirement Close/Cancel). All of them miss the same three things: focus on
  the safe button when the confirm opens (A1), Esc backs out (A4), and focus returns to the opener (A5). A kit
  `ApInlineConfirm` would fix them in one place.

## Shell (lead / fe-ops)
- **S1 [B / one h1]** Admin › Audit without admin mode shows the step-up form, whose headings are two
  "Admin mode" h2s and no h1. Fix: give the step-up gate an h1 (the page title), or make its heading the h1. `V`

## Readiness
- **[B2]** Finding rows show severity only as an aria-hidden mark. Only "Optional · " rows get a word; blocker,
  caution, stale and not-set-up rows don't — `features/readiness/FindingsPanel.vue:35-45`. Fix: prefix the title with
  the word ("Blocker · …"), as optional rows already do. `V`

## Add spacecraft
- **[B3]** "Show all N / Show first 8" has no `aria-expanded` — `spacecraft/add/BatchPreview.vue:63-65`. Fix:
  `:aria-expanded="showAll"` and `aria-controls`. `V`
- **[A5]** The failure callout's Retry clears `failure` at once, which unmounts the focused Retry —
  `spacecraft/add/StageBatchButton.vue:48,86`. Fix: focus the Stage button before clearing.

## Catalog (with import and the model-approval panel)
- **[B2]** Diff table: "breaking" is shown only by the row's caution wash, and the Op column is a bare
  `+ / − / ~` — `catalog/DiffPanel.vue:57-61`. Fix: add a "Breaking" word or tag, mark the glyph aria-hidden, and add
  an sr-only Added/Changed/Removed.
- **[B3]** "Show N warnings / Hide them" has no `aria-expanded` — `catalog/ImportVerdict.vue:39-41`.
- **[A6]** "New database name" has no `required` — `catalog/UploadPanel.vue:90`. A file-type or size problem is only
  in a callout, not wired to the file input — `UploadPanel.vue:76-81,94-96` (medium).
- **[A5]** In the approval panel, the focused control disappears in four places, each landing focus on `<body>`. Fix:
  focus the decided line (tabindex −1), or the now-enabled Approve.
  - After Approve, the refetch swaps in the decided view — `approval/ApprovalActions.vue:26-32`.
  - After Reject, the refetch does the same, after the sheet has already returned focus to "Reject…" —
    `ApprovalPanel.vue:39-46,72-80`.
  - "Run comparison" unmounts itself when the report arrives — `ApprovalActions.vue:18-25`.
  - The failure callout's Run comparison clears the callout it sits in — `ApprovalPanel.vue:81-85`.
- **[A6]** RejectSheet's server refusal is a plain `<p>`, so nothing announces it — `approval/RejectSheet.vue:40`.
  Fix: use `ApCallout tone="crit"` (medium).
- **[A5]** Removing a canary chip drops focus — `catalog/RolloutCanary.vue:25-31` (medium).

## Profiles
- **[A1/A5]** Each of these swaps controls without moving focus, so focus is lost on open and on close. Fix: focus
  the first field on open, and the opener again on close.
  - Section "Edit" swaps to SectionEditor — `profiles/SchemaSectionPanel.vue:35`, `ProfileSectionView.vue:23-39`,
    `StagedEditAside.vue:51`.
  - "Edit rules" and "Add a profile rule" swap to RulesEditor, and back on Cancel — `ProfileRoutingPanel.vue:34,43`,
    `RulesEditor.vue:127`.
  - "Add override" hides itself — `OverridesPanel.vue:18,25-26`, `OverrideCreate.vue:179`.
- **[B1]** OverrideCreate renders above its opener, so the Tab order runs backwards — `OverridesPanel.vue:18-26`.
- **[A6]** Rule problems are only in a callout: Label and Route name have no `aria-invalid` or `required`, and the
  reason is the generic "Fix the rules first." — `RulesEditor.vue:111-126`, `RuleForm.vue:19-30`.
- **[A7]** Check's `disabled-reason` is `invalid ?? ''`, which is empty while busy — `StagedEditAside.vue:38-42`. Fix:
  `invalid ?? 'Checking…'`. `V`
- **[A5]** Remove rule, Remove leg and the station-chip × each drop focus — `RuleForm.vue:47`, `RuleLegs.vue:36`,
  `RuleStations.vue:22-28` (medium).
- **[B2]** "Many overrides" is shown by colour only — `ProfilesTable.vue:46-50` (medium).

## Changes
- **[A5]** In each of these the focused control unmounts and focus drops to `<body>`. Fix: focus the outcome callout
  (tabindex −1), the next row's summary, or the "Nothing staged" heading.
  - A successful Apply or Request review hides the board — `changes/ChangesScreen.vue:133-134`,
    `ApplyAside.vue:112-117`.
  - The same for Approve & apply and Send back — `ReviewPanel.vue:44-58`.
  - Withdraw, and Discard all/mine — `ChangeRowHead.vue:21-30`, `ChangeList.vue:55-79`.
  - Conflict Keep mine / Take live — `ChangeConflict.vue:47-61`.
- **[A6]** "Why" has no `required` — `ApplyAside.vue:92`.
- **[B4]** Another user's staging bumps the version, so the preview drops to "Running checks…" and the focus on K2
  is lost — `ChangesScreen.vue:31-38`. Fix: keep the previous preview while the new one loads (medium; live check).

## Contact planning (requirements, requirement page)
- **[C]** The inline "book a pass" link and the template link in "Change it in its template:" are colour-only
  (`hover:underline`) — `planning/RequirementPlanning.vue:40`, `RequirementView.vue:58`. Fix: `underline
  underline-offset-2`. `V`
- **[A1/A4/A5]** Close… / Cancel… swap in place with no focus move, and Esc does nothing. Back drops focus, and a
  successful end unmounts the panel — `planning/RequirementEnd.vue:62-124`, `RequirementView.vue:70-76`. Fix: focus
  Reason on open; Esc does what Back does; Back focuses the opener; after the end, focus the ended-state callout.
- **[A1/A5]** Edit hides itself, and the editor's Save and Cancel don't return focus — `RequirementScreen.vue:29-33,62`.
- **[A6]** A validation error on an "Advanced" field stays inside the collapsed `<details>` —
  `RequirementGroups.vue:27` (medium). Fix: open it when one of its fields has an error.
- **[A5]** Newer/Older unmount the pager while the next page loads — `RequirementsPanel.vue:63-85`. Fix: move the
  pager outside ApRemote, or keep the value while loading.

## Plan, the review step and Re-plan
- **[B4]** Two live regions re-announce every second. Fix: aria-hide the clock, or keep it outside the live region.
  - The unconfirmed callout (role=status) holds a 1 Hz T− countdown — `scheduling/UnconfirmedCallout.vue:41-44`.
    This also affects Re-plan.
  - The drafting panel (role=status) holds a ticking `elapsed` — `PlanStatePanel.vue:90,106`. `V`
- **[B2]** The current drafting phase is marked by colour only — `PlanStatePanel.vue:96-100`. Fix: `aria-current` plus
  a word (medium).
- **[A5]** Submit and Send back return focus to their opener, then the refresh replaces it. Re-plan's Apply does the
  same — `PlanScreen.vue:98-103,139-147`, `ReplanScreen.vue:191-197`. Fix: after the refresh, focus the new primary or
  the state line.
- **[A5]** In each of these the focused control unmounts or is hidden. Fix: keep the sheet mounted while it's open,
  or focus the panel heading or empty state (medium for the first two).
  - A Resolve sheet sits inside its row and unmounts with it on success — `resolutions/ResolveBookingActions.vue:22-28`.
  - "Show all" unmounts while it's open once the count drops — `UnconfirmedCallout.vue:58-59`.
  - Remove pass and Add pass clear the selection — `PlanScreen.vue:151-155`, `SelectedPanel.vue:105-120`.
  - "Propose a re-plan" unmounts — `ReplanScreen.vue:363-370`.
- **[A6]** The gap reasons and Send back's "What should change" have no `required` — `SubmitSheet.vue:186-220`,
  `SendBackSheet.vue:38`.
- **[A7]** Several buttons are disabled with no reason:
  - StationIssues "Remove" on a locked pass — `StationIssues.vue:99`. `V`
  - Busy-disabled buttons with no "Working…": `PlanFooter.vue:65,68,76,84`, `PlanScreen.vue:371`,
    `SelectedPanel.vue:109,117`, `AlternativesList.vue:70`, `StationIssues.vue:93`, `ReplanScreen.vue:368,376`.
- **[B5]** Pass review's 30-day chart sentence describes only the encoding; the values are in hover titles —
  `review/DailyPanel.vue:35-37` (medium).

## People
- **[A6]** Invite email has no `required` — `people/InvitePanel.vue:63`. While sending, the reason still says "Enter an
  email address." — `:66-71` (medium).
- **[A1/A4/A5]** In-place confirms with no focus move or Esc. Fix: on open, focus Cancel; Esc does what Cancel does;
  Cancel focuses the opener; after a rotate, focus the "Rotated" callout.
  - Invitation Revoke… — `InvitationPanel.vue:61-67`.
  - Service identity Rotate key… and Revoke… — `ServiceIdentityActions.vue:24,61-76`. Confirmed live: no dialog.
- **[A5]** Resend replaces the route before the refetch, so the panel unmounts and the "Sent again" note is lost —
  `InvitationPanel.vue:26-28`, `InvitationScreen.vue:20-45`. Fix: refetch first.
- **[A5]** On create, the form is replaced by the token panel and focus drops, so the token that's shown only once
  isn't announced — `ServiceIdentityNewScreen.vue:64,83-92`. Fix: focus the "Created" callout or Copy.
- **[A6]** In remove-member's type-to-confirm, the email to type is only a placeholder, and the field has no
  `required` — `PersonManage.vue:80-85` (medium). Fix: label it `Type {email} to confirm`.
- **[A7]** Save's reason while busy is "Pick a different role" — `PersonManage.vue:65-67` (medium).
- **[B2]** The key-age warning on the service page is colour-only — `ServiceIdentityScreen.vue:74` (medium). Fix: add
  the caution mark, as the list does.

## Audit, Admin › Audit
- **[A5]** "Load older" (`audit/AuditResults.vue:38-45`) and "Older" (`admin/AuditScreen.vue:82-86`) are `v-if`, so the
  last page removes the focused button. Fix: keep it, disabled, with the reason "No older events".

## Provider accounts
- **[A1/A5]** Remove account's in-place confirm puts the danger "Remove" before "Keep", focus isn't moved, and
  Keep or a failure drops focus — `providers/RemoveAccount.vue:36,52-67`. Fix: Keep first and focused, then return to
  the opener. `V`
- **[A1/A5]** Edit hides itself, the form's first field isn't focused, and Save/Cancel drop focus —
  `ProviderAccountDetail.vue:56`, `AccountEditForm.vue:66-69`.
- **[A5]** After Revoke… (grant) and Revoke credential…, the refetch removes the opener —
  `AccountGrantsTable.vue:31-37`, `AccountCredential.vue:31-37` (medium). Fix: pass `return-focus`, or focus the
  row's state or the note after the refetch.
- **[A6]** Grant's Quota error is only the button's reason; pass it to the Quota field's `error` —
  `GrantMissionSheet.vue:30,94-99` (medium). The credential.backend error isn't wired to its control —
  `CredentialFields.vue:32-34` (medium).
- **[A1, ux to rule]** Reason-sheet danger confirms (Revoke grant or credential) open on the Reason textarea, not
  Cancel — `ReasonSheet.vue:36`. Other reason sheets do the same; ux should say whether "reason first" is the
  accepted pattern.

## Data sources (with the #90 platform switch)
- **[C, B4]** When the platform switch's blast radius changes on refetch, the typed name clears silently: the blast
  line isn't live — `sources/PlatformSwitchSheet.vue:36-43,137`. Fix: set the `changed` (role=status) callout there
  too, or make the blast line `aria-live="polite"`.
- **[A6]** In the platform switch, "Read from" and type-to-confirm have no `required` — `PlatformSwitchSheet.vue:139-152`
  (the select needs K1).
- **[A1]** The mission binding's Switch sheet has no `initial-focus`, so it opens on Cancel —
  `BindingSwitchSheet.vue:59`. Fix: `initial-focus="select"`. `V`
- **[A1]** Register source opens on Cancel, because the fields render after options load —
  `RegisterSheet.vue:17-49`. Fix: focus Name once ready. `V` (live, both roles)
- **[A6]** Register source's Stores, Kind, Isolation, Storage and Credentials have no `required` —
  `RegisterFields.vue:23-59`. Rotate credential's field has no `required` — `CredentialSheet.vue:51-56`.
- **[A1/A4]** The binding History sheet has no footer, so there's no close control at ≥768 and no focus target —
  `BindingHistorySheet.vue:32-55`. This is fixed by K2; a footer "Close" works too. `V`
- **[A5]** Switching a binding away removes its row and its Switch… opener — `SourceBindings.vue:72-76` (medium).
  Fix: pass `return-focus`.
- **Live check:** whether Deprovision…, Retry and Requeue disappear after acting (`SourceActions.vue:48-91`,
  `SourceRuns.vue:61-70`). Retry/Requeue's explanation is only a hover title.

## Mission settings, Org settings
- **[A1/A5]** In MissionSettingsField, Override and Change hide themselves with no focus move, and Save/Cancel drop
  focus. The in-place Reset confirm puts the danger first, isn't focused, and drops focus after either button. A
  Reset without a confirm loses its button after the refetch — `settings/MissionSettingsField.vue:28-95`. Fix: focus
  the input on open; afterwards, focus the opener or the outcome line; put Cancel first and focus it.
- **[C]** "Use 90%" disappears after it's applied (the ratio callout unmounts), dropping focus —
  `changes/SchemaTextField.vue:39-46`. Fix: focus the field again.
- **Org settings:** clean.

## Checked and clean
- **A2/A3/A4:** every ApSheet.
- **A7:** almost every disabled button has a reason.
- **B1:** order on every screen.
- **B2:** ApTag and verdict words.
- **B3:** `<details>`/`<summary>` (Technical details, Advanced), and the Changes row Details toggle.
- **Admin › data source bindings row (section C):** the confirm label reads "Type default_flight_telemetry to
  confirm", and the Switch's reason is read.
- **Org settings.**
- **390:** no sideways scroll anywhere, and sheets are full-height (D2).
