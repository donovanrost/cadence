# On call, from a phone (J6, phase 4)

Same routes as desktop; under **768px** the shell switches to the mobile layout. Board
`Mobile.dc.html` (390×844). Owner: fe-ops (lead owns the responsive shell). Scope: DECISIONS #6
(ack / hand-off), #7 (GO from the phone counts as a second GO), #4 (umbra omitted).

**Question:** "I got paged at 3 a.m. Is this real?" **Triage from anywhere: read, decide,
acknowledge or hand off.** Building new uplinks stays on the console, on purpose.

## Shell (< 768px)
- **Header** (56px, `chrome`): back button (`aria-label`), mono context line (`PAGED T+3m ·
  EARENDIL`) over the title (display 18px, `VBAT below limit`), UTC short on the right. No rail, no
  query bar, no mode switch.
- **Bottom tab bar** (58px, `chrome`, hairline top): `Now · Alarms 17 · GO polls 2 · Search`, icon
  18px + label display 11px; active = readout + inset top 2px white; counts in the label (alarm count
  in crit text). Safe-area padding at the bottom.
- Content is one column, 16px gutters, panels full width, gap 12. Page scrolls (the console
  hold-still rule is for desktop).
- Every primary action is ≥ 48px tall and full width (pairs split 50/50).
- **Setup** routes under 768px show a reading-only notice: "Setup is designed for a larger screen."
  with read-only content. Compose/Command routes show "New uplink sequences are desktop only, by
  design." with a link to the alarm.

## Alarm page (the paged view, `M/fleet/:id/investigate?alarm=…`)
1. **Alarm panel** (alert-crit): spacecraft name (display 22px) + `◆ CRITICAL`; two readouts
   (VBAT `23.1 V` crit, Red limit `24.0 V`); mono line `−0.4 V/ORB · 3 SISTERS IN P07 TRENDING`;
   a 6-orbit sparkline of the point vs the limit (full width, 80px, `role="img"` with the finding
   sentence).
2. **Timing panel:** `Next AOS · Fairbanks T−00:36:02` (readout 28px, white) and, when propagation
   exists, `Umbra T−00:57` (omitted now, DECISIONS #4).
3. **Your GO is requested** (only when a request awaits *your* GO): request name + scope (`Low
   power safe · 4 SC`), author + poll summary (`5 GO, 1 HOLD (yours)`), release plan sentence, the
   command stack in mono, then `GO` (primary) / `NO-GO` (secondary) 48px. GO opens a confirm sheet
   restating targets + commands, with re-auth if required.
4. **Actions:** `Acknowledge` / `Hand off` (sheet: on-shift people with `command.approve` first, a
   required note). Hidden until the alarm lifecycle ships.
5. Footer caption mono 11 `NEW UPLINK SEQUENCES ARE DESKTOP ONLY, BY DESIGN`.

## Other tabs
- **Now:** h1 (same rule as desktop), the stat strip as a 2×3 grid, then the action queue list.
  No constellation, matrix or passes.
- **Alarms:** list of active alarms (mark, spacecraft, point, now vs limit, age), tap → alarm page.
- **GO polls:** requests awaiting your GO, tap → mobile Approve: header, What changes (A1),
  Re-checked (A2), decision options, `Sign GO`.
- **Search:** the ⌘K query as a full-screen sheet; results limited to spacecraft, alarms, requests.

## Acceptance (for qa)
- At 390×844 nothing scrolls horizontally; targets ≥ 48px; the tab bar clears the home indicator.
- From a page link the alarm, its trend and the next AOS are visible without scrolling.
- No way to compose a new sequence on a phone; GO / NO-GO / ack / hand-off all work.
