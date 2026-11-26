We are working on Cadence -- a multi-tenant SaaS platform for managing constellation scale spacecraft operations.
Cadence's architecture is heavily inspired by Cosmos OpenC3, but adapted for Elixir idioms.

Read `docs/TEAM.md` first: it is the charter (ground rules, who owns what, how work flows).

## Code quality

- `mix compile --warnings-as-errors` must pass.
- `mix credo --strict` — we are burning down violations. Leave the codebase better than you found it.
- `mix format` on all touched Elixir files.
- Tests: run the tests for the area you touched, per app (`cd apps/cadence && mix test <files>`).
  Full suites run in CI.
- Frontend: from `frontend/`, lint, format check, workspace typecheck, the structure checks and the
  tests of the projects you touched (commands in `frontend/AGENTS.md`).

## UI rules (non-negotiable)

The console (`frontend/apps/console`, Vue 3 + `@cadence/apogee-ui`) is the only UI. LiveView pages,
the federated apps, the host and `packages/ui` are being deleted; don't add to them.
How the console is built: `frontend/apps/console/ARCHITECTURE.md`.

1. **Compose `@/ui`.** Screens use the `Ap*` components from `@cadence/apogee-ui`, imported through
   `@/ui` (with `ApRemote` for remote data). No third-party UI kit, no hand-rolled lookalikes. A
   component only one feature uses stays in that feature; a new shared primitive goes in
   `apogee-ui` (console reviews).
2. **Exactly one `<h1>` per screen, via `<ApPageHeader>`.** One `<main>`, a labelled `<nav>`, the
   shell's `<header>`. Ops screens you act from fit the viewport and scroll their panes; setup,
   reading and admin screens scroll `main`.
3. **Decode everything.** Every response goes through a reader from `@/api` `decoders`; types are
   inferred from readers. Closed vocabularies use `known`/`knownText`, ids are branded, errors are the
   closed `ApiResult` union handled exhaustively. One function per endpoint in `features/<area>/api.ts`.
4. **Remote state through `useRemoteQuery` and `<ApRemote>`.** Loading, failure and retry are shown,
   never skipped. Live data comes from the one socket (`@/live`); when `useConnection()` isn't `live`,
   show data as stale, never as nominal.
5. **Words.** Speak flight (AOS, LOS, pass, uplink, GO / HOLD / NO-GO), never "items" or "records".
   Name + SCID on every target row, never a dash for an identity. Times and numbers only through
   the `@/ui` formatters (UTC with `Z`, `T−`/`T+`). Word maps are keyed by the vocabulary's union.
   Source: `docs/apogee/ux/design-language.md` §4, §8.
6. **Accessibility.** WCAG 2.1 AA (axe clean). State is mark + color + word and reads in grayscale.
   Real elements, every icon-only control labelled, focus never lost to `<body>`, menus and sheets
   per the kit. Source: `docs/apogee/ux/design-language.md` §6 and `docs/apogee/ux/a11y-checklist.md`.
7. **500 spacecraft is the floor.** No per-spacecraft requests from the client; ask the server for
   the aggregate or a page. Long lists paginate or virtualize. Group identical findings by cause.
8. **Real data only.** If the backend lacks something, add it or show an honest empty state. No
   fixtures or invented numbers in the console.
9. **Row navigation is the Name-cell link.** In an `ApTable` (or list), the Name cell is a
   `RouterLink` to the row's page; never a whole-row click. Secondary actions go in one
   `ApMenuButton` per row, and only when there are real ones beyond View (drop a View-only menu).
   Never put several action buttons in one cell.
10. **No file over 400 lines.** `test:tools` enforces it with a shrink-only baseline; split by
   concern before you get there.
11. **Read the most similar existing screen first** and match its patterns.

## Architecture quick reference

**Domain layering:** `Cadence` facade → `Cadence.Auth` → `Cadence.Accounts`. Controllers and the
console API call the facade.

**Console API:** `/api/v1` (session-cookie authenticated, CSRF header on writes, JSON 401),
the console socket at `/socket`. The server checks org/mission scope and authorization on
every endpoint; client capability checks only hide affordances.

**Console serving:** Phoenix serves `/console/*` (`CadenceWeb.Console.Shell`). In dev, Phoenix stays
the origin and loads modules from the Vite dev server on `127.0.0.1:5181`.
