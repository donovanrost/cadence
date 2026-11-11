# Command a group (J3 · contingency uplink sequence)

Route `M/commands/new[?targets=<query>&from=alarm:<id>]` → after save `M/commands/:requestId` ·
**takeover console layout** (no rail; fits the viewport) · Board `Command.dc.html`. The routine
variant of the same flow is Compose (C1, phase 3); both share this route and these regions.
Owner: fe-ops. Data and gaps: `docs/apogee/plans/ops.md` §J3. Scope: DECISIONS #7 (two-person is
policy-driven), #8 (no waves yet), #4 (no umbra/propagation), CommandFlow rules R01–R06.

**Question:** "Shed load on 312 and its sisters before umbra." **Same flow for 4 or 400.**
**Journey:** target by live query → build the command stack from the catalog → read the GO/NO-GO
poll → request the second GO (if policy needs it) and arm each uplink for its target's own next
contact.

## Takeover header
`×` (`aria-label="Close and return to EARENDIL-312"`; returns to the origin, keeps the draft) ·
mono lbl `UPLINK SEQUENCE · FROM ALARM ON EARENDIL-312` (or `· NEW`) over the sequence name
(display 20px, editable inline; defaults to the procedure name or `Untitled sequence`) · **ApStepBar**
`01 Targets · 4 · 02 Commands · 2 · 03 GO / NO-GO · 04 Arm & uplink` (counts live; done `✓`, current
`●`, upcoming `○`) · right mono `UTC 02:44:09 · FIRST AOS T−00:35:13` (first contact across targets,
white).
Steps are **not pages**: all regions are on one screen; the step bar reflects progress and scrolls
the left column to the matching panel.

## Layout
```
┌ left column (scrolls) ──────────────────────────────┐ ┌ C5 Sequence summary (aside 360, pane) ┐
│ C1 Targets · live query  │ C2 Command stack         │ │ tiles Targets · Cmds · Window          │
│ C3 GO / NO-GO poll                                  │ │ Release options                        │
│ C4 Delivery plan                                    │ │ Second GO from                         │
└─────────────────────────────────────────────────────┘ │ Log entry · [Request GO · arm 4]       │
                                                        └────────────────────────────────────────┘
```

## C1 · Targets · live query (R02)
Header meta link `EDIT`. Query chips (key/value ApChip, removable): `plane 07`, `profile Earendil
Block 1`, `state caution+`, `sc 312` …; `+ filter` add-chip offers plane, profile, state, point
condition (when the backend supports it), explicit spacecraft. Result line: `**4** of 50 in plane
07`, then `save as group "P07 power watch"` (later). Below, a compact 50-cell matrix row for the
query scope with matches highlighted (white fill) and the rest `cell-empty`; >1 plane = one row
per plane.
- Identity on every line (R01): the resolved list (expand `Show 4 targets`) lists name + SCID +
  profile. A target without a SCID is a NO-GO in C3, never a dash.
- Query stays live until release: if membership changes, C1 shows a caution callout "1 spacecraft
  left the query since you started: EARENDIL-318 is back in limits. Keep it?" with Keep / Drop.
- **Data:** `query → [{id, name, scid, profile: {id, name, version}, plane?, state}]` (v1: resolved
  client-side from the fleet list, per ops plan).

## C2 · Command stack (R03)
Header meta `CATALOG rev 14` (mono). Rows (mono): index `01`, mnemonic (600), argument chips
(`mode LOW`). Clicking a row opens its form inline: args generated from the catalog (type, enum →
`choice` segmented, numeric → ApNumberField with unit and range, required marked); invalid values
can't be added. `+ Add command` opens a catalog search (same index as ⌘K Commands; ↵ adds).
Reorder with drag handle + `Alt+↑/↓`. Hazardous/critical commands show the classification tag
(`HAZARDOUS` inverted).
- **Data:** catalog for the targets' revision `[{mnemonic, description, classification, args:
  [{name, type, unit?, enum?, min?, max?, required, default?}]}]`; per-target compatibility.

## C3 · GO / NO-GO poll (R04/R05)
Header meta `5 GO · 1 HOLD`. Poll rows `[lbl 150px] [evidence sentence] [GO|HOLD|NO-GO tag]`,
computed server-side (preflight), re-run on any change to C1/C2:
| Check | GO example | Note |
| --- | --- | --- |
| Identity | All 4 targets resolve `SCID 309 · 312 · 314 · 318` | missing SCID = NO-GO |
| Catalog | Both commands valid for each target, arguments in range | per-target revision mismatch = NO-GO with names |
| Conflicts | No competing uplinks queued | |
| Plan impact | "Coastal sweep 14" loses 3 imaging slots | only when plans exist |
| Umbra margin | — | **omitted** until propagation (DECISIONS #4) |
| Two-person | Power mode changes need a second operator's GO → `HOLD` | from policy (DECISIONS #7); GO when not required |
Any NO-GO blocks arming, and the C5 button says why. HOLD = proceed with the named requirement.
Checks the backend doesn't compute are left out, never shown as GO.

## C4 · Delivery plan
Header meta `EACH TARGET AT ITS OWN NEXT AOS`. One row per target: mark + name link + `SCID 312 ·
FBK` | lane (time axis NOW → +2h30) with the uplink block at its next scheduled contact (white)
| mono `T−35m · 12m spare` (spare = time to the next eclipse, **omitted** while there's no eclipse
data). Targets with no scheduled contact in the window: caution row "No contact in the next 6 h" +
`Find a pass` (→ Contacts filtered). Axis labels at the bottom.
- **Data:** per target `next_contact: {station, aos, los} | null` from the contact schedule (not
  prediction).

## C5 · Sequence summary (aside pane)
Tiles `Targets 4 · Cmds 2 · Window 2h05` (first AOS → last LOS). **Release** ApOptions: `At each
target's next AOS` ("Recommended.") / `Hold until a set time` ("Then the first AOS after it"; opens
ApTimePicker with mission presets). **Second GO from** select (people with `command.approve`, on
console first; `Any operator on shift`); hidden when policy doesn't require it. **Log entry**
textarea (required for contingency sequences, prefilled from the alarm: "Load shed after VBAT red on
312."). Primary commit button: `Request GO · arm 4 uplinks` (or `Arm 4 uplinks` when no second GO
is needed); secondary `Save draft`. Caption mono 11 `ABORT AVAILABLE UNTIL EACH UPLINK STARTS`
(shown only once abort exists; ops gap M20).

## After arming
Route to `M/commands/:requestId` (Uplink & verify view, phase 3): per-target state trail
(Queued → Radiating → Executed → Verified). In v1 that view shows the request's state per target
from the existing command history.

## States
Draft autosaves (`DRAFT · SAVED 02:44:31Z` mono in the takeover header; no number, U25). One current draft per user per mission, visible only to its author. Commands lists it for its author as `Your draft · saved 02:44Z · Resume`.

Draft edge cases (fe-ops c0510343, ruled by ux):
- **New request while a draft exists:** info callout "You have a draft saved 02:44Z. This request replaces
  it once you start filling it in." [Resume draft] [Discard draft]. Replacement starts at the first
  edit the user makes. Values prefilled from the origin (alarm, `?targets=`) don't count, so arriving
  from an alarm never overwrites a draft by itself.
- **Discard** (callout, or the ghost `Discard draft` in the header) asks first, using the existing confirm
  pattern: "Discard the draft saved 02:44Z? It can't be recovered." [Discard draft] (danger) [Cancel]. Then
  it deletes the draft and closes.
- **Saved from another tab (409):** autosave pauses. Header `DRAFT · AUTOSAVE PAUSED`. Caution callout:
  "This draft was saved from another tab at 02:51Z. Autosave is paused until you choose." [Load the 02:51Z
  version] [Keep mine]. Keep mine saves this tab's version over the other one, and its caption says so:
  "Replaces the 02:51Z save." Use the other save's time when the server gives it; otherwise "was saved
  from another tab" with no time.
- **Save failed:** header `DRAFT · NOT SAVED` (plus `· LAST SAVED 02:44Z` when an earlier save exists).
  Caution callout: "Couldn't save the draft. Changes since 02:44Z are only in this tab." Use the server's
  reason when it gives one (U20). [Try again]. Autosave still retries on the next change.
- **Close (×):** it always returns to the origin. Its aria-label and tooltip add the draft state:
  `Close and return to EARENDIL-312 · draft saved 02:44Z`, or `Close and return to EARENDIL-312` when
  nothing has been entered. With unsaved changes (a pending or failed save), close saves first. If that
  save fails, it asks "Close without saving? Changes since 02:44Z will be lost." [Close without saving]
  [Stay]. Before any save, use "Your changes will be lost."

Preflight running: poll rows
show `CHECKING…`. Target over the batch cap (until M16): NO-GO "Up to 25 targets per request
today" with the count. No permission (`command.request` missing): page renders read-only with "You
can view this sequence. Commanding needs the operator capability."

## Acceptance (for qa)
- Same screen for 1 and 400 targets; size never changes the layout (list collapses, matrix scales).
- No target line without name + SCID.
- Missing checks are absent, not green; any NO-GO disables arming with the reason.
- No page scroll at 1440×900; left column and C5 scroll independently.
