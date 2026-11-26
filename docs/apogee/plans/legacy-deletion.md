# Legacy page deletion manifest (fe-setup for lead; api-ops deletes in reviewable batches)

fe-setup, 2026-11-13. One section per §11 row that's done or nearly done. Research only: nothing here is deleted
yet. R = `apps/cadence_web/lib/cadence_web/router.ex`, HPL = `apps/cadence_web/lib/cadence_web/live/host_page_live.ex`.
Module paths are under `apps/cadence/lib/cadence/` (domain) or `apps/cadence_web/lib/cadence_web/` (web) unless
they start with `frontend/`. Every "only" verdict comes from grepping callers; re-grep before each batch, since
the tree moves.

## Status at a glance
| Row | Legacy | Console replacement | Status |
| --- | --- | --- | --- |
| L1 requirements | `/ops/requirements…` | `setup.contact-planning` (+ `.requirement`) | **done** (batch 2, restart (a) 11-14 14:28Z: redirects f19f81649, pages 10343f337) |
| L2 templates | `/ops/requirement-templates` | `setup.contact-planning.template` | **done** with L1 (batch 2) |
| L3 fleet policy | `/ops/planning/policy` | `setup.contact-planning?tab=policy` | **done** with L1 (batch 2) |
| L4 mission create | `/missions`, `/missions/new` | `org.missions`, `org.missions.new` | **done** (batch 2, restart (a) 11-14 14:28Z: redirects f2e4f172d, pages f68df5163, host harness 738f24e9e); its federated surfaces wait for fe-ops' L1–L4 federated batch |
| L5 sign-in, invitations, no-org | POST `/sign-in`, POST `/invitations/:token` (+ dead modules) | console auth screens | **done** (batch 1, live 11-14 01:46Z, 12018de45; GET 302s stay) |
| L6 admin mode | `/admin-mode` | account menu admin mode | **done** (batch 1, 5320cb7a3; host account menu follow-up 9ece4eed3) |
| L7 platform admin | `/admin/**` | `/console/admin/**` | **done** (batch 3, restart (a) 11-14 14:28Z: redirects 0c6ed155c, pages b2cffbd10, federated surfaces 7227cc524, frontend 22d048048) |
| L8 dashboards | `/ops/dashboards[/new\|/:id[/edit]]`; library, playlists, settings, shares, snapshots | `ops.dashboards[.new]`, `ops.dashboard[?edit=1]` | L8a done (live 11-14 01:46Z, c21fad95a); federated batch done (restart 1, 11-14 08:01Z, 4cb04734d); L8b done (live 11-14 09:20Z, 3dbb243b0; Settings live a8649a04f, member path afd1201ca); L8c done (step 1 D18 `refresh`; step 2 live 11-14 15:54Z, fe-setup/l8c-r5, D18 latency flat); **L8 done** except L8c step 3, domain's later migration dropping the decision events table |
| L10 activations | `/ops/activations` | `setup.changes` + `setup.activation` | console live (be59d4f32, 6e289aa35); deletion pulled from the 11-16 combined batch (director: no in-node approval as a precondition); it runs after the model gate (~11-16 17:00Z) with a real console approval, then goes in the next batch |
| L11 data sources | `/ops/data-sources/**` | `setup.data-sources[/:sourceId]` | **done** (batch 3, restart (a) 11-14 14:28Z: redirects 70d25b5db, page 4d70c076d) |
| L12 mission providers | `/comms/providers…` | `setup.stations.providers[/:providerId]` | **done** (combined batch, live 11-16 07:52Z on c8f869d52; qa PASS 07:58Z) |
| L13 provider accounts | `/provider-accounts…` | `org.provider-accounts[/:accountId]` | **done** with L12 (combined batch, live 11-16 07:52Z) |
| L19 spacecraft apps | `/spacecraft/:sid/applications…` | `setup.spacecraft.app` | blocked: list read not built; surfaces emit legacy hrefs |
| L21 accept as signed-in | `/notifications` (accept event) | `account` invitations | **done** (batch 1, 163cd0dfa; host page frontend 09974fc56; the bell stays) |
| §11c(A) organization | `/`, `/settings[/:section]` | `org.home`, `org.settings` | **done** (combined batch, live 11-16 07:52Z on c8f869d52; qa PASS 07:58Z) |
| §11c(B) mission setup | mission home, settings, spacecraft, catalog, comms, applications (+ 18 comms aliases) | `setup.*` | **done** (live 11-16 09:21Z on 5f89cb782; qa PASS 09:24Z: 89 legacy routes 302 once → 200) |
| §11c(C1) ops (all but alarms) | `/ops` landing, planning, plans, contacts list/records, timeline, commands, contact-workspace | `ops.now`, `ops.contacts.*`, `ops.timeline`, `ops.commands.*` | built (`plans/c1-ops-deletion.md`: api b0958fd09, dashboards `dashboards/c1-frontend`, fe-setup's server half); dry waits on R1 + the A1/A2 armed run after the model gate |
| §11c(C2) ops alarms | `/ops/alarms` | `ops.alarms` | waits on A6c (mission-wide conditions, after #92 phase 3) |
| §11c(D) ops explore, data operations | `/ops/explore`, `/ops/telemetry/explore`, `/ops/data-operations[/manage]` | see `plans/parity-ops-d.md` | parity audit (dashboards, 11-16) |

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
- **api's redirects ride with each deletion (lead, 11-14).** api built them on `api/legacy-redirects` (worktree
  `…/cadence/api-legacy-redirects`, unpushed), one commit per row: `53c6cb123` L1+L2+L3 (adds
  `CadenceWeb.ConsolePaths`), `9fb865e63` L4, `78b406a26` L7, `a072ae6cb` L11; `db58dfa61` (legacy nav repointed)
  is independent. A row's legacy LiveView tests fail once its routes redirect, so `git cherry-pick -x` api's commit
  into the same batch as that row's deletion and run the touched tests together. Batch 1 (L5, L6, L21) has none.
- **Legacy frontend.** Each row's Vue pages live under `frontend/apps/host`, `frontend/apps/{mission-catalog,
  organization-admin,ops-console}` and `frontend/modules/*`. They go with their routes. Whether `frontend/apps/host`
  can go whole is open (lead).
- **Don't edit server copy for legacy-backed settings sections before §11c(B)/(C) (director, 11-15).** The legacy
  host admits a settings section only if its contribution's metadata EQUALS the server definition
  (`SettingsSectionBoundary`); a one-sided copy edit hid governance on the legacy settings pages from 11-13 to
  11-15 (3bb80ce99, fixed by devops f817c9ea0). devops' contract test guards it.
- **Docs** that map old URLs: `ux/information-architecture.md`, `ARCHITECTURE.md`, `api/session.md`,
  `ux/screens/Auth.md`. Update them in the same batch.

## L1 · L2 · L3 contact planning (one batch: the legacy pages link to each other)
**Routes:** L1 R:469, :473, :477; L2 R:465; L3 R:457. All are `HostPageLive` with `host_policy: :ops`. No legacy
REST route belongs to them. The console's `/api/v1/.../contact-planning/*` (R:1003-1075) stays.

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


## L1–L4 federated surfaces (own batch; owner fe-ops, after their L8 federated batch)
Batch 2 (fe-setup, `fe-setup/legacy-batch2`: 7172308b5 L1–L3, 8f6b8ce0e L4) deletes only what nothing else uses.
Building it found federated surfaces this manifest missed, which keep these alive (lead, 11-14):
- **ops_console surfaces:** `contact_requirement_list`, `contact_requirement_new`, `contact_requirement_show`,
  `contact_requirement_template` and `fleet_planning_policy` (spec in `applications/ops_console.ex`, dispatch in
  `reads/application_surfaces/ops_console.ex`, frontends in `frontend/apps/ops-console` and their modules).
  - **Reads kept for them:** `ContactRequirementList`, `ContactRequirementNew`, `ContactRequirementShow`,
    `Planning.RequirementTemplates`, `Planning.FleetPolicy`, `Planning.Form`.
  - **Actions kept for them:** `RequirementDecisions`, `FleetPolicyEditing`, `FleetPlanningFormDuration`.
- **mission_catalog surfaces:** `mission_list` and `mission_new`, with their validate/save bindings. They keep
  `Missions.Creation`, `Reads.Missions.CreationForm` and `Reads.Missions.Directory`. The bearer REST
  `POST /api/organizations/:id/missions` stays regardless.
- **Delete with the surfaces:** the specs, dispatch clauses, frontend modules, the federated manifests'
  entries, `first-party-manifest-parity.test.ts` rows (deletion-only in `frontend/apps/host`), then the reads,
  actions and modules above once nothing calls them. Re-grep each first.
- **Also delete `frontend/tools/retained-legacy-routes.json` and its test exception** (fe-ops, 11-14): batches
  2 + 3 keep the seven removed L1–L4 paths in plugin-sdk's route TYPE catalog through that file, because these
  surfaces still link them by type. Remove it, the generator's read of it and the routes.json ∪ retained comparison
  in `plugin-sdk/src/routes/routes.test.ts`, then regenerate the catalog.

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

**`UserSessionController`:** deleted with its root `DELETE /session` and `PUT /session/organization`
(#664). The console signs out with `DELETE /api/v1/session` and selects organizations with
`PUT /api/v1/session/organization`.

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

## L8 dashboards (dashboards for lead, 2026-11-14; three batches)
Only the directory, viewer, editor and New are replaced (lead 11-14). Library, playlists, settings (with its
activity and diagnostics tabs), shares and snapshots keep their legacy pages until their console slices are live.
The ten legacy pages share one frontend module, one HPL dispatch and one set of federated `ops_console`
surfaces, so most files are **trimmed** in L8a and **deleted** in L8b. Paths come from an inventory run on
11-14. R line numbers move while api-ops' redirect is in flight, so routes below are named by path. Re-grep
before each batch.

**qa:** the editing smoke passed live on 11-14, 11:52-11:56Z (duplicate, edit, save, versions, restore, Save as
copy, conflict with Continue editing). qa then cleared the redirect. New dashboard still needs qa's live
confirmation (the 422 fix was 78564fa90).

### L8a directory, viewer, editor, New (after qa's live check; to the director with qa's result)
**Routes:** `/ops/dashboards`, `/ops/dashboards/:id`, `/ops/dashboards/:id/edit`, `/ops/dashboards/new`.

**Done by the cutover (api-ops 5e151d4a3, one commit; qa passed it live on :4011, 11-14: the three redirect with
their params, and library, playlists, new, settings, activity and diagnostics still serve legacy):**
- The first three live routes are now `LegacyDashboardRedirectController` (one hop; slugs from the signed-in
  org's mission, else `/console`). Kept: `from`, `to`, `spacecraft` (legacy `spacecraft_id`), `refresh`, `kiosk`;
  the directory's `q`/`tags` (legacy `query`/`tag`); `/edit` adds `?edit=1`.
- `routes.json` lost its three entries.
- The page-only suites are deleted or moved to the console API tests (listed in the commit message).
- Left for this batch: `catalog.generated.ts`, which isn't regenerated because the legacy frontend still links
  those paths by type (`TimelinePanel.vue` etc.).

**Redirects** (slug lookup, falls back to `/console`):
- directory → `ops.dashboards`
- `/:id` → `ops.dashboard`, keeping `from`, `to`, `spacecraft`, `refresh` and `kiosk`
- `/:id/edit` → `ops.dashboard?edit=1`
- add `/new` → `ops.dashboards.new` in this batch (still a live legacy route)

**Delete (web):**
- `ops_dashboard_page.ex`, `ops_dashboard_page/actions.ex`, `ops_dashboard_page/updates.ex`
- `ops_directory_page.ex`, `ops_creation_page.ex`
- `Cadence.Dashboards.AuthoringDraft` (the LiveView-held draft; the console is stateless). First trim its
  legacy-only callers:
  - `Reads.Dashboards.Editor.staged/3` (editor.ex:38-50; `load/4` has no callers at all)
  - `DashboardPage.staged/3` (:63-88)
  - `ObservableChoices.staged/3` (:52-55)
  - `Versions.list/staged/summary`, which are legacy-only (`compare` stays)
- `Cadence.Dashboards.RuntimeCoordinator` and `RuntimeInvalidationRelevance` (`dashboards/runtime_coordinator.ex`,
  `runtime_invalidation_relevance.ex`). Nothing in lib calls them, and api-ops confirms C1 coalesces
  invalidations itself (lead 11-14).
- `test/support/dashboard_review_fixtures.ex` (no users)

**Trim (shared):**
- **HPL:**
  - the `workspace`, `create` and `directory` handlers (inside :658-803; `create` matches without an id guard);
  - `dashboard_refresh` (:1227-1236) and its `handle_info` clauses (:1169-1182);
  - the dashboard steps of the prepare pipeline (:1295-1299, :1308-1311; keep :1300 Exploration);
  - `active_dashboard_id` where only these pages use it.
- **`frontend/apps/host/src/routes.json`:** the `dashboards.new` entry (5e151d4a3 removed the other three). Then
  regenerate plugin-sdk's `catalog.generated.ts` with `tools/generate-route-types.mjs`, after repointing the
  legacy frontend's typed links to those paths.
- **`live/host_page_authorization.ex`:** nothing yet. `:ops_dashboard_author` still guards library, playlists
  and settings.
- **Host contributions** (`ops-workspace/features/module-pages/contributions.ts:126-169`): only the directory,
  workspace and creation contributions.
- **`frontend/modules/dashboards-and-exploration`:** nothing in L8a (fe-setup 11-14). `directory.ts`,
  `creation.ts`, `workspace.ts` and `features/{directory,creation,workspace,dashboard}` are still imported by the
  federated `OpsDashboard{Directory,New,Show}.vue`, `OpsConsoleApplication.vue`, `chart-runtime-compatibility.test.ts`
  and storybook's `TelemetryChart`/`DashboardWidgetDrawer` stories (`charts.ts` re-exports `features/workspace`).
  The L8b pages don't import them. They go with the federated batch below.
- **`frontend/tools/phoenix/ops_initial_state_browser.mjs`:** the dashboard routes (:44-52) and assertions
  (:135-167). Also its driver's `draft-dashboard` seed (`browser_test/…/ops_initial_state_browser_test.exs`
  :33-91). CI runs it in `ci.yml`'s "Federation browser (2/2)" job (#73; this branch's `frontend.yml` predates
  it). The trim keeps the step, because `/ops/explore`, commands and the other routes stay in it. If a later trim
  empties the step, tell devops.

**Keep** (the console API or channel uses them):
- web `OpsWorkspaceURL` (`console/dashboard_runtime.ex`)
- `DashboardPage.load`, `Editor.outline`, `Versions.compare`, `ObservableChoices.search`,
  `ExecutionDiagnostics.load`
- `Reads.Dashboards.{Workspace,Directory,Activity}`, `DirectoryActions`, `Dashboards.Creation`,
  `CurrentVersions`, `RuntimeInvalidation`
- `DashboardAuthorAuth.authorized?/2`

**Tests:**
- **Delete:**
  - `live/ops_dashboard_authoring_entry_live_test.exs` (5e151d4a3 removed its directory half)
  - `ops_directory_page_test.exs` (its two remaining read-model tests: move them to the read's own test first)
    and `ops_creation_page_test.exs`
  - `ops_dashboard_updates_test.exs` (5e151d4a3 already deleted the directory/editor live tests and the
    `ops_dashboard_{page,editor}` tests)
  - `dashboard_authoring_draft{,_conflict}_test.exs`
  - `reads/dashboards/{creation,directory}_destination_test.exs`
  - `dashboards/runtime_coordinator_test.exs`, `dashboards/runtime_invalidation_relevance_test.exs`
- **Change:**
  - `test/support/dashboard_authoring_draft_test_support.ex` calls `AuthoringDraft.open`, and the console tests
    use it (`dashboard_settings_api_test`, `dashboard_authoring_api_test`, `dashboard_stateless_authoring_test`).
    Rewrite `authoring_draft_setup` onto `StatelessAuthoring` before AuthoringDraft goes.
  - `test/support/ops_dashboard_page_test_support.ex`: keep `dashboard_page_setup`/`save` (the console channel,
    API and directory tests use them). Drop the `host:ops-page` helpers and `@renderer`.
  - `dashboard_workspace_read_test.exs:23` shells out to the deleted producer check; remove that assertion.
  - Frontend: `OpsModulePage.test.ts:7-18`, `landing.test.ts`, plugin-sdk `routes.test.ts`. (5e151d4a3 trimmed
    `BrowserHost.test.ts` and `routes.test.ts`; `host_page_live_test` now uses `/ops/dashboards/library` as its
    ops-layout example, so that changes again in L8b.)
  - Storybook: delete `DashboardWidgetDrawer.stories.ts` and `TelemetryChart.stories.ts`, unless L8b's pages
    still use those components.

**Links in:**
- Legacy host nav `dashboards/new` (author-only): `ops-workspace/features/frame/navigation.ts:35,49`,
  `primary-navigation/navigation.ts:64`, `ops-workspace/shared/destinations.ts:32`, `BrowserHost.vue:252`,
  timeline `contracts.ts:149` and `TimelinePanel.vue:79`. The directory and viewer links already go through the
  redirect.
- `live/dashboard_author_auth.ex:38` sends to the legacy directory, now one extra hop through the redirect.
  Point it at the console directory in this batch (api-ops).
- `ExplorationPanel.vue:20` "Open source dashboard" is covered by the redirect.
- **Explore's `add_to_dashboard`** (`ops_console/actions/telemetry_explore.ex`) links to `/edit?candidate_*`.
  It's unreachable, and the editor ignores the candidate (lead 11-14), so it's retired with the federated batch.

**Docs:** `ux/information-architecture.md:143`, `api/inventory.md:21`, `plans/dashboards.md:44,100`,
`briefs/dashboards.md:11`, and this section.

### L8 federated `ops_console` dashboard surfaces (own batch, after L8a)
- **Delete:**
  - `frontend/apps/ops-console/src/OpsDashboard*.vue` (11 files) and their tests;
  - `applications/ops_console/actions/dashboard_workflows.ex` (1175 lines) and `dashboard_deep_actions.ex`,
    trimming `action_provider.ex:11-12,26-27`;
  - `Reads.Dashboards.Creation` (only `reads/application_surfaces/ops_console.ex:31,580` uses it);
  - then the module entries L8a kept: `directory.ts`, `creation.ts`,
    `features/{directory,creation,dashboard}` and their `ownership.test.ts`, plus storybook's
    `TelemetryChart`/`DashboardWidgetDrawer` stories;
  - of `features/workspace`, only the parts nothing else uses: `OpsDashboardShow.vue` and its test, `charts.ts`,
    the `workspace.ts` re-export and `package.json`'s `./charts` export (fe-ops 840017e8a). The rest of
    `workspace.ts` and `features/workspace` goes in L8b: the legacy playlists and sharing pages
    (`playlists/{PlaylistPresentation.vue,contracts.ts,validation.ts}`,
    `sharing/{SharedDashboardView.vue,contracts.ts,validation.ts}`) import it, and
    `workspace_snapshot_test.exs` and `dashboard_workspace_read_test.exs` run its `producer-contract-check.mjs`.
  - Explore's `add_to_dashboard` action in `telemetry_explore.ex`: its dispatch (:132-150) and the helpers only it
    uses: `widget_type/1` (:177-180), `dashboard_target/3` (:192+), `candidate_query/4` (:244-260),
    `default_title/1` (:263) and `dashboard_path/3`. Keep `explore_path`, `navigation_result` and
    `compact_query`, which the other Explore actions use. Re-grep each helper first. Also drop it from `federated-application.ts:215` and from the tests
    (`telemetry_explore_test.exs`, `ops_console_test.exs`, `OpsConsoleApplication.test.ts`,
    `first-party-manifest-parity.test.ts`).
- **Trim:**
  - the surface specs and both ledgers in `applications/ops_console.ex` (:106-257, :425-435, :454-~480);
  - `reads/application_surfaces/ops_console.ex` (the dashboard read dispatch);
  - `OpsConsoleApplication.vue:24,109`;
  - the ops_console tests (`ops_console_test`, `_action_provider_test`, `_action_adapters_test`,
    `ops_route_action_ledger_test`, `ops_console_dashboard_workflows_test`, `dashboard_legacy_test`).
- **Blocker, being cleared:** the federation smoke used `dashboard_directory` as its canonical ops_console surface.
  devops moved it to `commands` (9f0927b4c on `ci/smoke-canonical-surface`). That commit doesn't merge on its
  own: lead/fe-setup cherry-pick it onto `ui/apogee-spa` **in the same batch** as this deletion, so the smoke keeps
  covering the dashboards until they're gone.

### L8b library, playlists, settings (+ activity, diagnostics), shares, snapshots, export (one batch; fe-setup)
**Done:** live 11-14 09:20Z at 3dbb243b0 (98440ca15 redirects, 1e4df94fc pages, ec2720628 policy, 4a717b586
present/search, 3bf3058ca frontend, 3dbb243b0 playlist reads). qa: all 8 legacy URLs 302 once to the console and
land 200; `/:id/export` 404s. The member path (Activity and Diagnostics only) is proven by afd1201ca's test: no
non-author persona exists while `author_dashboards` is `operate_mission`. devops follows with the smoke driver's
`draft-dashboard` seed.

- **Gate:** fe-setup switches `ops.dashboard.settings` from `pending` to its `SettingsScreen` first, and qa
  checks it live. Slice 6 (shares, snapshots, playlists, present, export) and the library are live (11-14).
- **Routes** (`router.ex`, 11-14 lines): the `HostPageLive` lives for `…/ops/dashboards/library`, `/playlists`,
  `/:id/settings` (:385-395), `…/ops/dashboard-shares/:share_id`, `…/ops/dashboard-snapshots/:snapshot_id`,
  `…/ops/dashboards/playlists/:playlist_id/present` (:397-410), `/:id/activity` and `/:id/diagnostics`
  (:526-533), and the export `get` (:218). Replace each with a `LegacyDashboardRedirectController` action (L8a's
  pattern; old bookmarks and links keep working) to the console's `telemetry/dashboards/…`: `library`,
  `playlists`, `playlists/:id/present`, `:id/settings`, `:id/settings/activity`, `:id/settings/diagnostics`,
  `shares/:id`, `snapshots/:id`. Export has no page to land on: let it 404. Put the literal `library` and
  `playlists` routes before `/:dashboard_id`, as L8a's comment at :739 says. New share links already use the
  console path (`Console.DashboardSettings.base_url/2`).
- **Delete then:**
  - their pages: `ops_{library,playlist,settings,activity,diagnostics,shared_view}_page.ex` and
    `ops_diagnostics_url.ex`;
  - their HPL handlers;
  - the rest of `frontend/modules/dashboards-and-exploration` except `exploration.ts`, `features/exploration`,
    `index.ts`/`contributions.ts` and `features/runtime-diagnostics` (L7). Also drop `gridstack`/`uplot`, the
    `exports` entries and the four CSS imports, among them `apps/host/src/phoenix.css:15`, which the Phoenix
    build imports;
  - the `:ops_dashboard_author` policy (`host_page_authorization.ex:22-23`) and `DashboardAuthorAuth`'s
    `on_mount`/`authorize/3`. **Keep `authorized?/2`:** the console's `DashboardSettingsController:52` and
    `ops_shell_hook.ex:74` call it;
  - `DashboardExportController` (the console has its own export) and its route;
  - their tests and the producer-check assertions in the settings, library, playlists, shared-views and
    execution-diagnostics tests, and in `workspace_snapshot_test.exs` and `dashboard_workspace_read_test.exs`
    (they run `features/workspace`'s `producer-contract-check.mjs`, which goes here with the rest of
    `workspace.ts`/`features/workspace`, left by the federated batch).
- **Keep:** the domain behind them: `SharedViews`, `SettingsAuthoring`, `Reads.Dashboards.{Settings,Library}`,
  `LibraryAuthoring`, `PlaylistAuthoring`. The console endpoints wrap them.
- **Also goes:** all of `Reads.Dashboards.Playlists` (`directory/present/search`: only `ops_playlist_page.ex` called
  them), with the functions only it used, `PlaylistStore.list/choices/dashboard` and
  `PlaylistInput.query/position` (`ids?/1` becomes private), and their cases in `dashboard_playlists_test.exs`
  (fe-setup e55c149d7).

### L8c dashboard invalidation decisions (follow-up batch; lead 11-14)
Nothing in lib records dashboard invalidation decisions any more. Neither writer has callers:
`RuntimeInvalidation.emit_decision` (`runtime_invalidation.ex:264`), which feeds RuntimeHealth's in-memory
projection, and `DashboardRuntimeInvalidations.record` / `DecisionEvents.record` (durable). Only tests write
decisions, and C1 coalesces invalidations itself. L7 already drops their only page, `/admin/runtime`'s "Dashboard
Invalidation Decisions" (with `Reads.Dashboards.RuntimeDiagnostics`); it gets no console home.

1. **D18's `refresh` block, in this order, so nothing fails decoding:**
   - fe-setup makes DiagnosticsTab's reader tolerate an absent `refresh`, then removes it;
   - only then, api drops `refresh {observed_at, decision_status, context_reason}` from D18 (it reads the same
     decisions: `execution_diagnostics.ex:133-139`).
2. **The decision machinery** (a deletion batch under #79: the director's go first). Step 1 is done: D18's
   serializer has no `refresh` (api 729f9e895) and the console reader doesn't read it (`settings/api.ts:252`).
   **Re-grep 11-14 (dashboards):** in lib, nothing calls any writer (`emit_decision`, `DecisionEvents.record`,
   `Diagnostics.record_runtime_invalidation_decision`, `DashboardRuntimeInvalidations.record`, the facades). Only
   tests write decisions. Three readers remain, all on pages that are going:
   - `Reads.Dashboards.RuntimeDiagnostics` → `Projections.DashboardRuntimeInvalidations` (`/admin/runtime`, L7);
   - `ExecutionDiagnostics.decisions/4` (`execution_diagnostics.ex:52,129-158`): it still runs on every D18
     request (a durable query, then a RuntimeHealth snapshot), but `Console.DashboardDiagnostics.build` ignores the
     decision collections. Its other caller is the legacy `ops_diagnostics_page.ex` (L8b).

   **Order: after L7 and L8b land** (L7 deletes `RuntimeDiagnostics` and `/admin/runtime`; L8b the legacy
   diagnostics page). Then delete:
   - `RuntimeInvalidation.emit_decision`, `decision_telemetry_event`, `@decision_telemetry_event` and
     `decision_metadata_keys/0` (`runtime_invalidation.ex:16,253-275,532-548`); keep `telemetry_event/0` and the
     boundary event;
   - `RuntimeHealth`'s subscription to it (`runtime_health.ex:55`);
   - `Dashboards.RuntimeInvalidation.{DecisionEvents, DecisionEvents.DecisionEventRow, DecisionProjection,
     DecisionEvent}`;
   - `Dashboards.Diagnostics.{runtime_invalidation_decisions, record_runtime_invalidation_decision,
     durable_runtime_invalidation_decisions}` (`diagnostics.ex:49-65`) and their aliases;
   - `Projections.DashboardRuntimeInvalidations` (whole module);
   - the facades `dashboards.ex:76-83` and `cadence.ex:745-779` (`dashboard_runtime_invalidation_decisions`,
     `durable_…`, `record_…`);
   - `ExecutionDiagnostics.decisions/4` and its `++` at :52 (moduledoc :3,7 too), and `ExecutionEvidence`'s
     `decisions/2`, `unavailable_decisions/0`, `refresh/1`, `invalidation/1` ("Recorded invalidation") and
     `decision_identity/1` (`execution_evidence.ex:44-51,256-295`);
   - tests: `dashboard_runtime_invalidation_decisions_test.exs`, `runtime_invalidation/decision_events_test.exs`,
     `runtime_invalidation/decision_projection_test.exs` (whole files); `runtime_health_test.exs` :107 and the
     decision case (:266-306); `cadence_web/dashboard_execution_diagnostics_test.exs`'s decision cases (:302,
     :365-375).

   **Not this:** same words, other things. `Telemetry.Storage.ObservationIdentityDecisionEvent` (ingest identity),
   and `decision_status` in `ComparisonReviewQueue` / `DocumentStore.LifecycleEvents` (comparison findings).
3. **Later, domain's call:** a migration dropping the durable decision events table.

Future note, not work now: "why did my board refresh" would be a per-dashboard Diagnostics feature fed by C1's own
coalescing. That's new work, not a port.

### Answers (lead 11-14)
- **Explore's `add_to_dashboard`:** dead at both ends. Nothing dispatches it: it appears only in ops-console's
  federated action list (`federated-application.ts:215`), and `OpsTelemetryExplore.vue` is just a redirect.
  The legacy editor never reads `candidate_*`. So there's **no redirect exemption and no console `?candidate`
  work**. Retire the action with the federated `ops_console` batch. A console "Add to dashboard" from Explore
  would be a future console design (WidgetSheet prefilled from an observable).
- **`RuntimeCoordinator` / `RuntimeInvalidationRelevance`:** api-ops confirms they aren't needed. Listed in L8a.
- **Federation smoke:** devops moved it to `commands` (9f0927b4c). It's cherry-picked together with the
  federated batch, not merged separately (devops 11-14).
- **Gate:** L8a goes to the director once qa confirms New live.
- **Storybook `dashboard-directory-study/`:** ux: delete it with the federated batch (the pre-Apogee directory
  study; Dashboards.md › Directory replaces it).

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

## L12 · L13 providers (console live 11-13; deletion waits on qa's live check)
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

**Was blocked** (until 11-13; L12 2e899643c and L13 b90f5401a are live): deleting either before then lost the only UI for:
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

## Covered-already host pages (BACKLOG §11c; lead 11-13)
Every other legacy browser route that HPL or ApplicationHostLive serves. Dispatch goes through `routes.json`
(`kind` / `contribution`) to a `CadenceWeb.*Page` module. Surface specs live in
`applications/{organization_admin,mission_catalog,spacecraft,comms,ops_console}.ex`. **Unless its row says
otherwise, no legacy URL here redirects to the console yet**: each target below is where the old URL should go
(with the slug lookup).

**Don't edit server copy for legacy-backed settings sections before §11c (B)/(C)** (director 11-15): the host
admits a section only if its metadata equals the server definition, so a copy change on the server alone shows
"… settings are unavailable" on the legacy settings pages (3bb80ce99 did; devops' f817c9ea0 fixed it).

| R | Legacy | Page / surface | Console | Status |
| --- | --- | --- | --- | --- |
| 239 | `/` | AdministrationPage, organization_home | `org.home` | redirect + deletion built (fe-setup/legacy-11c-a) |
| 242-243 | `/settings[/:section]` | SettingsPage (org routes only; the module stays) | `org.settings` | redirect + deletion built (fe-setup/legacy-11c-a) |
| 245, 249 | `/missions/:id/settings[/:section]` | SettingsPage | `setup.settings` | covered (the console renders every registry section, incl. `cadence.pass_review`, which the legacy host never had a contribution for; devops 11-15) |
| 265 | `/missions/:id` | MissionPage, mission_overview | `mission.home` (→ `ops.now`) | covered |
| 267, 271 | `…/spacecraft`, `/new` | SpacecraftPage | `setup.spacecraft`, `.new` | covered |
| 275-283 | `…/spacecraft/profiles[/new\|/:id]` | SpacecraftPage | `setup.profiles`, `setup.profile.new`, `setup.profile` | covered |
| 287 | `…/spacecraft/:sid` | SpacecraftPage + SpacecraftConfigurationPage | `setup.spacecraft.one` | **partly (L22):** switches and handled_apids |
| 291, 295 | `…/spacecraft/:sid/identity`, `/edit` | SpacecraftPage, edit | `setup.spacecraft.one` | **not covered (L17)** |
| 299 | `…/spacecraft/:sid/readiness` | SpacecraftPage | `setup.spacecraft.one` | covered |
| 303 | `…/spacecraft/:sid/routing` | SpacecraftModulePage | `setup.profile` (replacement model) | covered |
| 307 | `…/spacecraft/:sid/commanding` | SpacecraftModulePage | `ops.spacecraft` (configuration tab) | covered (§11c) |
| 311-331 | `…/catalog[/new\|/databases/:id\|/revisions/:id\|/imports/:id]` | CatalogPage | `setup.catalog`, `.import[/:importId]` | covered |
| 327 | `…/catalog/artifacts/:id` | CatalogPage, catalog_artifact_show | `setup.catalog.artifact` | **partly (L18)** |
| 335-380 | `…/comms`, `/transports…`, `/ground-stations…`, `/routing…`, `/validation` | MissionModulePage | `setup.comms`, `setup.comms.transports`, `setup.stations`, `setup.readiness` | covered |
| 582 | `…/applications` | application_management | `setup.apps` | covered |
| 609, 615 | `…/applications/:key[/:surface]` | ApplicationHostLive | `setup.app` | covered (L9) |
| 396 | `…/ops` | OpsLandingPage | `ops.now` | covered |
| 449-461, 481 | `…/ops/planning[…]`, `/ops/plans/:id` | OpsFleetDirectoryPage, OpsFleetWorkflowPage, OpsPlanReviewPage | `ops.contacts.plan` | covered |
| 485, 489 | `…/ops/contacts`, `/records/:id` | OpsContactSchedulingPage | `ops.contacts`, `ops.contact` | covered (**L15** single bookings off) |
| 493 | `…/ops/contacts/:reservation_id` | OpsContactSchedulingPage, reservation-review | `ops.contacts` | **not covered (L14)** |
| 497, 501 | `…/ops/alarms`, `/timeline` | OpsAlarmConditionsPage, OpsTimelinePage | `ops.alarms`, `ops.timeline` | covered |
| 505-543 | `…/ops/commands[…]` (workspace, new, stages, requests, history, queue) | OpsCommand*Page | `ops.commands[.new\|.request]` | covered (stages not needed, §11c) |
| 147, 149 | `…/ops/contact-workspace[/records/:id]` | ContactWorkspaceController (HTML) | `ops.contacts`, `ops.contact` | covered |
| 547 | `…/ops/explore` | OpsExplorationPage | `ops.telemetry` | **parked (L20)** |
| 445, 578 | `…/ops/data-operations[/manage]` | OpsHistoricalWorkflowsPage | none | **parked (L16)** |

**§11c (B) built (fe-setup/legacy-11c-b, on the combined L10-L13 + (A) branch).** api's B1-B11 redirects
(LegacyMissionSetupRedirectController) take over rows 245/249 (mission settings), 265 (mission home), 267/271
(spacecraft, New), 275-283 (profiles), 299/303/307 (a spacecraft's readiness, routing, commanding), 311-331
(catalog except artifacts), 335-380 (comms) and 582 plus the spacecraft's `…/applications` index; the host
pages that only served them are deleted. Kept: the spacecraft page with identity and edit (L17/L22), catalog
artifacts (L18), the ApplicationHostLive app pages (B12) and every federated surface. SettingsPage keeps only
the settings live updates for the pages that embed sections (batch C's); SettingsPage.vue stays.

**Retained legacy routes (lead 11-15).** The kept federated apps (comms_overview, mission_catalog, spacecraft)
still type their page headers by 27 of the retired paths, and SettingsPage.vue by the two mission settings paths.
`frontend/tools/retained-legacy-routes.json` keeps those 29 in the typed route catalog, each naming its
consumers and why. plugin-sdk's `routes.test.ts` holds the list to shrinking only: never back in `routes.json`, a
subset of a frozen baseline written in the test (never longer), and every entry with a live consumer that
still references its path. **B12 and (C) remove entries as they delete those surfaces or components**, and the
file and its tests once it is empty. Adding an entry means editing the frozen baseline too, which only a
deletion batch's own commit may do.

**Legacy dashboards are gone from the host (L8 done and live).** Every legacy dashboard URL (directory, new,
view, edit, library, playlists and present, settings, activity, diagnostics, shares, snapshots) redirects once to
the console through `LegacyDashboardRedirectController`, and the host pages and `dashboards.*` surfaces are
deleted; `/:id/export` 404s by design. See **L8** above.
- **Download to keep** until L18 decides: R:155 artifact download.

**Redirect-only controllers.** All of them still point at legacy pages:
- `LegacyOpsRedirect` R:224 goes to `/ops/explore` (L20).
- `LegacyApplicationRedirect` R:646 and :652 go to the L19 spacecraft applications.
- The 18 `LegacyCommsRedirect` aliases (R:660-766) go to `/comms` and `/comms/transports`.

Repoint each to its console target (`setup.comms`, `setup.comms.transports`, `setup.spacecraft.app`,
`ops.telemetry`) when its target page goes. `AuthRedirectController` (R:109-111) already points at the console.

**§11c(C) action/information parity (fe-ops, 11-16):** the "covered" ops rows above are covered at route level.
The per-action and per-field audit is in [parity-ops-c.md](parity-ops-c.md): 17 capability gaps (A), the evidence
fields (B), what's gone by design (C), and four bugs (D). Its gaps go to lead before fe-setup builds (C).

**Not covered: these block deleting the host app.**
- **Rows not built yet:** L17 (R:291, :295), L22 (R:287), L14 (R:493), L15 (R:485, built but off), L18 (R:327,
  :155).
- **Rows already blocked in this manifest:** L10, L12, L13 and L19.
- **Parked:** L16 (R:445, :578) and L20 (R:547).

## Answers (lead 11-13)
1. **Can `frontend/apps/host` go whole? No**, not while L16 and L20 are parked and the not-covered rows above are
   open. Even then, four things still depend on it:
   - LiveVue's `vue_root` points at `frontend/apps/host/src/shell` (`cadence_web.ex:57`).
   - `host_routes.ex`, `catalog_page.ex` and HPL compile its `routes.json`.
   - It is the package `@cadence/plugin-host`, which `frontend/apps/{ops-console,spacecraft,organization-admin,
     mission-catalog,storybook}` depend on.
   - ApplicationHostLive and the federated shells mount through it.

   The console doesn't import it; the federated bundles the console loads use only `@cadence/plugin-sdk`.
   Deleting it whole needs L16 and L20 decided, every row done, and those four moved off it.
2. **The bearer `POST /api/organizations/:id/missions`: keep it** (lead; the director has been asked).
   **Closed (director 2026-11-19): retired by #384**, along with `GET /api/organizations/:id` and
   `GET …/missions` (no external client; organization-level acts are a person's, #282).
3. **`ApplicationHostController.admin_federated`** (R:213-215, :219-221) serves only `organization_admin`'s six
   `scope: :admin` surfaces. `organization_admin.ex:288` is the only `:admin` installable scope, and nothing links
   to those URLs. **It goes with L7**, along with the bridge's `scope=admin` branches, `OrganizationAdminQuery`
   :150-171, and `OrganizationAdminAction`'s admin branches (:372).
4. **The generic host reaches the provider surfaces, so trimming changes what's reachable:**
   - **Comms provider surfaces** (`provider_list`, `provider_new`, `provider_show`: `scope: :mission`,
     `placement: :application_workspace`) are reachable through:
     - ApplicationHostLive (`/missions/:m/applications/comms/provider_*`) and the mission federated route (R:168);
     - the bridge (R:1158, :1168, :1176);
     - **the console's own L9 host.** Setup › Apps › Comms lists them as Setup surfaces (`MissionApps.surfaces`,
       `AppSurfaceController.host`).

     So L12's trim also removes those tabs from the console's Comms app page. That's intended, but do it in the
     same batch as L12's console writes, and tell qa.
   - **Provider-account surfaces** (`provider_accounts`, `provider_account_new`, `provider_account_show`:
     `scope: :organization`) are reachable through `organization_federated` (R:189-197) and the bridge with
     `scope=organization`. They aren't reachable through ApplicationHostLive or the console's L9 host, which only
     use mission or spacecraft context. Removing them also means editing `OrganizationAdmin.validate/0`
     (`organization_admin.ex:361-396`), which checks that every surface has a query and an action binding.

**Invitation email (L5):** move `user_notifier.ex:7` to `/console/invitations/<token>`, and keep the
`/invitations/:token` 302 for links already sent. The first batch (L5 + L6 + L21) waits on the director's go and
the apps/host exception; lead proposed fe-setup does it.
