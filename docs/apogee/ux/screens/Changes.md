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
  - *Applying*: **dropped** (fe-setup): the commit is one synchronous request on the review page, so the bar
    has no step source. The review page's primary shows `Applying…` while the request runs.
  - *In review* (the set is frozen while in review, change-sets §13.1): `r6 in review · staging is
    paused` + `Open review`; stage CTAs elsewhere are disabled with that reason.
  - *Apply failed before commit*: shown on the review page (below), not on the bar.
  - *Applied, runtime converging / degraded* (after commit, §7): bar is gone (the set is applied);
    the top bar shows `CONFIG r6 · APPLYING` (readout) while the runtime applies it, or `CONFIG r6 · NOT
    APPLIED` (caution) when it hasn't, with the U38 sentence as its tooltip. Both link to r6. "Converging" and
    "degraded" are our words, not the operator's. Never "nothing changed" after commit.
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
  - **Re-check after the change set moves** (another user stages or removes; setup audit B4, ux 11-16). The old
    verdict is never shown as current.
    - The previous rows stay, under a `text-3` sub-label "From the previous check (12 changes)". Their marks and tags
      are dimmed, and the text stays at full contrast (U27). The panel's verdict line gives way to a status line
      (`role="status"`): "Checking again: the change set now has 14 changes."
    - Apply is disabled with the reason "Checks are re-running for the new changes."
    - When the new result arrives, it replaces the rows and the status line announces it: "Checks done: 1 NO-GO,
      2 holds." or "Checks done: all GO." The holds checkbox clears only if the holds changed.
    - Focus: a focused control that still exists keeps focus; otherwise focus goes to K2's heading, never `<body>`.
    - If the re-check fails, the old rows stay dimmed, with crit "The checks couldn't run for the new changes." +
      `Try again`. Apply says "Checks haven't run for the current changes."
    - The first load, with no previous check, still reads `Running checks…`.
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
  `degraded`. Wording keeps the two steps apart: the configuration becomes **active**, then the
  runtime **applies** it (U38's verbs).
  - Right after commit: "r6 is active · 2 changes. The runtime is applying it."
  - Then nominal "r6 is active and the runtime has applied it · 2 changes." + `View r6`.
  - Or caution "r6 is active, but the runtime hasn't applied it yet: <U38 reason words>." + `View r6`.
  - The spacecraft count appears only if the read gives it (fe-setup 11-14). **Never say "nothing changed" after
  commit** (change-sets §7).
- **Empty:** "Nothing staged. Edits in Setup collect here before they reach the fleet."
  - **An empty set never stays open** (qa's probe 11-16; lead's server fix): withdrawing the last change closes the
    set as `discarded`, the same terminal state as Discard. The console just shows this empty state. There's no
    `Close` button and no words about why it closed, since discarded sets aren't listed anywhere.
- **Discard all / Discard mine always confirm** (qa's probe 11-16: it discarded at once). This is an ApInlineConfirm
  under the K1 header, danger action, focus on `Cancel` (§7). It counts only the changes you may discard.
  - All yours: "Discard your 3 staged changes? They can't be brought back." `Cancel` · `Discard 3 changes`.
  - Including other people's (`Discard all`): "Discard all 3 staged changes? 2 of them are other people's: Mira K.,
    Tomás R. They can't be brought back." Past two names: "Mira K., Tomás R. and 2 others".
  - With one other author: "Discard all 3 staged changes? 2 of them are Mira K.'s. They can't be brought back."
  - `Discard mine` when others' changes stay: one other author, "Discard your 2 staged changes? Mira K.'s 1 change
    stays staged."; more than one, "…? 3 changes by other people stay staged." (no list).
  - **Authors without a name** (a service or system actor) are counted, never called "someone": "Mira K. and 1
    other". With no named author: "2 of them are other people's." Several unnamed authors count separately.
  - The action states the count: `Discard 1 change` or `Discard 3 changes`. The trigger is `Discard all…` /
    `Discard mine…`: the `…` marks that it asks first.
  - K1's header is the only discard. The console has no status-bar Discard, and none is wanted.

## 4. Revisions (`M/setup/revisions`, reading layout)
- **List** (ApTable): Revision (mono link `r6`) · Applied (abs time) · By · Why (sentence,
  truncates with title) · Changes (`2 · 50 spacecraft, catalog`) · Kind tag (`Rollback of r5` when
  applicable). Current revision row has a white left inset bar + `LIVE` tag (readout outline).
  Select two (checkbox column) → `Compare r4 ↔ r6`.
- **Revision detail** `M/setup/revisions/6` (the route takes the bare number; the visible text stays `r6`): header `r6 · applied 2026-11-08 14:52Z by Donovan R.`
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
