# Cadence Design System

The canonical visual reference for Cadence's HUD aesthetic — Tokyo Night /
vaporwave dark, hot-pink accent, sharp 2px corners, monospace data, cyan glow.

These are **self-contained HTML preview cards**. Each renders standalone (no
build step) so it can be synced to a [Claude Design](https://claude.ai/design)
project via the `DesignSync` tool and browsed as a visual card.

## What this is (read first)

This design system is a **distillation of two things, held together**:

1. **Where the implementation is today** — the frozen CSS, design tokens,
   component layer, and page recipes as they actually exist in the app.
2. **Where the design is going** — decisions made but not yet shipped: the
   skin/outfit/body token architecture, the accessibility fixes, and the
   data-visualization foundations.

A future session should be able to open this and tell, for any area, *what is
real today* from *what is the agreed target*. That is what the status markers
are for. The implementation source of truth remains the app itself:

- **Tokens** — `apps/cadence_web/assets/css/app.css` (`:root` + `@theme` + the
  daisyUI `dark` theme block).
- **Frozen CSS** — `apps/cadence_web/assets/css/components/` (closed set; see
  rule 1 in `CLAUDE.md`).
- **Component layer** — `apps/cadence_web/lib/cadence_web/components/`.

When the code and the system diverge, update the matching card in the same PR —
that discipline is what keeps the distillation honest.

## Status & direction

**One source of status: `overview/system-status.html`** — the per-area map
(✅ implemented · 🎯 decided-not-built · 🧭 exploring) and the sequenced
backlog live there and only there. Don't duplicate that table here or in
`IMPLEMENTATION.md`; update the card as work lands. Cards with no status tag
are ✅ Implemented (a straight distillation of current code); cards that mix
states carry per-section `current` / `proposed` tags.

## Card index

Every card's first line is an `@dsCard` marker that places it in a group on
claude.ai/design.

### Principles
- `principles/principles.html` — the six north-star rules that adjudicate decisions.

### Foundations
- `foundations/token-architecture.html` — the skin / outfit / body split: three
  token tiers, the downward dependency rule, and the "which layer?" litmus test.
- `foundations/semantic-tokens.html` — the Outfit (semantic role) layer, step 1
  of the split. **Seeded in `tokens.css`; component migration is Phase 5.**
- `foundations/effect-tokens.html` — step 2: the flourishes (glow, label casing,
  pulse) as dial-able Skin knobs, plus the `prefers-reduced-motion` handling and a
  `[data-skin="legible"]` mode. **Shipped in `tokens.css` / `app.css`.**
- `foundations/data-viz-charts.html` — telemetry chart anatomy, the series palette
  (identity ≠ status), and limit overlays. Grounded in `telemetry_chart.js`.
- `foundations/telemetry-states.html` — the three orthogonal value axes (limit ×
  quality × freshness) and how to render them together. Grounded in
  `limits/evaluator.ex` + `telemetry/sample.ex`.
- `foundations/color.html` — primitive color ramps (hue-named, contrast-verified); the swatch reference for the scale model.
- `foundations/color-scale-model.html` — the two-tier color system (hue primitives → functional semantics) + oklch derivation rules.
- `foundations/choosing-color.html` — color selection rules + the cyan double-duty resolution (saturation = the interactive signal).
- `foundations/content-terminology.html` — voice, the noun glossary, and time/number/copy conventions.
- `foundations/layering.html` — depth model: elevation vs stacking, the ideal scale + Cadence's deltas.
- `foundations/stacking-tokens.html` — the `--z-*` tier scale + scrim (spec).
- `foundations/elevation-tokens.html` — elevation levels, state-layers, top-highlight (decisions locked).
- `foundations/motion.html` — duration, easing, liveness pulses, reduced-motion.
- `foundations/reduced-motion.html` — the audit + the applied `prefers-reduced-motion` block. **Implemented.**
- `foundations/typography.html` — type scale, `hud-label`, monospace data values.
- `foundations/spacing.html` — the `--space-*` scale.
- `foundations/radii.html` — the 2px sharp-corner system.
- `foundations/glows.html` — cyan/purple/pink glows + `hud-corners`.
- `foundations/status.html` — status colors, dots, and pulse animations.

### Components
- `components/button.html` — `<.button>` variants, sizes, states, and link mode.
- `components/inputs.html` — `<.input>` types (incl. textarea/checkbox), states, and error display.
- `components/status-badge.html` — `<.status_badge>` readiness pills.
- `components/severity-badge.html` — `<.severity_badge>` diagnostic counts.
- `components/card.html` — `<.card>` chrome, headers, and the nav/hero corner rule.
- `components/stat-tile.html` — `<.stat_tile>` metric tiles.
- `components/table.html` — `<.table>` data table, sorting, and LiveStream rows.
- `components/page-header.html` — `<.page_header>` breadcrumbs, title, suffix, actions.
- `components/list-controls.html` — `<.toolbar>` + `<.pagination>` and the URL-as-source-of-truth list-state contract.
- `components/form-helpers.html` — `<.form_section>` numbered headings + the `<.form_actions>` submit/cancel footer.
- `components/empty-state.html` — `<.empty_state>` no-rows placeholder, incl. the compact variant.
- `components/action-menu.html` — `<.action_menu>` row-actions dropdown with its keyboard/ARIA contract.
- `components/callout.html` — `<.callout>` inline contextual message (replaced raw daisyUI alerts).

Every component card carries a **Usage** do/don't panel lifted from the rules in
`CLAUDE.md` — the "when and why," not just the "what." Keep those panels in sync
when the rules change.

### Patterns
- `patterns/list-page.html` — the canonical list screen: `page_header` + flush
  `card` wrapping `toolbar` → `table` → `pagination`, plus the empty-state
  variant. Mirrors `CadenceWeb.CommsTransportListLive` /
  `CadenceWeb.SpacecraftListLive`.
- `patterns/detail-page.html` — the canonical show screen: `page_header`
  (breadcrumbs + identifier suffix), an optional workflow-status row of cards
  (status carried by the chip alone), then a main/sidebar split with an Overview
  `hud-data-row` definition grid. Mirrors `CadenceWeb.SpacecraftShowLive` /
  `CadenceWeb.CommsTransportShowLive`.
- `patterns/form-page.html` — the canonical create/edit screen: a narrow
  `max-w-2xl` `<.form>` of numbered `<section>` field groups (bare, not
  card-wrapped) closed by a submit/cancel actions row. Mirrors
  `CadenceWeb.CommsTransportNewLive` / `CadenceWeb.SpacecraftEditLive`.

Patterns are compositions larger than a single component — the recurring page
recipes (list, detail, form, dashboard). They're where consistency actually
bites for a multi-page app, so they document the *arrangement* and the
state-ownership contract, not just the parts.

## Implementation & enforcement

- **`assets/css/tokens.css`** — the token source of truth (primitives →
  semantics → systems), imported by `app.css`. `--color-action`, the `--z-*`
  tiers, and the effect knobs are consumed throughout; the remaining semantic
  roles (`--status-*-fill`, `--border-*`, `--on-*`, `--duration-*`/`--ease-*`)
  are seeded and await the Phase 5 component migration.
- **Checks** (all warn-only until Phase 6; `sh scripts/check-design-system.sh`
  runs the lint and the drift check):
  - `scripts/check-design-system.sh` — raw color literals, `z-[n]`, raw
    inputs, Tailwind `uppercase` (bypasses `--label-case`).
  - `scripts/contrast-check.mjs` — WCAG audit that **parses the shipped CSS**
    (tokens + overrides), so token changes are re-audited automatically.
  - `scripts/check-card-drift.mjs` — every `oklch()` literal in these cards
    must exist in the authored CSS; stale mirrors get flagged. Annotate
    deliberate non-token illustrations with `ds-allow` on the line.

See `overview/system-status.html` for the per-area map and the sequenced
backlog, and `IMPLEMENTATION.md` for the narrative of what's been applied.

## Syncing

Use the `DesignSync` tool (with the `/design-sync` workflow): create or pick a
design-system project, finalize a plan scoped to `apps/cadence_web/design-system/**`,
then `write_files`. Sync incrementally — one component at a time, never a
wholesale replace.
