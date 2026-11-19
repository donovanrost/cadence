# Setup · Readiness (S1 · is the mission ready?)

Route `M/setup` · Setup rail 01 · **reading layout** (page scrolls) · Board `Setup.dc.html`.
Owner: fe-setup. Data and gaps: `docs/apogee/plans/setup.md` §S1 (proposed
`GET …/readiness`). Rulings: decisions U2 (no global revision), U3 (severities).

**Question:** "Is the mission ready, and if not, what one change fixes the most?"
**Journey:** after any change, or before a campaign: read the verdict → scan the six areas → work
blockers, then suggestions, each linking to the profile / rule / station / source / app that fixes
all of them at once.

## Layout
```
lbl "EARENDIL · MISSION READINESS"
h1 verdict  [■ 0 BLOCKERS]                                 [Add spacecraft] [Import catalog]
subline: "3 suggestions, 1 caution · <last change line>"
area tiles ×6 (auto-fit, min 260px, 1px hairline grid)
┌ R1 Findings (flex 999 1 560) ──────────────┐ ┌ R2 Recent changes (flex 1 1 340) ┐
└────────────────────────────────────────────┘ └──────────────────────────────────┘
[staged-changes bar: only with a mission change set, U2]
```
Main `padding 20px 24px 24px`, gap 16. Max width ~1400px.

## Header
- h1 (setup page title 36px): `Ready for operations` when blockers = 0, else `N blockers`
  (`1 blocker`). Tag beside it: `■ 0 BLOCKERS` nominal, or `◆ N BLOCKERS` crit.
- Subline 14px `text-3`: counts of the other severities (`3 suggestions, 1 caution`), omitted parts
  when zero, then ` · ` + the latest change (`profile Block 1 v4 applied 2026-10-19 02:29Z by
  Donovan R.`) if the recent-changes feed exists.
- Actions (standard secondary buttons): `Add spacecraft` → `M/setup/spacecraft/new`,
  `Import catalog` → `M/setup/catalog/import`. Hidden for users without setup permission.

## Area tiles (6, fixed order)
Each tile: area name (display 17px) + status tag (22px) on one line; big number (sans 28px tabular)
+ unit (14px `text-4`); one-line detail (13px `text-3`). Non-ready tiles get the state's top inset
bar. Whole tile is **not** a link; the area name is (→ that Setup section).

| Area | Number · unit | Detail examples | Status |
| --- | --- | --- | --- |
| Fleet | `500` spacecraft | `2 profiles · every spacecraft has a SCID, a profile and a route` / `12 without a route` | Ready / Blocker |
| Catalog | `rev 14` · `547 declarations` | `revision 15 imported, not applied to any spacecraft` · `500 spacecraft use rev 14` (per U-plan: spacecraft, not profiles) | Ready / Caution |
| Comms & routing | `N` routing rules | `M spacecraft without a route` | Ready / Blocker |
| Ground stations | `6` stations (`· 9 antennas` when known) | `Svalbard downlink degraded since 01:52Z`; health unknown → `health not reported` | Ready / Caution / unknown |
| Data sources | `4` sources | `Flight events last received 47m ago, expected every 5m` | Ready / Stale |
| Apps | `5 of 6` installed | `Limits & Alarming is not installed, so ground limit checks are off` | Ready / Not set up |

Status word in the tag is the area's worst finding severity (`Ready` is nominal). If an area's
health can't be computed, the tag is `—  Unknown` in `text-3` with an `off` mark and the detail says
why; never `Ready` by default.
- **Data:** `areas: [{key, status, count, unit, secondary_count?, secondary_unit?, detail}]`.

## R1 · Findings (panel)
Header meta: `GROUPED BY CAUSE · 3,006 ITEMS → 4 LINES` (sum of affected → number of lines).
- First line is a **callout**: blockers = 0 → nominal "No blockers. Nothing stops commanding or
  contacts."; blockers > 0 → crit "N blockers stop commanding or contacts." Then rows in severity order
  (U3): blocker, caution, stale, not set up, optional.
- Row: `[mark 14px] [title 15/600 + body 13 text-3] [one action]`. Optional rows: title prefixed
  `Optional ·`, title in `text-2`, gray dash mark. Affected count lives in the title or body ("4
  spacecraft in plane 02…", "3,000 routes use…"), never as a per-spacecraft list.
- Action (compact secondary): verb + object from `fix.kind`: `Open station`, `Open source`,
  `Install` (for `not set up` apps), `Edit rule`, `Open profile`. (The canvas's "3,000 routes use
default protocol behavior" finding is dropped: protocol behavior is a retired concept.) No `fix` → no button (don't invent one).
- **Data:** `findings: [{id, severity, cause, title, body, affected_count, fix: {kind, id, label?} |
  null}]`. Grouping by cause is **server-side**.
- **Empty (no findings at all):** just the nominal callout, plus "No suggestions either."

## R2 · Recent changes (panel) **[U2]**
Replaces the canvas's "Revisions" while there's no mission revision. Row grid `44px | 132px | 1fr`:
version or kind chip (mono 12: `v4`, `rev 15`, `app`), time (mono 11 `text-4`, `10-19 02:29Z`),
sentence + actor (`Block 1 framing: CCSDS TM to 1,115 bytes · Donovan R.`). 5 rows, then
`AUDIT LOG →` in the header meta (→ `O/org/audit`). **If api can't unify an event feed, omit R2**
and let R1 take the full width.
- **Data:** `[{at, kind, version_label?, summary, actor: {name}, link?}]`.

## States
Loading: header shows the lbl + `LOADING…`; tiles show names with `—`. Error: crit callout in
place of tiles + `Retry`. Empty mission (no spacecraft, no catalog): h1 `Not ready · 2 blockers`
with findings "No spacecraft" (`Add spacecraft`) and "No catalog" (`Import catalog`). That is the
honest empty state; there is no separate onboarding checklist (review #7).

## Acceptance (for qa)
- Verdict and tile states derive only from findings; no tile is `Ready` without data.
- 1,000 identical findings render as one line with a count.
- Every finding with a fix has exactly one action linking to the fixing object.
- No `CONFIG rN` and no staged bar unless a mission change set exists.
