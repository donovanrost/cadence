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
admin, and the `mission_admin` branches in `ActivationPolicy.may_change/4` and
`ApprovalSettingAccess` are reachable only by a mission-scoped service or an organization admin.

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
   "any active member"** (section 5).
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
| `provider_change.approve` | `:approve_provider_changes` (P:139) | organization | 2 | Proposer/approver separation is elsewhere. |
| `mission_model.approve` | `:approve_mission_model` (P:152, 155) | organization (a revision) | 6 | A service is refused with its own atom (`human_mission_model_approver_required`, DECISIONS #92). |
| `contact_plan.approve` | `:approve_contact_plans` (P:166) | organization | 7 | |
| `fleet_planning_policy.manage` / `.approve` | `:manage_fleet_planning_policy` (P:177), `:approve_fleet_planning_policy` (P:188) | organization | 2 / 2 | **No author-vs-approver check at all** on approve. |
| `automation_grant.manage` | `:manage_automation_grants` (P:199) | organization | 7 | |
| `organization.read` | `:operate_organization` (P:89) | organization | 4 | Any **active member**, not an admin. Also `OrganizationScope`, which alone authorizes `GET …/people` and `GET …/missions` (section 5). |

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

The self-approval and two-person rules, by kind: **always enforced** for command groups,
activations and change-set review; **only when `separation_of_duties` is on** for contact plans,
automation grants and mission models; **none** for fleet planning policy approval.
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
  save rule for display (`ApprovalSettingAccess.flags` per field; `may_release?` per pass; the
  activation row's `can_decide` compares the raw requester id, unlike the enforcement path, which
  expands a service requester through `Accountability`).

## 5. Gaps the inventory found (each to be filed under #722 as a bug)

**Plug-only reads (nothing beyond "any active member of the organization")**: the whole commanding
read surface; `GET …/people` (every member's email, role and capability list, and pending
invitation addresses; the client shows People to organization admins only);
`GET …/organizations/:id/missions`; activation request `list`/`get`/`configuration_change_names`
(`control/activation_requests.ex:26,36,52`); `MissionModelApprovals.list`/`read` and `compare`
(which persists a report); `DashboardDirectoryController#view`. The only **writes** with nothing
beyond the scope plug are `DashboardDirectoryController#view` and the dev-only ingest; every
other write has a named check.

**Domain functions that rely on the caller**: `Control.Contacts.execute_approved_plan` inserts
execution items (`accept_approved_plan`) before `ContactPlanExecutions.execute` authorizes
(`control/contacts.ex:103-112`); `Control.Commanding.dispatch_queue_lane` takes no scope; the
provider functions that take `Scope | binary` skip authorization when given an organization id.

**Server stricter or weaker than the client**: ten or more setup screens hide config staging,
catalog import and requirement editing behind the client-only `canAdministerOrganization`, while the
server needs only `:operate_mission` (so any mission operator can do them); `data_sources.manage`
is advertised to any operator but the server needs `:read_organization` (organization admin);
`planning.edit` is one client token over three different server checks (organization admin,
`:manage_mission`, `:operate_mission`); the session `capabilities` list is part hand-written
(`organization_admin`, `platform_admin` strings) and part derived from `Policy`
(`command.request`, `command.approve`, `command.abort`, `org.invite`, `org.manage_members`,
`dashboard.author`). `data_sources.ex` requires organization admin for every action though its
`todo(authz)` says "any mission operator".

**Sockets never re-check identity after a join.** `disconnect` is broadcast only on password
change, session revoke and sign-out, not on membership removal, role change, deactivation or
admin-mode expiry; `admin_mode?` is captured once at connect, so a socket keeps platform-admin
joins after the hour ends; the `command_group` channel pushes with no authorization call; the
dashboard `view:set` event re-runs `:operate_mission` against the frozen join-time scope.

**Service bearer reach.** A mission-bound service can download raw catalog source files and
import a catalog as itself; `ContactPlanController#may_execute` returns ok for any service
(dead only because `ServiceAccess` excludes the route); `ContactRuntime#path_runtime` is opted in
though its sibling `runtime` (same check) is not.

**Platform admin**: in admin mode, passes `:operate_mission` for any mission by id without being a
member (`todo(authz)` at `console/access.ex:129`); `ReviewAccess` allows it with no membership.

## 6. Checks done per row (the 500-spacecraft floor)

A list read must authorize once and scope its query. These authorize, or compute the answer to an
authorization, once per item:

| Where | Cost |
| --- | --- |
| `Console.Capabilities.organization/1` (session load) | Three of its five sources run `Policy.authorize` over **every mission of the organization**, once per organization the person belongs to, on each session read. |
| `ReviewAccess.capabilities`, `GroupAbort.capabilities`, `Dashboards.Capabilities.list` | Each lists all missions and authorizes per mission; the **People directory runs the first two once per member** (members x missions). |
| `ReviewAccess.authorize` | Extra DB reads on every commanding call (it re-fetches the user and membership instead of trusting the request's scope; the domain sweep counted three). |
| Fleet planning (`Planner.run`, `update_requirement_progress`, `checkpoint_search_batch`) | `:operate_mission` per requirement and per batch (`fleet_planner.ex:356-370`, `fleet_search.ex:15`, `FleetPlanningRuns` per write). |
| Grant ledger flags | Policy, `ActivationPolicy.evidence` and a replaced-proposer query per grant. |
| `ApprovalSettingAccess.flags` | Per field. |
| Pass release flag (`may_release?`) | The booker check per pass. |
| Activation `can_decide`; mission-model `viewer_can_decide` | Per row / per revision, display only. |
| `GET …/people`, `GET …/dashboards`, activation and mission-model reads | Per-row flags on a plug-only read. |
| Each per-spacecraft channel join | One DB-backed `authorize_mission`. |

`Policy.mission_in_organization/2` caches confirmed (organization, mission) pairs for good but
re-queries every refused pair.

## 7. What the next steps need from this

- **One module** (#722 criterion 2): the catalog in section 3 is the list of names; the duplicates
  in section 4 collapse into it, and the wrappers become thin calls. A missing atom raises
  `FunctionClauseError` today (no catch-all); that stays.
- **The session capability list** (criterion 3, DECISIONS #38) is the one hand-written part: it
  should be derived from the catalog for every action, with the per-role agreement test extended.
- **List reads** (criterion 4): the table in section 6, starting with the session load and the
  People directory.
- **Cedar (#723)** needs the attributes the rules read: a person's membership role and
  platform-admin mode; a service's mission pin, capabilities and lifecycle; the resource's
  organization, mission and (for commanding) hazard, significance, fleet reach and requester; and
  for separation of duties the requester's accountable set. None of the rules reads a per-mission
  role for a person, because none exists; adding one is the first policy to write
  (`docs/apogee/authz-inventory.md`).
