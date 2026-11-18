# Apogee design language: build spec

Owner: **ux**. Status: rev 1 (2026-11-08). Values live in [`tokens.css`](tokens.css); this file says
how to use them. Team Q&A rulings are in [`decisions.md`](decisions.md). Source boards: `docs/apogee/design-reference/` (Main is the language board; every
screen board repeats the same CSS, which is where the measurements below come from).

> An instrument panel, not a web page. Sharp edges, hairline grids, real mission vocabulary, built
> for one operator flying 500 spacecraft from one seat.

Where this spec departs from or adds to the canvas, the item is marked **[decision]**.

---

## 1. Principles (from Main, with the build consequence)

| Principle | What it means in code |
| --- | --- |
| **Truth before calm** | "No data" is a state, never a zero or a green. Stale is hatched and outranks nominal. A count we can't compute is shown as unknown (`—` with a reason), not omitted. |
| **Fleet first** | Views open on the constellation and narrow: fleet → plane → group → spacecraft. Breadcrumbs follow that path. |
| **The clock is king** | UTC (and MET / next AOS in Ops) is in the top bar on every screen. Time axes run left to right. |
| **Speak flight** | AOS, LOS, pass, uplink, umbra, GO / HOLD / NO-GO. No "items", "records", "entities". |
| **Shape carries meaning** | State = shape + color + word. Must read in grayscale. |
| **The console holds still** | Ops screens you act from fit the viewport: the page never scrolls, panes do. The commit action sits beside the state that justifies it. Reading, setup and admin pages may scroll. |

Color rule: **the interface is grayscale.** White marks what you can act on and what is live. The
only hue on screen is operational state, so any color means something is wrong, stale or (green)
earned. Never use status hues for decoration, branding, categories or charts series.

---

## 2. Color

All tokens are in `tokens.css`. Default Tailwind colors are cleared, so `bg-panel`, `text-text-3`,
`border-hairline` etc. are the only colors that exist.

### Surfaces and lines
| Token | Hex | Use |
| --- | --- | --- |
| `vacuum` | #05070A | page background (with the 40px hairline grid), plot wells, input wells, lanes |
| `chrome` | #070A0E | top bar, rail |
| `panel` | #0A0E13 | every panel body, stat tiles |
| `raised` | #0F141B | buttons, hover and selected rows, emphasized panels, staged bar |
| `raised-hi` | #161D26 | the active result in the ⌘K palette only |
| `cell-empty` | #11161D | empty matrix slot, meter track |
| `hairline` | #1C2530 | panel borders, header rules, the 1px gaps of tile grids |
| `hairline-faint` | #141B24 | row dividers inside a panel, lane borders |
| `line` | #2A3644 | control borders: buttons, inputs, chips, toggles |
| `line-strong` | #3A4654 | scheduled-pass outline, kbd border, flow arrows |

### Text (contrast measured on `panel`)
| Token | Hex | Ratio | Use |
| --- | --- | --- | --- |
| `readout` | #E6EDF3 | 16.4 | primary text, live values, links |
| `bright` | #FFFFFF | – | link hover only |
| `text-2` | #C9D3DD | 12.8 | panel titles, strong secondary, table cell emphasis |
| `text-3` | #9DAAB8 | 8.2 | sentences, descriptions, secondary values, inactive controls |
| `text-4` | #7D8A99 | 5.5 | labels, meta, timestamps, units. **4.4 on `hairline`: never put it on a hairline-colored fill** (e.g. the micro segmented "on" state). |
| `text-off` | #4A5562 | 2.4 | decoration only: out-of-month days, disabled glyphs. Never informative text. |

### Action
`action` (#E6EDF3, "signal white") fills the primary button and marks selection, the now-line and
the in-contact ring. `on-action` (#05070A) is text on it. There is exactly one primary button per
decision region.

### Operational state
Each state has a **fill** (shapes, bars, cells, stripes) and a **text** tint (words, values).

| State | Shape | Fill | Text | Meaning |
| --- | --- | --- | --- | --- |
| `crit` | diamond (8px square rotated 45°) | #FF4D57 | #FF6B73 | Out of limits, a human acts now. Flashes once on arrival. |
| `caution` | triangle 10×9 | #FFB020 | #FFC24D | Trending to a limit or a soft limit crossed. |
| `stale` | hatched square, 1px border | #A497FF | #BDB3FF | No fresh telemetry. Outranks nominal everywhere. |
| `nominal` | solid square | #2FD08A (bulk: `nominal-bulk` #164E37) | #4FDB9E | Fresh and in limits. Drawn dim in bulk so problems stand out. |
| `off` | dashed square | border #9DAAB8 | #9DAAB8 | Not set up / not installed. Offer to install, never imply clean. |
| `live` | solid white square / white ring | #E6EDF3 | #E6EDF3 | In contact now, AOS, live pass. Not a health state. |
| `neutral` | solid #7D8A99 square | – | #9DAAB8 | Informational event (plan started, operator action). |
| `optional` | 10×2 gray dash | #7D8A99 | #C9D3DD | A suggestion, explicitly *not* a warning (Setup findings). |

**Aggregation precedence [decision]:** `crit > caution > stale > nominal`. `off` and `live` are
orthogonal (a spacecraft can be live and caution). The top bar's fleet posture (IA §Top bar) counts each state
across the fleet; stale beats nominal so "all green" is never claimed with stale members.

**Readiness words** GO / HOLD / NO-GO use nominal / caution / crit text tints in an outline tag. The
word carries the meaning, so no mark is needed.

**Washes** (backgrounds behind a status row): `--apogee-wash-crit` 8%, `--apogee-wash-caution` 6%
(4–5% on large table rows), nominal 4%. Use a wash only on the row or callout that *is* the problem,
never on a whole panel.

**Status accents** are inset 2px box-shadows, not borders:
- top inset in the state fill on a stat tile / area tile that is in that state,
- left inset 2px on a readout or fact that is out of limits,
- left inset 2px **white** on a selected list row,
- bottom inset 2px **white** on the active tab / active step.

---

## 3. Type

Three families (Google Fonts: `Saira:400,500,600`, `Saira Condensed:500,600,700`,
`Azeret Mono:400,500,600`; self-host in the SPA build if possible).

| Family | Token | Used for | Rules |
| --- | --- | --- | --- |
| Saira Condensed | `font-display` | labels, headings, panel titles, buttons, tags, rail, tabs | **always uppercase**, always tracked |
| Saira | `font-sans` | sentences and **every live number and time readout** | numbers use `tabular-nums` |
| Azeret Mono | `font-mono` | literal ids (SCID, point names, command mnemonics), timestamps, panel index + meta, kbd | never uppercase-transform ids; mnemonics are already upper |

### Role scale (build these as utilities or component props; don't hand-mix sizes)
| Role | Spec | Example |
| --- | --- | --- |
| entity title | display 700 36px, tracking .06em | `EARENDIL-312` |
| page title | display 600 28px (console) / 36px (setup), tracking .08em, upper | `3 spacecraft need you` |
| area heading | display 600 17–20px, .12–.14em | `Ground stations` |
| panel title | display 600 14px, .18em, `text-2` | `ACTION QUEUE` |
| panel index / meta | mono 500 11px, `text-4` | `A2`, `6 OPEN · SORTED BY URGENCY` |
| label (`lbl`) | display 600 12px, .2em, upper, `text-4` | `NEXT AOS` |
| table header | display 600 11px, .16–.18em, upper, `text-4` | |
| button | display 600 13px .14em (compact) / 14px .16em (standard) / 15px (commit) | |
| tag | display 600 13px, .16em, height 24 (22 inside tiles) | |
| readout XL | sans 500 30px (26px compact), tracking −.02em, tabular | stat tiles |
| readout L | sans 500 24px tabular, unit 13px `text-4` | facts, limits |
| fact value | mono 500 14px | `P07 · slot 12 · #4,812` |
| body | sans 400 14px/1.55, `text-3` | |
| row title | sans 600 14–15px, `readout` | `EARENDIL-312 · VBAT below limit` |
| secondary | sans 13px, `text-3` | |
| caption | sans 12px, `text-3` | under a stat value |
| axis tick | mono 500 10px, `text-4` | **charts and bar labels only** |

Units sit after the value in a smaller size and `text-4`: `23.1 V`, `−0.4 V/orb`.

---

## 4. Vocabulary, time and numbers (one format everywhere)

| Kind | Format | Notes |
| --- | --- | --- |
| absolute | `2026-10-23 02:41:17Z` | always UTC, always to the second, always the `Z` |
| short | `10-23 02:41Z` / `02:08:11Z` | within the current day / log lines |
| countdown | `AOS T−00:04:12`, beyond 24 h `T−4d 03:28:39` | **U+2212 minus**, not hyphen. White when it's the next action. Never more than 23 in the hours field. |
| elapsed | `LOS T+00:06:41`, queue age `T+6m` | |
| mission elapsed | `MET 412:07:14:05` | days:hh:mm:ss |
| duration | `9m 12s`, `5h 40m`, `95.6 min` | |
| identity | `EARENDIL-312` + `SCID 312` | name + SCID (+ profile) on every target row; **never a dash where an identity belongs** |
| negatives | `−18 %`, `−0.4` | U+2212 |
| counts | `4,812`, `3,000 routes` | thousands separators; correct plurals (`1 target`, `2 targets`) |
| separators | ` · ` (middle dot, spaced) | between facts in one line |
| ratios | `488/500`, `471/500` | denominator in `text-4` at smaller size |

Every time a user picks or reads should show its distance from now (`T−` ahead, `T+` behind).
Local time is opt-in, never default. Build one `formatTime` module; components never format dates
themselves.

---

## 5. Space, geometry, layout

- **Radius 0 everywhere. No shadows.** (Inset box-shadows are accents, §2.)
- Spacing unit 4px; the boards use 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24.
- Panel header: `padding 10px 16px`, gap 12. Panel body: 16px (14–18). List row: `12px 16px`.
- Gap between panels: 12px on console screens, 16px on setup/reading screens.
- Main padding: `14px 20px` console, `20px 24px` setup.
- **Tile grids** (stat strip, facts, area tiles, principle grids): `display:grid; gap:1px;
  background:hairline; border:1px solid hairline`, each tile `bg-panel`. This produces the hairline
  dividers; never draw per-tile borders.
- Background: `vacuum` + 40px hairline grid (`--apogee-grid`, 2.5% white).

### Shell
- Top bar 52px, `chrome` bg, items separated by hairline right borders.
- Rail 200px (Ops) / 220px (Setup), `chrome` bg.
- **Console layout** (Now, Investigate, Command, Contacts, Compose, Approve, Uplink, Replan, Plan):
  `height:100vh; overflow:hidden`; main is a flex column; regions are `.pane` (flex column,
  `min-height:0`, overflow hidden) whose body is `.scr` (`flex:1; min-height:0; overflow:auto;
  scrollbar thin, thumb line`). Below ~1100px wide the console may fall back to page scroll; below
  768px use the Mobile layout (§9).
- **Reading layout** (Setup readiness, Catalog, AddSpacecraft, Profile, People, PassReview,
  PassPrediction): normal document scroll, max content width ~1400px, sticky bottom bars allowed.

---

## 6. Interaction states and accessibility

- **Focus [decision]:** canvas defines none. Use `outline: 2px solid readout; outline-offset: 2px`
  on `:focus-visible` for every interactive element. Inside the fleet matrix and pass strips, where
  a white ring already means "in contact", focus uses the same ring **plus** the inspector/tooltip
  naming the cell, so focus is never ambiguous. A full-width search bar at the top of a sheet or the
  palette (#243) has no ring: on focus its bottom edge becomes 2px `readout` (1px border plus a 1px inset
  shadow, so nothing shifts).
- Hover: buttons and rows go to `raised`; text links go `readout → bright`. No color shifts on
  status elements.
- Pressed/selected: white inset bar (rows, tabs, steps) or white fill (choice segments, mode switch).
- Disabled: `text-off` text, `hairline` border, no hover, plus a reason (tooltip or adjacent text).
  Never disable a commit action silently: say what blocks it ("Needs the 3 breaking items fixed first").
- **Dimming never lowers text below its contrast tier** (U27): to mark something inactive, superseded or
  historical, dim the *marks and chrome* (bars, cells, borders, hatches to ~40%) and keep text at ≥ 4.5:1
  (`text-3` at the lowest). Add a word (`SUPERSEDED`, `ENDED`) rather than relying on fade. `opacity` on a
  container holding text is a bug.
- Targets: ≥44px for primary/commit actions (commit buttons are 44–46px). Compact 32px buttons are
  for in-row and panel-header actions only.
- Real elements: `<button>`, `<a>`, `<input>`, `role="tab"`/`radio` where the canvas shows them.
  Every icon-only control has `aria-label`. Status marks carry `aria-hidden` and the word next to
  them carries meaning; where the word is absent (matrix, plot dots) supply an `aria-label` or a
  text alternative.
- **Action menus** (`⋯`, account menu; one kit pattern, 11-15). Use the WAI-ARIA menu button:
  - The trigger has `aria-haspopup="menu"` and `aria-expanded`. Opening it focuses the first item.
  - ↑/↓ cycle through the items, Home/End jump, and Enter or Space activates.
  - Esc closes the menu and returns focus to the trigger. Tab closes it and lets focus move on.
  - `role="menu"` / `menuitem`.
  - **Disabled items stay focusable** (`aria-disabled`, never skipped), with the reason as their description, so the
    reason ("It's already first.") is reachable. Activating one does nothing.
  - A list of links that only opens on hover or Tab is a disclosure instead: no `aria-haspopup`, keep
    `aria-expanded`.
- Charts and the constellation are `role="img"` with a sentence `aria-label` that states the
  finding ("crossing the 24 V red limit in the last orbit"), not "chart".
- Motion: a newly arrived `crit` flashes once (≤600ms). Nothing else animates. Live values swap
  without tweening. Honour `prefers-reduced-motion` (no flash; use a 2s `raised` wash instead).

---

## 7. Component inventory

Names follow lead's `Ap*` convention. "Variants" are props, not separate components.

### Shell
**ApTopBar.** Left→right: brand (diamond mark + `CADENCE` display 700 16px, .36em) │ org / mission
switcher (`Reflect Orbital /` in `text-4` + mission in readout + chevron) │ **ApModeSwitch**
(OPS │ SETUP) │ query trigger (flex 1: search icon, placeholder by mode, `⌘K` kbd) │ fleet status
tag (Ops only) │ clock cluster (mono 13px: Ops `AOS T−… 118·SVB`, `UTC`, `MET` (only with a mission
epoch, decision U7); Setup `CONFIG r5` (only with a mission change set, U2), `UTC`) │ account button (initials, 52px square, `aria-label="Account menu for …"`).
**[decision]** The canvas Ops bar omits the mode switch; show it in both modes so the switch never
moves.

**ApModeSwitch.** Bordered (`line`) pair, 30px, display 13px .18em; active = white fill, dark text,
`aria-current="page"`.

**ApRail.** Links 36–38px, display 14px .16em upper, `text-3`; index in mono 10px `text-4`
(`01`…`07`, `··` for cross-mode links); right-aligned count mono 11px (`text-4`; crit count in
`crit-text`; live count like `7 AOS` in readout). Hover `raised`; active `raised` + 2px white left
border + `aria-current="page"`. Setup rail adds group labels (display 600 11px .22em `text-4`,
`Mission`, `Organization`). Divider: 1px hairline, 12px margin.

**ApClock.** Ticks once a second from a shared store; all clocks on screen tick together.

**ApStagedBar** (Setup only; not rendered until a mission change set exists, decision U2). Sticky bottom, `raised` bg, `line` top border, `12px 24px`. Mono 12
`STAGED · NOT APPLIED` · summary (`2 changes: …`) · right: Discard (secondary) + primary
`Review & apply as r6`. Hidden when nothing is staged.

**ApBreadcrumb.** Mono 12px `text-4`, `/` separators, current crumb `readout`. Follows fleet → plane
→ spacecraft. Optional prev/next spacecraft buttons (`[ 311`, `313 ]`) with `aria-label`.

### Surfaces
**ApPanel.** `panel` bg, 1px `hairline`, radius 0. Variants: `default`; `emphasized` (`raised` bg,
`line` border; for the one decision panel on a screen, e.g. Recommended procedure); `pane`
(console: fills its grid cell, body scrolls); `alert-{crit|caution}` (index colored in the state's
text tint only; the panel itself stays neutral).

**ApPanelHeader.** `index` (mono 11 `text-4`, e.g. `A1`, `B3`) + `title` (h2, panel-title role) +
right `meta` slot (mono 11 `text-4`; link variant is `readout` with ` →`, e.g. `OPEN CONTACTS →`).
Wraps on narrow widths. Index codes: one letter per screen + number, in reading order.

### Controls
**ApButton.**
| Variant | Spec |
| --- | --- |
| `primary` | white fill, dark text. One per decision region. Label states the consequence: `Arm uplink · 4 SC`, `Stage 50 spacecraft`, `Review & apply as r6`. |
| `secondary` (default) | `raised` bg, `line` border, readout text |
| `ghost` | transparent, no border, `text-3` (Cancel) |
| `danger` | `crit-deep` bg, `crit-line` border, `crit-text` (Abort pass). Never white-filled. |
| Sizes | `compact` 32px/13px (rows, panel headers) · `standard` 36–38px/14px (page actions) · `commit` 44–46px/15px (the action that changes the world) |
Buttons can be `<a>` when they navigate. No icons-only buttons except prev/next/close with labels.

**ApTag.** Inline-flex 24px (22 in tiles), display 13px .16em upper, **1px border in
`currentColor`**, transparent bg (optional wash for the hero status of an entity). Status tag =
ApStatusMark + word in the state's text tint (`◆ CRITICAL · POWER`). Neutral tag in `text-3`.
Readiness tags GO/HOLD/NO-GO. Classification tag (`cl`): small 11px, `HAZARDOUS` inverted
(white fill, dark text), `CRITICAL` white text + `text-3` border.

**ApStatusMark.** `state: crit | caution | stale | nominal | off | live | neutral | optional`,
size 8px (10 for caution triangle), `aria-hidden`. Exact geometry is in Main's `.s-*` rules.

**ApSegmented.** Three variants, by meaning:
- `choice` (radio semantics, choosing a value): bordered group, items 30–34px, display 12–13px;
  selected = white fill + dark text. Mode switch, source type, zone UTC/MET/LOCAL, range presets.
- `tabs` (switching views/filters): items 32–36px separated by hairline, `text-3`; active =
  `raised` + readout + inset bottom white bar. Use `role="tablist"`. Spacecraft sections, diff filters
  (`All 30 · Breaking 3 · …`, counts inside the label).
- `micro` (chart window inside a panel): 26px mono 11px; active = `hairline` bg + readout.

**ApField / input.** 36–38px, `vacuum` (well) bg, `line` border, readout text; mono for ids and
numbers, sans for words. Label above in `lbl` style. Open/focused = white border. Invalid = caution
border + caution-text message beneath (a value out of range can't be staged). **ApNumberField**
shows the unit inside, right-aligned, mono `text-4`. Inherited values (Profile overrides) render in
`text-4` until edited; edited cells get an inset 3px white left bar + `raised` bg.

**ApSelect.** Same box as ApField (32px compact / 38px standard, `well` bg, `line` border, radius
0), value in mono 12 (ids, planes) or sans 14 (words), custom chevron in `text-4`, white border on
focus/open. Native `<select>` underneath is fine if fully restyled (`appearance: none`); never ship
the browser default look. Always has a visible or `aria-label` label.

**ApOption** (radio card). Full-width label, `line` border, 12px padding, native radio
(`accent-color: readout`), title 14/600 + description 13 `text-3`. Selected = white border +
`--apogee-wash-action`. Recommended option says "Recommended." in its description.

**ApChip.** 28px, `raised` bg, `line` border, mono 12. Variants: key/value (`scid` in `text-4` then
`SCID`), legend chip (2px line swatch + name), removable (`×` button 22px with `aria-label`),
add-chip (dashed border, inline input).

**ApKbd.** Mono 10–11px, `line-strong` border, `text-3`.

### Data display
**ApStatStrip / ApStatTile.** Tile grid (§5). Tile = `lbl` + readout XL value (+ `/500`
denominator in `text-4` 14px) + caption 12px `text-3`. A tile in a non-nominal state gets the top
inset bar and the value in that state's text tint; its caption may also be tinted when it's the call
to action (`2 await your GO` in caution). 4–6 tiles. **Every number is real or the tile shows
unknown.**

**ApFactStrip.** Tile grid of `lbl` + mono 14 value; the "next action" fact gets a white top inset
bar and readout value (`NEXT AOS T−00:38:10 FBK`). Links inside facts are plain readout links.

**ApReadout.** Large value with a 2px left border: state fill when out of limits, `line` otherwise.
Value in state text tint when out of limits.

**ApTable.** `<table>`, full width, `border-collapse`. Header: table-header role, `10px 12–16px`,
`hairline` bottom border. Cells: 13px, `9–10px 12–16px`, `hairline-faint` dividers, `nowrap` for
ids. Ids and numbers mono; numbers right-aligned and tabular. Name cell is the row link (no
whole-row click). Problem rows get the state wash and the offending cell in the state text tint.
Footer row: "42 more rows · EARENDIL-509 to EARENDIL-550" + `Show all 50`. Horizontal scroll inside
the panel, never the page.

**ApListRow** (queue item, finding, impact, check/poll, event, revision). Grid: `[priority mono
11] [mark 12px] [content] [action]`, `12px 16px`, `hairline` top border except first. Content =
row title (14–15/600) + secondary sentence (13 `text-3`) + meta line (mono 11 `text-4`; `readout`
when it's live, e.g. `IN CONTACT · AWARUA · LOS T−03:20`). One action per row; the most urgent row's
action may be primary (`Engage`). **Check row** (`poll`): `[lbl 150px] [sentence] [Pass/Note/NO-GO tag]`.

**ApEventLine.** Grid `82–92px time | 14px mark | text`, mono 12 `text-4` time, 14px text,
entity names as links. Newest first.

**ApKeyValue.** `dl` grid: `dt` in label style, `dd` in `text-2` 13px. Technical details
(raw ids, point names) go in a `<details>` labelled "Technical details", never in the main view.

**ApCallout [decision].** The canvas has no generic alert; it uses an inline row: status wash +
mark + one sentence (e.g. "No blockers. Nothing stops commanding or contacts."; the time-picker umbra
warning). Spec: `tone: nominal | caution | crit | stale | off | info`, 10–12px 16px padding, wash bg
(info = `raised`), mark, sentence 14px readout, optional trailing action button. No border, no
icon other than the mark, no title.

**ApInlineConfirm** (dashboards' kit proposal, lead-approved, 11-15). An in-place confirm under its trigger, for
removing, revoking, resetting or closing **one** object whose result shows right there.
- **When to use a sheet instead:** more than one field, a list of consequences, or type-to-confirm (U53).
- **Look:** an ApCallout in `info` tone (`raised`, **no status mark, no wash**). A confirm isn't an operational
  state, and ◆/▲ mean the spacecraft or the ground, not "be careful". Destructiveness shows in the danger button and
  in the sentence.
  - The sentence is a question plus its consequence: "Remove the EARENDIL-312 provider account? Missions can't book
    with it afterwards."
  - An optional field (a required Reason) goes below the sentence.
- **Actions:** `Cancel` (secondary), then the action (danger or primary), right-aligned like a sheet footer.
  - The action's label is a verb plus its object (`Remove account`, `Revoke key`), never OK, Yes or Confirm.
  - On a phone, both share one row at 48px. If a label doesn't fit, they stack in the same order.
- **Focus:**
  - On open, focus goes to the first field, a reason included, as in the reason sheets; with no field, to Cancel.
    Never to the action (checklist A1).
  - Esc inside it means Cancel. Cancel returns focus to the trigger.
  - After the action, focus goes to the trigger if it still exists, else the caller's return target (the row's new
    state line), else the page h1.
  - It isn't a focus trap: Tab may leave it, and it stays open.
- **Semantics:** `role="group"`, named and described by its sentence. The trigger has `aria-expanded` and
  `aria-controls`. One is open at a time; opening another cancels the first.
- **Busy and refusals:**
  - While busy, the action is disabled, with "Removing…" as its reason (A7).
  - A refusal appears as a line under the sentence in a polite live region, in the refusal's own words. Focus
    doesn't move, and the confirm stays open so the operator can cancel or retry.

**ApStepBar.** Horizontal `<ol>` of steps, 40–52px high, hairline separators, display 13px .16em
`text-4`; done = mono `✓` + label; current = mono `●`, readout, `raised` bg, inset bottom white,
`aria-current="step"`; upcoming = number only. Commanding uses the same component for its seven
stations as the page header.

**ApStateTrail.** Progress pills (`st`: 30px, `raised`, `line` border, display 13px `text-2`)
joined by `→` in `line-strong`. **Progress states are gray; only outcomes carry a status mark and
color** (`■ VERIFIED`, `▲ NO ACK · RETRY`, `◆ VERIFY FAILED`, hatched `UNVERIFIABLE · NO TLM`).

**ApEmptyState [decision].** Inside the panel body: `lbl` headline stating the fact ("No passes in
the next 2 h"), one `text-3` sentence on why/what next, optional secondary button. For "not set up"
use the `off` mark and an Install action. Never an illustration, never "Nothing here!".

### Visualizations
**ApFleetMatrix.** Rows = planes (label mono 10px, selected plane readout), 50 square cells per row,
gap 2px. Cell: nominal `nominal-bulk`; caution fill; crit fill + 1px crit outline offset 1.5px;
stale `stale-deep` + hatch + stale border; live = 1px white outline offset 1.5px (combines with any
state); empty slot `cell-empty`; not-yet-heard = dashed `off` border. **Text never sits directly on a hatch** (any viz: matrix, Gantt bars, bands): a label over a hatched mark goes in a span with the mark's solid base (`stale-deep`, etc.) behind it, so it keeps its 4.5:1 against the base, not against the stripes. Hover/focus shows an
inspector with name, SCID, state word, last TLM. Always paired with a stat strip carrying the counts.

**ApPassStrip / ApGantt.** Rows = stations (code mono 11; degraded station code in caution text),
lane 28–30px `vacuum` with `hairline-faint` border. Bars (mono 10px label = spacecraft number):
scheduled `line-strong` outline + scheduled wash, `text-2`; live/AOS solid white, dark text,
600; conflict dashed caution border + caution wash + caution text; outage band red hatch; maintenance
amber hatch; unusable window dark hatch. Now-line 1px white extending 3–4px beyond the lane. Axis:
major/minor tick gradient + mono 10px `02:00Z … 04:00` labels. Gaps (longest silence) drawn as a
1px line with a mono label, caution when over the profile's limit.

**ApTimeSeries.** Plot well `vacuum` + `hairline-faint` border; grid lines `hairline-faint`;
primary series white 1.8px; comparison series `text-4` 1.2px; limits as dashed lines (caution
yellow, crit red) with a crit wash below the red limit; umbra bands `viz-umbra`; now-line white.
Legend below in mono 11 `text-3`. Range control = `micro` segmented; x-axis labels in orbits
(`ORB 4,808`) when the context is a spacecraft, otherwise UTC.

**ApConstellation.** SVG: Earth disc `viz-earth`, night side `viz-night`, back orbits dimmed, the
selected plane in white, dots sized by state (crit 3.5 > caution/stale/live 2.6 > nominal 1.8),
crit dots get a diamond ring and a leader-line label `EARENDIL-047` in crit text. Toggle
`Planes │ Ground track`. Legend bottom-left in mono 11.

### Overlays
**ApPalette (⌘K).** Modal dialog (`aria-modal`), dimmed backdrop over the still-visible console.
Header strip mono `CADENCE // QUERY` + scope counts. Input row: `›` prompt, sans 18px input, `ESC`
kbd. Results grouped (Spacecraft, Telemetry, Actions, Commands, Stations, Pages) under `grp` labels
(display 12 .2em with trailing hairline). Result row: 28px icon box (stroke icon tinted by the
object's state), mono title + sans 13 subtitle, right hint (`SCID 312`, `PLOT`, `⌘↵`, `G C`). Active
row `raised-hi` + 2px white left bar. Footer hints: `↑↓ MOVE · ↵ OPEN · ⌘↵ COMMAND IT · G N · G C ·
[ ]`. Empty: "No matches" + a hint naming real examples. Results are **actions**, not just
pages.

**ApTimePicker.** Trigger field 44px (clock icon, `2026-10-23 02:59:40Z`, relative `T−00:38:10`
right in mono). Dialog: type-a-time input (`now+2h`, `T+38m`, `2026-10-24 06:00`; status
`TYPE OR PICK` / `PARSED` / `CAN'T READ THAT` in caution) + zone `choice` segmented UTC│MET│LOCAL
(MET only with a mission epoch, U7);
three columns: **mission presets first** (Now, Next AOS, Umbra entry/exit, +1 orbit, Shift change,
from the spacecraft in context), month calendar (ticks under days with queued uplinks; today
bordered; selected white), and hh:mm:ss spinners (34px tabular). Summary UTC / From now / MET.
Umbra/no-pass warning as a crit callout. Footer: key hints + Cancel + primary `Set 10-23 02:59:40Z`.
Range variant: `choice` presets (Last pass, Last 1h, 1 orbit, 6 orbits, Around alarm, 24h) + From/To
fields + a 24h brush track showing umbra and passes. Ranges snap to orbits and passes.

---

## 8. Content rules

- Headlines state the situation, not the page name: "3 spacecraft need you", "Ready for operations",
  "Catalog v14 → v15". The page name lives in the `lbl` above it.
- Sentences are short, active, specific, and say why it matters: "Solar array current fell 18%
  since orbit 4,808, so the battery isn't recharging in sunlight."
- Buttons are verbs with the consequence and scope: `Prepare · 312 + 3 sisters`,
  `Stage v15 for Block 2`, `Fix all 3 before staging`.
- Group 1,000 identical findings into one line by cause. Never list per spacecraft what a profile
  rule fixes.
- Optional is not a warning: label suggestions "Optional ·" with the `optional` mark.
- Raw ids (`profile-earendil-block-1`, `sc_01J9…F3Q`) only in "Technical details".

## 9. Mobile (J6)

Below 768px: no rail; bottom tab bar (58px items, display 11px, active inset top white). Content is
one column, alarm-first. Buttons 48px, full width. Building new uplinks is deliberately absent on
mobile: GO / NO-GO, acknowledge and hand-off only. Detailed in `screens/Mobile.md`.

**Sheets below 768px (ApSheet, every sheet; lead and dashboards' D2, 11-15): full-height**, never a bottom sheet with
a max height. A sheet holds reasons, type-to-confirm and forms, and a short bottom sheet puts the field under the
on-screen keyboard.
- Edge to edge, sized to `100dvh`, so it shrinks with the keyboard instead of sitting behind it.
- The title row (title + close ✕, 48px) is pinned at the top. The action row (safe button + action, full width,
  48px) is pinned at the bottom, above `env(safe-area-inset-bottom)`.
- Only the body between them scrolls: one scroller. A focused field scrolls into view above the action row.
- No drag-to-dismiss and no backdrop tap: close, Cancel or Esc, as on desktop.
- The non-modal side sheet (Dashboards' Widget sheet) is modal at this width, since the board can't sit beside it.
  It then traps focus (a11y checklist A3) and takes `aria-modal`.
- The `⋯` action menus aren't sheets and stay popovers.

## 10. Do / Don't

| Do | Don't |
| --- | --- |
| Encode state as mark + color + word | Color a cell, dot or text without a shape or word |
| Show stale and "not set up" explicitly | Show 0, an empty chart or green when data is missing |
| Use white for the one primary action and for "live" | Use a status hue for a button, link, brand or chart series |
| Fit console screens to the viewport; scroll panes | Let the page scroll on Now / Investigate / Command / Uplink |
| Put the commit action next to the state that justifies it | Put commit buttons in a far-away footer or modal on console screens |
| Use tile grids with 1px hairline gaps | Draw rounded cards, drop shadows, gradients, glow |
| Format time with the shared formatter, UTC + Z + T± | Use locale dates, 12-hour clocks, "5 minutes ago" |
| Show name + SCID on every target row | Show `SCID —`, raw ULIDs or ids twice |
| Write "1 target" / "2 targets" | Write "1 targets" |
| Label every icon control | Ship an unlabeled icon (review findings #9, #11) |
