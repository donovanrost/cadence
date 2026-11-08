# Review: Now (fe-ops) + shell breakpoints (lead), rendered (2026-11-08, :4011, 390 / 900 / 1440)

**1440: Now is faithful.** It holds still, panel indices and metas are right, the h1 tells the truth
("No telemetry yet"), never-heard cells are dashed `off` (U8), A4 shows an honest empty state, and
the action queue explains *why* ("nothing here can be critical or caution"). Breakpoints: no
horizontal scroll at any width, index-only rail at 900, bottom tabs at 390. ⌘K hidden until the
palette registers: agreed, better than a stub.

## Fixes (fe-ops)
1. **Unknown health shows as `0`** (Caution / Critical / Stale tiles). With 0/500 fresh and ground
   limits not configured, "0 out of limits" is calm without truth, and the queue itself says nothing
   *can* be critical. → new rule **U13**: when no spacecraft is fresh, Caution / Critical / Stale
   show `—` with caption `no telemetry yet`. When ground limits aren't configured, Caution and
   Critical show `—` with caption `limits not configured` (flight-event criticals still count,
   if any exist, as a number).
2. **"Reconnecting…" forever.** If the fleet channel doesn't exist yet (M8), this isn't a lost
   connection. Say "Live updates aren't available yet. Values refresh every 30 s." (stale callout,
   with the real interval) and keep "Live updates lost at 02:41:17Z…" for a real drop.
3. **900px squeezes A1/A2 to ~70px.** Below 1100 the spec allows page scroll: give rows a min
   height (A1/A2 ≥ 320px, A3/A4 natural) and let `main` scroll; stack order under 768: A2 → A1 →
   A3 → A4.
4. **390px stat strip:** six columns truncate the labels ("NOMINA", "CAUTIO"). → 2 columns × 3
   rows under 768 (Mobile.md), 3 × 2 from 768 to 1100.
5. Minor: the matrix uses fixed ~10px cells and fills about half the panel; let columns be `1fr`
   (as the canvas grid does) with a max cell of 16px, so it reads at a glance.

## Fixes (lead)
6. **Bottom tab bar content:** Mobile.md has `Now · Alarms · GO polls · Search` (on-call
   triage). Fleet / Contacts / Commands aren't on-call jobs, and building uplinks is desktop-only by
   design. → `Now · Alarms · GO polls` now (GO polls = `M/commands?awaiting=me`), plus `Search`
   once a palette registers.
7. **Two `nav` landmarks both named "Ops"** (rail + bottom tabs). → name the tab bar "Ops tabs"
   (or hide the off-screen one with `display:none` at each breakpoint so only one exists in the a11y
   tree).

Not a bug: a blank white `/setup` frame at 900 didn't reproduce (HMR reload during capture).

## Resolved (re-checked 2026-11-08 22:12Z, 390px)
Items 6-7: tabs are `Now · Alarms · GO polls` (Search joins with the palette), landmark "On-call tabs". Items 1 and 4 also visible: U13 dashes, 2×3 stat grid, queue stacked first.

## Second look at 7cd1e7a4 (2026-11-08 22:19Z)
Verified: U13 dashes, 2×3 strip under 768 / 3×2 at 900, page scroll below 1100 (900 looks right),
A2-first stack, live-status callout (hidden now because the socket is live; copy checked in code).

**New regression at 1440×900 (fe-ops):** the 16px-capped matrix makes A3 ~420px tall for 20
planes, so the A1/A2 row shrinks to ~160px: the constellation is a thumbnail and the **action
queue, the screen's main job, shows 1.5 rows**. Rule: A1/A2 get the remaining height, with a
floor of 55% of it; A3/A4 take the rest. Size matrix cells to fit A3's height:
`cell = clamp(8px, (A3 body height − gaps) / planes, 16px)`. Below 8px the matrix scrolls inside
its panel (U8). At 1440×900 with 20 planes that's about 10px cells, close to the first build.

## Third look at 8ccf851f (2026-11-08 22:28Z, 1440×900)
A1/A2 now get the height they need: good. Two items:

1. **Matrix hides planes while the panel is two-thirds empty (fe-ops).** At 8px cells, P16–P20
   scroll out of view, but the 25-slot grid only uses ~250px of a ~630px panel. J1 step 02 is "see
   all 500". → when `planes × cell` overflows the height and width allows, **wrap plane rows into
   columns** (P01–P10 | P11–P20, a 24px gutter, each column with its own plane labels). Pick the
   column count that maximizes cell size within 8–16px. Scroll only when even that can't fit.
   (Recorded as U14.)
2. **The plane picker is a raw native `<select>`** (rounded, browser chevron, sentence case).
   That's off-language next to everything else. → use a kit select (lead: add **ApSelect** to the
   kit per design-language §7 ApField: 32px compact / 38px standard, `well` bg, `line` border,
   radius 0, mono 12 value, custom chevron in `text-4`, white border on focus). Label it for
   assistive tech ("Plane"), value `ALL PLANES` / `PLANE 07`. Keep it synced with `?plane=`.

## Closed (2026-11-08 22:32Z)
U14 verified at 1440×900: P01–P10 | P11–P20, all 20 planes visible. Plane picker is the kit ApSelect. Data is consistent with Setup (10 reporting, 490 not heard). Now review closed.
