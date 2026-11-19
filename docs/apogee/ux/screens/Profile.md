# Spacecraft Profile (S4 · edit once, apply to 500)

Routes: list `M/setup/profiles` · profile `M/setup/profiles/:profileId/:section` with
`section ∈ framing | routing | limits | commanding | catalog | overrides | history` (default `framing`; History is
a section tab, as built) · new `M/setup/profiles/new`. Setup rail 03 (count = profiles) · **reading layout**
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
configuration a block of spacecraft shares. Every spacecraft pins one." + `New profile`.
- As built, also: "N on older versions" under the Spacecraft count, and "Set per spacecraft" in Catalog when the
  profile sets no catalog. The Protocols column reads `CCSDS TM / TC` (ux, audit P7; the built "TM ↓ · TC ↑" is a
  console item).

## New profile (`M/setup/profiles/new`) — not on the canvas
A new profile starts as a copy (`Duplicate as new profile` opens it prefilled):
- Start from: the profiles to copy. With none: "No profile to start from" + "A new profile starts as a copy…".
- The name defaults to "Earendil Block 1 (copy)". The line under it: "Copied from Earendil Block 1 v4: its fields,
  routing rules and app settings. No spacecraft use it until you assign them."
- Primary `Stage new profile`, with "Nothing is live until the change set is applied." under it.

## Profile page
```
breadcrumb PROFILES / EARENDIL BLOCK 1
h1 "Earendil Block 1"                          [Duplicate as new profile]
subline: 500 spacecraft inherit this profile · 3 override it · catalog rev 14 · last changed in r5
┌ local nav ┐ ┌ section panels (flex 999) ───────────┐ ┌ P4 Staged edit (aside, while dirty) ┐
│ Framing   │ │ P1 Framing · CCSDS TM / TC           │ │                                      │
│ Routing   │ │ P2 Routing rule                      │ │                                      │
│ Limits    │ │ P3 Overrides                         │ │                                      │
│ ...       │ └──────────────────────────────────────┘ └──────────────────────────────────────┘
```
- **Subline** (14px `text-3`, counts bold readout): inherit count, override count (link → Overrides),
  catalog, last change (`in r5` with change sets; `v4 · 10-19 02:29Z by Mira K.` in v1).
- **Local nav** (`local`): links 13px display, left 1px hairline; active 2px white left border +
  readout. `Overrides · 3` carries its count. Sticky within the page. Each section is its own route;
  the board's stacked view is the Framing route showing Framing + summaries of Routing + Overrides
  **[decision: one section in full, the others as summary panels linking to their route]**.
- **Actions:** `Duplicate as new profile` (→ the new-profile form, prefilled). History is a section tab (→ versions
  and revisions touching this profile), not a header action. Read-only without `config.stage` (Changes.md §5).
- The subline adds "N on older versions" when some spacecraft are pinned to an older version, and "catalog set per
  spacecraft" when the profile sets no catalog.

### P1 · Section form (Framing shown; Limits, Commanding, Catalog use the same pattern)
**Framing is editable** like the other sections (DECISIONS #19 lifted; lead b2f92dba). Only when the mission's
settings keep profile framing out of the runtime (ST1 `profile_framing_generations` off), an info note reads:
"This mission's settings keep profile framing out of the runtime, so changing it here doesn't change how
telemetry is decoded." with the link `Mission settings`.
Header meta: `INHERITED BY 500 · 1 EDIT STAGED`. Body is a 2-column **key/value tile grid** (1px
hairline gaps): `lbl` + inline input (mono 14 for values). Fields come **only** from the server's
section schema (`docs/apogee/domain/profile-routing.md` §3: path, label, type, unit, enum, range,
default, overridable, runtime_impact, help), so the form is generated, never hand-written. Framing
today = TM transfer frame, TC transfer frame, packet protocol, TM frame length, secondary header,
insert zone, OCF, truncated primary header. **The canvas's spacecraft-id source, virtual channels,
FEC, TC segment and randomizer have no model backing: don't render them.** Fields with
`runtime_impact: generation` show a caution tag `Cancels queued commands` (as built; it says the effect, where
`RUNTIME` named the mechanism), with the generation note as its title. P3's override rows use the same tag.
Changing one triggers a runtime generation on apply.
- **Catalog section** carries a callout: "A catalog change goes through a change set…" (as built).
- **Conflict with a staged edit:** "Mira K. already staged 1,200. Resolve it on Staged changes first." (as built).
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
- A disabled rule's `DISABLED` tag (off, mark + word) keeps the built sentence "This rule is disabled; it generates
  no routes." as its secondary line (ux, audit P7).
- As built, the editor also has: the tokens `{station_name}` and `{direction}`; "Roll out to: All spacecraft on this
  profile / New version only"; `Check with the server`; and the primary `Stage rule change`.
- **Routing still set per spacecraft** (a profile with no rules while its spacecraft carry their own; as built):
  "Routing is still set per spacecraft" with `Add a profile rule` and `Open comms & routing`. It's the one place
  per-spacecraft routing shows outside overrides, until the profile has a rule.

### P3 · Overrides
Header meta `3 OF 500 DIFFER FROM THE PROFILE`. Rows `ov` (`150px | 1fr | auto`): spacecraft link
(mono) · what differs, as a sentence ("Routing excludes SVB", "TM frame length 1,115 instead of
1,279"; no limit overrides, which aren't backed) + mono `since r3` / `since v2` · `Reset`
(compact; stages a reset). Grouped by section when > 10 rows, with a filter box.
- **Data:** `overrides: [{spacecraft: {id, name}, section, path, profile_value, spacecraft_value,
  reason, since_revision, set_at, actor, redundant}]`. `redundant: true` (override equals the
  profile value) shows an `optional` row "Same as the profile now · Reset to inherit".
- **Empty:** nominal callout "All 500 spacecraft match the profile."
- **Add override** (director; fe-setup 15e3721f): compact header button `Add override` (only with `config.stage`).
  It opens a form panel above the list. The form panel has no index of its own; the list keeps P3.
  - Fields:
    - `Spacecraft`: mono select of this profile's spacecraft, hint `500 on Earendil Block 1`.
    - `Field`: `<label> · <section>`, with Catalog revision first.
    - The value, generated from the schema. A catalog revision is a select of revisions (`rev 4 · imported
      11-10`), never a raw id (U25). Fields with `runtime_impact: generation` carry the same
      generation tag as P1 (`Cancels queued commands`), beside `Profile value`.
    - `Why this spacecraft differs`: required, with the hint "Shown on the override and in the change set."
      and no placeholder.
  - The value starts at the profile's value, with `Profile value: rev 3` under it. If the chosen spacecraft
    already overrides that field, the value starts at its current override instead, and an info line reads
    "EARENDIL-001 already overrides this: rev 4 since r3 (Mira K.: <reason>)". The primary then reads
    `Stage change`, and the summary reads `EARENDIL-001 · change override Catalog revision`. Nothing is
    replaced silently.
  - Actions: `Check` (dry run), primary `Stage override`, ghost `Cancel`. Stage is disabled with its reason
    until a spacecraft is chosen, the value is valid and differs from the profile ("Same as the profile's value.
    Enter the value this spacecraft should use."), and the reason is filled in. It also stays disabled while
    the last Check is NO-GO. Stage opens Changes.
  - The change summary reads `EARENDIL-001 · override Catalog revision`.
  - Profiles whose spacecraft set their own routing (fe-setup 26e9ef92) list and offer catalog and framing
    overrides only, with an info line: "This profile's spacecraft set their own routing, so routing isn't
    overridden here. Catalog and framing overrides work." Don't promise a future change (U20).
  - Field reasons (as built): "Choose a spacecraft.", "Say why this spacecraft differs.", "That's its override
    already."
  - **Reset** stages a reset; the row then reads "Reset staged for EARENDIL-001. It applies with the change set."
  - Rows and options use field and choice labels, never paths or ids. Catalog revisions read `rev 4 ·
    imported 11-10` (server label, asked of api). `rN` is reserved for change-set revisions, so a catalog
    revision is never `r4`.

### P4 · Staged edit (aside; only while there are dirty fields)
As `Changes.md` §1: field path (mono), `− old` / `+ new`, tiles `Changes 499 SC` / `Keeps 1 SC`
(server dry-run), check callouts (compatibility, readiness), keeps explanation (which overrides
survive; a framing edit's `framing_governed` keeps read "2 keep their framing: it's set in their own
configuration review.", DECISIONS #45), primary `Stage edit` (v1: `Create version v5`, then "pinned spacecraft move to v5 when
you apply it" per the model's answer), secondary `Discard`. Multiple dirty fields list one block
each; one Stage for all.

## History (the `history` section)
Versions (v1) or revisions (change sets) touching this profile: rev/version, when, who, why, the
field diffs. `Compare` two (→ `revisions/rA...rB`). **No per-version "Pin spacecraft to vN"** (ruled after
fe-setup's question): pinning back multiplies version drift (499 of 500 are already on older versions). The tools
are a change-set rollback for everyone, and a P3 override for a few. Each version row says how many spacecraft
are on it (`12 spacecraft on v5`), so drift is visible.
- As built: the newest row carries `· latest`; a missing author reads "Not recorded"; with no revisions, "No revisions
  yet"; each row links "Compare with rN →".

## States
Loading per panel (`LOADING…`). Read-only (no capability): inputs render as text, the Stage aside
never appears, a `text-3` line under the header says who can edit. Conflict (someone staged the
same field): the field shows a caution chip `Mira K. staged 1,200` and Stage is blocked until
resolved on the review page.

## Acceptance (for qa)
- Every section states how many spacecraft inherit it; overrides are always counted and listed.
- One routing rule edit shows the generated route count and samples before staging.
- Effect counts (`changes N · keeps M`) come from the server, never computed in the browser.
- No per-spacecraft routing UI anywhere except overrides, and the "Routing is still set per spacecraft" state (P2)
  until a profile rule exists.
