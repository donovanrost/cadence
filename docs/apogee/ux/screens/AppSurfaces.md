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

## Frame (reading layout inside the shell)
```
lbl "EARENDIL · APPS · LIMITS & ALARMING"          [status tag]  [v3 · Active]
h1  <surface title from the app descriptor>
local nav: the app's surfaces as tabs (Definitions · Rules · History)
┌ surface body (full width; the app renders this) ┐
└──────────────────────────────────────────────────┘
staged-changes bar (host) when the surface has staged changes
```
- **Status tag:** `■ ACTIVE` / `○ NOT INSTALLED` (off) / `▲ ACTIVATION PENDING` (caution) / `◆ FAILED` (crit), plus
  the app version.
- **The host owns:** title, breadcrumb, tabs, the read-only notice ("Org admins change app configuration."), the
  loading, error and unavailable states, the leave guard for unsaved changes, staging and activation, and audit.
- **The surface gets** `{mission, scope (mission | spacecraft id), capabilities, theme tokens, locale/time
  format}` and reports `{dirty, staged_count, title?}`, plus navigation requests. It uses the console kit and
  tokens, so status colours, §4 time formats and U20 apply inside it too. It doesn't draw its own page header.

## Saving and activation
Changes that need activation go through the change set (Changes.md). The host bar reads "2 changes staged in
Limits & Alarming" with `Review` → Setup › Changes. Activation approvals (L10) appear there as approvals, and on
Now as "awaits your GO" when they need you. There's no app-local Apply button.

## States
- **Loading:** `LOADING LIMITS & ALARMING…` in the body. The frame is already drawn.
- **The surface failed to load:** a crit callout "This app's page couldn't load: <reason>." with `Try again`, and
  the app version in text-3.
- **Not installed:** an off callout "Limits & Alarming isn't installed on Earendil." plus `Install` (admins), which
  goes through a change set.
- **Read-only (no capability):** the body renders read-only, plus the notice.
- **Phone:** Setup's rule applies: "Setup is designed for a larger screen." with read-only content.
