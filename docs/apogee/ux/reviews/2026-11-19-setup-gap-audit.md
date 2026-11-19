# Setup gap audit: the console against the Setup screen specs (2026-11-19)

Owner: **mms-ux** (Mission Model & Spacecraft). For fe-setup to turn into board items; ux rules the items marked
**ux to rule**. A code read of develop `3ac4026b5`: `frontend/apps/console/src/features/{catalog, profiles,
spacecraft, readiness, changes, activations, apps}` against `screens/{Catalog, Profile, AddSpacecraft, Setup,
Changes, AppSurfaces}.md`, with `decisions.md` amending the specs (a later U-entry wins over a spec's text). No
browser run (designers.md §5). The serious items were checked line by line. The rest come from a full read and are
quoted from the code; check the line before you build on one.

**How to read it.**
- **Which side is right:**
  - **console**: the code changes.
  - **spec**: the spec text is stale, and gets a small docs PR later.
  - **ux to rule**: sent to ux as one batch.
- **Rank inside each list:**
  1. Wrong claims (U20) and missing or wrong refusal words.
  2. Accessibility.
  3. Layout and flow.
  4. Nits.
- **Cross-squad:** ✕ marks items that touch Commanding & Approvals' area. Changes is shared, and the approval panels
  in Activations are theirs. ca-ux is copied on those.
- **Known pending builds** (U99, U101, U102, U103) aren't repeated here. They're specified and with their owners.

## 1. Findings that cut across screens

These have the same cause on several screens, so each is one item, fixed once.

| # | Finding | Where (examples) | Side | Rank |
|---|---|---|---|---|
| X1 | **A missing name reads "someone" or "Someone", or falls back to a raw id** (U25: a person's name drops, a spacecraft or service reads "Unknown …", ids only in Technical details). | `changes/revision-record.ts:23`; `activations/api.ts:254,292`; `changes/itemLines.ts:23`; `changes/EntryList.vue:37`; `changes/RollbackOps.vue:39`; `apps/AppSurfaceScreen.vue:129` (spacecraft id in the breadcrumb); `catalog/RolloutPanel.vue:61` (profile id in the Stage label); `profiles/RuleStations.vue:11`; `profiles/OverridesList.vue:65` (raw path) | console ✕ | 1 |
| X2 | **Banned words on screen** ("items", "entries", "entities", "legacy"; designers §2). | `catalog/ImportVerdict.vue:38` "Unsupported items were skipped."; `catalog/DiagnosticsPanel.vue:34` "N items → M lines"; `changes/RevisionsTable.vue:84` and `EntryList.vue:22` "N entries"; `changes/CompareScreen.vue:32` "N entities changed"; `changes/RollbackPreviewBody.vue:24` "N items changed outside change sets"; `changes/RevisionsTable.vue:39` "Legacy activation" | console ✕ | 1 |
| X3 | **Enum values on screen instead of option words.** | `changes/ChangeOps.vue:11-13` (`{{op.action}} {{op.kind}} {{op.entity_id ?? "new"}}`, the expanded change row); `readiness/RecentChangeRow.vue:21` (raw `change.kind`); `catalog/approval/words.ts:128,137` (an unknown reason printed as its key with spaces) | console ✕ | 1 |
| X4 | **Who without when** (U29). | `changes/ReviewPanel.vue:53` "Submitted by … : “reason”" with no time, and "—" for no name; `catalog/approval/words.ts:96` "Imported by Mira K." with no time; `catalog/RevisionsPanel.vue:67-70` "11-14 22:10Z · Mira K." (should read "by Mira K. at …") | console ✕ | 3 |
| X5 | **"Not available in the console yet" states** for a server without a route. They're honest, but no spec has them. Write them into each spec as one shared pattern. | `catalog/CatalogScreen.vue:59-60`; `changes/ChangesEmpty.vue:13-14`; `apps/AppsScreen.vue:38`; `readiness/ReadinessScreen.vue:73-76` | spec | 4 |

## 2. Catalog (`Catalog.md`; U65, U88, U90, U99, U102, U103)

**A. Console and spec disagree**

| # | Spec or U-entry | Console | Side | Rank |
|---|---|---|---|---|
| C1 | designers §3: a refusal opens with the act ("Not approved:"); an unknown code reads "Not approved: Cadence refused this approval." with the code in Technical details. | `approval/words.ts:175-177` "Nothing changed: only an org admin can decide this." / "Nothing changed: {server message}." | console | 1 |
| C2 | Reject has its own refusals. | `approval/words.ts:144-174`: a failed **reject** reads "Not approved: …" | console | 1 |
| C3 | U100's catalog lines (`via_service`, `mission_model_approver_authors_unknown`, the up-front `authors_unknown`). | Not handled (`approval/api.ts:90`). It depends on #280 landing. | console ✕ | 1 |
| C4 | U17: catalog revisions are `rev 14`; `r14` is a change set. | `DiffPanel.vue:54` meta "Against r14 · sorted by risk" | console | 1 |
| C5 | § A empty state has primary `Import a catalog`. | `CatalogScreen.vue:72-76` "No catalog yet" with no action | console | 3 |
| C6 | § B drop zone, "Drop an XTCE (.xml) or CSV export, or choose a file". | `UploadPanel.vue:73` "Choose an XTCE or catalog export", with no drop handler | console | 3 |
| C7 | § C1 sort: breaking → removed → changed → added. | `DiffPanel.vue:12` puts breaking first only | console | 3 |
| C8 | § C3 change-set summary `Roll out rev 15 to Earendil Block 1 · 3 breaking`. | `RolloutPanel.vue:100` "Roll out rev 15 for …" | console | 4 |
| C9 | U102: no shorthand. | `RevisionsPanel.vue:63` Used by "500 SC" (U102 fixes the C3 cards; this column was missed) | console | 4 |
| C10 | § B parsing status is mono `PARSING · 1.8 MB · 00:04` plus live progress. | `ImportVerdict.vue:26` an info callout, "Parsing and validating… This page updates when it finishes." | console (ux ruled, §10) | 3 |
| C11 | § C stat strip: one `Declarations` tile only when the per-kind counts are missing; Unchanged "of 547 declarations". | `DiffStrip.vue:14,29` always a single Declarations tile, captioned "read from this file"; "of N commands and telemetry" | console when the read has per-kind counts, else spec (ux ruled, §10) | 3 |
| C12 | U90: a decided panel uses the short "not compared: no earlier configuration". | `approval/ApprovalPanel.vue:77` keeps the full callout | console (ux ruled, §10) | 4 |
| C13 | § C breadcrumb `CATALOG / IMPORT rev 15`; verdict on the file line; C1 shows the first 9 then `Show all`; U65's panel "above C1"; route `M/setup/catalog/:databaseId`. | Built differently and deliberately: `Catalog / <file name>`; a verdict callout (U99 builds on it); every row with a "Showing the first N…" footer; the revision page has no diff (U102); `?database=` | spec | 4 |

**B. The console does it; no spec covers it** (write into `Catalog.md`)
- The upload form's fields: "Catalog database" with "New catalog database…", "New database name", "Revision label" (e.g.
  FSW 3.2.0) and "Notes". Its reasons: "Choose a file.", "Name the new catalog database.", "Uploading…". Its
  refusals: "The file is X MiB; the limit is Y MiB." and "Cadence can't import {name}. Accepted: …"
  (`UploadPanel.vue`, `upload.ts:45,49`).
- The import runs panel: `rev N` under the file, Diagnostics "none" or "2 errors · 1 warning", and the panel hidden
  with no runs (`ImportRunsPanel.vue`, `CatalogScreen.vue:81`).
- "This revision couldn't be compared with rev N, so there's no diff." and "This is the database's first revision,
  so there's nothing to compare it with." (`ImportRunBody.vue:40-41`).
- Diagnostics: grouped identical rows with a "Count" column, at most 3 paths; the column is "Where", not "Path".
- Approval up-front lines: "Org admins approve catalog revisions." and "Cadence is still preparing this revision.
  Try again in a moment." (`approval/words.ts:122-127`). Also "The comparison didn't run: {error}"
  (`useApproval.ts:34`, not a "Not X:" form) and "No declarations changed." (`ComparisonReport.vue:32`).
- The revision page's Technical details rows and its generic "Database" breadcrumb (`ModelRevisionScreen.vue`).
- C3's reasons: "Choose profiles or spacecraft first.", "Nothing to stage: no spacecraft would move to rev N.", and
  "Check the N breaking changes first." (`RolloutPanel.vue:79-87`).

## 3. Profiles (`Profile.md`)

**A. Console and spec disagree**

| # | Spec or U-entry | Console | Side | Rank |
|---|---|---|---|---|
| P1 | P2: the route name previews live; an unknown token is named. | `RuleForm.vue:16` shows "Unknown token ." The token is never put into the message (**a bug**). | console | 1 |
| P2 | Rows use labels, never paths; refusals open with the act. | `RulesEditor.vue:57` "Nothing was staged. routing_rules.0.stations: …" (a raw path) | console | 1 |
| P3 | P2 acceptance: a rule edit shows the route count and samples before staging. | `sectionEdit.ts:107` "Checks pass · changes N spacecraft…" with no route count, samples or name preview | console | 3 |
| P4 | States: a read-only line says who can edit. | None in `ProfileScreen.vue` | console | 3 |
| P5 | P1 header meta `INHERITED BY 500 · 1 EDIT STAGED`; subline "3 override it" links to Overrides. | `SchemaSectionPanel.vue:31` no staged count; `present.ts:10` plain "3 overrides" | console | 3 |
| P6 | P3 meta "3 OF 500 DIFFER FROM THE PROFILE"; empty is a nominal callout; redundant rows "Same as the profile now · Reset to inherit". | `OverridesPanel.vue:36,49`; `OverridesList.vue:79` | console | 4 |
| P7 | P2 disabled rule dimmed with `DISABLED`; Limits links to the Limits app; the list's Protocols column reads `CCSDS TM / TC`. | `RuleBlock.vue:33` a sentence; `LimitsNotice.vue:12` links "Apps"; `api.ts:97` "TM ↓ · TC ↑" | console (ux ruled, §10) | 4 |
| P8 | P1 `RUNTIME` chip; header `[History]` plus a `…/history` route. | "Cancels queued commands" (P3 uses it too); History is a section tab | spec | 4 |

**B. No spec covers it**
- The whole **New profile** screen: "Copied from X vN: its fields, routing rules and app settings. No spacecraft use
  it until you assign them.", `Stage new profile`, "Nothing is live until the change set is applied.", "No profile to
  start from", "X (copy)" (`ProfileNewForm.vue`, `ProfileStartFrom.vue`, `ProfileNewScreen.vue`).
- Routing, still per spacecraft: "Routing is still set per spacecraft", `Add a profile rule`, `Open comms & routing`.
  Also the rule editor's "Roll out to: All spacecraft on this profile / New version only", `Check with the server`
  and `Stage rule change`, and the tokens `{station_name}` and `{direction}`.
- The list: "N on older versions" and "Set per spacecraft", and the empty state's "Every spacecraft pins one."
  History: "Not recorded", "· latest", "No revisions yet", and "Compare with rN →".
- Overrides: "Reset staged for X. It applies with the change set.", "Choose a spacecraft.", "Say why this spacecraft
  differs." and "That's its override already." Also "X already staged Y. Resolve it on Staged changes first."
  (`SectionEditor.vue:59`).

## 4. Spacecraft and Add spacecraft (`AddSpacecraft.md`; U25, U40, U94)

**A. Console and spec disagree**

| # | Spec or U-entry | Console | Side | Rank |
|---|---|---|---|---|
| S1 | U40: turning a switch off opens a short sheet that states the consequence ("Turning commanding off stops new requests and releases for EARENDIL-312…"), and the switch shows `STAGED · APPLIES WITH r7` until applied. | `OperationPanel.vue:39-41` shows On / Off / Not set tags only. Its comment says switches are staged through the Edit form (`edit.ts:14-15`), which is a deliberate placement. But no consequence sheet or line exists anywhere in `spacecraft/`, and the panel has no staged tag. | console (ux ruled, §10: staged on the Operation panel) | 1 |
| S2 | U25: "Deleted …" only where the server says so. | "Deleted profile" whenever the profile name is null (`SpacecraftTable.vue:51`, `SpacecraftPanels.vue:30`, `edit.ts:34`). Right only if api confirms a null name always means deleted. | console (unless api confirms) | 1 |
| S3 | U3's word for this severity is `Not set up`. | `detail.ts:176` maps `not_set_up` to "Note" | console | 1 |
| S4 | The commit is disabled with "Fix N NO-GO checks first". | `StageBatchButton.vue:36` "Fix the NO-GO checks first. <row problem>" | console | 1 |
| S5 | `×` returns to wherever the flow was opened. | `AddSpacecraftScreen.vue:72` always goes to the spacecraft list | console | 3 |
| S6 | U6: local section nav, plus Configuration and Overrides panels. | `SpacecraftPanels.vue` D1–D5 with neither (Configuration waits on U94's workspace route) | console | 3 |
| S7 | A2 has a Routing row; the Profile row names the catalog rev. A3 has Profile and Routes columns. Step 01 cards show `catalog rev 14`. A4 tile is `Routes 300`. | `checks.ts` has no Routing row; `BatchPreview.vue:13-20` has neither column and adds "Check"; `ProfilePicker.vue:40`; `SummaryAside.vue:39` "Routing rules — added later" | console | 3 |
| S8 | The step 03 primary is `Review batch`; the step 01 manifest has a drop zone and mapping chips. | "Continue to review"; a native file input and "N of 6 fields mapped" | console | 4 |
| S9 | Manifest cells are edited inline in step 02; the next free SCID comes from the server. | "fix them in the file and choose it again" (`StepIdentity.vue:37`); computed in the browser (`AddSpacecraftScreen.vue:37`) | console for the SCID; spec for inline edit (ux ruled, §10) | 3 |
| S10 | Step 03 is a transports checklist; after commit, `?created=`; checks come from `batch:validate`. | Built differently and deliberately: a summary of the profile's rules; Changes; browser checks plus the server's dry run | spec | 4 |
| S11 | U94's read refusals are the page's state, in body type, with no mark that misreads (U3: the dashed square means not set up). Added with ux's #349 review of the configuration workspace, which ranks the can't-view case; these are the other two. | All three `readRefusal` lines (`configuration/words.ts:148-166`) go to `ApEmptyState state="off"` as its `headline` (`ConfigurationScreen.vue:106`), so "This spacecraft isn't on this mission." and the packet-source limit line are also uppercase labels with the "not set up" mark. `ApEmptyState` has no `role="status"`. | console | 1 |
| S12 | U25, U98: the craft is named as the page names it, or not at all. | The middle crumb reads "Spacecraft" whenever the snapshot isn't ready (`ConfigurationScreen.vue:74-76`): while loading, as well as on every refusal (#349's #2). | console | 3 |
| S13 | U94's values read in bytes ("1,115 bytes"); U23: every number names its unit. | The framing line says "1,115 B frames · headers 0/0/4 B" (`words.ts:84`); #349's #3 names the three headers. Say "1,115-byte frames" and "secondary header 0 bytes · insert zone 0 bytes · OCF 4 bytes", as the Communications tab's labels do. | console | 4 |

**B. No spec covers it** (the Spacecraft directory and detail have no spec of their own)
- The directory: the summary line, the empty state, "No spacecraft match", the degraded callout, the columns, "not set",
  "Incomplete" and "Not known right now" (`SpacecraftListScreen.vue`, `SpacecraftTable.vue`).
- The detail: the `Ready` / `Incomplete` header tag, and "Not known right now (history unavailable)".
- Routing: "No routing rule" and "It can't be contacted until a routing rule covers it."; "Remove X?" with "Booked
  and running contacts keep the routes they were booked with."; "This extra route can't be opened for editing. It may
  have been removed."
- Add spacecraft: "Only an organization admin can add spacecraft. You can prepare a batch here, but not create it.";
  "No planes set. The fleet matrix orders these by SCID until you add them."; "Your draft is kept."

## 5. Readiness (`Setup.md`)

| # | Spec | Console | Side | Rank |
|---|---|---|---|---|
| R1 | Option words, never enum values. | `RecentChangeRow.vue:21` shows the raw kind (X3) | console | 1 |
| R2 | R2 is left out when there's no feed. | `RecentChangesPanel.vue:27` "Recent changes couldn't be read" | both, by cause (ux ruled, §10) | 3 |
| R3 | The fix action is `Edit rule`, etc. | `present.ts:123` "Open routing" | console (ux ruled, §10) | 4 |
| R4 | Only Optional titles carry a prefix; R2's meta is `AUDIT LOG →`. | Every title is prefixed ("Blocker · …"); "All revisions →" | spec | 4 |

**B. No spec covers it:** "Readiness not available"; "Readiness checks not available yet" with `Check again`;
"Nothing applied yet"; "Compare rA ↔ rB →"; "N stale" and "N not set up"; and the extra fix labels "Set up contact
planning", "Open changes", "Open app" and Install on optional findings (`present.ts:115-154`).

## 6. Changes ✕ (`Changes.md`, shared with Commanding & Approvals)

**A. Console and spec disagree**

| # | Spec or U-entry | Console | Side | Rank |
|---|---|---|---|---|
| K1 | **Four-eyes** (§3, designers §4): the reviewer differs from every author, and a stager never sees an Approve they can't use. | `ChangeSetBoard.vue:29-30` shows the review panel to anyone with `config.review`, authors included. The server refuses ("You staged part of this set, so you can't approve it…", `actions.ts:114`), so it's safe, but the person sees an Approve that can't work. | console ✕ | 1 |
| K2 | "Any NO-GO disables Apply with the reason"; without the apply capability, say who can apply. | `ApplyAside.vue:75` "A NO-GO check blocks apply. Fix it first." (no reason); `:70` "You can stage changes but not apply them." (no who) | console ✕ | 1 |
| K3 | Refusals open with the act ("Not applied:", U63, U65). | `actions.ts:272` "Nothing was applied. …" (U20's older "Nothing was staged." form) | console ✕ (ux ruled, §10) | 1 |
| K4 | U93: "r1 is saved · 2 changes…" in the nominal tone. | `nothingRunning.ts:13` "r1 is saved, 2 changes." in info (`ChangesOutcome.vue:36`) | console | 4 |
| K5 | §3 hold checkbox "I've read the 2 holds"; outcome action `View r6`. | "I've read the holds" (`ApplyAside.vue:122`); `View revisions` goes to the list (`ChangesOutcome.vue:59`) | console ✕ | 3 |
| K6 | §2 bar states: a conflict ("1 change conflicts with r6" / `Review conflicts`), awaiting review, and no apply capability (`Review changes`). | `StagedBarView.vue:47-61` has only "r6 in review · staging is paused" + `Open review` | console ✕ | 3 |
| K7 | §3 expanded row shows the diff (`path − old + new`, the per-spacecraft effect). | The raw op line (X3) | console ✕ | 3 |
| K8 | §4 kind tag `Rollback of r5` only when it applies. | Always a kind: `Rollback to r4` / `Baseline` / `Change set` / "Legacy activation" (X2) | console ✕ | 4 |
| K9 | §3 K2 checks are Conflicts · Readiness · In flight · Compatibility; K3 tiles are "Changes · SC · Routes" plus a readiness line; only Send back needs a comment; K1 `×` "Withdraw from r6". | Validation · Conflicts · Compatibility; `Changes` / `Authors` tiles; Approve also needs a comment ("Add a comment first. It's recorded with your decision."); the word `Withdraw` | console mostly ✕ (ux ruled, §10) | 3 |
| K10 | §2 bar `Discard all`; §3 K2 conflicts `Rebase` / `Remove`; §4 header; §6 v1 seam; §3's U38 reason words. | Deliberately changed: no Discard all (K1's header is the only discard); `Keep 1,115` / `Take 1,200`; U89's header; the seam is gone; U91 | spec ✕ | 4 |

**B. No spec covers it:** the outcomes ("N spacecraft staged. They're created when this change set is applied as r6.",
"Sent for review. An org member who didn't stage any of these changes approves or sends it back.", "Sent back to the
authors with your comment."); the checks panel's failure causes and lines (`ChecksPanel.vue:33-44`,
`ChecksBody.vue:28-31`); the apply reasons ("Waiting for checks.", "Acknowledge the holds first.", "Say why (10
characters or more)."); "Can't apply yet: …"; the conflict help ("Live changed under this since it was staged.",
"Keep mine … / Take live …"); `Details` / `Hide`; the rejection sentences in `actions.ts:110-130`; the whole
rollback preview ("A rollback is a new revision that reverses later ones. History isn't rewritten.", `Stage rollback
to r4`, "r5 was activated outside change sets. You can roll back to r5, not past it."); Revisions' subtitle and empty
state; Compare's "Nothing differs"; the older-format revision header.

## 7. Activations ✕ (U94, U95, U100)

| # | Spec or U-entry | Console | Side | Rank |
|---|---|---|---|---|
| V1 | **U94's approve refusals**, `activation_self_approval_forbidden` and `activation_approver_authored_content` (as amended by #292); U95's "Your approval wasn't recorded."; U100's `via_service` and `…_authors_unknown`; the up-front `cannot_approve_because`. | None are in the console. Only the old `self_approval_forbidden`, "You requested this. Someone else approves it." (`api.ts:319-320`). `approveRefusal.ts:132` handles 409s only. | lands with the #236, #240, #275 and #280 builds (none on develop yet), not a console bug today (ca-ux). Check it when they land. ✕ | 1 |
| V2 | U20, U94: `needs_review` is "approved, but Cadence couldn't confirm it was applied yet". | `api.ts:163-166` "Approved, but it didn't apply. …"; "Approved and applied." for any result that isn't a failure (`:168`) | console ✕ | 1 |
| V3 | U94: a decided request shows the muted line "What changes is shown only while a request waits…" with `Open configuration`. | `ActivationScreen.vue:79` hides the panel with no line | console ✕ | 3 |
| V4 | U41, U65: decisions read "by X at 11-13 02:20Z". | `api.ts:303` "Approved by X on 11-13 02:20Z" | console ✕ | 4 |
| V5 | U94's What changes label is `Handled APIDs` (U40's name; renamed by #349). | `changesWords.ts:15` and its tests say "Decoded APIDs", in the row and the summary ("Catalog revision (300), Decoded APIDs (12)") | console ✕ | 3 |

**B. No spec covers it:** "Approving applies it to the mission now. Rejecting leaves things as they are."; Approve
needs a reason ("Give a reason first."); the "Waiting for activation" panel with its `AWAITS YOU` tag; the tags
`WAITING` / `APPROVED` / `REJECTED` / `WITHDRAWN` / `SUPERSEDED` / `UNKNOWN`; "Rejected. Nothing changes." and
"Withdrawn. Nothing changes."; "It's already decided. Reload to see how." and "The approval rules changed since it
was requested. Reject it, …".

## 8. Apps (`AppSurfaces.md`)

| # | Spec | Console | Side | Rank |
|---|---|---|---|---|
| A1 | Not installed offers `Install` to admins only. | Everyone gets an `Install in Apps` link (`AppSurfaceNotice.vue:21`) | console | 3 |
| A2 | The spacecraft breadcrumb names the craft. | The raw id (X1, `AppSurfaceScreen.vue:129`) | console | 1 |
| A3 | Only the caution line "Waiting for activation approval…". | Also a nominal "Activation requested. It applies once it's approved." (`saveOutcome.ts:30`) | console (ux ruled, §10) | 4 |

**B. No spec covers it:** "N of M installed"; "This app or page doesn't exist on Earendil." and "… has no pages to
set up here."; "Leave this page? Changes you haven't saved here will be lost."; "This page lost its connection to the
app…" (`hostBridge.ts:17-21`).

## 9. What happens next

- **fe-setup:** turns the console items into board items. Rank 1 first. K1, K2 and V2 are cross-squad: copy ca-ux,
  and for Activations, the Commanding & Approvals owner. V1 isn't a new item: it lands with #236, #240, #275 and
  #280.
- **ux:** ruled the batch on 11-19 (§10). Those fixes go to fe-setup with the other console items.
- **ca-ux:** writes §7's "no spec covers it" words as a U94 amendment.
- **mms-ux:** spec items become small docs PRs per spec, and the "no spec covers it" lists are written into each
  spec. Catalog is first, since its U-entries are freshest.

## 10. ux's rulings on the batch (11-19)

| # | Ruling |
|---|---|
| C10 | The spec's mono line `PARSING · 1.8 MB · 00:04` with live progress, not a callout (callouts are for messages). "This page updates when it finishes." stays as a `text-3` line under it. |
| C11 | Per-kind tiles when the read carries per-kind counts; the single Declarations tile only when it doesn't (U20). Unchanged reads "of 547 declarations" (U23 unit). If the read never has per-kind counts, the console is right and the spec changes. |
| C12 | A decided panel uses U90's short form. |
| P7 | A `DISABLED` tag (off, mark + word), with the console's sentence kept as the row's secondary line. Limits links to the Limits app by name. Protocols reads `CCSDS TM / TC` (no arrows). |
| S1 | Switches are staged on the Operation panel (U40; U94's workspace says Open Operation, where they're staged). The Edit form's switch path goes, or links to the panel. The consequence sheet and `STAGED · APPLIES WITH r7` are console gaps. |
| S9 | The next free SCID comes from the server (a browser guess can collide, U20). Inline manifest edit is later: the console's "fix them in the file and choose it again" stands, and the spec says so. |
| R2 | By cause. With no feed by design, R2 is left out (spec): "couldn't be read" would be untrue. With a feed whose read failed, the console's line (U86). |
| R3 | The action names what it opens: `Edit rule <name>` when the finding has one rule to deep-link, else `Open routing`. |
| K3 | "Not applied:" opens it (U63, U65); "Nothing was applied." is the old form. |
| K9 | Checks: the console lists the checks the server runs. If the server runs Readiness or In flight checks the console doesn't show, that's a console gap; otherwise the spec changes. Tiles: the spec's Changes · SC · Routes plus the readiness line, with Authors moved to a meta line (four-eyes needs it, not a tile). Comment: optional on Approve, required only for Send back; if the server requires one on approve, that's an api item. Withdraw: the `×` stays as the visual, with the accessible name and tooltip "Withdraw <change> from r6" (B7). |
| A3 | One line. Drop the nominal "Activation requested…"; the caution "Waiting for activation approval…" is the save's outcome, announced as status (B6). |
