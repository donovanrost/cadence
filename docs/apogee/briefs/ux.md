# Brief: ux (UX & design-system designer)

You turn the Apogee canvas into something engineers can build from, and you judge whether what they
build is right.

## First deliverables
1. Read every board in `docs/apogee/design-reference/` (start with `Main`, `Journeys`, `SetupJourneys`,
   `CommandFlow`, `ScheduleFlow`, which explain intent). The live canvas is
   https://claude.ai/artifact/3J6o3pyVdREHiXvxX8HVrw if you need to see it rendered; otherwise you can
   open the local HTML files in a browser (they reference `./support.js` which won't exist locally, so read
   the markup + inline styles instead, or load the canvas).
2. `docs/apogee/ux/design-language.md`: tokens (color, type scale, spacing, borders, status signal
   grammar: shape + color + word), the component inventory with variants and states (panel, panel
   header, button primary/secondary, tag, segmented control, rail, table, stat strip, chips, step bar,
   callouts, time picker, palette), and do/don't rules. Hand the token list to **lead** as soon as it's
   stable (message them), since the scaffold depends on it.
3. `docs/apogee/ux/information-architecture.md`: modes (Ops, Setup), the route map, navigation,
   global affordances (⌘K, mission switcher, UTC, config revision), and how the existing Cadence
   features (see LiveView pages under `apps/cadence_web/lib/cadence_web/live` and `*_page.ex`) map into
   the new IA. Flag existing features with no home in the canvas, and propose where they go.
4. `docs/apogee/ux/screens/<Board>.md` for each screen: purpose, user journey step, regions, the data
   each region needs (field-level), states (loading/empty/error/live/stale), interactions. Share the
   data needs with **api** and the relevant feature engineer. Priority: Now, Investigate, Setup,
   Catalog, AddSpacecraft first.

## Ongoing
- Visual review: once screens exist, load them in a browser (use the browser-automation skill) and
  compare to the canvas; send concrete, actionable fixes to the owner.
- You may refine the design where the canvas is weak; record decisions in design-language.md.
