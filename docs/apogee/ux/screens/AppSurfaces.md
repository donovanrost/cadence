# App surface host (L9, director decision 2026-11-13)

The console hosts application surfaces (limits definitions, derived telemetry, CFDP, decom bindings, …) in one
frame. The host owns everything around the surface; the app renders only its body. Owners: api (surface registry
and contract) and fe-setup (host). L10 activation approvals and L19 spacecraft-scope apps build on this.

## Routes
- Mission scope: `M/setup/apps/:appKey/:surface?` (Setup › Apps, existing). With no `:surface`, the app's first
  surface opens.
- Spacecraft scope (L19): `M/setup/spacecraft/:scId/apps/:appKey/:surface?`.
- Surfaces an app marks as `ops` (for example a CFDP transfer monitor) mount at `M/apps/:appKey/:surface` with the
  Ops rail. They're reached from the palette and from the app's Setup page. There's no rail item until an app needs
  one (ux decides then).

- **Deep links into a surface** (U42, lead 11-13): the console links to one item with a query on the surface route.
  The query keys belong to the app (server-owned), and an unknown key fails the surface, so the console only uses
  keys the app declares and never invents one. Derived telemetry:
  `M/setup/apps/derived_telemetry/manage?definition=<derived_definition_id>`. There's no separate console page per
  app item: the editor is the app's surface.

## Frame (reading layout inside the shell)
```
lbl "EARENDIL · APPS · LIMITS & ALARMING"          [status tag]  [v3 · Active]
h1  <surface title from the app descriptor>
local nav: the app's surfaces as tabs (Definitions · Rules · History)
┌ surface body (full width; the app renders this) ┐
└──────────────────────────────────────────────────┘
save outcome / activation line (host, #77)
```
- **Status tag:** `■ ACTIVE` / `○ NOT INSTALLED` (off) / `▲ ACTIVATION PENDING` (caution) / `◆ FAILED` (crit), plus
  the app version.
- **The host owns:** title, breadcrumb, tabs, the read-only notice ("Org admins change app configuration."), the
  loading, error and unavailable states, the leave guard for unsaved changes, save outcomes and activation
  requests (#77), and audit.
- **The surface gets** `{mission, scope (mission | spacecraft id), capabilities, theme tokens, locale/time
  format}` and reports `{dirty, staged_count, title?}`, plus navigation requests. It uses the console kit and
  tokens, so status colours, §4 time formats and U20 apply inside it too. It doesn't draw its own page header.

## Saving and activation (DECISIONS #77)
For now the host honours each app's own save semantics. Change-set kinds for app config come later (domain); the
host then gains the staged bar, and the surface doesn't change.
- **Apps that save immediately** (limits, derived telemetry): the surface's save takes effect at once. The host
  shows the outcome in its frame: nominal "Saved. It applies now." or the server's error (U20). It records nothing
  in Changes and shows no staged bar.
- **Apps that need activation** (decom): saving creates a request for activation that a second person approves
  (L10). The host shows a caution line "Waiting for activation approval · requested by Mira K. at 02:10Z". The
  approval appears on Setup › Changes as an approval, and on Now as "awaits your GO" for the approver.
- The status tag says which kind the app is: `SAVES IMMEDIATELY` in text-3 beside the version, so nobody expects a
  review step that isn't there.

## States
- **Loading:** `LOADING LIMITS & ALARMING…` in the body. The frame is already drawn.
- **The surface failed to load:** a crit callout "This app's page couldn't load: <reason>." with `Try again`, and
  the app version in text-3.
- **Not installed:** an off callout "Limits & Alarming isn't installed on Earendil." plus `Install` (admins), which
  follows the app's own install flow (#77) until app config is a change-set kind.
- **Read-only (no capability):** the body renders read-only, plus the notice.
- **Phone:** Setup's rule applies: "Setup is designed for a larger screen." with read-only content.
