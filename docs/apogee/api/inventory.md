# Inventory: what existed before `/api/console/v1`

Owner: **api**. Snapshot of `ui/apogee-spa` on 2026-11-08. It covers what the console can reuse or wrap, and
what is missing. Paths: `W` = `apps/cadence_web/lib/cadence_web`, `L` = `apps/cadence/lib/cadence`.

**Summary.** The SPA can't call any existing JSON API as-is. The REST API under `/api/organizations` takes
**bearer service-identity tokens only**. Even if it took cookies, every mission route checks
`:manage_mission`, which needs an admin capability, so plain members would get 403s. The two browser
JSON APIs (application host, contact workspace) take cookies, but they're bound to the session's current
organization, need extra handshake headers, and return UI documents. What carries over is the **read models
in `L/reads/`** and the domain functions the controllers call. Console endpoints wrap these.

## 1. Auth surfaces

| Route family | Pipeline | Authenticates with | Policy | SPA as-is? |
| --- | --- | --- | --- | --- |
| `/api/organizations/:org/...`, `/api/current_scope` | `:api` + `:authenticated_api` (`FetchCurrentScope`, `RequireCurrentScope`) | Only `authorization: Bearer <token>`, resolved by `Cadence.Auth.authenticate_api_token/1` against **active `ServiceIdentityRow`s**. No session is fetched, so cookies are ignored. No header gives 401 `{errors:[{reason:"unauthenticated"}]}` | Mission routes use `ControlPlaneAccess.authorize_mission/3`, which is `:manage_mission` (`platform_admin`, `organization_admin`, or `mission_admin` on that mission). Org routes use `:read_organization` and `:manage_missions`, both `organization_admin` (the REST service-identity routes were removed, #281) | **No.** Service identities only. Plain members also fail `:manage_mission`. `current_scope` there describes the service actor |
| `/api/cadence/application-host/v1/...` | `:browser` + `RequireAuthenticatedScope` + `:application_host_json` | Session cookie. CSRF via `ApplicationHostCSRF` (`x-csrf-token`, JSON 403 `invalid_csrf`). On non-GET, `x-cadence-poc-session` must match the `application_host_session_id` issued by the first GET (returned as `sessionId` by `GET .../catalog`). Actions also need `idempotency-key` | `:read_application_catalog`, which is `:operate_mission` with **the session's current org** (`current_scope.organization_id`). After that, surface admission plus each action's own policy | Technically yes, but it's the wrong shape: versioned surface envelopes and presentation output (§3) |
| `/api/cadence/contact-workspace/v1/...` | `:browser` + `RequireAuthenticatedScope` | Session cookie, CSRF (`x-csrf-token`), plus `x-cadence-workspace-user` and `x-cadence-workspace-organization`, which must equal the session's user and current org on **every** call, GET included. A mismatch gives 409 `session_changed` | `:operate_mission` in the session's current org (active user only) | Mostly. The mission must be in the session's current org, so cross-org tabs break. Problems are `{code}` only |
| `/health/live`, `/health/ready`, `GET /api/health` | `:api` | none | none | Yes (`{data:{status:"ok"}}`), but it's only infra |
| Browser GETs: `/missions/:m/catalog/artifacts/:id/download`, `/missions/:m/ops/dashboards/:id/export` | `:browser` + `RequireAuthenticatedScope` | cookie | Download only fetches within the session's current org (no named policy). Export uses `DashboardAuthorAuth.authorized?` | Usable as plain links when the session org matches |
| `/api/cadence/frontend-release/v1/...` | `FrontendReleasePublisher` | publisher credentials | n/a | No (CI publishing) |

Policy facts that console endpoints depend on (`L/auth/policy.ex`): `:operate_mission` lets in an active member of
the scope's org, any `platform_admin` (admin mode), or a service bound to that exact mission. Most
operator actions (`:read_settings`, `:approve_activation`, `:author_dashboards`, user `:request_activation`)
reduce to `:operate_mission`. `:resolve_command_release` and `:resolve_provider_reservation` need **both**
operate and manage. Scope-taking reads use `scope.organization_id`, so console code must pass the scope
that `Console.Plugs.MissionScope` re-homed to the mission's org (it already does this).

## 2. Bearer REST endpoints (`…` = `/api/organizations/:org/missions/:m`)

All are in `W/controllers/`, with `action_fallback FallbackController` (`{errors:[{reason}]}`) and `{data: ...}`
on success. JSON views are in `W/api/*_json.ex`. Every `…` row passes `authorize_mission` (`:manage_mission`) first.

| Area | Method + path | Controller | Calls | Note |
| --- | --- | --- | --- | --- |
| Identity | `GET /api/current_scope` | CurrentScope | `IdentityJSON.current_scope` | service actor document |
| Identity | ~~`GET /api/organizations/:org`~~ | ~~Organization~~ | — | **Removed (#384):** a bearer is always a service, and organization-level acts are a person's (#282). |
| Identity | ~~`GET`, `POST /api/organizations/:org/missions`~~ | Mission | — | **Removed (#384):** as above. Missions are created in the console (L4). |
| Identity | `GET /api/organizations/:org/missions/:m` | Mission | `Missions.fetch_mission` | |
| Identity | ~~`GET`, `POST /api/organizations/:org/service_identities`~~ | ServiceIdentity | — | **Removed (#281):** services never manage service identities; people issue them in the console (O6). |
| Telemetry | `GET …/telemetry/latest` | Telemetry | `Reads.Telemetry.latest_values_for_mission` | `?spacecraft_id` |
| Telemetry | `GET …/telemetry/points/:point_id/latest` | Telemetry | `Reads.Telemetry.latest_value` | `data` may be null |
| Telemetry | `GET …/telemetry/points/:point_id/history` | Telemetry | `Reads.Telemetry.sample_history` | raw samples. `?spacecraft_id&from_receipt_time&to_receipt_time&limit`. No decimation |
| Telemetry | `POST …/dev/space_packets`, `POST …/dev/tm_frames` | DevSpacePacket, DevTMFrame | `Control.Ingress.process_and_persist` | dev ingest only |
| Limits/health | `GET …/mission_health` | MissionHealth | `Reads.MissionHealth.summary` | counts, worst state, `point_buckets`, per-spacecraft `scope_summaries`. **The only limits data on REST**: no alarms, limit-interval or limit-definition routes |
| Events | `GET …/mission_events` | MissionEvent | `Reads.MissionEvents.list_for_mission` | filters `limit, category, kind, severity, spacecraft_id, contact/path ids`. No from/to |
| Catalog | `GET …/catalog/importers` | CatalogImporter | `Catalog.list_importers` | |
| Catalog | `GET`, `POST …/catalog_artifacts`; `GET …/catalog_artifacts/:id` | CatalogArtifact | `Catalog.list_artifacts`, `persist_artifact`, `fetch_artifact` | JSON body upload, not multipart |
| Catalog | `GET`, `POST …/catalog_import_runs`; `GET …/catalog_import_runs/:id` | CatalogImportRun | `Catalog.list_import_runs`, `start_import_run`, `fetch_import_run` | |
| Catalog | `GET`, `POST …/packet_definitions` | PacketDefinition | `Governance.list_packet_definitions`, `persist_packet_definition` | |
| Catalog | `POST …/binding_sets`; `GET …/binding_sets/:id/versions/:v` | BindingSet | `Governance.persist_binding_set`, `fetch_binding_set` | |
| Spacecraft | `GET …/spacecraft`; `GET …/spacecraft/:id` (the REST `POST …/spacecraft` was retired by #328: spacecraft are created through the console's change sets) | Spacecraft | `SpacecraftStore.list_spacecraft`, `fetch_spacecraft` | full list, no paging. Plane/slot only in `metadata` |
| Spacecraft | `GET`, `POST …/spacecraft/:id/source_endpoints`; `GET`, `POST …/source_endpoints`; `GET …/source_endpoints/:id` | SourceEndpoint | `SourceEndpoints.list_*`, `persist_*`, `fetch_*` | the spacecraft variant uses `authorize_spacecraft` |
| Comms | provider_profiles: `GET`, `POST` collection; `GET`, `PATCH`, `DELETE /:id`; `GET /:id/versions`; `GET /:id/versions/:v` | ProviderProfile | `Contacts.{list,persist,fetch,version,delete}_provider_profile*` | legacy versioned model (pre-Transports) |
| Comms | transport_profiles: same 7 routes | TransportProfile | `Contacts.*_transport_profile*` | legacy model. The current UI uses Transports via the bridge |
| Comms | path_templates: same 7 routes, plus `POST /:id/link_assignments` | PathTemplate, LinkAssignment | `Contacts.*_path_template*`, `apply_link_template` | legacy "link template" model |
| Comms | `GET`, `POST …/link_assignments`; `GET`, `DELETE …/link_assignments/:id` | LinkAssignment | `Contacts.*_link_assignment` | legacy |
| Commanding | `GET`, `POST …/command_stages`; `GET`, `PATCH /:id`; `POST /:id/submit` | CommandStage | `Management.Commanding.*_command_stage`, `submit_staged_command_items` | |
| Commanding | `GET`, `POST …/command_stages/:id/items`; `GET`, `PATCH …/staged_command_items/:id` | StagedCommandItem | `Management.Commanding.*_staged_command_item*` | |
| Commanding | `GET`, `POST …/command_requests`; `GET /:id` | CommandRequest | `Management.Commanding.{list,persist,fetch}_command_request*` | |
| Commanding | `POST …/command_requests/:id/approve`, `/reject` | CommandRequest | `Management.Commanding.approve_/reject_command_request` | |
| Commanding | `POST …/command_requests/:id/enqueue` | CommandRequest | `Control.Commanding.enqueue_approved_command` | |
| Commanding | `GET …/command_approvals`, `/:id` | CommandApproval | `Management.Commanding.list_/fetch_command_approval*` | |
| Commanding | `GET …/command_queue_entries`, `/:id`; `POST /:id/release` | CommandQueueEntry | `Projections.CommandStatus.*`, `Control.Commanding.release_command_queue_entry` | **no cancel/abort route** |
| Commanding | `GET …/command_release_attempts`, `/:id` | CommandReleaseAttempt | `Projections.CommandStatus.*_release_attempt*` | |
| Commanding | `GET …/command_verifier_instances`, `/:id` | CommandVerifierInstance | `Projections.CommandStatus.*_verifier_instance*` | |
| Contacts | `GET`, `POST …/scheduled_contacts`; `GET /:id`; `POST /:id/realize`, `/:id/cancel` | ScheduledContact | `Contacts.*_scheduled_contact` | |
| Contacts | `GET …/realized_contacts`, `/:id`; `POST /:id/end_early` | RealizedContact | `Contacts.*_realized_contact*` | |
| Contacts | `GET …/realized_contacts/:id/runtime`, `/:id/paths/:path_id/runtime` | RealizedContact | `Runtime.realized_contact_snapshot`, `path_runtime_snapshot` | live runtime snapshot |
| Contacts | `GET …/contact_actions` | ContactAction | `Contacts.list_contact_actions` | |
| Activations | `POST …/activations`; `GET …/activations/active` | Activation | `MissionModels.request_promotion`, `Control.Activations.fetch_active_basis` | |
| Activations | `GET …/activation_requests`, `/:id`; `POST /:id/approve`, `/:id/reject` | Activation | `Management.Activations.{list,fetch,approve,reject}`, `Control.Activations.execute` | services can't approve; approve answers `outcome: applied \| needs_review` once the approval is recorded (#263) |

## 3. Browser JSON bridges

**Application host** (`W/controllers/application_host_controller.ex`, `W/application_host_bridge.ex`). This is the transport for the
federated application surfaces that the old host SPA (`frontend/apps/host`) renders.
- `GET .../catalog` (mission, spacecraft, or org/user/admin by `scope`) returns the admitted applications/surfaces and `sessionId`.
  With `scope=organization` it answers `404 no_organization_applications` ("No applications are installed at the organization level."): since §11c A + L13 no application has an organization-scope surface (the route stays until a later #80 shrink).
- `POST .../query` body: `applicationKey, applicationVersion, surfaceId, surfaceVersion, queryId, queryVersion, params`.
  `Applications.HostQueryRegistry` handles comms-overview compatibility first. Everything else is `ApplicationSurfaces.load`
  returning `{host, declarative_surface, application_surface_rows, ...}` or `{host, navigation, trusted_surface}`. These are
  presentation documents (labels, hrefs, tones), not domain DTOs.
- `POST .../actions` body: the same identity fields plus `actionId, actionVersion, params`, with header `idempotency-key`. Returns `{receiptId, completedAt, result}`.
- Query ids follow `cadence.<app>.<surface>` (`L/reads/application_surfaces/provider_registry.ex`). For example: `cadence.spacecraft.{list,new,profiles,
  profile.new,profile.show,show,edit,readiness,routing,commanding,applications}`, `cadence.mission_catalog.{mission_list,
  mission_new,mission_overview,mission_applications,catalog_index,catalog_database_new,catalog_database_show,
  catalog_revision_show,catalog_artifact_show,catalog_import_run_show}`, `cadence.comms.{overview,validation,transports,
  transport,routing,routing_detail,ground_stations,ground_station,provider_list,provider_new,provider_show,...}`,
  `cadence.limits.{manage,activity}`, `cadence.derived_telemetry.manage`, `cadence.telemetry_decom.manage`,
  `cadence.packet_bindings.manage`, `cadence.ops.<surface>` (`workspace`, `alarms`, `timeline`, `commands`, `data_sources`,
  `contact_schedule`, `dashboard_*`, `fleet_planning*`, ...) and org-admin queries. Actions are per surface (for example comms
  `create_provider`, `validate_provider`, `sync_provider`, `archive_provider`, `validate`, `save`; ops requirement templates
  `validate-template`, `create-template`, ...).
- **Reuse:** don't call it from the console. Its value is the per-surface read functions behind it (`Reads.Spacecraft.Pages`,
  `Reads.Catalog.Pages`, `Reads.Comms.Pages`, ...) and the action providers (for example `Spacecraft.Identity.action/5`).

**Contact workspace** (`W/controllers/contact_workspace_controller.ex`). This backs the contact schedule SPA.
- `GET .../missions/:m/schedule` calls `Reads.ApplicationSurfaces.Planning.ContactSchedule.load` (paged 25. The station is only in reservation metadata).
- `GET .../missions/:m/records/:contact_id` calls `ContactRecord.load`.
- `POST .../missions/:m/actions/:action` calls `Contacts.ScheduleOperations.request`. Actions: `search` (`{contract_version:2,payload}`),
  `reserve` and `cancel` (`{contract_version:2, operation_id:<uuid>, payload}`, idempotent by `operation_id`;
  `{..., observe:true}` polls the operation).
- Envelope `{version:1, actor_id, organization_id, mission_id, data}`. Console endpoints can wrap the same three calls.

## 4. Read models to wrap (`L/reads/`)

Two kinds. **Raw** reads take `(org_id, mission_id, opts)` and do no auth. **Authorized** reads take a `Scope`,
check policy themselves, and often return presentation fields (breadcrumbs, hrefs, tone strings) that console
DTOs should drop.

| Module | Key functions | Returns |
| --- | --- | --- |
| `MissionHealth` (raw) | `summary/3` (`:spacecraft_id`) | point counts, `worst_normalized_state`, `point_buckets`, per-spacecraft `scope_summaries` |
| `Alarms` (raw) | `snapshot/3`, `summary/3` | limit-condition rows sorted by severity/recency, `spacecraft_ids`, summary |
| `LimitAlarmConditions` (auth) | `load(scope, mission_id, params)`, `admit_query/1` | paged conditions for one spacecraft/state (backs `/ops/alarms`) |
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
| M9 alarms JSON `?spacecraft_id&state` | `LimitAlarmConditions.load`, `Alarms.snapshot`, `Limits.event_history` (first-crossed) | wrap |
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
