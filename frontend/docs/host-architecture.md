# Frontend and web ownership

The browser application lives in the frontend workspace. Phoenix authenticates requests,
loads authorized resource context, transports LiveView updates, and exposes the REST and
application-host APIs. Cadence core registers and executes domain application queries and actions.

| Owner                    | Responsibility                                                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `packages/design-tokens` | Semantic theme variables, chart colors, theme contracts                                                                 |
| `packages/ui`            | Shared Vue controls, accessible primitives, production CSS recipes                                                      |
| `apps/host`              | Application shell, navigation, account/session screens, federation lifecycle, route-to-surface catalog                  |
| Domain frontend apps     | Screen composition, interactions, application-specific components                                                       |
| `apps/storybook`         | Isolated development and browser interaction/accessibility checks using production tokens and components                |
| `apps/cadence`           | Domain state, policy, application definitions, query/action providers, operational read models                          |
| `apps/cadence_web`       | HTTP/session/CSRF boundaries, authenticated router scopes, LiveView transport, API adapters, frontend artifact delivery |

## Page composition

`apps/host/src/routes.json` declares the ordinary/inventory routes: application,
surface, scope, query allowlist, and layout metadata. `BrowserHost.vue` owns Vue Router,
commits authorized context with the selected route, and renders `ApplicationShell` plus
one page outlet. Layout selection, active links, document titles, query selection, and
history belong to Vue. The shell remains mounted across applications and missions.

Phoenix keeps explicit deep-link entry routes in the `:browser` and
`:require_authenticated_scope` pipeline and the `:application` LiveView session.
`HostPageLive` mounts a single `BrowserHost` and exposes `host:context` events. Each
request matches the requested path against the server router, reauthenticates the session,
and applies the route's server-owned policy. Path parameters override query parameters.
Phoenix returns an allowlisted context snapshot; it does not select a Vue page or layout.
Organization administration, dashboard authoring, and platform administration retain their
individual authorization checks. Catalog, query, and action APIs independently authorize
every request; the frontend guard is never an authorization boundary.

Vue Router waits for the authorized snapshot before committing a route. Late responses
cannot replace a newer route or mix mission contexts. Live props only refresh the resource
currently displayed. Reconnection requests context for the current browser route, which
may differ from the URL that originally opened the LiveView transport.

Plain remote anchors enter the same host router as shell links. The optional SDK
`bridge.navigate` method carries post-action navigation through that router too; older
host deployments retain native navigation. Invalidated bridges reject navigation as well
as queries and actions. Modified clicks, downloads, hash anchors, external destinations,
and session/controller links retain browser behavior.

Vue Router's history listener is registered before LiveSocket connects. While BrowserHost
is mounted, it owns Back/Forward events and prevents LiveSocket from also interpreting
them as LiveView navigation. Native Phoenix pages retain their history lifecycle.

The ordinary route catalog renders explicit host page components. Every catalog entry has
mounted dispatch coverage; an unrecognized kind renders a contained unavailable-page alert.
Legacy generic application workspaces and controller screens still use their existing
federation adapter/portal boundary and observer outside this catalog.

Mission and spacecraft application inventories render host-bundled recovery components,
independent of remote release admission. Each management mutation includes its resource
path, must match the active transport context, and reauthenticates before execution. A
late action from a departed page cannot mutate a newly selected mission. Ops installs one
refresh hook per transport and skips operational reads outside operational contexts.

Context contains identity, capabilities, notification data, operational summaries, and a
CSRF token. It never serializes entire user or organization records. Embedded legacy
`.html.heex` layouts pass `v-socket` explicitly because they bypass LiveVue's `~H` rewrite;
the connected socket is required for incremental updates.

Sign-in, organization switching, sign-out, invitation acceptance, and admin-mode
reauthentication remain native Phoenix forms and server-controlled session transitions.
Passwords remain in inputs and POST bodies, never bootstrap props or LiveView assigns.
Account menu submit items prevent Reka's `select` dismissal so their forms stay mounted
until document navigation. They do not prevent native clicks or submissions: removing a
form during a trusted click can cancel the browser's default submit action. Browser
coverage uses mouse input rather than DOM `.click()` to exercise that event ordering.
Vue hooks remove departed pages immediately during internal navigation. During a full
document unload they retain LiveVue's deferred cleanup: Phoenix destroys its views inside
the native submit event, before the browser serializes the form. Unmounting Vue at that
point detaches the form and cancels the submission. Controller entry links such as
`/admin-mode` use ordinary anchors rather than requesting a LiveView navigation.

## Page composition

`BrowserHost` mounts one `HostPage` per committed route. The host owns the page background,
gutter, heading placement, and content region. Its route/context breadcrumbs and title are
available while a remote loads and after a remote fails. Authentication layouts retain their
own native entry flow.

Domain pages declare `CadencePageHeading` with semantic breadcrumb items and named slots:
`title`, `description`, `metadata`, `actions`, and optional `eyebrow`. The shared UI package
composes these through `CadencePageChrome`, `CadencePageTitle`, `CadenceBreadcrumbTrail`,
`CadencePageDescription`, and `CadencePageActions`. Presentation DTOs supply copy and links;
header classes, decorative grids, and nested page gutters no longer select the appearance.
Use `presentationBreadcrumbs` and `pageContentAttrs` only when adapting older DTOs.

The host provides a route-scoped `PageChrome` context across the federation bootstrap.
Vue Teleports place slot contents into explicit host-owned regions. They retain their
original component ownership, events, native forms, and injected UI state. There is no
DOM scraping, global header store, or application-selected teleport selector. Registration
is idempotent by semantic content; unmount releases the owner, and a disposed route ignores
late registrations. An isolated page or Storybook preview renders the same UI components
locally when no host context is present.

Declare exactly one page heading per full-page surface. Keep section headings (`h2`),
filters, statistics, tables, and workspace tools in the page body. Actions belong to their
domain component; the host controls their placement. Narrow forms can constrain their
content width without shrinking or restyling the page header. New pages must use this
contract instead of `CadencePageHeaderFrame` or hand-authored `h1`/breadcrumb markup.

The production Page Composition stories cover lists, details, long mobile titles, loading,
and reactive actions. Host tests additionally mount a separate Vue application to verify
that remote content appears in the host and releases on failure.

## Tests and tools

- Vue interaction and lifecycle tests cover route selection, query allowlists, stale responses, history,
  and remote navigation alongside the owning host or UI package.
- Storybook tests exercise shared controls and accessibility in Chrome.
- The production browser journey clicks through Applications, Spacecraft, other feature areas,
  and Back/Forward, checking document,
  shell identity and sidebar state as well as remote release and action contracts.
- ExUnit covers scopes, authorization on context requests, explicit mutation paths, session changes, LiveView data delivery,
  and the HTTP/application-host contracts.
- `frontend/tools/phoenix/*.mjs` are genuine Node tools: publication locking, browser launch,
  process cleanup, and production federation smoke orchestration. Their Node tests remain `.mjs`.
- `mix test.browser`, `mix test.browser.full`, and `mix test.browser.federation` run the
  production federation browser gate, including publication build and signed release fixtures.
  The browser test VM enables `CADENCE_BROWSER_PROPS_DIFF=true` to exercise production-style
  incremental LiveVue props. Server contract tests use full projections for inspection.
  The gate checks mission entry even when that remote surface is unavailable, so sidebar
  context changes cannot depend on successful remote loading.

The old `cadence_web/assets/test` SFC compiler and historical extraction/source-snapshot
scripts are retired. Mounted assertions now compile real SFCs through Vite using workspace
packages. The old dashboard viewport suites called an absent `dashboard_viewport_smoke.mjs`
and targeted the earlier local-page architecture; those inactive suites and their fixtures
are retired. This is not a claim that the current federation smoke gate reproduces every
historical dashboard scenario. Add ongoing feature regressions to the owning domain frontend
package and production browser journey, rather than resurrecting migration snapshots.

Run `corepack pnpm test` from `frontend`, `mix precommit` from the repository root, and
`MIX_ENV=test mix test.browser.federation` from `apps/cadence_web` for the separate production
browser gate. A successful build or ExUnit run does not substitute for that browser gate.

## Organization and mission settings

Settings use the authenticated application host at `/settings/:section_id` and
`/missions/:mission_id/settings/:section_id`. The host supplies section navigation,
scope, history, opaque draft retention and page-bound transport ports. Mission
settings remain in the current mission. Application failures are contained within
their section.

Domain modules export `SettingsSectionContribution` from a public entry, with the
versioned `settings.section` metadata, a value reader and a Vue editor. The editor
receives `SettingsContext`, a snapshot, current edit permission, and a captured
`SettingsSectionPort`. `@cadence/plugin-sdk/settings-vue` provides the common
draft/conflict/save lifecycle; the domain owns its value decoder and semantics.

A backend application declares `SettingsSectionDefinition` with a
`SettingsProvider` implementing `settings_snapshot/2` and `save/4`. Providers
own defaults and validate values; shared versioned storage handles atomic revisions,
audit and updates. The settings coordinator admits platform applications or installed
applications applicable to the scope, and checks admission again for each write.
Register the matching lazy frontend loader in the host settings composition. These
are coordinated compiled contributions under ADR-024.

The initial owners are Cadence Governance and Commanding defaults. New owners can
reuse the shared UI without putting their domain values or effects in the host.
