# Legacy page deletion manifest (fe-setup for lead; api-ops deletes in reviewable batches)

fe-setup, 2026-11-13. One section per §11 row that's done or nearly done. Research only: nothing here is deleted
yet. R = `apps/cadence_web/lib/cadence_web/router.ex`, HPL = `apps/cadence_web/lib/cadence_web/live/host_page_live.ex`.
Module paths are under `apps/cadence/lib/cadence/` (domain) or `apps/cadence_web/lib/cadence_web/` (web) unless
they start with `frontend/`. Every "only" verdict comes from grepping callers; re-grep before each batch, since
the tree moves.

## Status at a glance
| Row | Legacy | Console replacement | Status |
| --- | --- | --- | --- |
| L1 requirements | `/ops/requirements…` | `setup.contact-planning` (+ `.requirement`) | after qa's live check (P4 re-test of b931638f2); delete with L2/L3 |
| L2 templates | `/ops/requirement-templates` | `setup.contact-planning.template` | after qa's live check; delete with L1/L3 |
| L3 fleet policy | `/ops/planning/policy` | `setup.contact-planning?tab=policy` | after qa's live check; delete with L1/L2 |
| L4 mission create | `/missions`, `/missions/new` | `org.missions`, `org.missions.new` | after qa's live check |
| L5 sign-in, invitations, no-org | POST `/sign-in`, POST `/invitations/:token` (+ dead modules) | console auth screens | deletable now (GET 302s stay) |
| L6 admin mode | `/admin-mode` | account menu admin mode | deletable now |
| L7 platform admin | `/admin/**` | `/console/admin/**` | after qa's live check (L7 migration) |
| L10 activations | `/ops/activations` | `setup.changes` + `setup.activation` | blocked: no console API yet |
| L11 data sources | `/ops/data-sources/**` | `setup.data-sources[/:sourceId]` | after qa's live check (endpoints 2e3c8c5ab) |
| L12 mission providers | `/comms/providers…` | `setup.stations.providers[/:providerId]` | blocked: L12 endpoints not built (api-ops) |
| L13 provider accounts | `/provider-accounts…` | `org.provider-accounts[/:accountId]` | blocked: grant/revoke/credential endpoints not built |
| L19 spacecraft apps | `/spacecraft/:sid/applications…` | `setup.spacecraft.app` | blocked: list read not built; surfaces emit legacy hrefs |
| L21 accept as signed-in | `/notifications` (accept event) | `account` invitations | deletable now (the bell stays) |

## Cross-cutting (every batch)
- **Shared files: trim, never delete.**
  - **Web:** HPL, `host_page_authorization.ex` (host policies) and `frontend/apps/host/src/routes.json`, which HPL
    compiles in. Remove each route's entry, then regenerate plugin-sdk's `catalog.generated.ts` with
    `frontend/tools/generate-route-types.mjs`.
  - **Domain:** `architecture/plane_boundary.ex` (its file list, lines ~121-157).
  - **Ops console:** `applications/ops_console.ex` (surface specs), `reads/application_surfaces/ops_console.ex`
    (read dispatch) and the shared action adapters, listed per row.
- **Redirects need a slug lookup.** Console URLs carry org and mission slugs (`shell/scope.ts`); legacy URLs carry
  ids. Follow `AuthRedirectController`'s pattern: look the slugs up from the id, and fall back to `/console`.
- **Legacy frontend.** Each row's Vue pages live under `frontend/apps/host`, `frontend/apps/{mission-catalog,
  organization-admin,ops-console}` and `frontend/modules/*`. They go with their routes. Whether `frontend/apps/host`
  can go whole is open (lead).
- **Docs** that map old URLs: `ux/information-architecture.md`, `ARCHITECTURE.md`, `api/session.md`,
  `ux/screens/Auth.md`. Update them in the same batch.

## L1 · L2 · L3 contact planning (one batch: the legacy pages link to each other)
**Routes:** L1 R:469, :473, :477; L2 R:465; L3 R:457. All are `HostPageLive` with `host_policy: :ops`. No legacy
REST route belongs to them. The console's `/api/console/v1/.../contact-planning/*` (R:1003-1075) stays.

**Delete (only these routes):**
- **L1:**
  - Web: `ops_requirement_page.ex`, `ops_requirement_declaration_page.ex`.
  - Reads: `reads/application_surfaces/planning/{contact_requirement_list, contact_requirement_new,
    contact_requirement_show, requirement_detail_projection, requirement_directory, requirement_declaration}.ex`.
  - Ops-console actions: `requirement_workflow.ex`, `requirement_declaration_workflow.ex`,
    `requirement_decisions.ex`.
- **L2:**
  - Web: `ops_requirement_template_page.ex`.
  - Reads: `planning/requirement_templates.ex`, `planning/template_ledger.ex`.
  - Ops-console actions: `requirement_template_workflow.ex`.
- **L3:**
  - Web: `ops_fleet_policy_page.ex`, `ops_fleet_policy_recovery.ex`.
  - Reads: `planning/{fleet_policy, fleet_policy_model, fleet_policy_projection}.ex`.
  - Ops-console actions: `fleet_policy_workflow.ex`, `fleet_policy_editing.ex`, `fleet_planning_form_duration.ex`.
- **All three together:** `reads/application_surfaces/planning/form.ex`, which only these three use.

**Trim:**
- `ops_console.ex` surfaces: `contact_requirement_list/new/show` :36-59, :88-90; `contact_requirement_template`
  :60-72, :91; `fleet_planning_policy` :272-285, :110.
- `reads/application_surfaces/ops_console.ex` clauses: :135-180, :241, :324-331, :507-577, :710-733.
- `actions/contact_planning.ex`: :37-45, :222-312, :403-420.
- `actions/fleet_planning.ex`: :26-31, :158-190, :318-392, :486-520. Check the last range.
- HPL: :150-190, :475-555, :1315-1318.
- `routes.json`: :767, :803, :817, :831, :845, :1240.
- **Keep:** `native_planning_input.ex`, `requirement_declaration_input.ex` and `requirement_template_input.ex`.
  `OpsContactSchedulingPage` and `OpsPlanReviewPage` use them; remove only their requirement and template
  clauses.

**Tests:**
- **Delete (web, `apps/cadence_web/test/cadence_web/`):**
  - `ops_requirement_page_test.exs`
  - `ops_requirement_declaration_page_test.exs`
  - `ops_requirement_template_page_test.exs`
  - `ops_fleet_policy_page_test.exs`
  - `live/ops_contact_requirements_live_test.exs` (move its `/ops/plans` check at :50 first)
- **Delete (domain):**
  - `reads/application_surfaces/contact_requirement_{list,show}_test.exs`
  - `applications/ops_console/actions/{requirement_decisions, fleet_policy_decisions, fleet_policy_editing}_test.exs`
- **Trim:**
  - `ops_console_contact_planning_test.exs`, `ops_console_test.exs`, `planning_producers_test.exs`
  - `trusted_surface_contract_test.exs`
  - `ops_fleet_planning_live_test.exs:39-46`, `fleet_planning_test.exs:23-31`

**Links in:**
- **Legacy pages deep-link to `/ops/requirements/:id`:** `OpsContactPlanShow.vue:60`, `OpsContactDetail.vue:218`,
  `OpsFleetPlanningRun.vue:227`, `OpsFleetPlanningNew.vue:216`. Delete them in the same batch or repoint them.
- **Server-side:** `contact_planning.ex:246`, a plan result pointing back.
- **Directory header:** the `/ops/planning` directory page (`OpsFleetPlanning.vue:29, :211`).
- The console, emails and priv have none.

**Redirects:**
- `/ops/requirements[/:id]` → `setup.contact-planning` (`?requirement=:id` once that view takes it).
- `/ops/requirement-templates` → `setup.contact-planning`.
- `/ops/planning/policy` → `setup.contact-planning?tab=policy`.

## L4 mission creation
**Routes:** R:240 `/missions`, R:241 `/missions/new`.

**Trim:**
- `mission_page.ex`: it also serves the `/missions/:id` overview. Remove `mission_list`/`mission_new`,
  `creation_session/4`, `matches?/2` and `action/3`.
- HPL: :840-863 (`host:mission`), :1278-1284.
- `applications/mission_catalog.ex`: :96-115.
- `mission_catalog/action_provider.ex`: :15-16, :78, :103, :111.
- `reads/application_surfaces/mission_catalog.ex`: :135-139.

**Delete:** `Missions.Creation`, `Reads.Missions.CreationForm` and `Reads.Missions.Directory`. The console uses
`ConsoleMissions`. **Keep:** `Reads.Missions.Pages`, which the overview uses.

**Tests:**
- Delete `live/mission_{new,list}_live_test.exs`.
- Trim the list/new cases in `mission_page_test.exs`.

**Keep:** REST `POST /api/organizations/:id/missions` (R:1197). It's a documented bearer API
(`api/inventory.md:40`), not part of the page. Retire it separately if ever (open: external clients).

**Links in:** `live/mission_auth.ex:22` and `application_host_controller.ex:869` redirect to `/missions`. Point
them at the console.

**Redirects:**
- `/missions` → `/console/:org/org/missions`
- `/missions/new` → `…/org/missions/new`

## L5 sign-in, invitation acceptance, no-organization (deletable now)
**Keep:** the GETs R:109-111 (`AuthRedirectController`'s 302s to `/console/*`).

**Delete:**
- **POSTs:** R:101 `POST /sign-in` (only `UserSessionController.create`) and R:135 `POST /invitations/:token`
  (`OrganizationInvitationController.update`). Answer stale POSTs with a 303 to the console screen.
- **Dead today:** `live/user_session_live.ex`, `controllers/no_organization_controller.ex`,
  `live/no_organization_live.ex` and `OrganizationInvitationController.show`.
- **Only these routes:** `controllers/organization_invitation_controller.ex`, `live/organization_invitation_live.ex`,
  `plugs/redirect_if_authenticated_scope.ex` and `authenticated_entry.ex`.
- **Helpers:** `IdentityParams.durable_session/1` and `organization_invitation_acceptance/1`.
- **Legacy frontend:** `frontend/apps/host/src/auth-and-navigation/features/{sign-in,invitation-acceptance,
  organization-access}` and `shell/registry.ts` rows :46, :48, :49.

**Keep in `UserSessionController`:**
- `delete` (R:141), used by the console's sign-out.
- `update` (R:142), used by `shell/admin-org.ts`.
- `too_many_attempts/1`, which `admin_mode_controller` and the invitation controller also use. Move it if those go.

**Tests:**
- Delete `controllers/{organization_invitation_controller, user_session_controller, no_organization_controller}_test.exs`,
  `live/user_session_live_test.exs` and `authenticated_entry_test.exs`. Move their redirect cases first.
- Trim `browser_shell_test.exs` :47, :110, :217, :266.

**Must stay:**
- `user_notifier.ex:7` emails `/invitations/<token>`: keep that GET's 302 indefinitely, or move the email to
  `/console/invitations/`.
- `/sign-in` and `/no-organization` are redirect targets in `require_authenticated_scope.ex:23`, `user_auth.ex:17`,
  `organization_auth.ex:27,31,48`, `admin_auth.ex:30` and `dashboard_author_auth.ex:17`. They keep working through
  the 302s.

## L6 admin mode step-up (deletable now)
**Routes:** R:143-145 `GET/POST/DELETE /admin-mode`.

**Delete:** `controllers/admin_mode_controller.ex`, `live/admin_mode_live.ex`,
`frontend/apps/host/src/auth-and-navigation/features/admin-mode` and registry row :47.

**Keep:** `CadenceWeb.AdminMode` and `ConsoleAdmin.record_admin_mode`; the console uses both.

**Tests:** trim `browser_shell_test.exs` :96, :137, :189 and `auth_navigation_contract_test.exs:12-26`.

**Links in:** `live/admin_auth.ex:23`.

**Redirect:** `GET /admin-mode` → `/console` (the account menu holds it).

## L7 platform admin
**Routes:** R:591-598 (`/admin`, `/admin/runtime`, `/admin/organizations[/new|/:org_id[/invite]]`).

**Delete:**
- **Web:** `platform_administration_page.ex`, `administration_diagnostics.ex`, `live/admin_auth.ex`.
- **Org admin providers:** `applications/organization_admin_providers/admin_{home,runtime,organization_list,
  organization_new,organization_show,organization_invite}.ex`.
- **Reads:** `Reads.Administration.{PlatformOverview,OrganizationDirectory,OrganizationDetail}` and
  `Reads.Dashboards.RuntimeDiagnostics`.
- **Administration:** `Administration.ServiceIdentityIssuance`.
- **Legacy frontend:** `frontend/apps/organization-admin/src/Admin*.vue` and
  `frontend/apps/host/src/administration/**`.

**Trim:**
- `organization_admin.ex` :110-190, :234-259
- `organization_admin_query.ex` :46-79, :150-178
- `organization_admin_action.ex` :265-333
- `plane_boundary.ex` :130-136
- HPL :1045-1072, :1244-1250

**Keep:** `OrganizationCreation` and `OrganizationInvitations`, which `ConsoleAdmin` uses. Only their `load/1,2`
die.

**Open:** whether `ApplicationHostController.admin_federated` (R:212-222) serves anything else.

**Tests:**
- Delete:
  - `platform_administration_page_test.exs`, `platform_organization_detail_page_test.exs`
  - `administration_diagnostics_test.exs`, `live/admin_live_test.exs`
  - `platform_organizations_test.exs`, `organization_detail_test.exs`
  - `auth/service_identity_issuance_test.exs`
- Trim `organization_admin_provider_test.exs:215-224`.

**Links in:**
- `authenticated_entry.ex:7` (deleted with L5)
- `organization_auth.ex:24`, `admin_mode_controller.ex:44` (deleted with L6)
- `runtime_diagnostics.ex:82`, `host_routes.ex:23`, `application_host_catalog.ex:1090`

**Redirects:** `/admin/**` → `/console/admin/**`, with `/new` and `/invite` going to the list or detail page.
Check that the console route takes the org id.

## L10 activation approvals (blocked: no console API)
**Routes:** R:563.

**Keep:** the REST `/api/organizations/:org/missions/:m/activation_requests…` (R:1386-1401). It's a tested public
API; the legacy page doesn't use it.

**Would delete:**
- **Web:** `activation_approvals.ex`, with HPL :13, :905-935, :1254-1261, :1380.
- **Surfaces:** the `activation_requests` surface (`ops_console.ex:300-306, :112`; read dispatch :500-504, :735).
- **Actions:** the `{"activation_requests","decide"}` clauses in `actions/mission_operations.ex`.

**Keep:** `Reads.ActivationApprovals` (reusable, `api/inventory.md:134`).

**Tests:**
- Delete `live/ops_activation_requests_live_test.exs`.
- Trim `activation_approvals_test.exs`, `host_page_live_test.exs:58` and `ops_console_mission_operations_test.exs:24`.

**Links in:**
- `reads/spacecraft/configuration.ex:130` (an `approvals:` link the legacy host checks at
  `spacecraft-configuration/contracts.ts:160`)
- `settings_page.ex:15`

Both need a console target (`setup.changes`). **Unblocks:** api lands `plans/activations.md` and fe-setup turns
`ACTIVATIONS_LIVE` on.

## L11 data sources
**Routes:** R:437, :441, :567 (`registration/new`), :571-576 (settings). They're served only by
`OpsDataSourcesPage` (HPL:98-142, :1322).

**Delete:** `ops_data_sources_page.ex`, `applications/ops_console/actions/source_inventory_actions.ex` and
`reads/application_surfaces/data_operations/sources.ex`. Its sibling `historical_workflows.ex` is L16 and stays.

**Keep:**
- `OpsConsole.Actions.DataSources`: the console writes controller wraps it (`data_source_writes_controller.ex:17`).
- `Reads.DataSources` and `Reads.DataSourceDirectory`.

**Trim:** `ops_console.ex` :349-395 (check :446, :475, :491).

**Tests:**
- Delete:
  - `ops_data_sources_page_test.exs`
  - `live/ops_data_sources_{,authorization_,byo_lifecycle_,focus_,capability_remediation_,deployment_}live_test.exs`
  - `reads/data_source_inventory_test.exs`, `applications/source_inventory_actions_test.exs`
- Keep `data_sources_test.exs` and `ops_console_action_adapters_test.exs`.

**Links in:** none in code; `ux/information-architecture.md:144`.

**Redirects:**
- list and `registration/new` → `setup.data-sources`
- `:id[/settings]` → `setup.data-sources/:sourceId`

## L12 · L13 providers (blocked: api-ops' endpoints, plans/providers.md)
**L12**
- **Routes:** R:384, :388, :392.
- **Would delete:** `mission_provider_page.ex`, `reads/application_surfaces/comms_providers.ex` and
  `reads/comms/mission_providers.ex`.
- **Trim:**
  - `applications/comms/action_provider.ex`: only the provider bindings :18-21, :104-124. It also serves the
    transport, routing and station forms.
  - `comms.ex`: surfaces :83-105, actions :141-145, :224-225.
- **Keep:** `MissionProviderRegistration`, `Control.Providers` and `Management.Providers`, the console writes'
  future backend.
- **Tests:**
  - Delete `live/comms_provider_live_test.exs`, `mission_provider_page_test.exs` and `comms_provider_pages_test.exs`.
  - Trim `application_surfaces_test.exs:472-487`, `trusted_surface_contract_test.exs:329`,
    `comms_application_test.exs:435-437` and `provider_registry_test.exs:212-218`.
- **Links in:** `reads/comms/pages.ex:660, :2322-2323`.
- **Redirects:** list and `new` → `setup.stations.providers`; `:provider_id` → `…/providers/:providerId`.

**L13**
- **Routes:** R:253, :257, :261. The `:provider_accounts` host policy belongs only to them.
- **Would delete:**
  - Web: `provider_account_detail_page.ex`, `provider_account_registration_page.ex`, `organization_module_page.ex`.
  - Org admin providers: `applications/organization_admin_providers/provider_account_{list,new,show}.ex`.
  - Reads: `Reads.Comms.ProviderAccountDirectory` and `Reads.Comms.ProviderAccountDetail`. The console uses
    `Management.ProviderAccountDirectory`.
- **Trim:** `organization_admin_action.ex` :13-60, :194-227 and `organization_admin.ex` :36-80, :211-222.
- **Keep:** `ProviderAccountOperations` (the future grants backend) and `ProviderAccountRegistration`. Check its
  hrefs :48, :60, :150.
- **Tests:**
  - Delete `live/provider_account_live_test.exs`, `provider_account_detail_page_test.exs`,
    `provider_account_registration_page_test.exs`, `organization_module_page_test.exs`,
    `provider_account_detail_test.exs` and `application_contributions/organization_admin_provider_test.exs`.
  - Trim `organization_admin_test.exs`, `host_page_live_test.exs` and `application_host_bridge_test.exs`.
- **Redirects:** list and `new` → `org.provider-accounts`; `:id` → `org.provider-accounts/:accountId`.

**Blocked:** deleting either now loses the only UI for:
- L12: create, validate, sync and archive.
- L13: grant, revoke and credential revoke.

The domain fixes listed in `providers.md` land with those endpoints.

## L19 spacecraft apps (blocked)
**Routes:** R:586 (list) and R:630-639 (`ApplicationHostLive`). The federated GETs (R:172-182) and the bridge API
(R:1160-1182) stay; the console's surface host uses them.

**No module goes whole.** Trim only the spacecraft branches:
- `application_management.ex:51-66`
- `application_host_live.ex:428, :469-470, :555-562`
- `ApplicationInventory.spacecraft/2`

Keep `SpacecraftInstallations`.

**Tests:**
- Delete `live/spacecraft_applications_live_test.exs`.
- Trim `application_management_test.exs`, `host_page_live_test.exs:55` and `spacecraft_telemetry_surface_test.exs`.

**Blocked:**
1. The spacecraft apps list read isn't built (`SPACECRAFT_APPS_LIVE` is off).
2. App surfaces emit legacy hrefs that the console's `SurfaceMount` sends through `window.location.assign`. Repoint
   these first:
   - `spacecraft_installations.ex:152`, `spacecraft/overview.ex:223`, `spacecraft/readiness.ex:168`
   - `readiness_contributions.ex:36`, `configuration.ex:127`, `comms/pages.ex:1926`
   - `telemetry_decom/configuration.ex:48, :421`, `packet_bindings.ex:83`
   - `legacy_application_redirect_controller.ex:18`

**Redirects:** list → `setup.spacecraft.one`; `:key[/:surface]` → `setup.spacecraft.app`.

## L21 accept an invitation as a signed-in user (deletable now)
**Routes:** R:590 `/notifications` (its accept event, HPL:1018-1040).

**Delete:** `notifications_page.ex`, `Reads.Notifications.Inbox`,
`applications/organization_admin_providers/notifications.ex` and
`frontend/apps/organization-admin/src/NotificationsPage.vue`. Also delete `Cadence.Notifications.Actions` after
trimming `organization_admin_action.ex:235, :249`.

**Keep:** `live/notifications_bell.ex` (every auth on_mount attaches it) and `Accounts.accept_invitation_as_user`,
which the console uses.

**Tests:**
- Delete `live/notifications_live_test.exs`, `notifications_page_test.exs` and `reads/notifications/inbox_test.exs`.
- Trim `live/notifications_bell_test.exs` and `live/user_menu_integration_test.exs` if the bell stays.

**Redirect:** `/notifications` → `/console/account`.

## Open questions for lead
1. Can `frontend/apps/host` go whole once these rows are gone, or do other legacy pages still need it?
2. Do external clients use the bearer `POST /api/organizations/:id/missions`? It's kept until someone knows.
3. Does `ApplicationHostController.admin_federated` (R:212-222) serve anything but the admin surfaces?
4. Can the comms provider and organization-admin provider-account surfaces also be reached through the generic
   `/applications/:key` host? If so, trimming their entries changes that host's catalog too.
