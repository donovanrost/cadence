# Contacts · live (J4 · plan contacts)

Route `M/contacts[?view=station|spacecraft&sc=<id>&contact=<id>]` · Ops rail 05 (count = `n AOS`,
in contact now) · **console layout** · Board `Contacts.dc.html`. Plan / Replan / Review are
separate specs (phase 3: SchedulePlan, Replan, PassReview). Owner: fe-ops. Data:
`docs/apogee/plans/ops.md` §J4. Scope: DECISIONS #4 (no propagation: ground track, sky plot,
footprints and max-elevation prediction are "not available").

**Question:** "Who talks to which station, and where are the gaps?" **Whole fleet, one view.**
**Journey:** see where passes happen → read the 6-hour schedule by station, conflicts dashed → fix a
conflict or coverage gap in one click.

## Layout
```
lbl "GROUND NETWORK · 6 STATIONS"  h1 "Contacts"   meta: 186 PASSES NEXT 6H · 7 AOS NOW · 2 CONFLICTS · 1 COVERAGE GAP
tabs: Live · Plan · Review                          [By station | By spacecraft]  [Book passes]
┌ D1 Ground track (flex) ────────────────────────┐ ┌ D2 Selected pass (aside 360, pane) ┐
└────────────────────────────────────────────────┘ └────────────────────────────────────┘
┌ D3 Pass schedule · 6 h (flex) ─────────────────┐ ┌ D4 Needs a decision (aside, pane)  ┐
└────────────────────────────────────────────────┘ └────────────────────────────────────┘
```
**[decision]** Contacts gets a section tab row (`Live · Plan · Review`, ApSegmented `tabs`) under
the header so the scheduling boards share one rail item. `Book passes` = shortcut to Plan.
`By station │ By spacecraft` is a `choice` segmented that swaps D3's row axis.

## Header
Meta (mono 12 `text-3`) counts over the 6 h window: passes, AOS now, conflicts (caution text when >
0), coverage gaps (crit text when > 0). Omit counts the backend can't compute (conflicts/gaps need
M22).

## D1 · Ground track · next orbit
**Not available (DECISIONS #4).** Keep the pane (U10) with ApEmptyState: `off` mark, "Ground track
not available", "Station locations and orbit propagation aren't in Cadence yet. The schedule below
is live." When stations have coordinates but no propagation (M21 without M12), draw the
equirectangular map with station markers and masks only, legend `STATION MASK · NIGHT`, header meta
`EQUIRECTANGULAR · 5° MASK`. **[decision]** Until either exists, collapse D1 to a 120px strip so
D3 gets the height (the layout still holds still).

## D2 · Selected pass (aside pane)
Opens on bar click in D3 (or `?contact=`). Default: the next AOS fleet-wide.
Title: spacecraft link (display 18px) + state tag; mono `FAIRBANKS · AOS T−00:38:10` (white
countdown). Sky plot: **omitted** (needs propagation). Key/values (`kv` rows): Window `02:59:40 –
03:08:52Z` · Duration `9m 12s` · Max el (omit without prediction) · Uplink (queued commands bound to
this pass: "Low power safe · 2 cmds", link to the request; "None queued") · Downlink (actual volume
for completed passes only; `~4 MB` estimates omitted until there's a real estimate). Actions:
~~`Swap station`~~ (out of scope for v1, DECISIONS #68: hidden until domain has a 'replace booking' op), `Release` (cancel the reservation; danger confirm; org admins only, and members see "Org admins can release a booking.").
Both hidden until their endpoints exist. State trail (ApStateTrail) for the contact: Requested →
Confirmed → In contact → Realized (+ off-ramps per ScheduleFlow M1).
- **Data:** `{id, spacecraft: {id, name, scid, state}, station: {code, name}, aos, los, state,
  queued_requests: [{id, label, command_count}], downlink_bytes?, provider_reservation_id}`.

## D3 · Pass schedule · 6 h (ApGantt)
Header: chips `sc any` (filter: type a spacecraft → its passes highlight in place, others dim;
never a picker, ScheduleFlow R02) and `highlight queued uplinks` (toggle; bars with queued uplinks get
an inset top dark notch `.cb.up`); meta `186 OF 186`.
Rows = stations (By station) with code (mono) + note (`Fairbanks · 2 ant`, `Degraded downlink` in
caution, `Inuvik · on demand`); By spacecraft = rows per spacecraft with a pass in the window (or
the filter's matches), virtualized. Bars: scheduled / live / conflict (dashed caution) / selected
(white + outline offset 2) / crit (crit outline + crit wash: the spacecraft is critical); outage
bands (red hatch) on degraded stations; now-line; axis `02:00Z … 08:00` hourly. Gaps over a
spacecraft's allowed silence are drawn on the spacecraft view (ScheduleFlow R03).
Keyboard: bars are buttons in a roving-tabindex grid (←/→ within a row, ↑/↓ between rows, ↵ opens
D2); `aria-label` per bar "EARENDIL-312, Fairbanks, AOS 02:59:40Z, 9 minutes, scheduled".
- **Data:** stations `[{code, name, note?, state, outages: [{from, to, kind}]}]`; contacts in window
  `[{id, station_code, spacecraft: {id, name, scid, state}, aos, los, state, has_queued_uplink}]`.

## D4 · Needs a decision (aside pane)
Rows: mark + title (600, mono ids) + sentence with the proposed fix + one action:
`SVB double-booked 03:20Z` / "073 and 251 overlap by 3 minutes. Awarua is free for 251." / `Move 251 →
AWA`; `389 · no pass for 5h 40m` (crit) / "…an opportunity at Hartebeesthoek, 04:12Z, closes the
gap." / `Request opportunity`. Fix proposals come from the server (M22); without them the row
shows the problem and `Open in Plan`. **Empty:** nominal callout "No conflicts or gaps in the next
6 h." **Unavailable (no M22):** hide D4 and let D3 take the width.

## States
Loading `LOADING…` per pane. Live: bars move along (the now-line advances; the axis scrolls once a
minute), state changes apply in place; a newly lost contact flashes once. No stations configured:
full-width empty state "No ground stations yet" + `Add a station` (→ Setup › Ground stations).

## Acceptance (for qa)
- One view for the whole fleet; filtering a spacecraft highlights in place (no picker, no new page).
- Propagation-dependent pieces are absent or show "not available" with the reason.
- Conflicts read as dashed + caution + the word in D4; nothing relies on color alone.
- Gantt is keyboard-operable.
