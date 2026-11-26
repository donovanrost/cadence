# L2 template pause / activate / close + L3 automation grants: shape proposal (fe-setup → api, cc lead)

fe-setup, 2026-11-13. BACKLOG §11 L2, L3. Spec: ux `screens/ContactPlanning.md` (template page; Policy tab).
Replaces the LiveView `/ops/requirement-templates` lifecycle buttons and `/ops/planning/policy` grant forms.
Shapes follow the requirement close / cancel endpoints already in the console API (`…/requirements/:id/close`).

## What exists (read, 2026-11-13)
- **Templates:** `ContactRequirementTemplates.activate | pause | close(scope, mission_id, id, expected_version,
  reason)`. Moves: active ↔ paused, active | paused → closed; anything else is
  `:invalid_template_lifecycle_transition`. A blank reason is `:contact_requirement_template_transition_reason_required`.
  Only active templates materialize requirements (`materialize_active`), so pause and close stop new ones.
  The console reads template rows and the detail with `state` (active | paused | closed) and `version`; there is no
  verb endpoint.
- **Grants:** `AutomationGrants.issue(scope, mission_id, attrs, expected_policy: evidence)` and
  `revoke(scope, mission_id, grant_id, expected_sha256, reason)`, behind `:manage_automation_grants` (org admin).
  The LiveView's form takes `service_identity_id, maximum_horizon_duration, maximum_contacts,
  maximum_execution_concurrency, valid_days, approval_reason`; the server fills `allowed_actions` and the cost
  limit from the **active** policy version, and the grant may not exceed it (`automation_grant_*_exceeds_policy`,
  `…_currency_differs_from_policy`, `automation_service_identity_disabled | _scope_mismatch`). Rows:
  `{automation_grant_id, service_identity_id, fleet_planning_policy_version, allowed_actions, maximum_*,
  valid_from, valid_until, lifecycle_state (active | revoked), approved_by/at, approval_reason, content_sha256,
  revoked_by/at, revocation_reason}`. The console's `GET /contact-planning/policy` has no grants and no
  service identities.

## L2 template verbs (`/api/v1/missions/:mission_id/contact-planning/templates/:template_id`)
```
POST /pause     {expected_version, reason}  → 200 {id, state: "paused", version}
POST /activate  {expected_version, reason}  → 200 {id, state: "active", version}
POST /close     {expected_version, reason}  → 200 {id, state: "closed", version}
  409 version_conflict {expected_version: <current>}       (as requirements)
  409 template_transition_not_allowed {state: <current>}   (e.g. activating a closed one)
  422 invalid_params {reason: "Say why."}
  403 forbidden
```
- `version` is the template's version after the move (unchanged if a lifecycle move doesn't bump it; say which).
- Who: whoever `authorize_admin` admits today; the console shows the buttons when `permissions` has `planning.edit`
  (say if pause/close needs a different token).
- **Please add** to the template detail: `state_changed {state, at, actor {id, name}, reason}|null`, the last
  lifecycle move, so the page can say "Paused by Mira K. on 11-12: provider outage".
- Already-materialized requirements stay as they are (the console says so). Correct me if pause or close ends them.

Console: the template page header gets `Pause…` / `Resume…` (active ↔ paused) and `Close…` (secondary, confirm
sheet with a required reason, as requirements' Close… / Cancel…). Copy: Pause "Cadence stops making new
requirements from it until you resume. Ones it already made stay." Close "Ends the template for good; it can't be
reopened. Ones it already made stay." Paused and closed templates read `PAUSED` (caution) / `CLOSED` (off) in the
Templates table.

## L3 automation grants (`/api/v1/missions/:mission_id/contact-planning`)
```
GET  /grants   → {grants: [{id, service_identity {id, name}, policy_version, allowed_actions: ["plan", "repair",
                  "execute", "submit", "approve"], maximum_horizon_seconds, maximum_contacts,
                  maximum_execution_concurrency, maximum_estimated_cost_micros|null, currency|null, valid_from,
                  valid_until, state: "active" | "revoked" | "expired", approved_by {id, name}, approved_at,
                  reason, revoked_by {id, name}|null, revoked_at|null, revocation_reason|null, sha256}],
                 service_identities: [{id, name, state: "active" | "disabled"}],   (this mission's)
                 limits: {maximum_horizon_seconds|null, maximum_contacts|null, maximum_execution_concurrency|null}
                         (the active policy's ceilings, for the form's hints),
                 permissions: ["grants.manage"]}
POST /grants   {service_identity_id, maximum_horizon_seconds, maximum_contacts, maximum_execution_concurrency,
                valid_days, reason, policy_version}
  → 201 {grant: <row>}
  409 policy_changed {active_version}          (policy_version isn't the active one; replaces the evidence map)
  422 invalid_params {field: msg}             (the exceeds_policy / currency / identity errors on their fields:
                                               maximum_horizon_seconds, maximum_contacts,
                                               maximum_execution_concurrency, service_identity_id)
POST /grants/:id/revoke {reason, sha256}
  → 200 {grant: <row>}
  409 grant_changed {}                        (sha256 no longer matches)
  422 invalid_params {reason: "Say why."}
```
- `state: "expired"` is computed (active and `valid_until` passed), so the table doesn't show a dead grant as live.
- `policy_version` and `sha256` stand in for the LiveView's evidence maps: the console sends back what it read,
  and the server rebuilds the exact evidence.
- Cost stays hidden in the console (DECISIONS #63); the server keeps filling it from the policy.

Console: the Policy tab gets a **Grants** panel under Mode (a grant is what lets a service identity act without a
person). Table: Service identity · Can (`plan, repair, submit`) · Limits (`48h · 40 contacts · 2 at once`) ·
Valid until · State. Primary `Grant automation…` (sheet: identity select, three numbers with the policy ceilings as
hints, days valid, required reason); row action `Revoke…` (confirm with a required reason). Without
`grants.manage` the panel reads as text with "Org admins grant automation."
