# Frontend ownership verification

Evidence reconciled on 2026-09-11 for [ADR-024](../decisions/024-host-composition-and-vertical-frontend-modules.md).
The implementation and workflow audit is complete, and the final documentation gate passed.

The target is six host areas containing 35 vertical features and eight domain
modules containing 40 vertical features. The existing remote application packages
remain delivery adapters with their durable application/release/surface identities.
Coordinated frontend publication is supported; independent releases and the future
payload-specific module are not requirements of this migration.

## Requirement evidence

| Requirement | Implementation and verification |
| --- | --- |
| Host owns core pages and placement | Six host areas listed below; `ApplicationShell.vue` composes their pages and keeps navigation outside contributed content. Its component tests cover all shell variants and retained sidebar identity across mission navigation. |
| Domain ownership independent of URL | Eight modules listed below. Provider accounts are Communications at organization scope; runtime diagnostics are Dashboards inside administration; Ops is host composition. |
| Vertical colocation | All 75 feature directories have local tests. Components, feature state, semantic contracts, validation and contribution implementations reside with their features. Public package entries assemble or export these implementations. |
| Public imports | TypeScript/Vue AST audit of 20 frontend packages found 714 cross-package imports, no private/unexported or relative cross-package imports and no unknown workspace package imports. This is static boundary evidence, separate from runtime behavior. |
| Compatibility without duplicate feature implementation | Existing remote feature files delegate to owner public entries or canonical native destinations. Application wrappers retain delivery, bridge lifecycle and compatibility event transport. Native and published dashboard destinations were checked separately, including persisted long identifiers. |
| Named, versioned contracts | `packages/plugin-sdk/src/*-contribution.ts` separates UI page/diagnostic slots from readiness data. Host registries admit compiled identities, supported slots and versions; server payloads cannot choose arbitrary imports. Feature registrations supply their own DTO validators. |
| Context admission | Mission, spacecraft, organization and Ops module-page tests reject wrong organization/mission/resource, slot, identity and version, malformed feature data, and stale interaction ports. Host envelopes are validated separately from feature-owned domain fields. |
| Failure isolation | `DiagnosticsContributionBoundary.test.ts` mounts the real boundary with healthy and throwing siblings, verifies navigation survives and private errors stay hidden, and verifies recovery on a fresh snapshot. Its parent is a minimal test parent. Mission/spacecraft/Ops boundaries have local failure and stale-context tests; `RemoteApplicationBoundary.test.ts` covers approved-load failure, fallback/retry and discarded late loads. Shell composition is tested separately. |
| Phoenix authority | Native page/action tests exercise authenticated route entry, scope-bound producer DTOs, exact tokens/revisions, permission rejection, duplicate effects, stale reads and revoked sessions. Browser sessions exercise the published frontend against these native endpoints. Loading or installing a module grants no authority. |
| Durable identities and URLs | Existing route families and application identities remain. Tests preserve exact version pins, reviewed-plan identity, wide integer/JSON values, microsecond timestamps, encoded URL selectors, selected evidence outside a page/filter, and reload behavior. The dashboard identity browser uses 240-character stored IDs within the existing publication transport bound; it does not prove every storage-accepted identifier can traverse that bound. |
| Usable workflows | Owner evidence below combines real component interactions, native producer/consumer and persistence tests, and authenticated browser navigation. Read-only remote loading is not counted as effect completion. |
| Production appearance and compilation | Shared production UI and tokens remain the presentation foundation. Desktop/mobile browser screenshots were reviewed. The latest code-changing frontend cohort passed 20-project checks, 1,456 component tests including 65 Chrome tests, transport/tool suites, publication build and Phoenix assets. Subsequent production repair changed only the native contact context DTO. |

## Owner workflows and native evidence

Paths in this table are relative to `apps/cadence_web/test/cadence_web/` unless otherwise noted.
The feature-local component tests are indexed in the next section.

| Owner | Authorized workflows verified | Representative native evidence |
| --- | --- | --- |
| Auth and navigation | Sign-in, admin-mode reauthentication, invitations, organization access, notifications, account menu and retained rails | Authentication/navigation route tests; notifications page tests; authenticated auth, notification and header browser cohorts |
| Mission and spacecraft | Mission/profile/spacecraft creation, directories, exact profile pins, identity changes, readiness and module composition | `mission_module_page_test.exs`, `spacecraft_module_page_test.exs`, `profile_creation_test.exs`, `spacecraft_identity_test.exs`, `spacecraft_page_test.exs` |
| Catalog | File upload, import execution, database/revision/artifact reads and provenance | Catalog native page/import tests; actual two-upload browser with immutable revision and artifact assertions |
| Administration | Organization directory/creation/detail/invite, platform counts, service identity and diagnostics composition | `platform_administration_page_test.exs`, `platform_organization_detail_page_test.exs`, `organization_home_page_test.exs`, `organization_module_page_test.exs` |
| Capability management | Both-scope installation lifecycle, pinned-profile eligibility, activation approval/application and rejection | Installation/activation native tests; later browser asserts exact activation request and runtime generation one |
| Ops workspace | Landing, shared frame, selected context, module placement and cross-module timeline | `ops_landing_page_test.exs`, `ops_timeline_page_test.exs`, local frame and shell tests |
| Communications | Provider-account registration, credentials and grants; mission provider creation/archive; transport/station/routing create/edit/read | `provider_account_registration_page_test.exs`, `provider_account_detail_page_test.exs`, mission/spacecraft module-page tests; browser asserts exact persisted references and immutable provider versions |
| Planning and contacts | Requirements/templates, plan version/approval/manifests/execution evidence, policy/grants, fleet create/continue/repair, contact booking and reviewed cancellation | `ops_requirement_page_test.exs`, `ops_requirement_template_page_test.exs`, `ops_plan_review_page_test.exs`, `ops_fleet_policy_page_test.exs`, `ops_fleet_workflow_page_test.exs`, `ops_contact_scheduling_page_test.exs`, `ops_contact_review_page_test.exs` |
| Dashboards and exploration | Creation/directory, editor/library/version pins, metadata/share/snapshot/archive/export, workspace/activity/playlists, physical sample exploration, execution/runtime diagnostics | `dashboard_authoring_test.exs`, `dashboard_library_test.exs`, `dashboard_settings_test.exs`, `ops_settings_page_test.exs`, `dashboard_shared_views_test.exs`, `dashboard_playlists_test.exs`, `dashboard_workspace_read_test.exs`, `dashboard_exploration_sample_test.exs`, `dashboard_execution_diagnostics_test.exs` |
| Commanding | Release/history/monitor and uncertain claim recovery; spacecraft endpoints | `command_history_read_test.exs`, `command_monitor_read_test.exs`, `spacecraft_commanding_page_test.exs` |
| Data operations | Source definitions, bindings/settings and lifecycle events; historical query/review/admission | `ops_data_sources_page_test.exs`, `ops_historical_workflows_page_test.exs`; browser verifies six historical audit events and two admitted jobs |
| Telemetry decom | Configuration, packet revisions/bindings, exact approved prerequisite and activation request | Native decomposition/packet/preflight tests; populated browser verifies exact packet, revision, endpoint and review identity |
| Derived telemetry | Definition save/read/latest state and scoped activation contribution | Native definition/action tests and contribution lifecycle browser with exact point version and second-mission isolation |
| Limits and alarming | Definition save/read, posture, alarm evidence/navigation | Native limits/action tests, contribution lifecycle and alarm browser cohorts; exact sample href verified separately from populated exploration |

Dashboard settings reconciliation includes every supported effect: metadata saves
preserve publication; shares enforce expiration and dashboard-bound revocation;
snapshots retain their captured definition; archive rejects later authoring; export
records the saved version and requires authentication. Native tests also exercise
stale publication changes, invalid input, foreign scopes and bounded metadata.
Component tests cover confirmation, dirty navigation, uncertain writes and explicit
rebase/discard. These are separate from the browser's narrower save/share navigation.

Commanding reconciliation covers all nine features. Exact-value authoring and
review avoid JavaScript numeric coercion; stage edits retain actor/version pins;
queue/release attempts are single-flight and receipt-bound; history and monitor
keep selections across paging/filters. Recovery of an uncertain attempt preserves
the held lane and original records rather than claiming successful delivery.

## Feature-local test index

The host areas and domain modules this index linked (`frontend/apps/host`, `frontend/modules/*`)
were deleted with the federated host (#668, #672); the console (`frontend/apps/console`) is the
only UI. The rows are in the git history.

## Authenticated browser record

The following 43 cohort results were reconciled with passing native test terminals,
not merely browser result files. Each native test starts an ephemeral endpoint in
a SQL sandbox, runs the actual Chrome frontend and makes its own persistence
assertions where effects are exercised. Scenario counts describe that cohort and
must not be summed as independent or exhaustive cases. Local evidence currently
lives under `/tmp/<cohort>/`; it is run evidence, not a permanent test location.
The committed native/component tests remain reproducible from the repository.

| Cohort | Scenarios | Passing native terminal/log within the cohort |
| --- | ---: | --- |
| `cadence-administration-directory` | 16 | `authenticated/run.log` |
| `cadence-alarm-owner` | 10 | `authenticated/browser-test-3.log` |
| `cadence-auth-navigation` | 12 | `browser.log` |
| `cadence-command-authoring` | 15 | `browser.log` |
| `cadence-command-exact-authoring-next` | 19 | `final-native-browser-exit.json` |
| `cadence-command-history-next` | 17 | `browser-2-exit.json` |
| `cadence-command-monitor-next` | 15 | `browser-2-exit.json` |
| `cadence-command-recovery-next` | 11 | `native-browser-exit.json` |
| `cadence-command-release` | 13 | `queue-browser-2-exit.json` |
| `cadence-command-review` | 13 | `browser.log` |
| `cadence-command-review-exact` | 13 | `browser-exit.json` |
| `cadence-command-stages` | 24 | `authenticated/browser.log` |
| `cadence-contribution-lifecycle-next` | 12 | `native-browser-retry-exit.json` |
| `cadence-creation-destination-next` | 12 | `native-browser-console-exit.json` |
| `cadence-dashboard-identity-next` | 9 | `native-browser-confirmed-exit.json` |
| `cadence-dashboard-legacy-next` | 8 | `native-browser-3-exit.json` |
| `cadence-dashboard-registry-next` | 14 | `native-browser-exit.json` |
| `cadence-data-sources-authenticated-next` | 10 | `native-browser-validation-exit.json` |
| `cadence-directory-destination-next` | 13 | `native-browser-exit.json` |
| `cadence-notifications-feature` | 14 | `authenticated/run.log` |
| `cadence-ops-header` | 12 | `authenticated.log` |
| `cadence-ops-landing-next` | 13 | `native-browser-4-exit.json` |
| `cadence-organization-home` | 10 | `authenticated-2.log` |
| `cadence-plan-review-authenticated-next` | 13 | `native-browser-labels-exit.json` |
| `cadence-platform-administration` | 18 | `browser-2.log` |
| `cadence-remote-residual-next` | 11 | `native-browser-exit.json` |
| `cadence-timeline-feature` | 14 | `authenticated/run.log` |
| `cadence-decom-authenticated-next` | 13 | `native-browser-final-exit.json` |
| `cadence-historical-authenticated-next` | 9 | `native-browser-deeplink-exit.json` |
| `cadence-requirements-authenticated-next` | 10 | `native-browser-label-exit.json` |
| `cadence-mission-identity-authenticated-next` | 10 | `native-browser-final-exit.json` |
| `cadence-activation-authenticated-next` | 6 | `native-browser-exit.json` |
| `cadence-catalog-authenticated-next` | 13 | `native-browser-fixed-exit.json` |
| `cadence-installations-authenticated-next` | 10 | `native-browser-exit.json` |
| `cadence-policy-authenticated-next` | 7 | `native-browser-disclosures-exit.json` |
| `cadence-provider-accounts-authenticated-next` | 10 | `native-browser-exit.json` |
| `cadence-comms-forms-authenticated-next` | 9 | `native-browser-exit.json` |
| `cadence-mission-provider-authenticated-next` | 6 | `native-browser-fixed-exit.json` |
| `cadence-contact-scheduling-authenticated-next` | 7 | `native-browser-fixed-exit.json` |
| `cadence-fleet-workflow-authenticated-next` | 10 | `native-browser-refresh-exit.json` |
| `cadence-dashboard-authoring-authenticated-next` | 9 | `native-browser-exit.json` |
| `cadence-exploration-authenticated-next` | 7 | `native-browser-persisted-exit.json` |
| `cadence-diagnostics-authenticated-next` | 11 | `native-browser-context-exit.json` |

The final exploration cohort stores real Postgres evidence, packet and observation
fixtures with distinct generation/receipt clocks. It verifies exact microsecond
selection and rejection of a one-microsecond mismatch; sample and binding remain
unchanged. Persisted source mode is enabled explicitly because the test environment
otherwise defaults to fallback sources.

The final diagnostics cohort uses a stored runtime decision event. It verifies
selected evidence outside the current filter, waits for Show context navigation,
then reloads. Process-local runtime health alone cannot satisfy that durable
lookup. It also verifies password reauthentication for platform administration,
private metadata redaction, session removal and scoped execution inspection.

## Practical limits

- Provider-account credential validation uses the test backend configuration.
  Contact booking/cancellation uses the Req provider adapter and proves exactly
  one request for each plus persisted cancellation revision two. No external
  provider account or reservation was contacted by these browser runs.
- Fleet continuation finishes with a partial fixture outcome. Repair creates a
  source-pinned successor while retaining the uncertain source. Plan execution
  covers governed unavailable-route behavior, not a successful external booking.
- Historical workflows prove authorized job admission and audit records, not
  external processing. Source tests prove persisted definitions/bindings and
  events, not remote backend provisioning. Exploration proves stored observations,
  not live ingress. Decom review and the separately tested activation inbox are
  distinct workflows; a review alone is not an applied activation.
- UI failure isolation is covered by actual component boundaries and native
  authorization tests. No claim is made that every browser workflow injects every
  renderer failure or that every mobile screenshot covers every state.
- This verification does not merge, commit, deploy or publish an external release.
  Local publication artifacts are builds for validation.

## Final gate

The preceding code checkpoint passed 42 plane tests and 3,955 workspace tests
(333 foundation, 2,581 domain, 905 web, 136 simulator). Architecture checked
1,456 domain/web sources and 6,180 dependencies with zero dependency-boundary findings. The subsequent
exploration/diagnostics runs left all 5,660 recorded source files unchanged.

Final documentation gate passed at 2026-09-11T04:38:09.074287+00:00: 42 plane tests and 3,955
workspace tests (333 foundation, 2,581 domain, 905 web, 136 simulator). Architecture
checked 1,456 domain/web sources and 6,180 dependencies with zero dependency-boundary findings. All
5,661 frozen files matched with zero drift; both changed paths are owned by this
documentation cohort. Only this result and the ADR completion status changed after
the gate. The checked inventory and terminal evidence are recorded under
`/tmp/cadence-ownership-verification-next/`.

The architecture checker also reports existing source-size pressure (24 production
files, one test file and two test functions); its passing boundary check is not a
claim that every maintainability metric is zero.

Required commands were `corepack pnpm check`, `corepack pnpm test`,
`corepack pnpm build:publication` from `frontend/` (deleted with the federation, #672), the
repository Phoenix asset build, and `mix precommit` from the workspace root. Use the pinned Erlang/Elixir
versions for the checkout. Clear `CADENCE_BROWSER_PROPS_DIFF` for ordinary native
Vue-prop tests and the root gate; the ephemeral native Chrome harness enables it.
