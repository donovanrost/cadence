# Review: Investigate tabs (Telemetry, Uplink, Passes, Configuration, History), live after the restart

As qa-org-admin on EARENDIL-001 (stale, next AOS T−2d), 1440×900 plus 390 for Uplink and Passes. Writes
were blocked. Load was under 16.

## Verified
- All five tabs render in the console layout with no page scroll, and there's no horizontal scroll at 390.
- **Uplink:**
  - U1 reads `NEXT COMMANDABLE PASS · SVA 11-14 00:33Z · T−2D…`, and the route sits in the header meta.
  - Every panel has its empty sentence.
- **Telemetry:**
  - T1 has search, chips (`Out of limits 0 · Stale 146 · All`) and a key under each label.
  - T2 shows two stacked small multiples on a shared axis, with the `mean with min-max band · dashed: limits` legend.
  - T3 is labelled `PER PLOT BUCKET`.
- **Configuration:** G1 shows `not set` for the NORAD id, and G2 reads "Uses its profile as is.".
- **History:** the empty state is neutral, and the Timeline link is there.

## Fixes (fe-ops), ranked
| # | Impact | Tab | Issue → fix |
| --- | --- | --- | --- |
| 1 | High | Passes | **P3 fails to decode:** "The server sent data this console does not understand (data.passes[0].source.synthetic: expected boolean)". P2's Gantt is also empty. → Accept `null` for `synthetic` (meaning unknown, not false), or have api-ops send a boolean. Then check that P2 draws. |
| 2 | Med | Passes | **P1 contradicts the header:** `NEXT CONTACT None booked`, while the header says `NEXT AOS T−2d 06:24` and Uplink shows SVA 11-14 00:33Z. The next contact isn't limited to the 24 h window, so show `AOS T−2d 06:24:32 SVA`. |
| 3 | Med | Passes | **`LONGEST GAP 24h 0m from 18:09Z`** with no pass in the window is the window length, not a gap. → When there's no pass in the next 24 h, show "No pass in the next 24 h" (caution) instead of a gap. |
| 4 | Med | Passes | **P4 shows two rows for the same pass** (`SVA · 18:57Z–19:05Z` as MISSED and as PARTIAL). If they're two bookings (e.g. a repair re-book), say which ("re-booked by repair"); if it's a duplicate in the read, collapse it. The trailing `· —` is unclear: label it (`received —`), or leave it out when unknown. |
| 5 | Low | Telemetry | "No samples for this point in the last **6H**" → "in the last 6 h" (units keep their case). Draw no 0–1 y-axis ticks when there's no data (they suggest values). T1 rows are missing the age the spec asks for: show `T+1d 11:59` or "No value yet". |
| 6 | Low | Configuration | Slot reads `P01 · slot 1` in G1 but `slot 01` in the header, so use one format. G3 rows repeat the role (`SCL · candidate · Santiago (Demo) — candidate`) and have an empty left gutter. → `SCL · Santiago (Demo) · candidate`, with the gutter removed if it's an empty mark column. |

Not checked (no data on :4011): Telemetry with live samples (pass bands, crosshair), the U33 readiness states,
queued and released rows, History episodes, and G4 pending.

## Status
- fe-ops 2145617b: #1–#6 accepted per commit (P3 and P2 load, next contact beyond 24 h, no fake gap, re-booked label, Telemetry wording and empty axis, slot format, G3 rows). Seen live at 21:32Z (below), before the CI-only browser rule.

## Live recheck (21:32Z, EARENDIL-001, 1440×900 and 390, writes blocked)
#1–#6 hold: all five tabs load, next contact reads `AOS T−2d 03:01:40 SVA`, the gap says "No pass in the next
24 h", the second booking says `re-booked`, Telemetry shows "No samples between …", slot reads `P01 · slot 01`,
G3 names each role once. No horizontal scroll at 390. New findings (fe-ops), ranked:

| # | Impact | Issue → fix |
| --- | --- | --- |
| 7 | Med | **P4: a rejected booking reads MISSED in crit** although the same window (SVA 18:57Z–19:05Z) was re-booked and flown. Crit there claims lost contact that didn't happen (U20). → When a later booking of the same window flew, the rejected row is `off` with the word `REJECTED`, not crit `MISSED`. Keep crit `MISSED` only when no booking of that window flew. |
| 8 | Low | **P4: "Provider rejected (provider)"** names the party twice. → Drop the attribution suffix when the reason already names it: `Not flown · Provider rejected`. |
| 9 | Low | **P1 Longest gap stacks "No pass in the next 24 h" over "No pass in the next 6 h".** The second line adds nothing. → Show the 6 h line only when a pass exists inside 24 h but none inside 6 h. |
| 10 | Low | **T1: every point says "No value yet"** while the header says LAST TLM T+1d 15:22. "Yet" claims it never had one. → Show the last known value with the stale hatch and its age if the read has it; if not, `No recent value`. |
| 11 | Low | **Telemetry empty plot says "between 11-11 15:31Z and 11-11 21:31Z"** on today's date. → §4 short time: `between 15:31Z and 21:31Z`; the date only when it isn't today. |
| 12 | Low | **U2 "No other commandable pass is booked in the next 24 h"** when U1's pass is T−2d away, so "other" implies one inside 24 h. → Drop "other" when U1's pass is beyond 24 h. |
| 13 | Low | **P2 row label truncates to `EARENDIL-0…`.** → Widen the label column to fit the name, or drop the label on a single-spacecraft track. |
- fe-ops 699689f6: #7–#13 accepted per commit (Rejected vs Missed, suffix, 6 h line, "No recent value" since the read has no last value outside its window, today-less window, "other", label width).
