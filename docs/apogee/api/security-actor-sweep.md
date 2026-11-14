# Security sweep: client-supplied actors and identities (DECISIONS #30, #32)

Owner: **api-ops**. Date: 2026-11-09. Rule: an action's actor (who did it) always comes from the
authenticated scope (a user, or a service identity acting as itself). A request that names an
actor is refused with `422 actor_not_assignable`, not silently ignored. Fields the server builds
are refused the same way.

## Found and fixed

| Where | Problem | Fix |
| --- | --- | --- |
| `api/commanding_params.ex`: stage `owner` (create + update), submission and request `requested_by`, approval and rejection `decided_by`, queue entry `enqueued_by`, release attempt `released_by` | The client document overrode the scope actor. A requester could name another user as approver, which bypassed self-approval and the two-person rule (D7) and misattributed the audit. `owner` gates private-stage access. | `d8de442f` (+ `3bca028d`): `scope_actor/4`; tests in `test/cadence_web/controllers/commanding_actor_assignment_api_test.exs`. Behaviour change (accepted by the director): the service-identity REST API can no longer approve or reject, because approval needs a human actor. |
| `api/contact_params.ex` `contact_action` (scheduled-contact cancel, realized-contact end early) | A client `actor` was accepted, and it defaulted to `%{}` instead of the caller. | `5bba6a9c`: the actor is the scope's actor document; tests in `contact_actor_assignment_api_test.exs`. |
| `activation_params.ex` `request` (domain's follow-up) | Arbitrary client `metadata` went into `Activations.request`, including keys the server builds during admission. Admission re-validates them, so it isn't exploitable today. | This commit: `spacecraft_configuration_version`, `spacecraft_configurations`, `fleet`, `configuration_review` and `mission_model` → `422 reserved_metadata_key`; tests in `activation_metadata_api_test.exs`. |

## Checked, no change needed

| Where | Why it's fine |
| --- | --- |
| `api/catalog_params.ex`, `api/comms_params.ex`, `api/read_params.ex`, `api/runtime_ingress_params.ex`, `console/config_params.ex`, `console/window_params.ex` | No actor, author or identity fields. Change-set authors come from the scope in `Cadence.Control.Configuration`. |
| `api/identity_params.ex` `service_identity` | `service_identity_id` names the new identity, not an actor. Capabilities are limited to `organization_admin` / `mission_admin` (`ParamParser.normalize_capability`), and creating one needs `organization_admin` (`Policy :manage_service_identities`), so an org admin can't grant beyond their own authority. |
| `controllers/application_host_controller.ex` | `params["user_id"]` and the generic scope ids are only **compared** to the scope (`fetch_user_route_context`, `generic_scope_ids_match?`) → `scope_mismatch` on difference. Action actors come from `actor_document(current_scope)` (`application_host_catalog.ex:274,293`). |
| `controllers/contact_workspace_controller.ex` → `Contacts.ScheduleOperations` / `ScheduleCommands` | No actor fields are read from the body; the operation journal records the scope's user. |
| `controllers/activation_controller.ex` | Request and decision actors come from `current_scope` via `ManagementActivations`. |
| Console API (`controllers/console/*`) | Every write takes the actor from `conn.assigns.current_scope`. The alarm `assign` / `hand-off` `user_id` / `to` is the **target** (validated as a member by the domain), not the actor. |
| Domain struct constructors (`CommandRequest.new`, `CommandApproval.new`, `ContactAction.new`, `OperationalEvents.Event.new`, …) take `attrs[:actor]` etc. | Callers are now all server-side or go through the guarded params above. |

## Method

`grep` over `apps/cadence_web/lib` and `apps/cadence/lib` for actor and identity keys
(`actor`, `user_id`, `owner`, `author`, `operator`, `*_by`, `actor_id`, `service_identity_id`) read
from request params or body maps, then a read of each hit's call path back to the controller.
