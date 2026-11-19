# Apogee console: architecture

Owner: lead. Changes to anything here go through lead; record them in this file.
Confirms the TEAM.md defaults, with the refinements below.

## Location

| What | Where |
| --- | --- |
| SPA source | `frontend/apps/console` (package `@cadence/console`) |
| Apogee design system | `frontend/packages/apogee-ui` (`@cadence/apogee-ui`: tokens + base css, `Ap*` components, formatting, shared clock; lead owns, ux owns token values). A separate package because `packages/ui`'s boundary test forbids an app-local UI kit (`apps/*/src/ui`). |
| Feature code | `frontend/apps/console/src/features/<area>/**` (fe-ops: `now`, `fleet`, `alarms`, `commands`, `contacts`, `palette`; fe-setup: `readiness`, `spacecraft`, `catalog`, `profiles`, `people`) |
| App shell, router, API client, live socket | `frontend/apps/console/src/{shell,router,api,live}/**` (lead) |
| Build output | `apps/cadence_web/priv/static/console/` (gitignored) |
| Phoenix glue | `CadenceWeb.ConsoleController`, `/api/console/v1` scope, `CadenceWeb.ConsoleSocket` (api) |

Feature directories import shared code only through `@/ui` (`src/ui.ts`: the package + `ApRemote`), `@/api`, `@/live`, `@/shell`.
A feature never imports another feature's internals; if two features need the same thing, ask lead to
promote it.

## Stack

Vue 3 + TypeScript (`<script setup lang="ts">`), vue-router 4, Tailwind v4 (`@tailwindcss/vite`),
Vite+ (`vp`) like the rest of the workspace. No Pinia: shared state is a few typed composables with an
explicit owner (see State). No UI kit: the Apogee component set is small and ours. Fonts are
self-hosted via `@fontsource` (Saira, Saira Condensed, Azeret Mono) so ops consoles work without
Google Fonts.

The workspace compiler baseline (`tsconfig.strict.json`), typed oxlint rules and ast-grep rules apply
unchanged. `corepack pnpm verify` from `frontend/` must pass.

## Routing

History mode, base `/console/`. Every operational URL is mission-scoped by slug.

```
/console/                                  → redirect: last mission (localStorage) or first available
/console/:org/                             → redirect: first mission in org
/console/:org/:mission/                    → redirect: now

Ops mode (meta.mode = "ops")
/console/:org/:mission/now                 J1 Now
/console/:org/:mission/fleet               Fleet
/console/:org/:mission/alarms              Alarms
/console/:org/:mission/alarms/:alarmId     J2 Investigate
/console/:org/:mission/commands            J3 Command a group
/console/:org/:mission/commands/compose    C1 Compose
/console/:org/:mission/commands/:requestId Approve / Uplink & verify (state decides the view)
/console/:org/:mission/contacts            J4 Contacts (K1 plan)
/console/:org/:mission/contacts/predict    K0 Pass prediction
/console/:org/:mission/contacts/replan     K2 Replan
/console/:org/:mission/contacts/review     K3 Pass review
/console/:org/:mission/telemetry           Telemetry
/console/:org/:mission/timeline            Timeline
/console/:org/:mission/spacecraft/:scid    Spacecraft detail

Setup mode (meta.mode = "setup")
/console/:org/:mission/setup               S1 Readiness
/console/:org/:mission/setup/spacecraft    Spacecraft list
/console/:org/:mission/setup/spacecraft/new S2 Add spacecraft
/console/:org/:mission/setup/profiles[/:profileId]  S4 Profiles
/console/:org/:mission/setup/catalog       S3 Catalog import + diff
/console/:org/:mission/setup/comms | stations | sources | apps
/console/:org/setup/people                 S5 People & access (org-scoped)
/console/:org/setup/missions | settings | audit
```

Each route record carries `meta: { mode, nav, title }`. The rail highlights from `meta.nav`; the
Ops|Setup toggle links to the other mode's home for the same mission. ⌘K palette is global.
ux's `information-architecture.md` may rename or regroup screens; lead updates this table to match.

## API client and decoding

- Transport: `src/api/http.ts`. `fetch` with `credentials: "same-origin"`, `accept: application/json`,
  and `x-csrf-token` on every non-GET (token from the bootstrap response). Returns `unknown`.
- Decoding: `src/api/decode.ts`, small composable readers (`object`, `array`, `string`, `nullable`,
  `oneOf`, …) in the style of `modules/communications/src/shared/form-validation.ts`. Static types are
  inferred from readers (`type Session = Decoded<typeof session>`), so there is one definition of each
  shape. A decode failure throws `DecodeError` with the JSON path.
- Results: `ApiResult<T> = { ok: true; value: T } | { ok: false; error: ApiError }` where
  `ApiError` is a closed union: `unauthenticated` (→ full-page redirect to `/sign-in`), `forbidden`,
  `not_found`, `conflict` (with server detail), `invalid` (field errors), `unavailable`, `malformed`
  (decode failure). Feature code handles the union exhaustively.
- One function per endpoint, per feature: `features/<area>/api.ts` exports precise operations
  (`fetchMissionHealth(scope): Promise<ApiResult<MissionHealth>>`). Generic paths and `unknown` stay
  inside `src/api`.
- Server error body (api contract): `{"error": {"code": "...", "message": "...", "details": {...}}}`.

## Auth and session

- `/console/*` is served by Phoenix inside the browser pipeline and requires an authenticated scope;
  unauthenticated GETs redirect to `/sign-in` and return to the requested URL afterwards.
- On boot the SPA calls `GET /api/console/v1/session` → user, organizations with missions,
  capabilities, `csrf_token`. Until it resolves the shell shows a boot state; 401 → `/sign-in`.
- `/api/console/v1/*` is session-cookie authenticated (`fetch_session` + `protect_from_forgery` via the
  `x-csrf-token` header) and returns JSON 401 instead of redirecting. Org/mission scope is checked
  server-side on every endpoint; the SPA's capability checks only hide affordances.

## State

- `useSession()`: the decoded bootstrap snapshot (readonly), provided once by `App.vue`.
- `useMissionScope()`: current `{ organization, mission }` derived from the route + session (computed,
  never copied). Unknown slugs render a not-found page inside the shell.
- Screen data lives in feature composables (`useNowSnapshot(scope)`), which own their fetch, live
  subscription and cleanup, and expose a `RemoteState<T>` union:
  `idle | loading | ready(value, receivedAt) | failed(error)`. Stale-response guard: results for a scope
  that is no longer current are dropped.

## Live data

- One Phoenix socket per tab: `src/live/socket.ts` (the `phoenix` JS client), connected to
  `/socket/console` after bootstrap. Session-authenticated on the server via `connect_info: [:session]`;
  the bootstrap's CSRF token is sent as `_csrf_token` param.
- `useChannel(topic, handlers)` joins on mount, leaves on unmount or scope change, and exposes
  `connection: "connecting" | "live" | "stale" | "offline"`. Payloads are decoded like HTTP responses.
- Topics (api defines, documented in `docs/apogee/api/live.md`), e.g. `mission:<mission_id>:health`.
- The UI treats a lost socket as **stale**, never as nominal (Apogee: "truth before calm").

## Phoenix serving

- Prod: `corepack pnpm --filter @cadence/console build` writes `index.html` + hashed `assets/` to
  `apps/cadence_web/priv/static/console/`. Plug.Static serves `/console/assets/*` (immutable). The
  router catch-all `GET /console/*path` → `ConsoleController.index` sends `priv/static/console/index.html`
  with `cache-control: no-store`. If the file is missing (dev without a build) it renders a short
  page pointing to the Vite dev server.
- Dev (agreed with api): **Phoenix stays the origin**, no proxy. In dev the `/console/*` catch-all
  emits a shell that loads `http://127.0.0.1:5181/console/@vite/client` and
  `http://127.0.0.1:5181/console/src/main.ts`, so cookies, CSRF and the socket stay same-origin with
  Phoenix while Vite serves modules + HMR cross-origin (`server.origin`, `cors: true`, port 5181
  strict). Run Phoenix for this worktree (qa runs it on `http://127.0.0.1:4011`, see
  `docs/apogee/qa/runbook.md`) and `corepack pnpm --filter @cadence/console dev`, sign in at
  `/sign-in`, open `/console/`.
- CSRF: Phoenix injects `<meta name="csrf-token">` into the served index; the session payload also
  carries `csrf_token` (used for the socket connect params).

## Shell contract (qa e2e builds against this)

Signed-out `/console` redirects to `/sign-in`. Signed in, every screen has one `<header>` (banner)
showing org and mission names as text, a labelled `<nav>`, exactly one `<main>` and exactly one
`<h1>`; any `/console/*` path returns 200 + the SPA index on full reload; no console errors and no
app request ≥400 on load; axe WCAG 2.1 AA clean.

## Shared components (src/ui)

`ApPanel` (indexed header `A1 TITLE … right meta`, optional scroll body), `ApButton` (primary /
secondary / danger, sizes, renders `<button>` or `<RouterLink>`), `ApTag` + `ApStatusMark`
(nominal / caution / critical / stale / off: shape + color + word), `ApStatStrip` + `ApReadout`,
`ApTable`, `ApSegmented`, `ApLabel`, `ApEmptyState`, `ApCallout`. Tokens live in
`packages/apogee-ui/src/styles/tokens.css` as Tailwind v4 `@theme` variables (from ux's `design-language.md`).
Feature engineers compose these; ask lead before adding a new shared primitive.

## Working in the console (feature engineers)

- Run: Phoenix on `http://127.0.0.1:4011` (qa runbook) + `corepack pnpm --filter @cadence/console dev`
  (from `frontend/`). Open `http://127.0.0.1:4011/console/`. Checks before commit, from `frontend/`:
  `node_modules/.bin/vp fmt apps/console && node_modules/.bin/vp check apps/console`,
  `cd apps/console && npx vue-tsc -b && corepack pnpm test`. (Use `mise exec --` if node isn't on PATH.)
  That is the whole routine check: format, lint, typecheck, unit tests. Browser and e2e tests
  (`test:e2e`, Playwright, headless browser checks) are **not** part of routine validation:
  not before commit, not on iterative checks, not after a restart. CI runs them. Running a spec
  locally is fine only while writing or fixing that spec (user rule, via the director).
  vue-tsc runs with `checkUnknownComponents`: a component used in a template but not imported is
  an error (otherwise it renders as an inert unknown element). `strictTemplates` stays off: it
  also rejects `aria-*`/`data-*` fallthrough on Ap components.
- A screen: `src/features/<area>/<Name>Screen.vue`, swap `pending` for it in
  `src/router/ops-routes.ts` (fe-ops) or `src/router/setup-routes.ts` (fe-setup). Route names are
  stable; link with `{ name: "ops.now" }` (org/mission params are inherited inside a mission).
- Exactly one `<h1>` per screen, via `<ApPageHeader>`. Ops screens get a fixed-height `main`
  (use `ApPanel pane` for scrolling regions); Setup screens scroll `main`.
- Scope: `useMissionScope()` from `@/shell` → `{ organization, mission }` (ids for API calls,
  slugs for links). Session + capabilities: `useSession()`, `hasCapability()`.
- Data: `features/<area>/api.ts` declares readers (`@/api` `decoders`) and one function per endpoint
  using `request(path, reader, { signal })`. A composable owns each read with
  `useRemoteQuery(() => scope.value.mission.id, (id, signal) => fetchX(id, signal))` (aborts on key
  change/unmount, drops stale responses, refetch keeps the last value) and refetches via
  `useMissionInvalidation(missionId, [...], refetch)`. Render with `<ApRemote :state @retry>`.
- Live: `useConnection()` → `connecting | live | offline`; show data as stale when not `live`.
- Formatting: only from `@/ui` (`formatAbsolute`, `formatCountdown`, `formatCount`, `plural`, `useNow`).
  Old `@/ui/index.ts` / `@/lib/*` paths resolve through a transitional alias; use `@/ui` in new code.
- UI: compose `@/ui`. Need a new shared primitive (ApListRow, ApFactStrip, ApEventLine, ApKeyValue,
  ApStepBar, ApStateTrail, ApChip, ApField, ApBreadcrumb, …)? Ask lead; don't build a local copy.
  Feature-only components stay in the feature dir.

- **Load (director, 2026-11-13):** ~12 agents share one 8-core machine. Run a single targeted heavy
  process (one `vue-tsc`, one `mix compile` / architecture check, one test file) through
  `scripts/check-slot.sh <command…>`: it waits for one of 3 shared slots and runs the command under
  `nice -n 10`. Full suites, builds and parallel runs stay gated on load < 16. Save full output to a
  file; never judge a check through `| tail` (the pipe hides the exit status). Freezes still win.
- **Elixir checks never build the live server's code (2026-11-13 outage):** in the shared tree, run every
  Elixir check (compile, credo, xref, `mix cadence.architecture.check`, tests) with `MIX_ENV=test`,
  which builds to `_build/test`. A dev-env build rewrites `_build/dev` under the running :4011 node and
  can purge modules (`Cadence.Repo`) from running processes. Lib saves reach :4011 through its own reloader.
  `scripts/check-slot.sh` refuses a `mix` task without `MIX_ENV=test`. Dev-DB migrations go to qa, who runs
  them through the live node (`Ecto.Migrator`) or inside a planned restart, never `mix ecto.migrate` from the
  shared tree.
  A save that changes a widely used struct, schema or macro (e.g. `%Spacecraft{}` fields) makes :4011's
  reloader recompile much of the app: tell qa before saving one, and never during a freeze.
