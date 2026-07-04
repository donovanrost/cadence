# Cadence Design System — Status & Roadmap

A narrative companion to the card index (`README.md`) and the visual compass
(`overview/system-status.html`). It explains **what the design system is, what's
been applied to the code, and what remains.**

---

## TL;DR

We built a design system as a set of visual reference cards (in
[Claude Design](https://claude.ai/design) and mirrored in `design-system/`),
made the key decisions, then began applying it to the codebase in phases.
Phases 0–4 are in code; Phase 5 (visible migrations) and Phase 6 (enforcement
lock) remain.

**Status lives in one place: `overview/system-status.html`** — the per-area
map and the sequenced backlog. This file is the narrative companion (what
happened and why), not a second status table.

**The app still renders essentially identically** — everything applied so far is
additive, opt-in, or invisible (the one visible change is a small green hue shift).

---

## Three artifacts (where things live)

1. **The cards** — the visual reference. Live in the Claude Design project and
   mirrored as self-contained HTML in `design-system/` (`foundations/`,
   `components/`, `patterns/`, `overview/`). `README.md` is the index.
2. **The token source of truth** — `apps/cadence_web/assets/css/tokens.css`,
   imported by `app.css`. Primitives → semantics → systems.
3. **The app** — `lib/cadence_web/` consumes the tokens/components.

---

## What we've done

### The design system (documentation)

- **Principles** — six north-star rules (`principles/principles.html`).
- **Foundations** — color (palette ramps, the two-tier scale model, choosing
  color), typography, spacing, radii, glows, status; the token architecture
  (skin/outfit/body) and its steps (semantic tokens, effect tokens); data-viz
  (chart anatomy, the three telemetry value axes); layering (elevation +
  stacking, with token specs); motion + reduced-motion; content & terminology.
- **Components** — button, input, the two badges, card, stat-tile, table — each
  with states and a usage do/don't panel lifted from `CLAUDE.md`.
- **Patterns** — list, detail, and form page recipes.

### Decisions locked

- **Green → hue 175** (unified the old 155/185 split). Ramps tuned and
  **contrast-verified**.
- **Cyan double-duty → saturation is the interactive signal.** Saturated cyan =
  act/live; structural chrome drops to low-chroma. (Reallocation is Phase 5.)
- **Input → a recessed well**; **hover → a translucent state-layer film**
  (replaces the absolute `--surface-hover`, which out-elevated overlays).
- **Contrast** — text tiers verified; three fixes applied (see below).
- **Token architecture** — primitives named by *hue*, semantics named by *job*;
  components consume only semantics.

### Applied to the code (Phases 0–4)

- **Phase 0 — source of truth.** Extracted `tokens.css` from `app.css`.
- **Phase 1 — seeded all token tiers** (additive, non-breaking): the color
  primitive ramps, the semantic roles (`--color-action`, `--status-*-fill`,
  `--border-*`, `--on-*`), and the systems (`--z-*`, `--duration-*`/`--ease-*`,
  `--elevation-*`, `--state-*`, `--highlight-*`, effect knobs). **Green-175
  unified** across `--status-success`, daisyUI `--color-success`, and
  `badge-success`.
- **Phase 2 — warn-mode enforcement.** `scripts/check-design-system.sh` (raw
  color literals, `z-[n]`, raw inputs) and `scripts/contrast-check.mjs`
  (oklch→WCAG audit). The blunt `check-css-frozen.sh` hook stays for now.
- **Phase 3 — mechanical migrations.**
  - All 20 `z-[n]` literals → `z-[var(--z-*)]` tiers. **Fixed the
    popover-below-chrome bug** (dashboard popovers now sit above the sidebar).
  - Parameterized the flourishes: `text-transform` → `var(--label-case)`,
    status pulses → `var(--pulse-*)`.
  - Shipped the **legibility skin** `[data-skin="legible"]` (un-uppercases +
    stops pulses; composes with `data-theme`).
  - *(Earlier, as "captured + small" applies: the three contrast fixes and the
    `prefers-reduced-motion` block.)*
- **Phase 4 — `/admin` pilot.** The pages were already component-clean, so the
  work was pattern + content conformance: org-list → list-page pattern (table +
  Name-cell link, fixing a whole-row-link rule violation), the two forms →
  form-page pattern (width + actions row + Cancel), home → monospace stats,
  empty-state actions, sentence-case labels. The pilot **surfaced and filled a
  gap**: `<.input>` had no checkbox type, so we added one (+ a `description`
  attr) and dropped the invite page's bespoke checkbox.

### Truth reconciliation (2026-07-04 review)

An external review found the docs lagging the code — status markers said
"not yet in `app.css`" for shipped work, and 52 retired hue-185 greens
survived in the cards. Applied:

- **Status consolidated** — `overview/system-status.html` is the one status
  table; README and this file now point at it. Stale markers on the
  semantic-tokens / effect-tokens / motion / stacking / elevation / layering
  cards flipped to reflect shipped code.
- **`contrast-check.mjs` rewritten to parse the shipped CSS** (tokens.css,
  app.css, component-overrides.css, hud-system.css) instead of hard-coded
  values — it now audits reality and re-audits automatically on token changes.
  Real finding: the seeded `--border-default`/`--border-strong` sit below the
  3:1 UI-boundary ratio; resolve during Phase 5 border migration.
- **New `check-card-drift.mjs`** — every card `oklch()` literal must exist in
  the authored CSS (card-chrome allowlist + `ds-allow` escape). Clean at zero.
- **Card fidelity fixes** — retired greens → 175; specimen chrome text
  desaturated to `--chrome-chroma` 0.02; badge/table/detail status text
  matched to theme tokens; color-ramp chips synced to final `tokens.css`
  values; input specimens show the shipped recessed well + `/0.5` dark rest
  border; pattern specimens use breadcrumbs (not back links); detail-page card
  now marks which real show page each band mirrors; button card documents
  `:danger → btn-error btn-outline`, real daisyUI heights, and link mode;
  table card documents sorting + LiveStream.
- **Five new component cards** — page-header, list-controls, form-helpers,
  empty-state, action-menu (the connective tissue the patterns reference).
- **Lint extended** — Tailwind `uppercase` in templates now flagged (bypasses
  `--label-case`, so the legibility skin can't reach it; ~47 sites);
  3/4/8-digit hex covered; the dead `mc-pulse` classes removed from
  `hud-system.css`.
- One review claim was **withdrawn on verification**: the inputs card's `/0.5`
  rest border was called drift against the base `.input` rule, but the
  `[data-theme="dark"]` override (the only theme in practice) is `/0.5` — the
  card was right.

**Verification so far:** `mix compile --warnings-as-errors` and `mix
assets.build` clean throughout. Visual (browser) verification of `/admin` is
still outstanding.

---

## What remains

### Phase 5 — visible migrations (least → most disruptive)

These live in the shared component/CSS layer, so they're **global by nature** —
the `/admin` pilot confirmed you migrate *components*, and pages come along for
free. Order is by blast radius and how much taste-iteration each needs:

1. **Components off `--glow-cyan` → `--color-action`** — mechanical, same color,
   correct tier.
2. **Hover-as-film** — replace hand-rolled `hover:bg-base-300` with the
   `--state-*` layers. Touches every hover state.
3. **Elevation polish** — the top-edge highlight, reserve blur to
   floating/modal. (Input-as-recessed-well already shipped via
   `--surface-input`/`--shadow-sunken`.)
4. **Template `uppercase` sweep** — ~47 Tailwind `uppercase` utilities bypass
   `--label-case`, so the legibility skin can't un-uppercase them. The lint
   flags them; migrate to `hud-label` or a knob-wired class.
5. **Border/status-fill token migration** — move components onto the seeded
   `--border-*` / `--status-*-fill` / `--on-*` roles; resolve the
   border-contrast finding (`--border-default` fails 3:1) while doing it.
6. **The scrim** — a real dim+blur layer; do it when a modal first needs it.
7. **Cyan reallocation** — *last, biggest.* Point chrome tokens at neutral so
   "cyan = actionable" reads. The vocabulary now exists, so it's a token repoint,
   not a find-replace — but it's the largest aesthetic change, so review it alone.

### Phase 6 — lock it

- Flip `check-design-system.sh` from warn → **error**.
- **Retire `check-css-frozen.sh`** (the precise lint now covers its job).
- Tag a **version** and start a **changelog**.

### Open findings from the pilot

- **Forms validate via `put_flash`, not inline field errors** — the admin LVs
  bind `to_form` on plain maps, not changesets. A deeper fix that touches the
  LiveView/domain.
- **No `<.form_actions>` component** — both admin forms hand-roll the identical
  actions row; a candidate for extraction.

### Breadth (lower priority)

- **Data-viz implementation** — fix the series palette in `telemetry_chart.js`
  (it collides identity with alarm hues), add threshold band shading, stale /
  no-data rendering, sparklines.
- **More components** — modal, sidebar nav, tabs, toast, `status_dot`,
  `detail_row`, `section_header` (page-header, list-controls, form-helpers,
  empty-state, and action-menu now have cards).
- **More patterns** — the dashboard / ops console (deliberately its own design
  language).
- **Direction-shaping foundations still open** — iconography, responsive.

### Verification follow-ups

- **Visual check** of the `/admin` pilot (run the app; needs platform-admin auth).
- **Contrast audit of the new ramp values** before broad adoption.

---

## How to work with it

- **Source of truth is `tokens.css`.** Components consume **semantics**
  (`var(--color-action)`), never primitives (`--cyan-500`) or raw `oklch()`.
- **Status convention:** ✅ implemented · 🎯 decided, not built · 🧭 exploring —
  tracked only in `overview/system-status.html`.
- **Enforcement:** `sh scripts/check-design-system.sh` (lint + card drift) and
  `node scripts/contrast-check.mjs` (WCAG, parses the shipped CSS). Warn-only
  until Phase 6. In cards, mark deliberate non-token values with `ds-allow`.
- **Commits touching CSS** must include `[css]` in the message (the frozen-CSS
  hook is still active) — or `HK=0` to skip hooks.
- **Preview the legibility mode:** set `data-skin="legible"` on `<html>`.
- **Editing the cards:** update the matching card in the same PR when code and
  card diverge; sync to Claude Design with the `/design-sync` flow.

---

## Quick reference — the principles

1. Information density over decoration.
2. Legible under stress.
3. Status is always a color.
4. Sharp and technical (2px, uppercase labels, monospace data).
5. Glow means "live" (and buttons never glow).
6. One way to do each thing (closed set; compose, don't invent).

Plus: color is allocated by job and spent like a scarce signal; time is always
UTC; the voice is operator-to-operator (precise, terse, calm).
