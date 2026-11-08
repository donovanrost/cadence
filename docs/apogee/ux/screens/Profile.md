# Spacecraft Profile (S4 · edit once, apply to 500)

Routes: list `M/setup/profiles` · profile `M/setup/profiles/:profileId/:section` with
`section ∈ framing | routing | limits | commanding | catalog | overrides` (default `framing`) ·
history `M/setup/profiles/:profileId/history`. Setup rail 03 (count = profiles) · **reading layout**
· Board `Profile.dc.html`. Owner: fe-setup. Data: `docs/apogee/plans/setup.md` §S4.
Scope: DECISIONS #1 (change sets, v1 seam), #3 (**routing rules live on the profile**, materialized
per spacecraft, with per-spacecraft overrides). "Profile" in the UI = Spacecraft Profile
(Spacecraft Type in the model).

**Question:** "Change routing / framing / limits for the whole block, and know exactly who it
affects." **Journey:** open the profile → each section shows what inherits it → overrides are the
listed exception → stage, see the per-spacecraft effect, apply.

## Profile list (`M/setup/profiles`) — not on the canvas
Header: lbl `EARENDIL · PROFILES`, h1 `2 profiles`, primary `New profile`.
ApTable: Name (link) · Version (`v4`, mono) · Spacecraft (inherit count) · Overrides (count;
caution text when > 10% of its fleet **[decision]**) · Catalog (`rev 14`) · Protocols (`CCSDS TM /
TC`) · Last changed (`r5` or `v4 · 10-19 02:29Z`). Empty: "No profiles yet" + "A profile holds the
configuration a block of spacecraft shares." + `New profile`.

## Profile page
```
breadcrumb PROFILES / EARENDIL BLOCK 1
h1 "Earendil Block 1"                          [Duplicate as new profile] [History]
subline: 500 spacecraft inherit this profile · 3 override it · catalog rev 14 · last changed in r5
┌ local nav ┐ ┌ section panels (flex 999) ───────────┐ ┌ P4 Staged edit (aside, while dirty) ┐
│ Framing   │ │ P1 Framing · CCSDS TM / TC           │ │                                      │
│ Routing   │ │ P2 Routing rule                      │ │                                      │
│ Limits    │ │ P3 Overrides                         │ │                                      │
│ ...       │ └──────────────────────────────────────┘ └──────────────────────────────────────┘
```
- **Subline** (14px `text-3`, counts bold readout): inherit count, override count (link → Overrides),
  catalog, last change (`in r5` with change sets; `v4 · 10-19 02:29Z by Donovan R.` in v1).
- **Local nav** (`local`): links 13px display, left 1px hairline; active 2px white left border +
  readout. `Overrides · 3` carries its count. Sticky within the page. Each section is its own route;
  the board's stacked view is the Framing route showing Framing + summaries of Routing + Overrides
  **[decision: one section in full, the others as summary panels linking to their route]**.
- **Actions:** `Duplicate as new profile` (→ new-profile form prefilled), `History` (→ versions /
  revisions touching this profile). Read-only without `config.stage` (Changes.md §5).

### P1 · Section form (Framing shown; Limits, Commanding, Catalog use the same pattern)
Header meta: `INHERITED BY 500 · 1 EDIT STAGED`. Body is a 2-column **key/value tile grid** (1px
hairline gaps): `lbl` + inline input (mono 14 for values). Fields come **only** from the server's
section schema (`docs/apogee/domain/profile-routing.md` §3: path, label, type, unit, enum, range,
default, overridable, runtime_impact, help), so the form is generated, never hand-written. Framing
today = TM transfer frame, TC transfer frame, packet protocol, TM frame length, secondary header,
insert zone, OCF, truncated primary header. **The canvas's spacecraft-id source, virtual channels,
FEC, TC segment and randomizer have no model backing: don't render them.** Fields with
`runtime_impact: generation` show a mono `RUNTIME` chip; changing one triggers a runtime
generation on apply.
- **Limits section:** read-only notice "Limits apply mission-wide per point; per-profile limits
  aren't supported yet." + link to the Limits app (profile-routing §3). **Commanding section:** only
  app-declared settings; omit the nav item when there are none. **Catalog section:** the
  `catalog_revision_id` reference field. **Edited** = inset 3px white bar +
`raised` bg + label `· edited` + old value struck mono `text-4` before the input. **Staged** (after
Stage) = same, label `· staged`. Invalid = caution border + message under the field; can't stage.
Fields where some spacecraft override the value show a mono chip `2 override` linking to P3
filtered.

### P2 · Routing rule (DECISIONS #3)
Header meta: `1 RULE → 3,000 ROUTES`. The rule reads as a sentence in mono, keywords in `text-4`:
```
FOR EACH  spacecraft in Earendil Block 1
AND EACH  station in [SVB, FBK, AWA, PUQ, HBK, INU]
ROUTE     downlink · primary   uplink · primary
NAME      "{station} · {spacecraft}"
```
Legs are **direction + role** (`downlink|uplink` × `primary|candidate|contributing`); the canvas's
"→ archive / ← console" destinations aren't a model concept (profile-routing §5). Transport comes
from each station.
Edit mode turns each line into controls: station multi-select chips (station `code`, removable,
`+ station`), a direction + role select per leg (`+ leg`), name template field with token chips (`{station}`,
`{spacecraft}`, `{scid}`) and live preview. **Generates**: three sample route names (mono chips) +
`+ 2,997` (`text-3`). (The canvas's "Protocol behavior" line is dropped: a retired concept.)
A disabled rule renders dimmed with `DISABLED`. Multiple rules on one profile stack as
separate rule blocks, each with its route count.
- **Data:** `rules: [{id, stations: [{id, code, name, transport_id}], legs: [{direction, role}],
  name_template, route_count, samples: [string], enabled}]` (profile-routing §5).

### P3 · Overrides
Header meta `3 OF 500 DIFFER FROM THE PROFILE`. Rows `ov` (`150px | 1fr | auto`): spacecraft link
(mono) · what differs, as a sentence ("Routing excludes SVB", "TM frame length 1,115 instead of
1,279"; no limit overrides, which aren't backed) + mono `since r3` / `since v2` · `Reset`
(compact; stages a reset). Grouped by section when > 10 rows, with a filter box.
- **Data:** `overrides: [{spacecraft: {id, name}, section, path, profile_value, spacecraft_value,
  reason, since_revision, set_at, actor, redundant}]`. `redundant: true` (override equals the
  profile value) shows an `optional` row "Same as the profile now · Reset to inherit".
- **Empty:** nominal callout "All 500 spacecraft match the profile."

### P4 · Staged edit (aside; only while there are dirty fields)
As `Changes.md` §1: field path (mono), `− old` / `+ new`, tiles `Changes 499 SC` / `Keeps 1 SC`
(server dry-run), check callouts (compatibility, readiness), keeps explanation (which overrides
survive), primary `Stage edit` (v1: `Create version v5`, then "pinned spacecraft move to v5 when
you apply it" per the model's answer), secondary `Discard`. Multiple dirty fields list one block
each; one Stage for all.

## History (`…/history`)
Versions (v1) or revisions (change sets) touching this profile: rev/version, when, who, why, the
field diffs. `Compare` two. In v1, also `Pin spacecraft to v5` per version if the model keeps
version pinning.

## States
Loading per panel (`LOADING…`). Read-only (no capability): inputs render as text, the Stage aside
never appears, a `text-3` line under the header says who can edit. Conflict (someone staged the
same field): the field shows a caution chip `Mira K. staged 1,200` and Stage is blocked until
resolved on the review page.

## Acceptance (for qa)
- Every section states how many spacecraft inherit it; overrides are always counted and listed.
- One routing rule edit shows the generated route count and samples before staging.
- Effect counts (`changes N · keeps M`) come from the server, never computed in the browser.
- No per-spacecraft routing UI anywhere except overrides.
