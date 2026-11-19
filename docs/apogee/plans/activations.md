# L10 app activation approvals: shape proposal (fe-setup → api, cc lead; fe-ops for Now)

fe-setup, 2026-11-13. BACKLOG §11 L10. ux `screens/AppSurfaces.md` "Saving and activation" (DECISIONS #77): a save
that needs activation creates a request a **second person** approves; it shows on Setup › Changes as an approval
and on Now as "awaits your GO" for the approver. Replaces the LiveView `/ops/activations`.

## What exists (read, 2026-11-13)
- `Management.Activations` requests: `approval_pending | approved | rejected`; decisions `approved | rejected`
  (append-only, human only); executions `in_progress | succeeded | failed`. Created by telemetry decom's
  `request_activation` and by spacecraft configuration review (`Activations.request`); change-set applies make
  requests that are born approved.
- **Approve applies at once**: `approve/4` records the decision, then `Control.Activations.execute/2` re-checks the
  content hash, records a new binding-set generation and applies it to the runtime, in the same request.
  `Review.decide` answers `outcome: "applied"` or `"application_needs_review"` (approved, but the apply failed).
- A reason is required for both decisions (1–4096 bytes). Self-approval is refused
  (`activation_self_approval_forbidden`). No expected-version evidence: the server checks the stored policy and,
  at apply, the content hash and spacecraft configuration tokens.
- Requests carry requester, time, binding set id/version/sha256, policy, and app metadata (decom: composition,
  contributors, mission-model comparison report; spacecraft review: configuration revision and token). No diff and
  no base generation are stored.
- No console endpoint; legacy REST under `/api/organizations/:org/missions/:m/activation_requests`.

### Asks beyond the port
1. **Stuck requests.** After an approval-policy change a pending request can be neither approved nor rejected
   (`reject` also runs `ActivationPolicy.validate`). Let **reject** skip the policy check, and add **withdraw** for
   the requester, so nothing stays pending forever.
2. **Say what failed.** When approve answers `application_needs_review`, include the execution's error so the
   console can say "Approved, but it didn't apply: <reason>." and what to do next.
3. **Superseded.** Several pending requests for one binding set can coexist; the older ones can only fail at apply.
   Mark a request `superseded` when a newer one for the same binding set arrives (or say which is newest per row).
4. **todo(authz):** `:approve_activation` is `:operate_mission`, so any mission operator other than the requester
   approves; the ops-console path additionally wants org admin `:manage_missions`, the LiveView and REST paths don't.
   The console endpoint should use `:approve_activation` (as the domain) and the rule should be settled for Cedar.
   Also `Management.Activations.fetch/2` checks only the org: the endpoint must compare `mission_id`.

## Proposed (`/api/console/v1/missions/:mission_id/activations`)
```
GET  /?state=pending|decided&before=   → {requests: [<row>], next|null, permissions: ["activations.approve"]}
<row> = {id, kind: telemetry_decom | spacecraft_configuration, app: {key, name} | null,
         summary,                              (server sentence: "Decom composition for 3 spacecraft")
         binding_set: {id, version},
         requested_by: {kind, id, name}, requested_at,
         state: approval_pending | approved | rejected | withdrawn | superseded,
         decision: {state: approved | rejected | withdrawn, by {kind, id, name}, at, reason} | null,
         execution: {state: in_progress | succeeded | failed, error|null} | null,
         can_decide: bool}                     (you may approve or reject it: approver, and not its requester)
GET  /:id → <row> + {details: [{label, value}],                     (server-made facts: what it activates)
                     comparison: {report_id, label} | null}         (decom's mission-model comparison, if any)
POST /:id/approve  {reason} → 200 {request: <row>, outcome: applied | needs_review}
POST /:id/reject   {reason} → 200 {request: <row>}
POST /:id/withdraw {reason} → 200 {request: <row>}                 (requester only; ask 1)
  409 not_pending {state}            · 403 self_approval_forbidden · 403 forbidden
  409 policy_changed                 (approve only, after ask 1)
  422 invalid_params {reason: "Say why."}
```
- `can_decide` lets Now ask "awaits your GO" without re-deriving the rule; `GET /?state=pending` filtered to
  `can_decide` is Now's list (fe-ops).
- **Invalidate:** a separate `activations` topic on the mission channel (fe-ops: so Now doesn't refetch on every
  configuration change), sent when a request is created or decided.

## Console (fe-setup, against fixtures)
- **Setup › Changes** gains a **Waiting for activation** panel above the change set (only when something is
  pending): app, summary, requested by/when, and `Review` (the row's link). An `Activations` tab or section lists
  decided ones (who, decision, reason, applied or not).
- **Review page** `setup.activation` (`M/setup/changes/activations/:requestId`), reading layout: what it activates
  (summary, details, comparison link), requested by/when, a required **Reason**, `Approve and apply` (primary) and
  `Reject` (secondary). The requester sees "You requested this. Someone else approves it." with `Withdraw…`.
  After approve: nominal "Approved and applied." or caution "Approved, but it didn't apply: <error>." A decided
  request reads its decision line instead of the form.
- The app host's caution line ("Waiting for activation approval · requested by Mira K. at 02:10Z", L9) links to
  the review page.

## Addition (lead, director-approved 2026-11-13): resume a stalled or failed apply
Domain adds a manual resume for an activation whose apply failed or stalled midway: the activation committed,
decom state rolled back, execution stuck.
- **Execution on every row** (`<row>.execution`): `{state: in_progress | succeeded | failed, since, error_code|null,
  error|null}`. `error_code` includes the new `activation_execution_interrupted`; `error` is the reason in words.
- **`POST /:id/resume`** (empty body) → `200 {request: <row>, outcome: applied | needs_review}`. Behind the approval
  permission (`activations.approve`, the same gate as approve), audited. `409 nothing_to_resume {state}` when the
  execution isn't failed or stalled.
- **Console:** the review page shows a caution line for a failed or stalled apply ("Approved, but it didn't
  apply: <reason>. Since 02:14Z.") with `Retry apply` for people who may approve. Now (fe-ops) can list these as
  needing attention, from the same rows.
