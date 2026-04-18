We are working on Cadence -- a multi-tenant SaaS platform for managing constellation scale spacecraft operations.
Cadence's architecture is heavily inspired by Cosmos OpenC3, but adapted for Elixir idioms.

## Code quality

- `mix compile --warnings-as-errors` must pass.
- `mix credo --strict` — we are burning down violations. Leave the codebase better than you found it.
- `mix format` on all touched Elixir files.
- Tests: run per-app (`cd apps/cadence && mix test`, `cd apps/cadence_web && mix test`).

## UI rules (non-negotiable)

1. **Never add rules to CSS files.** The CSS in `assets/css/components/` is a closed set ported from legacy. Compose from daisyUI classes + Tailwind utilities + existing HUD utilities (`hud-label`, `hover-glow-cyan`, `hud-grid`, etc.). If you think you need new CSS, you're wrong — use an existing class or a Tailwind arbitrary value.

2. **Never write raw HTML form inputs.** Use `<.input>` from `CadenceWeb.CoreComponents` for all form fields. It handles labels (`hud-label`), daisyUI styling, error display, and select/text/email/password types.

3. **No render function over 50 lines.** Extract a private component function or a separate component module. Large render functions are where duplication hides.

4. **Before writing any template, read the most similar existing template.** Match its patterns. Don't invent new card layouts, button styles, or page structures — reuse what's there.

5. **No file over 400 lines.** If approaching this, split by concern before continuing.

6. **Table row actions use `<.action_menu>`, not inline buttons.** The component renders a vertical ellipsis that opens a dropdown menu. Never put multiple action buttons directly in a table cell.

## Architecture quick reference

**Domain layering:** `Cadence` facade → `Cadence.Auth` → `Cadence.Accounts`. Controllers/LiveViews call the facade.

**Layouts:** `auth` (narrow centered, for `/sign-in` and `/invitations`), `sidebar` (drawer, for authenticated pages), `app` (minimal fallback).

**Sidebar navigation:** Set `@nav_context` (`:admin` or `:operator`) and `@nav_item` (e.g., `:admin_dashboard`) in mount. The sidebar template renders the matching section and highlights the active item.

**Admin routes:** Inside `live_session :admin` with `CadenceWeb.AdminAuth` on_mount hook. The hook authenticates, checks `platform_admin` capability, and assigns `current_scope` + `nav_context`.

**Frontend stack:** daisyUI 5 + Tailwind v4 + Tokyo Night dark theme (hot pink accent, sharp 2px corners, oklch colors) + HUD utility layer. Use `card bg-base-200`, `btn btn-primary`, `hud-label`, `hover-glow-cyan transition-glow`, `text-base-content/60` for muted text.

**Legacy reference:** `legacy/cadence_legacy/` has the visual reference for the HUD aesthetic. Use it for pattern reference, not code copying.
