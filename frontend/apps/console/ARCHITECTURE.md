# Console architecture

The console is Cadence's UI: a Vue 3 single-page app served by Phoenix at `/console/`. Owner:
`console` (docs/TEAM.md). Domain Heads build the screens for their area; console sets the patterns
here and reviews them. Change this file in the same PR as the pattern it describes.

## Where things live

| What                                   | Where                                                                                                                                                                            |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The app (`@cadence/console`)           | `frontend/apps/console`                                                                                                                                                          |
| Design system (`@cadence/apogee-ui`)   | `frontend/packages/apogee-ui`: tokens and base CSS (`src/styles/`), the `Ap*` components, formatting, the shared clock, focus and announce helpers                               |
| Feature code                           | `src/features/<area>/**`, one directory per area (`now`, `fleet`, `alarms`, `commands`, `contacts`, `telemetry`, `dashboards`, `spacecraft`, `catalog`, `profiles`, `people`, …) |
| Shell, router, API client, live socket | `src/{shell,router,api,live}/**`                                                                                                                                                 |
| Browser tests                          | `e2e/` (Playwright; `e2e/a11y/` holds the axe passes)                                                                                                                            |
| Build output                           | `apps/cadence_web/priv/static/console/` (gitignored)                                                                                                                             |
| Phoenix glue                           | `CadenceWeb.Console.Shell` (serves the index), the `/api/console/v1` scope, `CadenceWeb.ConsoleSocket` at `/socket/console`                                                      |

Features import shared code only through the public entries:

- `@/ui` (`src/ui.ts`): all of `@cadence/apogee-ui` plus `ApRemote`, `OutcomeCallout` and a few
  view helpers.
- `@/api`, `@/live` and `@/shell`.

A feature never imports another feature's internals. If two features need the same thing, promote
it to one of those entries (console reviews). The `@/ui/index.ts` and `@/lib/*` paths are
transitional aliases of `@/ui`. Don't use them in new code.

## Stack

- Vue 3 with `<script setup lang="ts">` and vue-router (typed route names).
- Tailwind v4 through `@tailwindcss/vite`, and Vite+ (`vp`) for dev, build, lint, format and test.
- No Pinia: shared state is a few typed composables, each with an explicit owner.
- No third-party UI kit: `apogee-ui` is ours. Fonts are self-hosted through `@fontsource` (Saira,
  Saira Condensed, Azeret Mono).

The workspace compiler baseline (`frontend/tsconfig.strict.json`), the typed oxlint rules and the
ast-grep rules in `frontend/ast-grep/` all apply. vue-tsc runs on `tsconfig.app.json` with
`checkUnknownComponents`, so a component that is used in a template but not imported is an error.
`strictTemplates` stays off because it also rejects `aria-*`/`data-*` fallthrough on `Ap` components.

## Routing

History mode, base `/console/`. Operational URLs are scoped as `/:org/:mission/...` by slug. The
route tree is in `src/router/index.ts` (`ops-routes.ts`, `setup-routes.ts`). The typed names and
params are in `src/router/route-map*.ts`, and `route-map.test.ts` checks the two against each other.

- Each route record carries `meta: { mode, nav, title }`. `mode` is one of `ops`, `setup`,
  `takeover`, `account` or `admin`, and it picks the rail. `nav` highlights the rail item. `title`
  sets the document title.
- Link by name: `{ name: "ops.now" }`. Inside a mission, `org` and `mission` are inherited.
- Ops screens live under `/:org/:mission/` (now, fleet, alarms, commands, contacts, telemetry,
  timeline). Setup screens live under `/:org/:mission/setup/…`. Org setup lives under
  `/:org/org/…`. Platform admin is `/admin` and account is `/account`.
- `/` redirects to the last mission or the first available one. Unknown slugs and paths render
  the not-found screen inside the shell.

## Data: API client and decoders

- Transport is `request(path, reader, { signal })` and `requestPage(...)` from `@/api`. They send
  same-origin `fetch` with the `x-csrf-token` header on every non-GET request. A response is
  decoded before anything reads it.
- Decoders are the composable readers in `@/api` `decoders` (`object`, `array`, `string`,
  `nullable`, `oneOf`, `known`, `knownText`, …). Static types are inferred from them
  (`type X = Decoded<typeof x>`), so each shape is defined once. A decode failure carries the JSON
  path.
  - Closed vocabularies use `known`/`knownText`, never a plain string (ast-grep:
    `vocabulary-field-decoded-as-text`).
  - Lists that may hold an unreadable item use `perItem`: that item is left out and described,
    and the rest still render.
  - Resource ids are branded types (`missionId`, `scid`, `spacecraftId`, `stationId`), minted only
    by their decoders and param readers.
- Results are `ApiResult<T>`: either `{ ok: true, value }` or `{ ok: false, error }`, where `error`
  is a closed union (`unauthenticated`, `forbidden`, `not_found`, `conflict`, `invalid`,
  `unavailable`, `malformed`). Handle it exhaustively. Server error codes are typed (`codeOf`,
  `hasErrorCode`, `fieldErrors`), never compared as text (ast-grep: `error-code-compared-as-text`).
- Each feature has an `api.ts` with one function per endpoint and precise types. Generic paths and
  `unknown` stay inside `src/api`.
- Reads go through `useRemoteQuery(key, fetch)`. It aborts on a key change or unmount, drops stale
  responses, and keeps the last value while it refetches. It exposes a `RemoteState<T>` that a
  screen renders with `<ApRemote :state @retry>`. Refetch on server changes with
  `useMissionInvalidation(missionId, [resources], refetch)`.

## Session, scope and auth

- Phoenix serves `/console/*` only to an authenticated session. Signed out, the browser goes to
  `/sign-in` and comes back afterwards. `/api/console/v1/*` answers with JSON 401 instead of
  redirecting, and the client turns that into a full-page redirect.
- On boot the app reads the session (user, organizations with missions, capabilities, CSRF token,
  socket path). The shell shows a boot state until the session is read.
- `useSession()`, `hasCapability()` and `useMissionScope()` (from `@/shell`) give
  `{ organization, mission }`, with ids for API calls and slugs for links. The scope is computed
  from the route, never copied.
- The server checks org/mission scope and authorization on every endpoint. A client capability
  check only hides an affordance.

## Live data

- There is one Phoenix socket per tab (`src/live/socket.ts`), started by `App.vue` after the
  session is read. Channels are joined with `useChannelSubscription` or `useChannelEvent`, and
  their payloads are decoded like HTTP responses.
- `useConnection()` reports `connecting`, `live` or `offline`. When the connection isn't `live`,
  show the data as stale, never as nominal ("truth before calm").

## Serving

- Built: `vp build` writes `index.html` and hashed `assets/` to
  `apps/cadence_web/priv/static/console/`. Phoenix serves the assets and returns the index for
  every `/console/*` path, adding `<meta name="csrf-token">`.
- Dev: Phoenix stays the page origin, with no proxy. When `config :cadence_web, :console,
dev_server:` is set, `CadenceWeb.Console.Shell` fetches the index from the Vite dev server
  (`127.0.0.1:5181`, base `/console/`) and points its module URLs at it. Cookies, CSRF and the
  socket stay same-origin with Phoenix, while Vite serves the modules and HMR.
- To run it, start Phoenix for your worktree (your own database and port: docs/TEAM.md "Dev stack")
  and, from `frontend/`, run `corepack pnpm --filter @cadence/console dev`. Then sign in at
  `/sign-in` and open `/console/`.

## Building a screen

- One file per screen: `src/features/<area>/<Name>Screen.vue`. Register it in `ops-routes.ts` or
  `setup-routes.ts`, and add it to the route map.
- The shell contract, checked by `e2e/shell.e2e.ts`:
  - one `<header>` showing the org and mission names, a labelled `<nav>`, exactly one `<main>`,
    and **exactly one `<h1>`, rendered by `<ApPageHeader>`**;
  - every `/console/*` path returns the app on reload;
  - no console errors and no app request ≥ 400 on load;
  - axe WCAG 2.1 AA clean.
- Ops screens you act from fit the viewport: `main` has a fixed height and panes scroll
  (`ApPanel pane`). Setup, reading and admin screens scroll `main`.
- Compose `@/ui`: `ApPanel`, `ApTable` (with the `virtual` prop for long lists), `ApListRow`,
  `ApButton`, `ApTag`/`ApStatusMark`, `ApField`/`ApSelect`/`ApTextarea`, `ApSheet`, `ApMenuButton`,
  `ApCallout`, `ApEmptyState` and the rest of `packages/apogee-ui/src`. A component that only one
  feature uses stays in that feature. A new shared primitive goes in `apogee-ui` (console reviews).
  Never build a local copy of one.
- Real data only. When the backend lacks something, add the endpoint or show an honest empty state.
  Never ship fixtures or invented numbers.

## Words

The vocabulary and formats are in `docs/apogee/ux/design-language.md` (§4 and §8).

- Speak flight: AOS, LOS, pass, uplink, GO / HOLD / NO-GO. Never "items", "records" or "entities".
- Every target row shows its name and SCID. Never put a dash where an identity belongs. Raw ids
  appear only under "Technical details".
- Times and numbers come only from the `@/ui` formatters (`formatAbsolute`, `formatShort`,
  `formatCountdown`, `formatDuration`, `formatCount`, `plural`) and the shared clock `useNow`.
  Times are UTC with a `Z`, and countdowns use `T−`/`T+` with U+2212. Components never format dates
  themselves.
- Word maps are keyed by the vocabulary's union type (`Record<Union, string>`), so a renamed key is
  a compile error (ast-grep: `word-map-keyed-by-text`). An unknown server word is shown as itself,
  never dropped.
- Headlines state the situation ("3 spacecraft need you"). Buttons are verbs with their scope.
  A disabled action says what blocks it.

## Accessibility

The rules are in `docs/apogee/ux/design-language.md` §6 and `docs/apogee/ux/a11y-checklist.md`.

- State is shown as mark + color + word and must read in grayscale. Status marks are
  `aria-hidden`, and the word next to them carries the meaning.
- Use real elements (`<button>`, `<a>`, inputs from `apogee-ui` with their labels). Every
  icon-only control has an `aria-label`.
- Action menus follow the WAI-ARIA menu button pattern (`ApMenuButton`). Sheets trap focus and
  return it when they close.
- After a removal, focus moves with `focusAfterRemove` or `focusFirstConnected`, never to
  `<body>`. Words that arrive on their own are announced with `announcePolite`.
- Dim marks and chrome, never text: `opacity` on a container that holds text is a bug.

## Scale: 500 spacecraft is the floor

- Never fetch per spacecraft from the client. Ask the server for the aggregate or a page
  (`requestPage`, cursor-based).
- Long lists are paginated or virtualized (`ApTable` `virtual`). Never render 500+ rows into the
  DOM at once.
- Group identical findings by cause into one line. Don't list per spacecraft what a profile rule
  fixes.
- Live updates patch state in place. They never refetch the fleet on every event (see
  `src/live/coalesce.ts`).

## Checks

From `frontend/`, before a PR (full suites and browser tests run in CI):

```sh
./node_modules/.bin/vp lint
./node_modules/.bin/vp fmt --check
node tools/typecheck-workspace.mjs
corepack pnpm -s lint:structure && corepack pnpm -s test:structure && corepack pnpm -s test:tools
(cd apps/console && ../../node_modules/.bin/vp test --run <touched test files>)
```

`test:tools` includes the 400-line rule with its shrink-only baseline
(`tools/file-lines-baseline.json`). Run a Playwright spec locally only while writing or fixing
that spec.
