# L19 spacecraft-scope apps: shape proposal (fe-setup → api, cc lead)

fe-setup, 2026-11-13. BACKLOG §11 L19. ux `screens/AppSurfaces.md` routes: spacecraft scope
`M/setup/spacecraft/:scId/apps/:appKey/:surface?`. Builds on L9 (`plans/app-surfaces.md`): same frame, same host.

## What exists (read, 2026-11-13)
- Apps installable at spacecraft scope: `spacecraft` (`[:mission, :spacecraft]`) and `telemetry_decom`
  (`[:spacecraft]` only). Everything else is mission or org scope.
- **S1 already takes `?spacecraft_id=`**: `AppSurfaceController.route_context/2` fetches the spacecraft and builds
  `HostContext.spacecraft(mission, spacecraft)`; the console's `fetchSurfaceHost` already passes it.
- **A1 lists mission scope only**: `Reads.MissionApps.load/2` uses `Registry.available_for_scope(:mission)` and the
  mission's installations, so a spacecraft's apps and their per-spacecraft status have no read.

## Proposed: one read (`/api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id/apps`)
```
GET → {apps: [<A1 row> for the apps available at spacecraft scope, with
               status and installation for THIS spacecraft, and only surfaces with scope: "spacecraft">],
       permissions: ["apps.install"]}
  404 spacecraft_not_found
```
- Same row shape as A1 (`key, name, description, platform, installed, state, version, status, surfaces`), so the
  console reuses its reader and the app row component.
- Install / disable / uninstall at spacecraft scope: the same verbs as A1 under this path
  (`POST /apps/:key/install | disable | uninstall`), if installations are per spacecraft; say if they're
  inherited from the mission instead, and the console shows them read-only with "Installed for the mission."
- Telemetry decom's activation requests (L10) carry `triggering_spacecraft_id`; the row's `activation_pending`
  should count only this spacecraft's open request.

## Console (fe-setup, against fixtures)
- Setup › Spacecraft › one spacecraft gains an **Apps** panel: the spacecraft-scope apps (name, status tag,
  version), each opening `setup.spacecraft.app` (`M/setup/spacecraft/:scId/apps/:appKey/:surface?`).
- That route reuses the L9 host frame with the spacecraft in the label (`EARENDIL-004 · APPS · TELEMETRY DECOM`),
  the breadcrumb back to the spacecraft, the app's spacecraft-scope surfaces as tabs, and S1 with
  `spacecraft_id`. Save outcomes and the activation line are as L9 (#77).
