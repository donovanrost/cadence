# Now (J1 · start of shift)

Route `M/now` · Ops rail 01 · **console layout** (fits the viewport) · Board `Now.dc.html`.
Owner: fe-ops. Data sources and gaps: `docs/apogee/plans/ops.md` §J1 (this spec doesn't repeat them).

**Question it answers in 5 seconds:** "Is my constellation OK, and what needs me?"
**Journey:** land on Now → see all spacecraft (constellation + matrix) → work the action queue P1→P3
→ Engage opens Investigate (J2) / Review opens the request / Station opens Replan or the station.

## Layout (1440×900 reference)
```
┌ top bar 52 ─────────────────────────────────────────────────────────────┐
│ rail 200 │ page header: lbl "EARENDIL · CONSTELLATION STATUS" + h1 + meta│
│          │ stat strip ×6 (flex none)                                    │
│          │ ┌ A1 Constellation (1.2fr) ┐ ┌ A2 Action queue (1fr, scrolls)┐│
│          │ │   flex 1, min-height 0   │ │                               ││
│          │ └──────────────────────────┘ └───────────────────────────────┘│
│          │ ┌ A3 Fleet matrix (1fr) ───┐ ┌ A4 Passes · next 2 h (1fr) ──┐ │
└──────────┴──────────────────────────────────────────────────────────────┘
```
Main: column, `padding 14px 20px`, gap 12. Row 3 (A1/A2) takes the remaining height; row 4
(A3/A4) is natural height. Below 1100px wide: page may scroll, rows stack A2 → A1 → A3 → A4
(queue first).

## Regions

### Header
- `lbl` (readout color): `<MISSION NAME> · CONSTELLATION STATUS`.
- h1 (page title 28px) states the situation, computed:
  - crit > 0: `N spacecraft need you` (N = distinct spacecraft with a P1 item).
  - else caution/stale > 0: `N spacecraft to watch`.
  - else all fresh and nominal: `All N nominal`. Only when every spacecraft is fresh: stale > 0 is
    never "nominal".
  - no telemetry at all for the mission: `No telemetry yet` + empty states below.
- Meta line (mono 12 `text-3`, right): `TLM FRESH 488/500 · LAST PKT 2s · <worst station issue>`.
  Each part omitted if unknown.
- **Data:** mission name; counts (below); last packet received_at (mission-wide); station issues
  `{station_name, state, since}`.

### Stat strip (6 ApStatTiles)
| Tile | Value | Caption | Accent |
| --- | --- | --- | --- |
| Nominal | `471/500` | fresh and in limits | none |
| Caution | `14` (caution text) | trending to limits | caution top bar if > 0 |
| Critical | `3` (crit text) | `+1 in the last hour` (delta) | crit top bar if > 0 |
| Stale | `12` (stale text) | `no TLM over 15 min` (threshold from server, U9) | stale top bar if > 0 |
| In contact | `7` | `41 passes next 2 h` | white top bar if > 0 |
| Uplinks queued | `23` | `2 await your GO` (caution text when > 0) | none |
Rules: counts partition the fleet by **worst state** (crit > caution > stale > nominal);
never-heard spacecraft are counted in none of these and shown as `+N awaiting first AOS` in the
Nominal caption. Zero renders `0` in `text-3` (no accent). Unknown → `—` + "not tracked yet" (U10).
Tiles link: Critical/Caution/Stale → `M/alarms?state=…` or `M/fleet?state=…`; In contact → Contacts;
Uplinks → Commands filtered.
**Data:** `{nominal, caution, critical, stale, never_heard, total, critical_delta_1h, in_contact,
passes_next_2h, uplinks_queued, uplinks_awaiting_me, stale_after_s}`.

### A1 · Constellation (ApConstellation)
Header meta: `10 PLANES · SSO 97.6° · 550 KM` (plane count, inclination, altitude when known).
SVG fills the pane; dots placed by plane and in-plane phase; selected plane drawn white; crit dots
ringed and labelled. Toggle `Planes │ Ground track` (choice segmented, bottom right). Legend bottom
left. Click a dot → `M/fleet/:scId`; click a plane → selects it (also highlights the matrix row).
`aria-label` summarises counts and names the critical spacecraft.
- **Data:** per spacecraft `{id, name, plane, phase_deg | slot, state, in_contact}`; per plane
  `{index, raan_deg?}`; mission `{inclination_deg?, altitude_km?}`.
- **Unavailable (no orbit data):** keep the panel; ApEmptyState `off` — "Orbit data not available"
  / "The constellation view needs orbital elements per spacecraft." (U10). Ground-track toggle hidden.

### A2 · Action queue (ApListRow list, scrolls)
Header meta: `6 OPEN · SORTED BY URGENCY`. Ranking rule: decision U11.
Row: `[P1] [mark] [title link / secondary / meta] [action]`.
- Title: `<SPACECRAFT NAME> · <what>` linking to the item's target; group rows have no
  spacecraft (`4 in plane 2 stale`).
- Secondary: one sentence with the evidence (`23.1 V vs 24.0 V, falling 0.4 V per orbit`).
- Meta (mono 11): age `T+6m` + next opportunity `AOS FAIRBANKS T−38m`; live contact in readout
  (`IN CONTACT · AWARUA · LOS T−03:20`).
- Action (compact button): `Engage` (alarm → Investigate), `Review` (GO poll → request review),
  `Station` (→ station / Replan), `Install` (→ Setup › Apps). The top P1 row's action is primary.
- **Over 100 open** (fe-ops and lead, 11-15; render budget at 1,000 craft). The first 100 rows render in server
  order (U11), then one row-width button says what's hidden **by status**, with marks and words, and zero counts
  left out: `Show 900 more · ▲ 412 caution · 488 other`. Crit is named only when some is hidden: `Show 900 more ·
  ◆ 3 crit · ▲ 409 caution · 488 other`, and then the button row is crit-tinted, because something crit is out of
  sight.
  - No caption claiming the rest are "less urgent": equal priorities tie across the cut (U20).
  - The meta stays `1,000 OPEN · SORTED BY URGENCY`. Showing the rest keeps scroll position and focus, on the first
    newly shown row.
- **Data:** `[{id, priority, state, kind: alarm|flight_event|missed_pass|approval|stale_group|
  station|setup|attention (U31), title, spacecraft?: {id, name, scid}, evidence, raised_at, next_aos?: {station,
  at}, live_contact?: {station, los_at}, target: {kind, id}}]`.
- **Empty:** `■` nominal callout "Nothing needs you. N spacecraft fresh and in limits." Never shown
  while anything is stale.
- **Live:** new P1 rows slide in at the top and flash once (design-language §6); rows resolved by
  someone else fade out with a one-line "Resolved by Mira K." for 5s.

### A3 · Fleet matrix (ApFleetMatrix)
Header meta: `ROW = PLANE · 50 SLOTS` (shape rules: U8). Cells as design-language §7; hover/focus
inspector `EARENDIL-312 · SCID 312 · ◆ Critical · VBAT · last TLM 2s`. Click → spacecraft.
Selected plane label in readout. The matrix grid itself is `aria-hidden`; an equivalent
"View as table" link goes to `M/fleet` (the accessible path).
- **Data:** same per-spacecraft list as A1 (`plane, slot, state, in_contact, never_heard`).

### A4 · Passes · next 2 h (ApPassStrip)
Header meta link `OPEN CONTACTS →`. Rows = stations with passes in the window (station code, caution
tint when degraded); bars per contact: scheduled / live (AOS) / conflict; now-line; axis
`02:00Z … 04:00` in 30 min majors. Click a bar → contact drawer in Contacts.
- **Data:** `[{station: {code, name, state}, contacts: [{id, spacecraft: {name, scid}, aos, los,
  state: scheduled|live|conflict}]}]`, window = now − 15 min → now + 2 h.
- **Empty:** "No passes in the next 2 h" + `Open contacts`. **Unavailable** (no contact data):
  ApEmptyState `off` with the reason.

## States
| State | Behavior |
| --- | --- |
| Loading (first) | Panels render with headers; bodies show a single mono `LOADING…` line (`text-4`). No skeleton shimmer. Stat values `—`. |
| Live | Values update in place via the fleet channel; the top-bar `LAST PKT` ticks. |
| Connection lost | Callout `stale` under the header: "Live updates lost at 02:41:17Z. Values may be out of date. Reconnecting…"; every live value gets the stale treatment (hatched mark in tiles); never keep showing them as fresh. |
| Error (one panel) | That panel's body shows a crit callout with the error sentence and `Retry`; others keep working. |
| Empty mission (0 spacecraft) | h1 "No spacecraft yet"; one `info` callout with `Add spacecraft` (→ Setup) in place of A1–A4. |

## Interactions & keys
`G N` here; `[`/`]` not active (no spacecraft context). Selecting a plane in A1 or A3 syncs both
(`?plane=7` in the URL). Engage / Review / Station follow the target. ⌘K available.

## Acceptance (for qa)
- No page scroll at 1440×900 and 1280×800; A2 scrolls.
- Every count matches the backend; unknowns show `—` with a reason, never `0`.
- Stale spacecraft never contribute to the h1 being "nominal".
- Each queue row has mark + priority + words; nothing relies on color alone.
