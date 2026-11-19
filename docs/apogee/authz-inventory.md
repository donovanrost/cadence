# Authorization inventory: every `todo(authz)` (groundwork for Cedar)

api, 2026-11-13, for the director (lead's queue). This is read-only groundwork: **no Cedar code**
(deferred by the user). Source: `grep -rn "todo(authz)" apps/*/lib packages/*/lib` on
`ui/apogee-spa`, 30 markers. Line numbers are as of this write; re-grep before acting on them.

Each entry gives the action, today's rule (what the code checks now) and what a Cedar policy
would need to decide it: the principal's attributes, the resource's attributes and the request
context. "Operator" below means `Policy :operate_mission`.

## The one rule underneath almost everything

- `apps/cadence/lib/cadence/auth/policy.ex:114` · **access to a mission**. Today any active member
  of the organization operates every mission of that organization, with no mission-level grant.
  `:operate_mission` is the gate for nearly every row below. Cedar would need: per-mission roles
  for the principal (e.g. `viewer | operator | flight_director | admin` on `Mission::"…"`), and
  the mission as a resource in its organization. **This is the first policy to write**: once
  mission roles exist, most of the rows below become "role X on this mission" rather than "any
  operator".
- `apps/cadence/lib/cadence/auth/policy.ex:72` · **create a mission** (§11 L4). Today it's
  organization admins and platform admins (`:create_missions` → `:organization_admin`). Cedar
  would need the principal's organization role and, if wanted, a quota or plan attribute on the
  organization.

## Commanding (DECISIONS #62: any operator today, minus self-approval)

Today every command action is `:operate_mission`. The only extra rule is that you can't approve
your own request. The markers all ask for finer decisions on the same few attributes, so they can
share one policy set. Cedar would need:
- **resource** `CommandRequest`/`CommandGroup`: command significance, `hazardous`, `critical`,
  subsystem, target set (spacecraft ids, fleet reach = how many), requester;
- **principal**: mission role, and possibly subsystem or spacecraft assignments;
- **context**: is the principal the requester (self-approval), is a second GO required.

| file:line | action | today |
|---|---|---|
| `management/commanding/review_access.ex:62` | the shared gate: request, approve, no-go, send back, stage, queue | operator |
| `management/commanding/request_authoring.ex:8` | author and request a command | operator |
| `management/commanding/request_review.ex:10` | approve or reject a single request | operator, not the requester |
| `management/commanding/stage_access.ex:10` | stage, edit, share command stages | operator |
| `control/commanding/group_submission.ex:23` | request a command group | operator |
| `control/commanding/group_decision.ex:40` | GO / NO-GO / send back a group | operator, not the requester |
| `control/commanding/group_abort.ex:159` | abort or cancel a group (#42) | operator |
| `control/commanding/group_notes.ex:15` | add a note to a group | operator |
| `control/commanding/queue_submission.ex:55` | queue or reorder released commands | operator |
| `control/commanding/command_drafts.ex:50` | keep a Compose draft | whoever may request, own draft only |
| `control/command_brief.ex:24` | read a request's brief | anyone who may review (operator) |
| `control/command_encoding_preview.ex:20` | read encoded command bytes | anyone who may review (operator) |

The two reads (brief, encoding) may deserve their own `view` action, separate from `review`, if
command bytes are sensitive.

## Contacts and passes

| file:line | action | today | Cedar would need |
|---|---|---|---|
| `cadence_web/…/console/pass_controller.ex:128` | release (cancel) a booked pass | organization admins (`:manage_missions`), or the booker for an off-plan booking | principal's org role; reservation's booker and provider account; perhaps provider-account or spacecraft assignment |
| `contacts/single_bookings.ex:33` | cancel an off-plan booking | booker or mission manager | same as above (the booker is a reservation attribute) |
| `cadence_web/…/console/pass_controller.ex:280` | recover a pass's uplink (DECISIONS #58) | operator | principal's ground-network or spacecraft assignment; the pass's provider account and spacecraft |
| `cadence_web/…/console/contact_requirement_controller.ex:11` | read requirements (open to members); write them | reads: mission member; writes: operator | split `view` from `edit` on `ContactRequirement`; mission role |
| `contacts/contact_settlement_attention.ex:160` | mark lost telemetry as seen (#71) | operator | mission role; the realized contact |
| `cadence_web/…/console/attention_controller.ex:18` | acknowledge / resolve an attention item, per source | operator | per source: e.g. pass resolutions only for the provider account's owners; the item's source and provider account as resource attributes |

Provider-change decisions (L14) are already narrower than the rest: `:approve_provider_changes`
(organization admins). They have no marker, but belong in the same policy set as release.

## Activations and apps

| file:line | action | today | Cedar would need |
|---|---|---|---|
| `control/activation_requests.ex:8` | read activation requests; approve, reject, resume | reads: mission member; decisions: `:approve_activation` = operator; self-approval refused | an `approve_activation` role; the request's change class and requester; context: self |
| `control/activations/resume.ex:32` | resume (Retry apply) | `:approve_activation`, like approve | same as approve (the director chose this) |
| `cadence_web/…/console/app_surface_controller.ex:124` | load an app surface vs operate it | `:read_application_catalog` and `:operate_mission` are the same check, so who can see a surface can operate it | split `view_surface` from `operate_app`; the app's key and scope (mission or spacecraft) as resource |

Also outstanding: org-wide `:approve_activation` equals `:operate_mission` (`policy.ex:174`), and
the ops-console path also wants `:manage_missions`, which the other paths don't (BACKLOG L10). One
rule should come out of the Cedar work.

## Dashboards and data

| file:line | action | today | Cedar would need |
|---|---|---|---|
| `dashboards/capabilities.ex:21` | author dashboards on a mission (`dashboard.author`) | operator (`:author_dashboards`) | mission role; perhaps the dashboard's owner or folder |
| `applications/ops_console/actions/dashboard_workflows.ex:795` | share, snapshot, archive a dashboard | author actions: `:author_dashboards`; the rest: operator | dashboard owner and visibility; share audience (data visibility) |
| `cadence_web/…/console/data_source_writes_controller.ex:208` | manage data sources (L11) | operator | mission role; data source's owner (organization vs shared) |
| `applications/ops_console/actions/data_sources.ex:729` | change a data source or binding | operator for their organization's own; platform admins in admin mode for shared ones | resource owner (organization or platform); context: admin mode |
| `cadence_web/…/console/catalog_controller.ex:96` | import a catalog, or import again (L18) | operator | mission role (catalog maintainer?) |

## Reads with a visibility question

- `reads/action_queue/change_set_items.ex:19` · Now shows the staged change set (with its
  authors) to anyone who passed `operate_mission`, and Setup shows it to anyone who sees Setup.
  Cedar should decide whether Ops viewers see change-set authors. It needs the principal's mission
  role and the change set's authors.

## Not a policy decision (tenancy hygiene)

- `applications/ops_console/actions/historical_workflow_request.ex:150` · historical run ids are
  client-supplied; a tenant suffix prevents cross-tenant collisions. The real fix is server-minted
  ids or a unique index per organization and mission. It's marked `todo(authz)` because it's a
  tenancy boundary, but it's a data-model fix, not a Cedar rule.

## What Cedar needs overall (entity sketch)

- **Principals:** `User` (organization memberships with role; mission roles, which are new;
  optional subsystem, spacecraft or ground-network assignments), `ServiceIdentity` (mission
  binding, automation grants: already modelled in `AutomationGrants`).
- **Resources** (each `in` its `Mission` `in` its `Organization`): `CommandRequest` and
  `CommandGroup` (significance, hazardous, critical, subsystem, targets, requester),
  `Reservation` (booker, provider account, spacecraft, off-plan), `ProviderChange`,
  `ActivationRequest` (change class, requester), `Dashboard` (owner, visibility), `DataSource`
  (owner: organization or platform), `ContactRequirement`, `AttentionItem` (source),
  `App`/`Surface` (key, scope).
- **Context:** `self` (is the principal the requester or booker), admin mode, second-GO required.
- **Action vocabulary** already used on the wire (`permissions` arrays): `apps.install`,
  `activations.approve`, `catalog.import`, `grants.manage`, `config.*`, `settings.edit`,
  `dashboard.author`. Cedar actions should keep these names so the console doesn't change.
