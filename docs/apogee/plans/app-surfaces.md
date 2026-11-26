# L9 app surface host: shape proposal (fe-setup → api, cc lead)

fe-setup, 2026-11-13. Spec: ux `screens/AppSurfaces.md` (aed431cb). DECISIONS #75: a console surface host; apps own
their UI (managed-application framework).

## What exists (read, 2026-11-13)
- **Surfaces are Module Federation Vue components** (no iframes, no web components). Contract package
  `frontend/packages/plugin-sdk`: a module exports `{manifest, default}`; the host passes
  `{application, surface, context: HostContext, bridge: HostBridge}`. `HostContext` = `{scope, organizationId,
  missionId, missionName, spacecraftId, spacecraftName, actor {displayName, permissions[]}}`. `HostBridge` =
  `query`, `execute`, `navigate?`, `subscribe`.
- **Loading** (`frontend/apps/host/src/remote-loader.ts`): `@module-federation/runtime` registers the remote's
  `mf-manifest.json`, `loadRemote` with a 15 s timeout and a shared Vue singleton, then checks the module manifest
  against what the server approved (`catalog.ts`).
- **Data** goes only through the host bridge: `POST /api/cadence/application-host/v1/missions/:m[/spacecraft/:sc]/
  {query,actions}`, authenticated by the session cookie + `x-cadence-poc-session` (a per-catalog session id) +
  `x-csrf-token`. The console is same-origin, so this works from the SPA as is: **no new token is needed**.
- **Catalog** `GET …/catalog?application_key&surface_id&scope` returns the session id, CSRF token, bridge URL,
  context and the release coordinates (`remote_name, manifest_url, exposed_module, release_id`).
- **Surfaces shipping today:** `limits` (mission: `manage` "Definitions", `activity` "Current posture"),
  `derived_telemetry` (mission: `manage`), `telemetry_decom` (spacecraft: `manage`, `packet_bindings`).
- **Installation** applies directly (`ApplicationInstallations`), not through change sets. Limits and derived
  telemetry saves are immediate, versioned definitions. Only `telemetry_decom` has activation
  (`request_activation` → `ActivationRequest` approvals, legacy `/ops/activations`, L10).

## Gaps against the spec
1. `actor.permissions` is hard-coded `["applications:view"]`: the surface can't render read-only honestly.
2. No single app status (`ACTIVE / NOT INSTALLED / ACTIVATION PENDING / FAILED` + version): it's spread over the
   installation lifecycle, the app's `status_query_id` document and `ActivationRequest`.
3. Surfaces have no ops-vs-setup flag; `placement` (`application_workspace | ops_workspace | ops_dock`) is the
   nearest, so the host maps `application_workspace` → Setup and `ops_*` → Ops.
4. No dirty / title reporting from a surface (host-owned leave guard and title).
5. "Saving and activation go through the change set" (spec) has no backing: there's no change-set kind for app
   configuration or installation. **Ruled (DECISIONS #77): A now**: the host shows each app's own save results
   (a per-app save-outcome adapter, the seam for B later) and telemetry_decom's `request_activation` goes to L10
   approvals. B (change-set kinds for app config) is queued for domain much later.

## Proposed endpoints (console API, `/api/v1/missions/:mission_id`)

### A1 extended: `GET /apps` rows gain
```
status:   {state: "active"|"not_installed"|"disabled"|"activation_pending"|"failed", label, version|null}
surfaces: [{surface_id, label, order, purpose, area: "setup"|"ops", scope: "mission"|"spacecraft"}]
```
`status.state` merges installation + the app's status document + an open `ActivationRequest`; `label` is the
app's own words when it has them. `area` is from `placement` (gap 3).

### S1 `GET /apps/:key/surfaces/:surface_id/host?spacecraft_id=` (operator)
```
{catalog: <today's FrontendApplicationCatalog for this one surface:
           {schema: "cadence.first-party-frontend-catalog.v1", hostContract, generatedAt,
            session {sessionId, csrfToken, bridgeBaseUrl, context}, applications: [one CatalogApplication]}>,
 status: {state, label, version},
 surfaces: [the app's surfaces as in A1, for the host's tabs]}
```
- The catalog is built by today's code (`ApplicationHostCatalog`), console-authorized, so the console validates it
  with plugin-sdk's `assertFrontendApplicationCatalog` and hands it to the copied loader and bridge unchanged.
- The one change inside it: `session.context.actor.permissions` carries the REAL permissions (gap 1).
- `404 application_not_found | surface_not_found`; `409 application_not_installed` with `details.status` (the host
  shows "Limits & Alarming isn't installed on Earendil." + `Install` for admins).
- The bridge stays `/api/cadence/application-host/v1` (query/actions), unchanged.

### Later (DECISIONS #77: A now, B queued for domain much later)
- `application_installation` change-set kind (install / disable / uninstall staged; the apps list seam is ready).
- `application_configuration` change-set kind for app saves that need activation, and L10 reading
  `ActivationRequest`s as approvals.

## Console (fe-setup)
- Routes (spec): `setup/apps/:appKey/:surface?` (the existing `setup.apps` gains `:surface`),
  `setup/spacecraft/:scId/apps/:appKey/:surface?` (L19), `apps/:appKey/:surface` (Ops, `area: "ops"`).
- Frame: label + status tag + version, h1 = surface label, tabs = the app's surfaces, body = the federated
  component, host-owned loading / failed / not-installed / read-only states, leave guard.
- Loading: reuse `remote-loader.ts` and the bridge from `frontend/apps/host` by moving them into
  `frontend/packages/plugin-sdk` (shared), and add `@module-federation/runtime` to the console (lead's call).
- `HostBridge` gains an optional `report({dirty?, title?})` (plugin-sdk minor) for the leave guard; surfaces that
  don't call it never block leaving.
- Built against fixtures (a stub surface component) until S1 ships.
