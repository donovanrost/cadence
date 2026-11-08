# Catalog · import and diff (S3 · know the blast radius)

Routes: index `M/setup/catalog` · import `M/setup/catalog/import` (upload) →
`M/setup/catalog/import/:importId` (validation + diff) · database `M/setup/catalog/:databaseId`.
Setup rail 04 (count = current revision, `rev 14`) · **reading layout**, in-shell (U5) ·
Board `Catalog.dc.html`. Owner: fe-setup. Data and gaps: `docs/apogee/plans/setup.md` §S3.

**Question:** "What does this new FSW database change, and what will it break?"
**Journey:** drop an XTCE/CSV export → Cadence parses and validates → read the diff against the live
revision, riskiest first → see impact on live config → choose rollout and stage/apply.

## A · Catalog index (`M/setup/catalog`) — not on the canvas
Header: lbl `EARENDIL · CATALOG`, h1 `Catalog revision 14` (current), subline `547 declarations ·
212 commands · 335 telemetry points · applied to 500 spacecraft` (parts omitted when unknown),
primary `Import a new revision`.
Panels: **Revisions** (ApTable: Revision (link), Label, Source file (mono), Declarations, Used by
(spacecraft count), Imported (time + actor)); **Import runs** (ApTable: File, Status tag
(`Parsing`, `Valid`, `Failed`), Diagnostics count, Started). Databases, if a mission has several,
are a `choice` segmented above the tables.
Empty: "No catalog yet" + "Commands and telemetry come from an XTCE or CSV export of your flight
software database." + primary `Import a catalog`.

## B · Upload (`M/setup/catalog/import`)
Single panel `Source file`: drop zone (dashed `line` border, 160px, "Drop an XTCE (.xml) or CSV
export, or choose a file", 50 MiB limit stated), accepted formats as chips, then `Upload and
validate` (commit size). On upload → route to `…/import/:importId`. While parsing: status line
mono `PARSING · 1.8 MB · 00:04` + live progress via the import-run channel.

## C · Validation + diff (`…/import/:importId`)
```
breadcrumb CATALOG / IMPORT rev 15
h1 "Catalog rev 14 → rev 15"                                     [Replace file]
file line: earendil_fsw_3.2.0.xtce.xml · XTCE 1.2 · 1.8 MB · parsed and validated, no schema errors
stat strip ×4: Commands 212→218 (+7 ~4 −1) │ Telemetry 335→341 │ Unchanged 517 of 547 │ Breaking 3
┌ C1 Diff (flex 999 1 640) ──────────────┐ ┌ aside (flex 1 1 340) ─────────┐
│ tabs All 30 · Breaking 3 · Added 16 …  │ │ C2 Impact on live config      │
│ table op · kind · name · change · used │ │ C3 Roll out to (options, CTA) │
└────────────────────────────────────────┘ └───────────────────────────────┘
```
Naming **[decision]**: we say `rev 15`, not `v15`, because the model has catalog *revisions*;
the canvas's `v14` was illustrative.

### Header and file line
- h1: `Catalog rev <current> → rev <new>`; first import ever: `Catalog rev 1`.
- File line: file name (mono, readout), format + version, size, validation verdict.
- Validation failed: replace stat strip + diff with a crit callout "This file can't be imported:
  N errors" and a **Diagnostics** ApTable (Severity mark+word, Code mono, Message, Path mono). Warnings
  on a valid file show as a caution callout above the diff with `Show N warnings` (expands the same
  table).

### Stat strip
Commands `a → b` + caption `+7 · ~4 · −1`; Telemetry points likewise; Unchanged `517` / `of 547
declarations`; Breaking `3` (caution tint + bar when > 0) / `in use by live config`. Per-kind counts
missing (ops gap) → one tile `Declarations a → b` instead of two. Breaking unknown (no rule set yet)
→ tile omitted.

### C1 · Diff (panel)
Header meta `SORTED BY RISK`. Tabs (`tabs` variant) with counts in the labels. Table columns:
op glyph (mono 15/600: `+` `~` `−`; `+` in `text-3`, `~` readout, breaking rows caution) · kind
(`CMD` / `TLM` small mono box) · name (mono 13, wraps) · change (sentence, `text-2`: `arg duration:
u16 seconds → u32 milliseconds`) · used by (`40 queued uplinks · 1 procedure`; caution when
breaking; `not used yet` / `unused · safe` in `text-3`).
Breaking rows: caution wash. Sort: breaking → changed-in-use → removed → changed → added. Shows the
first 9, footer "21 more, all additions or unused" + `Show all 30`.
- **Data:** `{from_revision, to_revision, counts: {commands: {from, to, added, changed, removed},
  telemetry: {…}, unchanged, total, breaking}, changes: [{op, kind, name, change_text, breaking,
  used_by: [{kind, count, label}] | null}]}`.
- `used_by` null (no cross-refs yet) → the column is **dropped**, and the sort is breaking → removed
  → changed → added.

### C2 · Impact on live config (panel)
Rows: object count title (`40 queued uplinks`) + verb tag (`▲ BREAKS`, `▲ UPDATE`, `▲ REMAP`) +
sentence. Footer `Fix all 3 before staging` (secondary). **Hidden until cross-references exist**
(plan: phase 2); the aside then starts with C3.

### C3 · Roll out to (panel)
ApOption radio cards: the recommended subset first ("Earendil Block 2 first · 50 SC" +
"Recommended. Runs rev 15 on the new batch while Block 1 stays on rev 14.") and "All spacecraft ·
550 SC" (disabled with reason when breaking items are unfixed: "Needs the 3 breaking items fixed
first"). Options are generated from profiles (grouping spacecraft by profile) since catalogs are set
per spacecraft today. Primary commit button: `Stage rev 15 for Block 2` under option A, or
**`Request activation for 50 spacecraft`** under option B (U2: goes through the existing
draft/review/activate flow per spacecraft configuration). Caption mono 11: `REV 14 KEPT FOR
ROLLBACK`.

## States
Parsing (live), Valid, Valid with warnings, Failed (diagnostics), Already applied (read-only diff
with a nominal callout "Applied to 50 spacecraft on 10-19 02:29Z by Mira K."). Leaving mid-import
keeps the run; the index lists it.

## Acceptance (for qa)
- Upload → validation → diff without a page reload; progress is live.
- Breaking changes sort first and carry caution mark + wash + word.
- Panels whose data doesn't exist (impact, used-by) are absent, not empty.
- Rollout options state their consequence; a blocked option says why.
