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
- **Search** (lead builds; BACKLOG §5): a full-screen sheet over the current tab.
  - **Entry:** the `Search` tab in the bottom bar. It opens with the input focused and the keyboard up. There's no
    ⌘K or prefix legend on a phone. Close with `Cancel` (text button right of the input, ≥ 48px) or back; it
    returns to the tab you came from.
  - **Empty query:** `Recent` (the last 5 opened from this sheet, phone kinds only). With nothing recent, the hint
    "Search spacecraft by name or number, alarms by point, requests by title." Then nothing else, no page list.
  - **Groups, in order:** `Alarms` (active only; matches the spacecraft name or the point) → `Requests` (awaiting
    your GO first, then other open ones; matches the title, mnemonic or request id) → `Spacecraft` (name or
    SCID). Alarms lead because a paged person is looking for the alarm. Typing a spacecraft name shows its alarms
    first.
  - **Rows:** ≥ 56px, with a status mark, a title and one subtitle line.
    - Alarm: `EARENDIL-312 · VBAT below limit` / `23.1 V · red 24.0 V · T+3m`.
    - Request: `Low power safe · 4 SC` / `Your GO · Mira K. · T+12m`, or its state.
    - Spacecraft: `EARENDIL-312` / `SCID 312 · P07 · stale 2h`.
  - At most 5 per group, then `Show all 23` expands in place.
  - **A row opens:**
    - an alarm → the alarm page (`M/fleet/:id/investigate?alarm=…`);
    - a request awaiting your GO → mobile Approve (`…/review`); any other request → its status (Uplink,
      read-only);
    - a spacecraft → its Investigate page.
    - There's no "command it" action on a phone.
  - **States:** `Searching…` keeps the last results (no flicker). No match: `Nothing matches "xyz".` A group whose
    read failed shows one row "Alarms couldn't load." with `Try again`; the other groups still show.

## Acceptance (for qa)
- At 390×844 nothing scrolls horizontally; targets ≥ 48px; the tab bar clears the home indicator.
- From a page link the alarm, its trend and the next AOS are visible without scrolling.
- No way to compose a new sequence on a phone; GO / NO-GO / ack / hand-off all work.
