# Staged changes, apply, revisions (mission change sets)

Scope decision: `docs/apogee/DECISIONS.md` #1 (build change sets; v1 ships on per-entity versions
behind a seam; no fake `rN`). Model: **domain** (`docs/apogee/domain/change-sets.md`, approved: DECISIONS #13–16). Endpoints:
**api**. UI: **fe-setup**. The six model questions at the end are answered in change-sets.md §13.
Boards: `Setup.dc.html` (staged bar, R2 revisions), `Profile.dc.html` (P4 staged edit, edited
fields), `AddSpacecraft.dc.html` / `Catalog.dc.html` (stage CTAs), `SetupJourneys` ("stage, diff,
apply · one revision number").

## Mental model (what the user should believe)
1. The fleet runs **one live configuration**, numbered: `r5`.
2. Setup edits never touch the live configuration. They **stage** into the mission's one open
   change set, which everyone in Setup can see, and each change is signed by its author.
3. **Apply** turns the whole change set into `r6`, atomically, with a required *why*.
4. History is append-only. **Rolling back** to r4 stages a change set that reverses r5 and r6, and
   applying it makes `r7`. Nobody rewrites a revision.

## 1. Where changes are staged (stage points)
Every editing surface in Setup ends in a **Stage** action instead of Save. After staging, the
staged bar appears or updates, with a one-time 2s `raised` wash on the bar. No toast.

| Surface | Stage CTA | Staged change summary (bar + list) |
| --- | --- | --- |
| Profile field edit (P1) + P4 aside | `Stage edit` | `Block 1 · framing.tm_frame_length 1,115 → 1,279 · 499 SC` |
| Profile routing rule (P2) | `Stage rule change` | `Block 1 · routing adds INU · +500 routes` |
| Override reset (P3 `Reset`) | `Stage reset` | `EARENDIL-047 · reset VBAT red limit to profile` |
| Add spacecraft (S2) | `Stage 50 spacecraft` | `50 new spacecraft (Block 2)` |
| Catalog rollout (S3 C3) | `Stage rev 15 for Block 2` | `Catalog rev 15 → Block 2 · 50 SC` |
| Station, transport, data source, app setting edits | `Stage change` | `Svalbard · antenna 2 disabled` |
Fields with a staged edit render the Profile board's edited state everywhere they appear: inset
3px white left bar, `raised` bg, label suffix `· staged`, old value struck in mono `text-4`, new
value in the input. Panel meta counts them: `INHERITED BY 500 · 1 EDIT STAGED`.

**P4 Staged edit aside** (shown while a field is dirty and not yet staged): field path (mono),
`− old` (crit-text) / `+ new` (nominal-text) lines, tiles `Changes 499 SC` / `Keeps 1 SC`, checks
as callouts (caution "1,279-byte frames need flight software 3.2. **0 of 499** run it today…"),
the keeps explanation ("EARENDIL-389 keeps its pinned 1,115 override"), primary `Stage edit`,
secondary `Discard`. Effect counts come from the server (dry-run), not computed in the browser.

## 2. Staged bar (every Setup page, ApStagedBar)
Sticky bottom, `raised`, top border `line`, `12px 24px`. Hidden when the change set is empty.
```
STAGED · NOT APPLIED   2 changes: 50 new spacecraft (Block 2), catalog rev 15 → Block 2   by you, Mira K.   [Discard all] [Review & apply as r6]
```
- Left mono 12 `text-3`: `STAGED · NOT APPLIED`.
- Summary 14px: `<b>N changes:</b>` + first two summaries, then `+ N more`. Authors (`by you, Mira
  K.`) in `text-3` when anyone besides you has staged.
- Right: `Discard all` (secondary, opens a confirm listing what will be dropped; only the changes
  you may discard) and primary `Review & apply as r6` → `M/setup/changes`.
- **States:**
  - *Conflict* (live config moved since a change was staged): caution mark + `1 change conflicts with
    r6`; primary becomes `Review conflicts`.
  - *Applying*: summary replaced by mono `APPLYING r6 · 3 OF 5 STEPS` (live); buttons hidden.
  - *In review* (the set is frozen while in review, change-sets §13.1): `r6 in review · staging is
    paused` + `Open review`; stage CTAs elsewhere are disabled with that reason.
  - *Apply failed before commit*: crit mark + `Apply failed · nothing changed`; primary `Review`.
  - *Applied, runtime converging / degraded* (after commit, §7): bar is gone (the set is applied);
    the top bar shows `CONFIG r6 · CONVERGING` (white) or `CONFIG r6 · RUNTIME DEGRADED` (caution,
    links to the revision). Never "nothing changed" after commit.
  - *Awaiting review* (policy, §3): `r6 awaits review by an org admin · requested 14:02Z`; primary
    `Open review`.
  - *No apply capability*: primary reads `Review changes`; the review page explains who can apply.
- Top bar Setup clock cluster: `CONFIG r5` becomes `CONFIG r5 · 2 STAGED` (link to the review).
  In Ops, nothing about staging shows (it isn't live), except a Now P3 item when a change set has
  been sitting for more than 24 h.

## 3. Review & apply (`M/setup/changes`, reading layout)
```
lbl "EARENDIL · STAGED CHANGES"
h1 "Apply r6 · 2 changes"                                  base r5 · staged 14:02Z–14:40Z
┌ K1 Changes (flex 999) ─────────────────────────────┐ ┌ K3 Apply (aside, sticky) ───────┐
│ ▸ 50 new spacecraft (Block 2)       Donovan R. [×] │ │ tiles: Changes 2 · SC 549 · Routes +300
│   diff: table of the 50 + routes                   │ │ Readiness after: 0 blockers (=) │
│ ▸ Catalog rev 15 → Block 2 · 50 SC  Mira K.    [×] │ │ Why (required textarea)         │
├ K2 Checks (GO / NO-GO poll) ───────────────────────┤ │ [Apply as r6]  (commit, 46px)   │
│ Conflicts · Readiness · In flight · Compatibility  │ │ [Request review] (policy)       │
└────────────────────────────────────────────────────┘ └─────────────────────────────────┘
```
- **K1 Changes:** one row per change, collapsed by default: summary, author, staged time (mono),
  `Withdraw` `×` (`aria-label="Withdraw from r6"`; the model's `withdraw`: the change returns to its
  surface as unstaged edits for its author). Conflicting rows offer `Keep mine` / `Take live`. Expanded = the change's **diff**: field changes as `path  − old  + new` mono
  rows; entity additions as an ApTable (first 8 + `Show all`); per-spacecraft effect `changes 499 ·
  keeps 1 (EARENDIL-389 override)`. A link opens the surface where it was made.
- **K2 Checks** (same `poll` rows as commanding, server-computed, each GO / HOLD / NO-GO with
  evidence):
  - *Conflicts*: every change still applies cleanly on the live revision ("r6 was applied after
    this was staged; framing.tm_frame_length changed in both" → NO-GO, `Rebase` / `Remove`).
  - *Readiness*: blockers after apply vs now (`0 → 0`); new blockers = NO-GO.
  - *In flight*: queued uplinks, active contacts, running plans touched by the change ("40 queued
    uplinks use SET_ADCS_MODE args changed in rev 15" → HOLD with link).
  - *Compatibility*: flight software / catalog requirements ("needs FSW 3.2 on 0 of 499") → HOLD.
  Any NO-GO disables Apply with the reason. HOLD allows Apply after an explicit checkbox
  "I've read the 2 holds" **[decision]**.
- **K3 Apply aside:** tiles (changes, resulting fleet size, routes delta); readiness delta line;
  **Why** textarea (required, 10+ chars; goes in the audit and the revision list); primary `Apply as
  r6`. If mission policy requires review (DECISIONS #7 pattern, policy-driven): primary becomes
  `Request review`, and a reviewer (distinct from **every** author in the set, change-sets §7;
  capability-gated) sees `Approve & apply as r6` /
  `Send back` with a required comment. Caption mono 11: `ATOMIC · ALL OR NOTHING · r5 KEPT FOR
  ROLLBACK`.
- **Applying:** the page becomes a live step list in two parts.
  *Commit* (all-or-nothing): freeze & check → compose → request approval (if policy) → write
  revision. A failure here = crit callout "Nothing changed. <step> failed: …", and the set returns
  to open. *Runtime* (after commit, from the `config_runtime` signal): `converging` → `applied` or
  `degraded`. Success = nominal callout "r6 applied · 2 changes · 549 spacecraft · runtime applied"
  + `View r6`. Degraded = caution callout "r6 is applied. The runtime hasn't converged on 2
  partitions." + link to the revision's runtime detail. **Never say "nothing changed" after
  commit** (change-sets §7).
- **Empty:** "Nothing staged. Edits in Setup collect here before they reach the fleet."

## 4. Revisions (`M/setup/revisions`, reading layout)
- **List** (ApTable): Revision (mono link `r6`) · Applied (abs time) · By · Why (sentence,
  truncates with title) · Changes (`2 · 50 spacecraft, catalog`) · Kind tag (`Rollback of r5` when
  applicable). Current revision row has a white left inset bar + `LIVE` tag (readout outline).
  Select two (checkbox column) → `Compare r4 ↔ r6`.
- **Revision detail** `M/setup/revisions/r6`: header `r6 · applied 2026-11-08 14:52Z by Donovan R.`
  + why as a `text-3` sentence; its changes (same diff rows as K1, read-only); approver if reviewed;
  `Roll back to r5` (secondary, danger tone only in its confirm) → stages a reverting change set and
  opens the review page with the summary `Roll back r6 (2 changes)`. Disabled with reason when the
  change set already has staged changes ("Apply or discard the 2 staged changes first").
- **Compare** `M/setup/revisions/r4...r6`: combined diff grouped by entity.
- Readiness R2 (Setup board) shows the last 4 revisions in its `ev` row style, plus `Compare
  revisions` and `AUDIT LOG →`.
- Ops surfaces: Timeline event `Config r6 applied · 2 changes · Donovan R.` (neutral mark);
  spacecraft Configuration tab shows `config r6` with "changed in r6" markers on fields.

## 5. Permissions (capabilities from session bootstrap, DECISIONS #2)
`config.stage` (edit + stage), `config.apply`, `config.review`, `config.rollback`. Without
`config.stage`, Setup forms render read-only with a `text-3` line "You can view configuration.
Ask an org admin to make changes." Never hide the data, only the controls.

## 6. v1 seam (until change sets land)
Per DECISIONS #1 and U2: no staged bar, no `CONFIG rN`, no `/changes` or `/revisions` routes. Stage
CTAs read as their direct v1 equivalents (`Create 50 spacecraft`, `Request activation for 50
spacecraft`, `Create profile version v5`). Build the stage points as one component contract
(`stage(change) → result`) so v1 binds it to the direct calls and v2 to the change set without
touching the screens.

## Questions for domain (model must answer these for the UX to hold)
1. One open change set per mission, shared by all authors? (UX assumes yes.)
2. Can a single change be removed from the set and returned to its author as a draft?
3. Conflict detection: does each change record the base revision + field paths, so the server can
   flag overlaps with later revisions and offer rebase?
4. Effect dry-run: can the server compute "changes N · keeps M" and readiness-after for a staged set?
5. When does an applied revision reach a spacecraft in contact or with queued uplinks? (Drives the
   "In flight" check wording.)
6. Rollback = new revision reversing earlier ones (UX assumes yes; never history rewrite).
