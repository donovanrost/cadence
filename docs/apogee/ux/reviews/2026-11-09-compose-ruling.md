# Compose ruling: CommandFlow C1 board vs. as built (DECISIONS #64)

Live on :4011 as qa-org-admin, 1440×900, 1100×800 and 390×844. One target (EARENDIL-001), DISABLE_LOAD and
SET_HEATER_SETPOINT added. Writes were blocked except the read-only preflight. The single browser run waited
for load < 16.

## Ruling: accept Command.md C1–C5 as built. Don't schedule the three-column board.
The whole task fits one 1440×900 screen:
- targets (C1) | stack + inline form + catalog (C2) | summary, release, title, log and Arm (C5);
- the station bar tracks the step (`✓ 01 TARGETS · 1`, `● 02 COMMANDS · 1`);
- Arm is always visible, with its reason ("Fix the highlighted argument values.").

The board's real advantages are the per-target values pane and the verifier line. Both can land inside the
current layout as the gaps already listed, so the board itself wouldn't fix a usability problem. 390 shows
the desktop-only notice as specified.

## Fixes (fe-ops), ranked
| # | Impact | Issue → fix |
| --- | --- | --- |
| 1 | Med | **Enter on an incomplete form closes it.** SET_HEATER_SETPOINT with `heater_id` empty: Enter dismisses the form and leaves `▲ NEEDS VALUES`, with no visible way back in. → While invalid, Enter keeps the form open and focuses the first invalid field. Make the row's value summary (`heater_id — · setpoint 1 degC`) a button that reopens the form. |
| 2 | Med | **C4 says `via EARENDIL-001`:** the spacecraft name sits where the route belongs. → `via SVB-1 · Northlight` (station · provider of the booked pass). If it's unknown, drop the `via` clause (U20). |
| 3 | Med | **Verifier line missing** from the argument form (gap, CommandFlow C1). → `Verifies THERM.batt_setpoint = value ±0.1 within 60 s` when the catalog defines one, else `No verifier: this command can't turn green` in stale text. Of the gaps, this one matters most: it tells the operator whether success will be visible. |
| 4 | Low | **Title placeholder reads like a real value** (`Load shed after VBAT red on 312`, unrelated to this request). → `e.g. Load shed after VBAT red on 312`, or a neutral placeholder. Placeholder colour stays text-4. |
| 5 | Low | **1100px:** the catalog's arg count wraps (`0` / `arg` on two lines), and the header clock drops to a second line. → `white-space: nowrap` on the count. The clock cluster stays in the header row (drop the `UTC` label below 1200 if needed). |
| 6 | Later | Remaining listed gaps: per-target values (B2), Keep/Drop for excluded targets. Reorder already exists (↑ ↓). |

Not a finding: the floating `Sign in` widget at the bottom left is the dev-only Tidewave overlay, not the console.

## Status
- fe-ops b8fe16e0: #1–#5 accepted per commit (the #5 header clock went to lead, TakeoverHeader). No live recheck: browser checks run in CI now, not as routine checks (user rule, ARCHITECTURE.md "Working in the console").
- fe-ops e262c233: draft edge-case rulings (601a32f9) accepted per commit and copy read: both Discards confirm, close saves first, autosave-paused and not-saved headers, Load/Keep mine.
