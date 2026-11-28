# Authorization inventory (#722, criterion 1)

Every authorization decision on `develop` (e7584c72d), what it decides, who it admits, over which
resource, the rule, and where it is enforced. It is the input for routing every check through one
module (#722) and for the Cedar action catalog (#723). It supersedes the 30-marker draft in
`docs/apogee/authz-inventory.md` (11-13), which stays as history.

**Read this file first; the three tables behind it hold every row** (about 490 rows, one per
distinct check, each with `file:line`):

| File | What it holds |
| --- | --- |
| [`docs/authz/policy-and-access-modules.md`](authz/policy-and-access-modules.md) | `Auth.Policy` (every clause and helper), the other `auth/` modules, the `*Access` modules, `Governance.ActivationPolicy`, the session capability list, the web access modules and plugs. |
| [`docs/authz/domain-call-sites.md`](authz/domain-call-sites.md) | Where `apps/cadence` enforces: every call of a policy action, every hand-written scope or self-approval check, all 43 `todo(authz)` markers. |
| [`docs/authz/web-layer.md`](authz/web-layer.md) | The router's pipelines, every controller action (350 route entries), the sockets and channels, the service-bearer allowlist, and what the client hides by capability. |

How it was made: a read-only sweep of the tree in three parts, each row checked against the
source. Every `file:line` in the three tables resolves to an existing file and a line inside it
(1,029 references; ten abbreviated ones are ambiguous basenames), and each of the 43
`git grep -n "todo(authz)" -- apps` markers appears. The `todo(authz)` markers are an index, not
the list: most checks have none. Counts and line numbers drift; re-grep before acting on one.

## 1. The model today

**Principals.**

| Kind | How it is built | What it can be |
| --- | --- | --- |
| Person (`actor_kind :user`) | A session cookie (CSRF header on writes). `Scope.user_scope` gives the capabilities `organization_admin` (membership role) and `platform_admin`. | A member (any active membership), an organization admin, a platform admin. |
| Platform admin | A person with the `platform_admin` capability **while in admin mode** (it lapses after the hour). | Passes `:operate_mission` / `:operate_organization` / `:manage_mission` for any organization with no membership. |
| Service identity (`actor_kind :service`) | `Authorization: Bearer`, built only by `Auth.authenticate_api_token`; mission-scoped (`mission_id`) or organization-scoped. | Refused every organization-level action, and reaches only the 12 console actions in `Console.ServiceAccess` (below). |

**A person is never a mission admin.** `Scope.user_scope` sets `mission_id` nil and gives only the
two capabilities above, so `:manage_mission` for a person means organization admin or platform
admin. The `mission_admin` branches in `ActivationPolicy.may_change/4` and `ApprovalSettingAccess`
are therefore reachable only by an organization admin or a platform admin in admin mode: a
mission-scoped service holding `mission_admin` never gets there, because `SettingsAccess` refuses
services (`auth/settings_access.ex:19`) before `may_change` runs.

**The intended model (not findings).**
- *Access to a mission is access to everything in it.* Any active member of an organization
  operates every mission of that organization (DECISIONS #62); nothing is per spacecraft, per
  command or per subsystem. So a read that carries only the `MissionScope` plug, including the
  whole commanding read surface, is authorized by design.
- *Any active member can see the people directory*, `GET …/people`: every member's email, role and
  capability list, and the invitations (including recently decided ones) with their addresses.
- *A platform admin in admin mode operates any mission by id without being a member*
  (`console/access.ex:129`, the `todo(authz)` there): the mission must exist and belong to its
  organization; the organization membership is skipped.
- *Separation of duties* is a setting (`ActivationPolicy`), not a role: see section 3.3.
- *Provider changes have no Cadence author.* They are only observed from the provider (`observe/3`), so `:approve_provider_changes` has no requester to separate from; it is an organization-admin decision by design.

**Resources.** An organization (membership, people, provider accounts, fleet planning policy),
a mission (all operations), or one of a mission's records (a command group, an activation request,
a contact plan, a change set, a dashboard, a provider reservation). Nothing is per spacecraft,
per command or per subsystem: **access to a mission is access to everything in it**. Any active
member of an organization operates every mission of that organization (`Policy` P:212).

**Error atoms for one refusal.** Refused service: `:authenticated_user_required` (most),
`:human_mission_model_approver_required`, `:human_activation_approver_required`. Wrong organization:
`:scope_mismatch`. Missing capability or inactive membership: `:forbidden`. The wrappers then
collapse them differently: `:unavailable` (`ReviewAccess`, `CommandReadAccess`,
`Administration.Access`), `:forbidden` (`Configuration.Access`), 404 `mission_not_found`
(`MissionScope`, `OrganizationScope`), 403 `forbidden` (`ReviewAccess`, `GroupAbort`).

## 2. Where the checks are

1. **Plugs.** `APISession` (cookie) or the service bearer, `MissionScope` (`:operate_mission`),
   `OrganizationScope` (`:operate_organization`), `RequireAuthenticatedScope`. Every console
   mission route sits behind `MissionScope`; **a route with nothing more is authorized only by
   "any active member"** (the intended model, section 1).
2. **`Auth.Policy.authorize/3`** (`auth/policy.ex`): 25 action atoms and the four `provider_delivery_credential.*` atoms
   (section 3), about 210 references outside the module, `:operate_mission` alone about 80.
3. **Wrappers with their own logic.** `Management.Commanding.ReviewAccess`
   (the command gate: reloads the user and membership on every call), `GroupAbort.authorize`
   (a private copy of `:operate_mission`, no reload), `CommandReadAccess` (a complete operator
   check that **nothing calls**), `Configuration.Access`, `SettingsAccess`, `Administration.Access`,
   `ControlPlaneAccess` (two functions with no callers), `ApprovalSettingAccess`,
   `Governance.ActivationPolicy`.
4. **Separation of duties** (who may not approve what): not in `Policy`. It is in
   `Governance.Accountability.separate/4` and each kind's own module (command groups, activations,
   change sets, contact plans, automation grants, mission models, provider changes).
5. **Sockets.** The connect check, each channel join (`:operate_mission`), and nothing after.
6. **The client.** A `capabilities` list in the session hides affordances; the server re-checks.

`Console.ServiceAccess @allowed` is the only door for a bearer: catalog index, import run,
artifact, apids and download, `CatalogImport` importers and create, `MissionController#show`,
spacecraft index, names and detail, `ContactRuntime#path_runtime`. Every other route answers a
bearer `403 service_not_allowed` before any other plug runs.

## 3. Proposed action catalog (#18's naming)

Names say what is decided, `resource.verb`, as `provider_delivery_credential.issue` already does.
"Today" is the atom or module that enforces it now; "sites" counts references to the atom outside
`policy.ex` (`git grep`, `apps/*/lib`). Rules are as in the tables; **the row count of the real
catalog is smaller than the atom count suggests, because about 12 organization-level atoms are one
rule (below).**

### 3.1 Organization level

One rule behind all of them (`authorize_organization_capability/4`, P:347): person only (a service
is refused first; the allowed-services list is empty since #384), then a platform admin in admin mode
passes, else the scope's organization must equal the target (`:scope_mismatch`), else the person
needs `:organization_admin` (`:forbidden`).

| Proposed | Today | Resource | Sites | Note |
| --- | --- | --- | ---: | --- |
| `organization.administer` | `:read_organization` (P:26) | organization | 7 | **Misnamed**: reads as "read", is "administer". |
| `mission.create` | `:create_missions` (P:119) | organization | 2 | `todo(authz)`. The REST route that used `:manage_missions` is gone (#384). |
| (fold into `organization.administer`, or give each use its name) | `:manage_missions` (P:35) | organization | 9 | **Misnamed**: plural, org level, despite the singular `:manage_mission`. Used for contact cancellation, the pass-release flag, `can_administer`, approval-setting flags. |
| `member.manage` | `:manage_organization_members` (P:106) | organization (people, invitations) | 7 | |
| `service_identity.manage` | `:manage_service_identities` (P:283) | organization | 5 | Person only; an extra redundant person check. |
| `provider_account.manage` | `:manage_provider_accounts` (P:128) | organization | 13 | |
| `provider_change.approve` | `:approve_provider_changes` (P:139) | organization | 2 | A provider change is observed from the provider, with no Cadence author, so there is nothing to separate (the model, section 1). |
| `mission_model.approve` | `:approve_mission_model` (P:152, 155) | organization (a revision) | 6 | A service is refused with its own atom (`human_mission_model_approver_required`, DECISIONS #92). |
| `contact_plan.approve` | `:approve_contact_plans` (P:166) | organization | 7 | |
| `fleet_planning_policy.manage` / `.approve` | `:manage_fleet_planning_policy` (P:177), `:approve_fleet_planning_policy` (P:188) | organization | 2 / 2 | `Policy` has no separation, but the decision does: `not_author/2` (`contact_planning/fleet_planning_policies.ex:354-365`) refuses `created_by == actor` for approve and reject, unconditionally. |
| `automation_grant.manage` | `:manage_automation_grants` (P:199) | organization | 7 | |
| `organization.read` | `:operate_organization` (P:89) | organization | 4 | Any **active member**, not an admin. Also `OrganizationScope`, which alone authorizes `GET …/people` and `GET …/missions` (the intended model, section 1). |

### 3.2 Mission level

| Proposed | Today | Principals | Sites | Note |
| --- | --- | --- | ---: | --- |
| `mission.operate` | `:operate_mission` (P:212) | any active member or platform admin; a **mission-scoped, active** service for its own mission | 80 | The rule almost everywhere; plus the plug `MissionScope`. Strict: checks the mission belongs to the organization, and pins a service to its mission and lifecycle. |
| `mission.administer` | `:manage_mission` (P:298) | organization admin or platform admin; a service holding `organization_admin`, or `mission_admin` pinned to the mission | 18 | **Looser than operate**: it does not check the mission belongs to the organization; a platform admin skips the organization check; a service with `organization_admin` passes for any mission of its organization even if mission-scoped; service lifecycle is not checked. |
| `command_release.resolve`, `provider_reservation.resolve`, `prepared_send.reconcile` | `:resolve_command_release`, `:resolve_provider_reservation`, `:reconcile_prepared_send` (P:44) | `:operate_mission` **and** `:manage_mission` | 2, 2, 1 | One rule, three names. A plain member fails the second. |
| `provider_delivery_credential.issue` / `.rotate` / `.revoke` / `.downgrade` | the four atoms (P:54) | person with `:manage_mission` | dynamic call, `provider_delivery_credentials.ex:390` | A service gets `authenticated_user_required`. Reads of a credential use a write permission. |
| `settings.read` / `settings.manage` | `:read_settings`, `:manage_settings` (P:71) | a person; org level uses `:operate_organization`, mission level `:operate_mission` | 3 / 7 | **Any active member**, not a manager: the configuration and pass-review settings sections that check only this are writable by every member. |
| `dashboard.author` | `:author_dashboards` (P:256) | person; delegates to `:operate_mission` | 12 | `todo(authz)` (`dashboards/capabilities.ex:21`). |
| `application_catalog.read` | `:read_application_catalog` (P:232) | `:operate_mission` | 4 | Same rule as `mission.operate`. |
| (delete) | `:read_legacy_application` (P:242) | `:operate_mission` | 0 | **Never called outside tests.** |
| `activation.request` | `:request_activation` (P:263) | person: `:operate_mission`; service: `:manage_mission` | 7 | The one action whose rule differs by principal. Ignores `change_class`. |
| `activation.approve` | `:approve_activation` (P:268, 271) | person: `:operate_mission` (any member may approve; separation is elsewhere); service: refused (`human_activation_approver_required`) | 4 | |

### 3.3 Not in `Policy`: command, change set and approval checks

| Proposed | Today | Rule | Where |
| --- | --- | --- | --- |
| `command_group.request`, `.decide`, `.release`, `.note`, `command.encode`, `command.brief`, `command_draft.manage` | `ReviewAccess.authorize/2` | `:operate_mission` for a person (reloads user and membership each call); the decision adds the self-approval rule (`Accountability.separate/4`; a service requester counts as its accountable people) | `management/commanding/review_access.ex`, `management/commanding.ex`, `control/commanding/group_submission.ex`, `group_decision.ex` (`todo(authz)` at each) |
| `command_group.abort`, `command_request.cancel` | `GroupAbort.authorize` | `:operate_mission`, user only; a private copy, **no fresh reload** | `control/commanding/group_abort.ex` |
| `command_group.read` (list, show, targets, events, preflight, verifier series, command history, catalog) | the plug only | `MissionScope`; the readers take only organization and mission ids. `CommandReadAccess` is a full operator check that **nothing references** | `web-layer.md` §2.5 |
| `approval_setting.change` | `ApprovalSettingAccess` + `ActivationPolicy.may_change/4` | direction rules for tightening/loosening a mission's approval requirement; the mission-admin branch is reachable by a mission-scoped service or an organization admin | `management/approval_setting_access.ex` |
| `change_set.review` | `Configuration.Access` and the submission's separation check | always enforced | `domain-call-sites.md` §3 |

The self-approval and two-person rules, by kind (verified against the code):

| Always enforced | Enforced only when `separation_of_duties` is on (`ActivationPolicy` "independent") | Not enforced |
| --- | --- | --- |
| command group GO (`Accountability.separate/4`); activation request (the requester check; the author check is skipped only when the request recorded `separation_of_duties` false); change-set review (a set in review); fleet planning policy approve **and** reject (`not_author/2`, `fleet_planning_policies.ex:354-365`) | contact plan approve (only approve); automation grant approve and resume (reject, revoke and narrow have none); mission model approve (reject has none, and an importer with no record is approvable by any admin) | (not applicable) provider change approval: observed from the provider, no Cadence author |

`ActivationPolicy.evidence` is the switch: `"independent"` is one human approval plus separation of
duties, `"direct"` is none.

## 4. Duplicates

- About 12 organization-level atoms are the same rule under different names (section 3.1).
- `mission.operate` has six aliases: `:read_application_catalog`, `:read_legacy_application`,
  `:author_dashboards`, `:read_settings`/`:manage_settings` (mission level), `:approve_activation`,
  and the person branch of `:request_activation`.
- `ReviewAccess.authorize`, `GroupAbort.authorize` and `CommandReadAccess` each implement
  `:operate_mission` again; and
  `scope.mission_id in [nil, mission_id]` is repeated in about 15 modules, where for a person it
  does nothing (`mission_id` is always nil) and for a service `Policy` already pins it.
- The pass-release flag, the approval-setting flags and the `can_decide` flags each repeat the
  save rule for display (`ApprovalSettingAccess.flags` per field, in memory; `may_release?` once
  per request; the activation row's `can_decide` compares the raw requester id, unlike the
  enforcement path, which expands a service requester through `Accountability`).

## 5. Findings, with severity

Each finding was re-checked against the code by a second pass trying to disprove it; the ones that
did not survive are in "Withdrawn" below. Severity is for the decision of whether to fix it now:
**high** a person or session keeps access it should have lost; **medium** a rule that is weaker
than the rest of the system or than the client shows, or a missing separation; **low** a hazard,
a misnaming, dead code or a cost that does not grow with a fleet.

| # | Sev | Finding | Evidence |
| --- | --- | --- | --- |
| F1 | **high** | **A live console socket keeps its channels after the person's access ends.** Only a password change, a session revoke and a sign-out disconnect a socket (`account_controller.ex:16,45,53,57`, `session_controller.ex:32`); membership removal, a role change, deactivation and admin-mode expiry do not. `connect/3` captures `admin_mode?` once, so an admin-mode socket keeps it for later joins (each join re-reads the session, user, membership and `platform_admin` capability, but reuses the connect-time `admin_mode?`). After a join nothing re-checks: the `command_group` channel pushes with no check, the `dashboard` channel's `view:set`/`view:subscribe` re-run `:operate_mission` against the join-time scope struct, so the check can never fail, and `fleet:subscribe`, `fleet:unsubscribe` and `points:set` authorize nothing. Filed as #1153. | `console_socket.ex:24-34`; `mission_channel.ex:67`; `command_group_channel.ex:20,57`; `spacecraft_channel.ex:28,61`; `dashboard_channel.ex:29,66` |
| F2 | medium | #1158 (**fixed**: `:manage_mission` now checks the mission against the organization for every principal, and a service pinned to one mission administers only that one; the row below describes what it was). **`:manage_mission` is looser than `:operate_mission`**: it does not check the mission belongs to the organization; a platform admin skips the organization check; a service holding `organization_admin` passes for any mission of its organization even when pinned to another (the admin UI forbids that combination, `Auth.issue_service_identity` does not). Callers compensate through `MissionScope` and by fetching the mission by organization id, so it is defence in depth. A service's lifecycle is checked by bearer authentication (only active identities load), so that part is fine. | `auth/policy.ex:298-320` |
| F3 | medium | #1159 (**fixed**; ruled: organization-level `:manage_settings` needs an organization admin; mission level stays operate). **Any active member can write the organization-level configuration and pass-review settings.** `:read_settings`/`:manage_settings` admit any active member (organization level: `:operate_organization`; mission level: `:operate_mission`), and those two sections check nothing stricter; only the governance section adds `ActivationPolicy.may_change`. | `auth/policy.ex:71-84`; `management/configuration_settings_section.ex`, `management/pass_review_settings_section.ex` |
| F4 | medium | #1160 (a per-action table, with a default ruling per row). **The client gate is stricter than the server**: ten or more setup screens hide config staging, catalog import, settings, requirement editing and activations behind the client-only `canAdministerOrganization`, while the server needs only `:operate_mission`, so any mission operator can do them. (Equal for mission create, provider accounts, audit and plan approve/reject.) The server is the authority; this is the same rule as F3 seen from the client. | `web-layer.md` §4 |
| F5 | low | (F5-F14 are tracked in #1161.) `data_sources.manage` is advertised to any operator, but every data-sources write also needs `:read_organization` (organization admin), so a non-admin operator sees an action and is refused with 403. The `todo(authz)` there says "any mission operator". | `applications/ops_console/actions/data_sources.ex` (`authorize/3`) |
| F6 | low | **`MissionModelApprovals.compare` persists a report on a read path** with no authorize call (`comparison.ex:427`), as do `list`/`read`; activation request `list`, `get` and `configuration_change_names` have no domain check either. The route's `MissionScope` plug is the only check (by the model above, any member). | `reads/mission_model_approvals.ex`, `control/activation_requests.ex:26,36,52` |
| F7 | low | `DashboardDirectoryController#view` is a write authorized only by the plug. | `web-layer.md` §2.8 |
| F8 | low | **Reads that use a write permission, and misnamed actions**: `:read_organization` is "administer"; `:manage_missions` is plural and org-level (9 sites); the delivery-credential `show` needs `:manage_mission`. About 12 organization-level atoms are one rule. | section 3 |
| F9 | low | **Dead code**: `CommandReadAccess` (a complete operator check, nothing calls it), `:read_legacy_application`, `ControlPlaneAccess.authorize_mission/3` and `authorize_spacecraft/4`, `Policy.service_allowed_organization_actions/0` (non-test callers: none). | section 2 |
| F10 | low | `Control.Contacts.execute_approved_plan` inserts the execution items (`accept`, one insert per snapshot, no transaction) before `authorize_execution`; no caller exposes it (the user path already passes `may_execute`; the service path inserts nothing new). | `control/contacts.ex:103-112` |
| F11 | low | The provider functions that take `Scope | binary` (`persist_provider`, `archive_provider`, `validate_provider`, `sync_provider`, `ProviderCredentials.create`/`rotate`/`revoke`) skip authorization for a binary organization id; the binary callers are tests, fixtures and re-calls after the Scope clause authorized; none is reachable from the web. `version_provider` is organization-id only. | `domain-call-sites.md` §5 |
| F12 | low | **Service bearer reach** is wide for a mission-bound service: it can download raw catalog source-file bytes (no check beyond `ServiceAccess` and `MissionScope`) and import a catalog as itself (`create` re-runs `:operate_mission` and records the service as the importer). By design (an opt-in), recorded so the Cedar catalog sees it. `ContactPlanController#may_execute` returns ok for any service, dead only because `ServiceAccess` excludes the route. | `console/service_access.ex`; `contact_plan_controller.ex` |
| F13 | low | **Refusals differ for the same cause** (section 1), and `Administration.Access`'s `:unavailable` becomes 403 `admin_mode_required`. | `web-layer.md` |
| F14 | low | A signed-out application-host request gets a 302 only when its CSRF token is valid (else a JSON 403 `invalid_csrf`); the JSON 401 plug is dead. `HostPageLive` (3 ops routes, being deleted) applies no `:operate_mission` at mount; its data reads apply it in the domain. | `web-layer.md` §2.13 |

**Withdrawn after the re-check and the review**: "fleet planning policy approval has no author check" (it
refuses the author, `fleet_planning_policies.ex:354-365`); "provider change approval has no author check" (a
provider change is observed from the provider and has no Cadence author, so it is the model); "the plug-only commanding reads and the people
directory are gaps" (they are the model above); "`Control.Commanding.dispatch_queue_lane` takes no
scope" (called only as the dispatchers' default function); "`may_release?` runs per pass" (once per
request); "the mission-admin branches are reachable by a mission-scoped service" (they are not).

## 6. Authorization cost per request (the 500-spacecraft floor)

A list read should authorize once and scope its query. Measured by reading the code (not
profiled); none of these grows with the number of spacecraft, but the first two grow with members
and missions:

| Where | Cost |
| --- | --- |
| Session capability list (`Console.Capabilities.organization/1`) | Per organization the person belongs to, per session read: its three Policy-derived sources use `Enum.any?`, so about one `Policy.authorize` each (in memory, with an ETS-cached mission-organization check), but each starts with a `list_missions` full-row read: 4 reads per organization, and 3 more for the current organization in `SessionJSON`. |
| People directory | The commanding and abort capability sources run **per member**: two `list_missions` queries per member, O(members) queries and O(members x missions) rows. |
| `ReviewAccess.authorize` | Three DB reads per call (the user, the membership, the mission), a fourth on a cold mission-organization cache; it re-fetches instead of trusting the request's scope. `GroupAbort.authorize` reloads nothing and skips the mission pin and id validation. |
| Fleet planning | One authorize per run, per 250-requirement batch and per phase in production; the per-requirement path runs only through test seams. |
| Grant ledger flags | Proposed grants: 2 settings reads each; suspended: 1; the replaced-proposer query only for replacing proposals under "independent". Others cost no query. |
| `ApprovalSettingAccess.flags` | Per field of the governance section; 1-2 in-memory Policy calls, no DB. |
| Each channel join | One full `authorize_mission` (session, user, membership, mission reads). |

`Policy.mission_in_organization/2` caches confirmed (organization, mission) pairs for good and
re-queries every refused pair.

## 7. What the next steps need from this

- **One module** (#722 criterion 2): the catalog in section 3 is the list of names; the duplicates
  in section 4 collapse into it, and the wrappers become thin calls. A missing atom raises
  `FunctionClauseError` today (no catch-all); that stays.
- **The session capability list** (criterion 3, DECISIONS #38) is the one hand-written part: it
  should be derived from the catalog for every action, with the per-role agreement test extended.
- **List reads** (criterion 4): the table in section 6, starting with the People directory and the
  session load (`list_missions` once per request, not per source).
- **Cedar (#723)** needs the attributes the rules read: a person's membership role and
  platform-admin mode; a service's mission pin, capabilities and lifecycle; the resource's
  organization, mission and (for commanding) hazard, significance, fleet reach and requester; and
  for separation of duties the requester's accountable set. None of the rules reads a per-mission
  role for a person, because none exists; adding one is the first policy to write
  (`docs/apogee/authz-inventory.md`).
