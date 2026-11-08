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
