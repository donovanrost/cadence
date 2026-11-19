# Query line · ⌘K (J5 · find anything)

Global overlay, available on every console page (Ops and Setup). Open with `⌘K` / `Ctrl+K` /
`/` (when focus isn't in an input) or the top-bar query button. Board `Palette.dc.html`.
Owner: lead (shell component ApPalette) with content providers from fe-ops / fe-setup. Visual
spec: design-language §7 ApPalette.

**Question:** "Take me to 312's VBAT." "Send SET_ADCS_MODE." **Type, ↵.**

## Anatomy
Modal dialog (`role="dialog" aria-modal="true" aria-label="Search and run commands"`), 680px wide,
top 14vh, `panel` bg, `line` border, backdrop `rgba(3,5,8,.7)` over the still-visible console.
1. Strip (mono 11 `text-4`): `CADENCE // QUERY` · right `EARENDIL · 500 SC · 547 CMDS · 6 STATIONS`
   (real counts; omitted if unknown).
2. Input row: `›` prompt, `Search` (visually hidden label), sans 18px input, placeholder `spacecraft,
   telemetry, commands, stations…`, `ESC` kbd. Combobox semantics: input `role="combobox"`
   `aria-expanded` `aria-controls` → results `role="listbox"`, rows `role="option"`,
   `aria-activedescendant` follows the active row.
3. Results, grouped in this order: **Spacecraft, Telemetry, Actions, Commands, Stations, Profiles,
   Pages** (Setup mode ranks Profiles, Catalog, Stations, Pages first). Group label `grp` with
   trailing hairline. Max 5 per group, `Show all 23 spacecraft` row at the group end.
4. Footer hints: `↑↓ MOVE · ↵ OPEN · ⌘↵ COMMAND IT · G N NOW · G C CONTACTS · [ ] PREV/NEXT SC`.

## Result rows (all are actions)
| Group | Title (mono) | Subtitle (sans 13) | Hint | ↵ does | ⌘↵ does |
| --- | --- | --- | --- | --- | --- |
| Spacecraft | `EARENDIL-312` | `Critical · VBAT below limit · plane 07 · Earendil Block 1` | `SCID 312` | open spacecraft (Investigate if alarmed) | Command it (`M/commands/new?targets=sc:<id>`) |
| Telemetry | `312 › VBAT` | `23.1 V · red limit 24.0 V · HK.battery_voltage` | `PLOT` | open spacecraft Telemetry tab with the point plotted | – |
| Actions | `Command EARENDIL-312…`, `Passes for EARENDIL-312` | consequence sentence | `⌘↵`, `G C` | do it | – |
| Commands | `SET_ADCS_MODE` | `Attitude control · mode, duration` | `CATALOG` | start a new sequence with this command (targets empty) | same |
| Stations | `SVB · Svalbard` | `Degraded downlink since 01:52Z · 1 AOS now` | `STATION` | Contacts filtered to the station | – |
| Profiles | `Earendil Block 1` | `500 spacecraft · v4` | `PROFILE` | Setup › profile | – |
| Pages | `Contacts` | `Ground track and pass schedule` | `G C` | navigate | – |
Icon box (28px, `line` border) holds a 14px stroke icon tinted by the object's **state** (crit red
for a critical spacecraft); the subtitle also states the state in words, so color isn't alone.
Pages/actions icons are `text-3`. Active row: `raised-hi` + 2px white left border.

## Matching
Server-side search over mission objects (one endpoint, typed results; fuzzy on name, SCID, point
name/description, mnemonic, station code/name), debounced 120 ms, results for the current mission
only. Numeric queries match SCIDs first (`312` → EARENDIL-312). `>` prefix = commands only, `@` =
stations, `#` = spacecraft **[decision]** (shown in the empty-query hint). Recent items (last 5
opened) appear first on an empty query, then Pages.

## States
Empty query: Recent + Pages. Loading: the previous results stay, with a mono `SEARCHING…` in the
strip (no flicker). No matches: "No matches" + "Try a spacecraft number, a command like SET_ or a
station code like FBK." Error: crit line "Search is unavailable" + pages still navigable (they're
local).

## Keyboard
`↑/↓` move (wraps), `↵` open, `⌘↵` command it (only on rows that support it; otherwise no-op with
the hint dimmed), `Tab` cycles groups, `Esc` closes and returns focus to the trigger. Global `G x`
shortcuts work only with the palette closed and no input focused (IA §2).

## Acceptance (for qa)
- Opens from anywhere with ⌘K and `/`; focus lands in the input; Esc restores focus.
- `312` → first result EARENDIL-312; `set_` → commands; `fbk` → Fairbanks.
- Screen reader announces the active option and the result count.
- Results never include objects from another mission or org.
