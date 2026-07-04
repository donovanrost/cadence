We are working on Cadence -- a multi-tenant SaaS platform for managing constellation scale spacecraft operations.
Cadence's architecture is heavily inspired by Cosmos OpenC3, but adapted for Elixir idioms.

## Code quality

- `mix compile --warnings-as-errors` must pass.
- `mix credo --strict` — we are burning down violations. Leave the codebase better than you found it.
- `mix format` on all touched Elixir files.
- Tests: run per-app (`cd apps/cadence && mix test`, `cd apps/cadence_web && mix test`).

## UI rules (non-negotiable)

1. **No new CSS selectors.** The CSS in `assets/css/components/` is a closed set of selectors ported from legacy. Tuning the *values* of existing declarations and defining missing custom-property tokens inside the existing `:root`/`@theme` blocks in `app.css` is allowed; adding selectors or new rule blocks is not. Compose new looks from daisyUI classes + Tailwind utilities + existing HUD utilities (`hud-label`, `hud-grid`, etc.). If you think you need a new rule, you're wrong — use an existing class or a Tailwind arbitrary value.

2. **Never write raw HTML form inputs.** Use `<.input>` from `CadenceWeb.Components.FormInputs` for all form fields. It handles labels (`hud-label`), daisyUI styling, error display, and select/text/email/password types. For standalone controls outside a form binding (filter boxes, `phx-change` selectors), pass `name`/`value` instead of `field`.

7. **Use the component layer, not raw daisyUI markup.** `<.button>` (never `class="btn ..."`), `<.card>`/`<.stat_tile>` (never `class="card bg-base-200 ..."`), `<.table>` for data tables, `<.page_header>` for page titles, `<.empty_state>` for empty lists, `<.status_badge>`/`<.severity_badge>` for pills. All live in `lib/cadence_web/components/` and are imported everywhere via `html_helpers`. A one-off layout that would need more than a couple of `class` escape hatches may stay raw — leave a one-line comment saying why.

8. **Glow and `hud-corners` are reserved for navigation cards, heroes, and live/alert signals.** Buttons never glow (`<.button>` enforces this). Use `<.card hover_glow>` only on cards that are themselves navigation targets (it brings the corner brackets with it); `corners` opts a non-navigating hero panel in. Content cards get neutral chrome — no brackets, no colored border. Status on a card lives solely in its `<.status_badge>` (the old `accent` attr was retired for double-encoding it). Inline contextual messages use `<.callout>`, never raw daisyUI `alert`.

3. **No render function over 50 lines.** Extract a private component function or a separate component module. Large render functions are where duplication hides.

4. **Before writing any template, read the most similar existing template.** Match its patterns. Don't invent new card layouts, button styles, or page structures — reuse what's there.

5. **No file over 400 lines.** If approaching this, split by concern before continuing.

6. **Row navigation is the Name-cell link; secondary actions use `<.action_menu>`.** The Name column links to the row's show page (`text-primary hover:underline`) — never whole-row `phx-click`. Keep `<.action_menu>` only when the row has real secondary actions beyond View (a View-only menu should be dropped). Never put multiple action buttons directly in a table cell.

## Architecture quick reference

**Domain layering:** `Cadence` facade → `Cadence.Auth` → `Cadence.Accounts`. Controllers/LiveViews call the facade.

**Layouts:** `auth` (narrow centered, for `/sign-in` and `/invitations`), `sidebar` (drawer, for authenticated pages), `app` (minimal fallback).

**Sidebar navigation:** Set `@nav_context` (`:admin` or `:operator`) and `@nav_item` (e.g., `:admin_dashboard`) in mount. The sidebar template renders the matching section and highlights the active item.

**Admin routes:** Inside `live_session :admin` with `CadenceWeb.AdminAuth` on_mount hook. The hook authenticates, checks `platform_admin` capability, and assigns `current_scope` + `nav_context`.

**Frontend stack:** daisyUI 5 + Tailwind v4 + Tokyo Night dark theme (hot pink accent, sharp 2px corners, oklch colors) + HUD utility layer, wrapped by the component layer in `lib/cadence_web/components/` (rule 7).

**Text contrast tiers (WCAG AA on the dark surfaces):** informational text (table cells, descriptions, subtitles) is `text-base-content/70` minimum or full `text-base-content`; short secondary text (timestamps, counts, captions) is `/60` minimum; `/40`–`/50` only for true decoration, placeholders, and disabled states; `/20`–`/30` only for borders and `aria-hidden` glyphs. Don't put `text-base-content/NN` next to `hud-label` — the label's own color wins the cascade and the utility is inert.

**Legacy reference:** `legacy/cadence_legacy/` has the visual reference for the HUD aesthetic. Use it for pattern reference, not code copying.
