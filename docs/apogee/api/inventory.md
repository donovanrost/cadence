# Inventory: what existed before `/api/v1`

Owner: **api**. Snapshot of `ui/apogee-spa` on 2026-11-08. It covers what the console can reuse or wrap, and
what is missing. Paths: `W` = `apps/cadence_web/lib/cadence_web`, `L` = `apps/cadence/lib/cadence`.

**Summary (as of Phase 0; the REST scope below is deleted, §2).** The SPA can't call any existing JSON API as-is. The REST API under `/api/organizations` took
**bearer service-identity tokens only**. Even if it took cookies, every mission route checks
`:manage_mission`, which needs an admin capability, so plain members would get 403s. The two browser
JSON APIs (application host, contact workspace) take cookies, but they're bound to the session's current
organization, need extra handshake headers, and return UI documents. What carries over is the **read models
in `L/reads/`** and the domain functions the controllers call. Console endpoints wrap these.

## 1. Auth surfaces

| Route family | Pipeline | Authenticates with | Policy | SPA as-is? |
| --- | --- | --- | --- | --- |
| ~~`/api/organizations/:org/...`~~ | ~~`:api` + `:authenticated_api` (`FetchCurrentScope`, `RequireCurrentScope`)~~ | **Removed (#754, #922, #747):** the scope, the pipeline and both plugs are deleted. A service authenticates with its bearer on `/api/v1` (opted in through `Console.ServiceAccess`) and on the two named machine surfaces. | — | — |
| ~~`/api/cadence/application-host/v1/...`~~ | ~~`:browser` + `RequireAuthenticatedScope` + `:application_host_json`~~ | **Removed (#672):** the scope, its pipeline, the `ApplicationHostCSRF`, `ApplicationHostSession` and `RequireApplicationHostScope` plugs, and the console's `/host` read are deleted; the console mounts no app surfaces. | — | — |
| ~~`/api/cadence/contact-workspace/v1/...`~~ | ~~`:browser` + `RequireAuthenticatedScope`~~ | **Removed:** no such route remains; the contact schedule is the console's. | — | — |
| `/health/live`, `/health/ready` | `:api` | none | none | Yes, but it's only infra (`GET /api/health` deleted, #747) |
| Browser GETs: `/missions/:m/catalog/artifacts/:id/download`, `/missions/:m/ops/dashboards/:id/export` | `:browser` + `RequireAuthenticatedScope` | cookie | Download only fetches within the session's current org (no named policy). Export uses `DashboardAuthorAuth.authorized?` | Usable as plain links when the session org matches |
| ~~`/api/cadence/frontend-release/v1/...`, `/releases/:app/:release/artifacts/*`~~ | ~~`FrontendReleasePublisher`~~ | **Removed (#672):** release publishing, artifact serving, their plugs and the stage janitor are deleted. | — | — |

Policy facts that console endpoints depend on (`L/auth/policy.ex`): `:operate_mission` lets in an active member of
the scope's org, any `platform_admin` (admin mode), or a service bound to that exact mission. Most
operator actions (`:read_settings`, `:approve_activation`, `:author_dashboards`, user `:request_activation`)
reduce to `:operate_mission`. `:resolve_command_release` and `:resolve_provider_reservation` need **both**
operate and manage. Scope-taking reads use `scope.organization_id`, so console code must pass the scope
that `Console.Plugs.MissionScope` re-homed to the mission's org (it already does this).

## 2. Bearer REST endpoints (removed)

The whole `/api/organizations/:org/missions/:m` bearer REST scope (catalog, comms, contacts, activations,
commanding and identity routes, behind `:authenticated_api`) is deleted: its commanding half with #708/#754,
the rest with #922 and #747's last step. Every area has a console endpoint under `/api/v1` (see the
other docs in this folder), and a service reaches the ones it may with its bearer through
`Console.ServiceAccess`. The rows that stood here are in the git history.

## 3. Browser JSON bridges (removed)

The application host bridge (`/api/cadence/application-host/v1`: catalog, query and actions for the
federated app surfaces) is deleted with the console's surface host (#672). The read functions and
action providers behind it are in `L/` until the app registries go; the console doesn't call them.

## 4. Read models to wrap (`L/reads/`)

Two kinds. **Raw** reads take `(org_id, mission_id, opts)` and do no auth. **Authorized** reads take a `Scope`,
check policy themselves, and often return presentation fields (breadcrumbs, hrefs, tone strings) that console
DTOs should drop.

| Module | Key functions | Returns |
| --- | --- | --- |
| `MissionHealth` (raw) | `summary/3` (`:spacecraft_id`) | point counts, `worst_normalized_state`, `point_buckets`, per-spacecraft `scope_summaries` |
| `Alarms` (raw) | `snapshot/3`, `summary/3` | limit-condition rows sorted by severity/recency, `spacecraft_ids`, summary |
| `Limits` (raw) | `latest_state`, `latest_states_for_mission`, `latest_states_for_points`, `event_history`, `definition_intervals`, `watermark_result` | `Limits.Event` latest/transitions; `DefinitionInterval` bands over time |
| `Telemetry` (raw) | `latest_value`, `latest_values_for_mission`, `sample_history(_result)`, `decimated_sample_history(_result)`, `sample_watermark` | samples; decimated `{buckets, diagnostics}` via `HistoryStore` (backend-dependent) |
| `DerivedTelemetry` (raw) | `latest_value(s)`, `sample_history` | derived-point samples |
| `Commands` (raw) | `snapshot/3`, `summary/3`, `fetch_*`, `list_*` | request/queue/release/verifier status; `queued_count`, `release_pending_count`, `in_flight_count` |
| `CommandMonitor`, `CommandHistory`, `CommandReview`, `SpacecraftCommanding` (auth) | `load`, `admit_query` | command monitor, request history, review (`can_decide`, `expected_review`), pinned target interpretation |
| `OperationalState` (raw) | `list_transports`, `fetch_ground_station`, `list_routing_rules`, `list_spacecraft`, `list_scheduled/realized_contacts`, `list_pending_command_queue_entries`, ... | current operational records |
| `OperationalState.Snapshots` | `connection`, `antenna_pointing`, `transport_bitrate`, `link_rf_*`, `ingress_latency` | link/RF snapshots |
| `MissionEvents`, `MissionTimeline` (raw) | `list_for_mission`, `page_for_mission`, `fetch_for_mission` | mission events; timeline merging projection and operational events |
| `OperationalEvidence` (raw) | `list_contact_events`, `list_operational_events`, `list_effective_intervals`, `list_source_health_events`, ... | evidence for audit/recent-changes |
| `DataSources` (raw) | `source_inventory_page`, `binding_inventory_page`, `*_event_page`, `list_data_sources`, ... | desired/observed source state (health and watermarks in `Projections.DataSources`) |
| `Spacecraft.Directory`, `Spacecraft.Profiles` (take a `%Mission{}`, no auth) | `Directory.load(mission, params)` (`q`, `page`, `sort`, `dir`, filters `missing_scid`, `missing_profile`, `profile_drift`, `profile:<id>`); `Profiles.directory/detail` | paged spacecraft directory with ready flag; profile list and versions |
| `Spacecraft.Overview`, `.Readiness`, `.Configuration` (auth) | `load(scope, mission, id[, section])` | overview; per-spacecraft readiness checks; saved/active config and review |
| `Comms.Pages` and `Comms.SpacecraftReadiness`, `.SpacecraftRouting`, `.MissionProviders`, `.ProviderAccount*` | `load`; `Pages.validation` | comms overview, validation findings (owner/severity), routing, providers |
| `Catalog.*` (`Pages`, `Databases`, `Revisions`, `Imports`, `Artifacts`, `SpacecraftUsage`) | `load`; `catalog_*_show`; `SpacecraftUsage.summary` | catalog index/detail; spacecraft per catalog revision |
| `Missions.Directory`, `.Overview` (raw: `load(org)`, `load(org, mission)`) | `load` | mission list; mission overview with spacecraft readiness |
| `Applications.Inventory`, `.SpacecraftInventory` | `catalog`, `declared_with_installations`, `summary`; `load` | app install state (`:not_installed`, ...) |
| `ActivationApprovals` (auth) | `load`, `presentation` | governed activation inbox |
| `Administration.OrganizationDetail` (auth) | `load` | org facts, members, invitations, service identities (paged) |
| `Notifications.Inbox` (auth) | `load(scope, params)`, `query` | recipient-scoped notification page |
| `OpsWorkspace.Landing`, `.Timeline` (auth) | `load` | ops nav permissions; cross-module timeline |

## 5. Live-update sources

| Source | Topic / API | Payload | Fires on | Used by console channel? |
| --- | --- | --- | --- | --- |
| `Platform.ScopedReadUpdates` (`L/platform/scoped_read_updates.ex`) | Phoenix.PubSub `read-updates:<event>:<org>:<mission>` | `{event, org, mission}` (no data). Published after commit only | `:commanding_changed` (request/queue/release stores, stage access, activations), `:spacecraft_configuration_changed` (SpacecraftStore, SourceEndpoints, config drafts/review, app installs, packet bindings, telemetry decom), `:dashboards_changed`, `:settings_changed` | Yes, mapped to `commanding`, `spacecraft`, `dashboards`, `settings` |
| `Dashboards.RuntimeInvalidation` (`L/dashboards/runtime_invalidation.ex`) | PubSub `dashboards:runtime_invalidation:org:<o>[:mission:<m>[:dashboard:<d>]]` | `{:dashboard_runtime_invalidated, %Event{boundary, ...}}` | `dashboard_version_changed`, `catalog_revision_changed`, `limit_definition_changed`, `data_source_binding_changed`, `source_watermark_changed` (new samples), `historical_data_changed`, `telemetry_revision_state_changed`, `source_health_changed`, `events_changed` | Yes, mapped to `dashboards`, `catalog`, `limits`, `data_sources`, `telemetry`, `events` |
| `Platform.EventBus` (in-process GenServer, **not** PubSub, local node) | `{:cadence, <area>, :facts}` for `telemetry` (`ObservationsCommitted`), `limits` (`Limits.Event` per transition, definition lifecycle), `runtime` (`*RecordsPersisted`), `contacts` (scheduled/realized/action), `catalog` (revision), `activations`, `data_sources` (health/watermark), plus `{:cadence,:jobs,:available}` | typed fact structs, delivered after commit, best-effort | domain transitions | No. This is where data-carrying pushes (planned `fleet`, `points`) can come from |
| `Catalog.Events` (`L/catalog/events.ex`) | PubSub `catalog:mission:<m>:import_runs`, `catalog:mission:<m>:import_run:<id>` | `{:import_run_started \| _updated \| _completed \| _failed, %ImportRun{}}` | import-run lifecycle | No. Needed for S3 import progress |
| `Notifications` (`L/notifications.ex`) | PubSub `notifications:<user_id>` | `{:notification_created \| :notification_updated, %Notification{}}` | per-user notifications | No (it would need a user topic) |

## 6. Gaps for the console

From `docs/apogee/plans/ops.md` ("Missing-data ask list") and `docs/apogee/plans/setup.md` ("Missing" rows).
"Backing" is the existing code a console endpoint can wrap. **new** means nothing backs it today.

| Ask | Backing today | |
| --- | --- | --- |
| M1 typed plane/slot/orbit, profile name on list | `SpacecraftStore` `metadata`; `SpacecraftTypeStore` | partial; typed fields **new** |
| M2 fleet status per spacecraft | `MissionHealth.summary` `scope_summaries`; dashboards `Sources.OperationalObservables.ConstellationHealth` (`worst_state`, `:no_data`); `Applications.Inventory` | compose |
| M3 per-spacecraft `last_received_at` and freshness | `Reads.Telemetry.sample_watermark` (per point), `Projections.DataSources.Watermarks` (per source) | per-spacecraft **new** |
| M4 in contact now, per spacecraft | `OperationalState.list_realized_contacts`, `Runtime.realized_contact_snapshot` | spacecraft join **new** |
| M5 command counts incl. awaiting approval | `Reads.Commands.summary` | approval-pending count **new** |
| M6 ranked action queue | `Alarms.snapshot` + approval-pending requests + `Applications.Inventory` | compose |
| M7 passes by station, next AOS / last LOS | `ContactSchedule.load`; `OperationalState.list_scheduled_contacts` | station field and window filter **new** |
| M8 fleet deltas, live points, uplink progress | invalidations live on `mission:<id>`; `Limits.Facts`, `Telemetry.Facts` (EventBus) | data pushes **new** |
| M9 alarms JSON `?spacecraft_id&state` | `Reads.AlarmList` over `SemanticObservations.AlarmPage` (#1117); a spacecraft's points: `Reads.PointConditions` | done |
| M10 decimated history | `Reads.Telemetry.decimated_sample_history_result` | wrap (check backend support) |
| M11 limit bands for a point | `Reads.Limits.definition_intervals` | wrap |
| M15/M16 group request N×K, no cap of 25 | `Control.Commanding.WorkspaceSubmission` (1 command × ≤25 targets) | **new** |
| M17 command catalog JSON with `?q` | `Management.Commanding.AuthoringCatalog.page/query` | wrap; range/units **new** |
| M18 preflight checks | request validation at create time only | **new** |
| M19 request note; M20 cancel queued request/entry | none (no cancel route) | **new** |
| M21 stations with location/antennas/status | `Comms.GroundStationStore`, `OperationalState.fetch_ground_station` (no geo/antennas/health) | fields **new** |
| M22 cross-reservation findings | conflicts only inside contact plans / fleet optimizer | **new** |
| M23 telemetry point search | `reference_providers/canonical_telemetry_points.ex` | wrap |
| M12 propagation, M13 procedures, M14 alarm lifecycle, M24 encode preview, M25 waves, M26 retries | none | **new** / deferred (DECISIONS D1–D5) |
| S1 mission readiness, grouped by cause | `Spacecraft.Readiness` (per spacecraft), `Comms.Pages.validation`, `SpacecraftStore.fleet_summary/2`, `Applications.Inventory` | aggregate **new** |
| S1 data-source freshness | `Reads.DataSources` and `Projections.DataSources.{Health,Watermarks}` | wrap; expected interval may not exist |
| S1 app consequence text; station antennas/health | none | **new** |
| Change sets, mission revision, recent changes / audit log | per-entity versions; `OperationalEvidence`, routing-rule events | **new** (DECISIONS #1) |
| Spacecraft list (paged, `q`, route count) | `SpacecraftStore.list_spacecraft_page`, `Spacecraft.Directory.load`, `RoutingRuleStore` | wrap |
| Spacecraft detail and config actions | `Spacecraft.Configuration.load`, `Control.SpacecraftConfiguration.submit/decide` | wrap |
| S2 create one spacecraft | `Spacecraft.Identity.action/5` (bridge `cadence.spacecraft.new`) | wrap |
| S2 batch validate/create, next-free SCID, NORAD/plane/slot | none | **new** |
| S3 multipart upload and import status | `Catalog.Upload.import_revision/5`; `Catalog.Events` PubSub | wrap |
| S3 per-kind counts, revision diff, breaking rules, bulk revision rollout | none | **new** |
| S4 profiles list/detail/versions | `Spacecraft.Profiles.directory/detail`, `SpacecraftTypeStore.list_spacecraft_type_versions`, `fleet_summary.profile_version_counts` | wrap |
| S4 profile edit to v+1, profile-level routing, overrides | create only (`ProfileCreation`) | **new** (DECISIONS #3) |
| S5 members, invitations | `Accounts.page_organization_members`, `page_pending_organization_invitations`, `Administration.OrganizationDetail` | wrap |
| S5 org-admin invite | `Administration.OrganizationInvitations` (platform-admin path) | wrap with org-admin policy |
| S5 service identities via session | `Auth.list_service_identities`, `issue_service_identity` | wrap; last-used and key age **new** |
| S5 presence/last active, command policies | none | **new** |
