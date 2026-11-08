# UX decisions log

Owner: **ux**. Answers to design questions from the team. Newest at the bottom. Each entry: question
→ decision → why. These override the canvas where they conflict; design-language.md and
information-architecture.md are updated to match.

## 2026-11-08

### U1 · URL scheme (fe-setup plan)
**Decision:** `O = /console/:orgId`, `M = O/:missionId`. Org pages are `O/org/<page>`. Account and
notifications are not org-scoped: `/console/account`, `/console/notifications`.
**Why:** a deep link must survive an org switch in a multi-tenant app. Lead owns the router; if the
scaffold differs, lead's scheme wins and ux updates the IA.

### U2 · Setup without a mission-wide revision (fe-setup Q1, option B)
**Decision:** while there is no mission change set, **drop `CONFIG rN` from the top bar** (Setup
clock cluster = `UTC` only) and **hide the staged-changes bar**. Each entity shows its own version
in its page header (`EARENDIL BLOCK 1 · v4`, `Catalog revision 14`, spacecraft config `active v3 ·
draft pending review`). Readiness R2 becomes **Recent changes** (who, when, what, from a unified
event feed) if api can provide one; otherwise R2 is omitted.
**Why:** truth before calm. A fake `rN` would lie about atomic applies.
**Update (DECISIONS #1):** change sets will be built. This entry is the v1 behavior behind the seam;
the target design is `screens/Changes.md`.

### U3 · Finding severities (fe-setup Q2)
**Decision:** blockers get their own shape. Order and grammar:
| Severity | Mark | Word | Meaning |
| --- | --- | --- | --- |
| blocker | crit diamond | `Blocker` | stops commanding or contacts |
| caution | triangle | `Caution` | degraded, act soon |
| stale | hatched square | `Stale` | a source or station is late |
| not set up | dashed square | `Not set up` | install / configure to enable |
| optional | 10×2 gray dash | `Optional ·` prefix in the title | a suggestion, never a warning |
The verdict headline counts blockers only ("Ready for operations · 0 blockers" / "2 blockers").

### U4 · Providers and transports in the Setup rail (fe-setup Q3)
**Decision:** **Transports** = a tab in 05 Comms & routing (`Routing rules · Transports`).
**Ground-network providers** (mission) = a tab in 06 Ground stations (`Stations · Providers`),
because providers supply the stations, antennas and pass opportunities. **Provider accounts**
(org credentials) = Organization group.

### U5 · Takeover vs in-shell (fe-setup Q4)
**Decision:** a **multi-step creation wizard with a step bar** is a full-page takeover without the
rail: Add spacecraft, New mission, and the catalog **upload** if it grows beyond one step. The
takeover header has `×` close (returns to where you came from, keeps the draft) plus the step bar.
**Catalog import review (the diff) stays in-shell**, as on the board, since it's a reading view
inside the Catalog section and links into the rest of Setup.

### U6 · Spacecraft detail in Setup (fe-setup Q5)
**Decision:** yes, reuse the Profile layout: entity title + readiness tag, then local section nav
with panels `Identity · Profile & version · Configuration (active vs draft, review) · Routing ·
Overrides`. Header link `Open in Ops →` goes to `M/fleet/:scId`. Ops › spacecraft › Configuration
tab is read-only and links back here to edit.

### U7 · MET (fe-ops Q-ux-1)
**Decision:** **omit MET** wherever there is no mission epoch: top bar, time picker summary, time
picker zone switch (UTC│LOCAL only). Never derive it from mission creation time. Backlog for api:
optional `mission.epoch_at` (launch or ops start); when set, MET appears.

### U8 · Fleet matrix shape (fe-ops Q-ux-2)
**Decision:** rows = planes **when plane metadata exists**. Columns = the largest slot count across
planes (20 × 25 in the demo is fine; header meta `ROW = PLANE · 25 SLOTS`). A cell is placed by
slot when known, else by ordinal; unused slots draw as `cell-empty`. Spacecraft without a plane go
in a final row group labelled `—` (meta `NO PLANE`). A fleet with **no** plane metadata is a flat
grid ordered by SCID, wrapping at 50 per row, row labels are SCID ranges in mono (`001–050`), meta
`ORDERED BY SCID`. Minimum cell 8px; below that the matrix scrolls inside its panel. Never-heard
spacecraft use the dashed `off` cell, not stale.

### U9 · Stale threshold (fe-ops Q-ux-3)
**Decision:** product default **15 min without fresh TLM**, overridable later per profile (expected
telemetry cadence). **The server decides staleness** and returns the threshold it used
(`stale_after_s`); the client never hardcodes 15. The Stale tile caption states the rule it used
("no TLM over 15 min"). A spacecraft never heard since creation is `off` ("Awaiting first AOS"),
not stale.

### U10 · Panels whose data doesn't exist yet (fe-ops Q-ux-4)
**Decision:**
- **Structural console regions** (A1 Constellation, A4 Passes, B1 trend chart) **stay in the
  layout** with ApEmptyState: `off` mark, a fact headline and the reason ("Orbit data not available ·
  the constellation needs orbital elements per spacecraft"). The console holds still; nothing
  reflows when the data arrives.
- **Panels or controls that recommend or act** (B3 Recommended procedure, Acknowledge, Assign)
  are **hidden** until real. Never show an empty recommendation or a dead button.
- **Single facts** in a fact strip (Next eclipse, Last LOS): omit the fact. Don't show a row of
  dashes.
- **Fleet summary tiles** (Stale, In contact): keep the tile, value `—`, caption "not tracked yet".
- Overlays that need missing data (umbra bands on a plot) are simply not drawn, and the legend
  leaves them out.

### U11 · Action-queue ranking (fe-ops Q-ux-5)
**Decision:**
- **P1 · act now:** critical alarm; a critical flight event (safe mode); a verify failure; a missed
  pass when the spacecraft's next contact is beyond its allowed gap (or unknown).
- **P2 · needs you soon:** caution alarm; a GO / approval waiting on **you** (not on anyone);
  no-ACK retries; stale groups; a degraded station with upcoming passes.
- **P3 · when you can:** not set up (missing app or source); setup suggestions.
- Within a priority: soonest time-to-consequence first (next AOS, umbra entry, release time), then
  oldest first. Group identical causes into one row ("4 in plane 2 stale", likely cause in the
  secondary line). Priority label mono 11 in the underlying state's text tint, next to that state's
  mark. Only the top P1 row's action is primary. The queue scrolls; nothing is truncated without a
  count.
