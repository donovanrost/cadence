# Console API conventions

Owner: **api**. Every contract the console SPA uses is documented in this folder before or with its code.

| Doc | Covers |
| --- | --- |
| [session.md](session.md) | SPA hosting, auth, bootstrap, organization switch |
| [realtime.md](realtime.md) | `/socket/console`, `mission:<id>` channel |
| [ops.md](ops.md) | Now / Investigate reads (owner: api-ops) |
| [setup.md](setup.md) | Readiness, spacecraft, profiles, catalog, people |
| [changes.md](changes.md) | Mission change sets and configuration revisions |
| [domain.md](domain.md) | domain's facade contracts (owner: domain) |
| [commanding.md](commanding.md) | Command catalog, requests, preflight (api-ops) |
| [alarms-console.md](alarms-console.md) | Alarm episodes: list, show, ack/assign/hand-off/notes (api-ops) |
| [inventory.md](inventory.md) | What existed before the console API, and the gaps |

## Base and auth

- Base path: `/api/console/v1`. Same-origin with the SPA, served by Phoenix.
- Auth: the browser session cookie (`_cadence_web_key`), set by `/sign-in`. No bearer tokens.
- CSRF: every non-GET request sends `x-csrf-token: <token>`. Read the token from
  `<meta name="csrf-token">` in the SPA document, or from `csrf_token` in `GET /session`.
- Send `accept: application/json`. Responses are always JSON, including errors and unknown routes.

## Mission addressing

Mission-scoped endpoints live under `/api/console/v1/missions/:mission_id/...`. **There is no
organization in the URL.** The server finds the mission's organization and checks that the user
can operate it there (an active member of that organization, or a platform admin in admin mode).
So a user in several organizations can open missions from different organizations in different
tabs without switching. A mission the user cannot operate gets the same answer as a missing one:
`404 mission_not_found`.

Organization-scoped endpoints (members, invitations, service identities) will live under
`/api/console/v1/organizations/:organization_id/...` and check membership plus the matching
capability.

## Envelope

Success: `{"data": ...}`. Lists may add `"meta"`, for example `{"next_cursor": ...}`.

Error:

```json
{"error": {"code": "mission_not_found", "message": "Mission not found.", "details": {}}}
```

`code` is stable and snake_case; switch on it. `message` is for people and may change. `details`
is optional; for `invalid_params` it maps field to problem.

| Status | Codes |
| --- | --- |
| 401 | `unauthenticated`: no or expired session. Send the user to `/sign-in?return_to` (the server stores the return path for full-page GETs under `/console`) |
| 403 | `invalid_csrf`, `forbidden`, `scope_mismatch` |
| 404 | `not_found`, `mission_not_found`, `organization_not_found`, and `<thing>_not_found` |
| 422 | `invalid_params` and domain rejections (`code` names the reason) |

## Breaking changes

Each breaking change to an API in this folder (a field required, removed or renamed, or a new
error for a request that used to succeed) is listed here with the date it landed, newest first.
Readers are told before it lands (the first entry was written after it landed, #249); the
linked doc has the detail.

| Landed | API | Change | Doc |
| --- | --- | --- | --- |
| (lands with #499) | Console governance settings save (`PUT …/missions/:mission_id/settings`, `PUT …/organizations/:organization_id/settings`), the contact-planning grant reads, and new `POST /api/console/v1/missions/:mission_id/contact-planning/grants/:grant_id/resume` | **#499.** A save that tightens a mission's approval setting (to 'independent', directly or through an organization save) suspends that mission's automation grants that went active on one approval. Without `acknowledged_suspensions` matching the current list it answers `409 approval_tightening_suspends_grants {grants: [{id, mission: {id, name}, service: {id, name}, allowed_actions, valid_until}], digest}` and writes nothing; such a save used to succeed. Grants gain the lifecycle value `suspended` (it authorizes nothing) and `suspension: {at, by: {kind, id, name}, settings_revision} \| null`; `by` names a person only while an active member (id and name null for anyone outside the organization, kind kept; #146). Resume takes `{sha256, operation_id}` as approve does, with replays (`replayed: true`); the setting in force decides who may: under 'independent' a separated approver (#280's refusal codes), under 'direct' any organization admin who holds what it confers. It refuses `409 automation_grant_legacy` (a pre-#283 grant; those are never suspended) and `409 automation_grant_not_suspended {state}` (not suspended, or expired). | [scheduling.md](scheduling.md), [setup.md](setup.md) |
| (lands with #466) | REST `/api/organizations/:organization_id/missions/:mission_id`: command requests (`requested_by`), command approvals (`decided_by`), queue entries (`enqueued_by`), release attempts (`released_by`), command stages (`owner`); activation requests (`requester_actor`), decisions (`actor`) and executions (`executor_actor`) | **#466 (#462).** These actor objects no longer carry `email` or `user_email`. Nothing else in the object changes. New records never store an email; a record written earlier keeps it in the database (#116), and the REST encoder drops it on the way out. #465 later replaces these objects with `kind`, `id` and `name`. | [commanding.md](commanding.md), [activations.md](activations.md) |
| (lands with #283) | Console `/api/console/v1/missions/:mission_id/contact-planning/grants` | **#283.** Under 'independent', `POST /grants` answers a grant in state `proposed` that authorizes nothing until another org admin approves it (`POST /grants/:id/approve`, new); under 'direct' it's `active` at once, as before. New: `POST /grants/:id/reject` and `/narrow`, with `operation_id` replays. Revoke no longer needs `sha256` or a reason, and no longer answers `409 grant_changed` or `422` for them. A grant gains `state` values proposed, rejected and withdrawn, plus proposal, rejection and withdrawal fields, `validity_seconds`, `replaces_grant_id` and the viewer's flags. `valid_from` and `valid_until` are null until approval. People are named only as active members (#146's rule). Using a grant that isn't active answers `403 automation_grant_not_active {state}`. | [scheduling.md](scheduling.md#automation-grants-11-l3-283) |
| (lands with #263) | REST `POST /api/organizations/:organization_id/missions/:mission_id/activation_requests/:id/approve` | **#263.** Once the approval is recorded, the answer is always `200 {data: {request, decision, execution, outcome}}`. It used to be `200 {data: {request, decision, execution}}` only when the apply succeeded, and an error (through the fallback controller) when it didn't, even though the approval was recorded. New: `outcome`, a closed set: `applied` (the apply succeeded) or `needs_review` (it failed, didn't finish, or couldn't run; the cause is logged, never sent). `execution` is null when the apply couldn't record one. Read `outcome`, not the status, to tell an apply that didn't finish. Refusals before the approval is recorded are unchanged. No client reaches this answer today: only service identities hold API tokens, and they can't approve (`human_activation_approver_required`). REST `POST …/command_requests/:id/approve`: no shape change; the approved-command check now runs before the decision commits, so a failure refuses with nothing recorded instead of erroring after it. | [inventory.md](inventory.md) |
| (lands with #366) | REST `GET`, `POST …/catalog_artifacts`, `GET …/catalog_artifacts/:id`, `GET`, `POST …/catalog_import_runs`, `GET …/catalog_import_runs/:id`; console catalog C1/K1 and the model approval read | **#366.** REST `uploaded_by` and `requested_by` are now `{kind: user \| service \| system, name: string \| null} \| null`, the console's #146 shape and rule, instead of the stored actor document. The stored document carried `user_id`, `user_email`, `user_display_name`, `service_identity_id` and `service_identity_display_name`. A person is named only while an active member of the mission's organization, and a service only when it belongs to it. No email or id is sent. The console's `uploaded_by` and `revisions[].actor` gain `kind` and follow the same rule. The model approval read's `imported_by` is `{id: null, name: null}` for anyone not named (it fell back to email before). | [setup.md](setup.md) |
| (lands with #280) | Every approve path: activations (console + REST), contact plans, mission-model revisions, change-set review, REST command requests | **#280, service identities count as their accountable people.** Where a kind refuses approving your own work, it now also refuses an approver accountable for the service identity that did it (its issuer, rotators, and anyone recorded), with the existing self-approval code. `details.via_service` is on the console's activation, contact-plan and mission-model self-approval 403s only. Change-set review stays `409 reviewer_is_author` with no details, and REST command requests and REST activations carry no details. New `403 <kind>_approver_authors_unknown` (`activation_`, `contact_plan_`, `mission_model_`, `change_set_`, `command_request_`) when the service has nobody on record. Under 'independent', an automation grant's service can no longer approve a plan its own service made. Additive: `details.via_service` on those three console 403s (always sent; null when it was you), `cannot_decide_details` and the `authors_unknown` reason on the model approval read, and `POST /service-identities/:id/accountable`. | [setup.md](setup.md), [activations.md](activations.md), [scheduling.md](scheduling.md), [changes.md](changes.md), [commanding.md](commanding.md#rest-command-requests-command-group-members-owner-api-ops-four-eyes-p0-2026-11-18) |
| 2026-11-19 | REST `POST /api/organizations/:organization_id/missions/:mission_id/spacecraft` | **#328.** Removed: the pre-console spacecraft create (`SpacecraftController.create`) answers `404`. Nothing outside tests called it (api confirmed). Spacecraft are created through the console's change sets (the `spacecraft` kind). `GET …/spacecraft` and `GET …/spacecraft/:spacecraft_id` stay. | [inventory.md](inventory.md) |
| 2026-11-19 | Console `POST /api/console/v1/missions/:mission_id/contact-plans/:plan_id/execute` | **#268.** Once the plan's day has ended, execute answers `409 contact_plan_day_ended {day}` and starts nothing (it used to start a run whose passes then failed). Additive: Now's `plan_coverage` item for an approved, unstarted plan carries `booking` too, and `booking` gains `bookable` (passes never placed). | [scheduling.md](scheduling.md#post-contact-plansplan_idexecute) |
| 2026-11-19 | Console `POST /api/console/v1/missions/:mission_id/contact-plans/:plan_id/approve` | **#273 step 1.** `contact_plan_opportunity_expired` (the booking window has closed for a selected pass, so the approval is refused and nothing is recorded) answers `409` with its own message; it was a generic `422`. | [scheduling.md](scheduling.md#post-contact-plansplan_idapprove-257) |
| 2026-11-19 | REST `/api/organizations/:organization_id/service_identities` | **#281. Removed** (`GET` and `POST`; both now `404`). A REST bearer is always a service identity, and services never list, issue, rotate or revoke service identities, so these could succeed for no one. People issue service identities in the console (`/api/console/v1/organizations/:organization_id/service-identities`); there a service identity is refused (`403 authenticated_user_required` in the domain; the console's organization scope already refuses services), and whoever issues or rotates must hold every capability the identity has (`403 capability_beyond_issuer {capabilities}`, ux U104). | [setup.md](setup.md#service-identity-writes-o6) |
| 2026-11-19 | Console `/api/console/v1/missions/:mission_id/contact-plans` | **#257.** New `POST /:plan_id/approve` (the only console path that approves; `403 contact_plan_self_approval_forbidden {because}` under 'independent'). `POST /:plan_id/submit` only submits: under 'direct' an admin's submit no longer approves and books (`202` → `200 pending_approval`), so Re-plan's Apply under 'direct' is two calls too; a plan already pending answers `409 plan_already_submitted` (was a silent `200`); `decision_note` is refused on submit (`422`); a replayed `operation_id` returns the original answer with `replayed: true` (was `200 outcome: "replayed"`), and a different request on a known id answers `409 duplicate_operation`. Additive: submit's `200` carries `version`; the plan detail and list rows carry `approval_setting`. | [scheduling.md](scheduling.md#post-contact-plansplan_idapprove-257) |
| 2026-11-18 | REST `/api/organizations/:organization_id/missions/:mission_id`: `command_requests`, `command_queue_entries` | Approve, reject and enqueue of a command-group member answer `409 command_request_in_group`; a queue entry's release answers `409 command_group_not_armed` while its group has no GO; a create whose `metadata` names a group answers `422 command_request_group_reserved` (four-eyes P0, #249). | [commanding.md](commanding.md#rest-command-requests-command-group-members-owner-api-ops-four-eyes-p0-2026-11-18) |

## Wire conventions

- IDs are opaque strings. Field names are snake_case.
- Timestamps are ISO-8601 UTC strings (`2026-11-08T02:41:17Z`). Durations are integer seconds with a
  `_s` suffix (`stale_after_s`).
- The server decides staleness (ux ruling U9). Freshness fields come with the server's
  `stale_after_s` and a computed `stale` boolean.
- Enumerations are lowercase strings. Each doc lists the full set.
- Absent optional values are `null`, never omitted.
- No invented values. When the backend doesn't know something, the field is `null`, or the
  endpoint returns an explicit `not_set_up` / `not_installed` state the UI can show.
