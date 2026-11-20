# Change sets and configuration revisions

Status: **implemented** (P1). This is a thin pass-through of `Cadence.Control.Configuration`. The
semantics and shapes live in [domain.md](domain.md); the HTTP mapping is fe-setup's
setup-shapes.md §K, adopted as is. Conventions: [README.md](README.md).

Base: `/api/console/v1/missions/:mission_id/config`. Write calls need `x-csrf-token`.

| Method + path | Facade | Body | `data` |
| --- | --- | --- | --- |
| `GET /` | `current/2` + `permissions/2` | | `{head, change_set \| null, permissions}` |
| `POST /stage` | `stage/4` | `{summary, source?, ops: [op]}` | stage result (`201`) |
| `POST /preview` | `preview(…, {:ops, ops})` | `{ops}` | preview |
| `GET /change-sets/:id` | `change_set/3` | | change_set |
| `POST /change-sets/:id/preview` | `preview/3` | | preview |
| `POST /change-sets/:id/discard` | `discard/4` | `{expected_version}` | discard result |
| `POST /change-sets/:id/submit` | `submit/4` | `{reason, expected_version, acknowledged_holds?}` | `{state: applied \| in_review, …}` |
| `POST /change-sets/:id/review` | `review/5` | `{decision: approve \| send_back, comment, expected_version}`. `comment` is required to send back and optional to approve (#521, ux K9): blank or absent is recorded as `null`, never `""`; over 2,000 bytes is `422 invalid_params {comment}` either way | `{state: applied \| open, …}` |
| `POST /changes/:change_id/withdraw` | `withdraw/3` | | `{change_set_id, version, state}` |
| `POST /ops/:op_id/rebase` | `rebase/4` | `{choice: keep_mine \| take_live}` | `{change_set_id, version, state}` |

`has_active_configuration` (11-17, ux U93; additive, readers first): a boolean, never null, on
every preview (`POST /preview`, `POST /change-sets/:id/preview`) and on a submit or review result
whose `state` is `applied`. It is true when the mission has an active activation, and says
nothing about runtime health (a mission whose runtime isn't admitted, U91, reads true). With
`false`, applying saves the changes and starts nothing: a mission's first generation comes from
each spacecraft's configuration. Don't infer it from `runtime: not_applicable`, which also covers
changes the runtime doesn't use. On a result it is read right after the apply commits.

`outcome` (#522, K3; additive, readers first, optional): what applying the set would leave behind, on
the explicit previews only (`POST /preview`, `POST /change-sets/:id/preview`). It's never on a submit
or review result: the preview those run as their gate doesn't compute it (api-ops).
`{spacecraft: {now, after}, routes: {now, after, added, removed}, readiness: {now, after} | null} | null`.
- `spacecraft`: active (not archived) spacecraft. K3's Spacecraft tile is `after` (ux U102, #579).
- `routes`: usable routes (active and enabled routing rows, one per spacecraft) of active spacecraft,
  counted by id, so a set that swaps routes has both `added` and `removed`. K3's Routes tile is the
  signed difference ("+300", "−50"), or both when both are nonzero (ca-ux).
- `readiness`: Readiness' verdict counts, `{blocker, caution, stale, not_set_up}`, before and after.
  It's `null` when the set touches none of spacecraft, profiles, overrides, routes, transports or
  stations (domain). One evaluation at 500 spacecraft takes about 85 ms.
- Read in the preview's own rolled-back transaction, before and after the staged ops. `outcome` is
  `null` when the pipeline didn't fully check the set (a halt, a validation error or a conflict) or
  when a read failed. A failed read never changes `verdict` or `checks`.
| `GET /revisions?limit=&before=` | `list_revisions/3` | | `{revisions: [revision_summary]}` (newest first; `limit` 1–100) |
| `GET /revisions/:n` | `get_revision/3` | | revision_summary + `entries` |
| `GET /revisions?entity_kind=&entity_id=&limit=` | `entity_revisions/5` | | `{revisions: [revision_summary + entries]}`: only the revisions touching that entity, newest first, each with just that entity's entries, labelled as `GET /revisions/:n`'s (Profile History; `422 details.entity_kind` for an unknown kind) |
| `GET /compare?from=&to=` | `compare/4` | | `{from, to, entries}` |

`op` = `{kind: "ground_station" | "transport" | "spacecraft" | "spacecraft_profile", action:
"create" | "update" | "delete", entity_id?, document?, changes?: [{path, value}], options?}`. Unknown
top-level keys are ignored; documents, values and options pass through as JSON.

Wire encoding: the facade shapes with string keys. Atoms become lowercase strings, times are
ISO-8601, revision numbers are integers (render them as `rN`), and actors are `{kind, id, name}`.

## Who is named (#471)

Every actor in these reads (`opened_by`, `submitted_by`, change `author`, review `actor`,
`applied_by`, approvals, `changed_by`) is `{kind, id, name}`. The `name` follows #146's rule:
- a person is named only while they hold an active membership in the mission's organization,
  checked at read time, and never by email;
- a service is named only when it belongs to the organization;
- Cadence keeps its system name.

An actor outside the organization reads `{kind, id: null, name: null}`: a person who isn't an
active member (a platform admin acting as support, someone who has left) or another
organization's service. `kind` stays, but the id isn't sent either. An active member with no
display name, or the organization's own unnamed service, keeps its `id` with `name: null`, so the
console still knows its own changes.

Records written before #471 stored `display_name || email`. That stored name is never sent: an
old record by someone who has left reads `id: null, name: null`, and one by an active member
with no display name reads their `id` with `name: null`.

## Errors

`code` is the facade's tag, so switch on it.

| Status | Codes |
| --- | --- |
| 409 | `holds_blocking` (details = the preview; at submit, and at approve when a blocking item appeared after the submit (#262)), `catalog_command_in_flight` (details = `{command_request_ids}`), `frozen_in_review`, `change_set_changed`, `path_already_staged` (details = `{change_id, author, kind, entity_id, path, value}`), `reviewer_is_author` (#280: also when a service identity you're accountable for authored a change), `activation_policy_changed`, `entity_gone`, `in_use` (details = `{entity, uses}`: an archive of a transport or station still in use, at stage, submit or review; [setup.md](setup.md)), `conversion_in_progress` (details = `{change_set_id, batch \| null}`: a legacy route conversion batch is staged, so nothing else can be staged until it's applied or discarded; TEMPORARY, [setup.md](setup.md)), `conversion_already_staged`, `open_change_set_not_empty` (the conversion's own) |
| 403 | `change_set_approver_authors_unknown` (#280; details = `{service: {id, name} \| null}`): a service identity with nobody recorded as accountable authored a change, so nobody can review the set until an org admin records who is. No console route lets a service stage today; the domain allows it, so the check holds anyway |
| 422 | `invalid_op` (details = `{index, errors: [{path, message}]}`), `reason_required`, `comment_required` (send back only, #521), `nothing_staged`, `not_in_review`, `checks_failed` and `holds_not_acknowledged` (details = the preview), `invalid_range`, `invalid_params` (malformed body; details keyed by field), `nothing_to_convert` (the conversion's) |
| 403 | `forbidden` |
| 404 | `change_set_not_found`, `revision_not_found`, `change_not_found`, `op_not_found`, `mission_not_found` |
| 503 | `apply_interrupted` (submit/approve: nothing changed; safe to retry), `preview_failed` (submit/approve: Cadence couldn't run the checks, a database or connection error; nothing changed, the set keeps its state, safe to retry; details null, the cause is only in the server log; #262: was a 500 at approve and the generic `422 unprocessable` at submit) |

## Live (on `mission:<id>`)

- `invalidate` with resource **`configuration`** after every mutation. Refetch `GET /config` (and
  revisions if they're open). Applies that touch spacecraft or profiles also emit `spacecraft`.
- **`change_set_progress`** `{change_set_id, key, label, state, at}`: apply steps (`validate`,
  `write_config`, `notify_runtime`, `verify`; `state` = `running | done | failed`) for the mission's
  current open set. The channel follows whichever set is current. In P1 the apply runs inside the
  submit/review HTTP call, so the steps arrive while that request is in flight.
- **`config_runtime`** `{revision, activation_id, generation, runtime, degraded_partitions}` after an
  apply (`runtime` is `not_applicable` in P1).
- Once the apply has committed, submit and approve never fail the response (qa #19). If notifying
  or converging the runtime crashes afterwards (a DB pool timeout under load, say), the response
  is still `200 {state: "applied", revision, …}` with `runtime: "degraded"`, and the mission
  reconciler keeps retrying. If the connection drops during the apply itself (or during a submit
  or review), the server checks whether THIS request landed, never just the set's state (#261):
  its own review row or revision (by the id it chose before its transaction), or for a submit to
  review everything that submit records (submitter, version, reason, policy). If it did, the
  normal result (an apply with `runtime: "degraded"`). If not, including when another person's
  decision is what landed, `503 apply_interrupted` ("did not take effect"): refetch the set
  before retrying. Any other 5xx on
  submit means "unclear": refetch the change set and head before telling the operator it failed.

## Permissions

**Per set, for the viewer** (ux U79): every change set (`GET /config`'s `change_set` and `GET
/change-sets/:id`) carries `viewer: {can_review: bool, review_blocked_reason: "reviewer_is_author" |
null}`, the same test the review applies, computed up front: false when the set needs approval and
the viewer submitted it or authored one of its changes. Gate Approve and Send back on it. A set
holding a legacy route conversion batch also carries `legacy_conversion: {batch, batches_total}`
(else `null`; TEMPORARY).

`GET /config` returns the mission's `permissions` (`config.stage`, `config.apply`, `config.review`,
`config.rollback`, `config.discard_any`). Gate staged-bar actions on them; the server enforces
them anyway.

**A delete you already staged adds nothing.** Staging a `delete` of an entity you have already
staged for deletion in the open set doesn't add a second change. If every op in the stage is such a
delete, the response is the existing change (`change_id`, `version` and `staged_count`
unchanged). Another author's delete of the same entity is still `409 path_already_staged`.

## Batch spacecraft creation

There are no dedicated batch endpoints. Stage N `spacecraft` create ops in one `POST /stage`. Use
`POST /preview {ops}` as the server-side validation step first: it runs the ops in a sandbox in
order, so a SCID repeated **within the batch** fails validation for the later op (`no_go`, with a
`validation` item on `scid`), as does a SCID already used in the mission.

## Rollback (DECISIONS #49; design: domain/change-sets.md §8)

- `GET /config/rollback?to=N` previews rolling back to revision `N`, checked like any change.
  Nothing is written. It returns `{target, head, reverts: [n], summary: "Roll back to r4 (reverts
  r5, r6)", ops: [{kind, entity_id, action}], outside: [{kind, entity_id}], preview}`.
  - `preview` is the usual checks (`verdict`, `checks`, `effects`, `diffs`), or `null` when
    nothing differs.
  - `outside` lists entities changed outside change sets since `N`. They come back as a HOLD
    (`rollback_overwrites_outside_change`) that must be acknowledged on submit.
- `POST /config/rollback` `{to: N}` stages the rollback as one change in a new change set and
  returns the stage result (`change_set_id`, `version`, …). It then goes through
  `submit`/`review` like any set (holds, approval policy, apply). The revision it applies has
  `kind: "rollback"` and `rolls_back_to: N`.
- Each op is the kind's own inverse against the current state:
  - created after `N` → delete (stations, transports, profiles and spacecraft archive; a
    spacecraft that has had reservations or command requests raises the
    `spacecraft_has_traffic` HOLD);
  - deleted → re-created;
  - changed → updated back.

  Order is dependency-aware: creates and updates run parents first (station, transport,
  profile, spacecraft, override), deletes run children first. Derived kinds (`spacecraft_routes`)
  aren't reverted directly: reverting the profile re-derives them. A pin version that only moved
  because of a profile rollout follows the reverted profile's rollout. A framing rollback produces a runtime generation
  with the same HOLDs as any framing change. Catalog revisions are never deleted: pins move back.
- Refusals:
  - `422 invalid_rollback_target`: `N` must be from r1 up to the revision before the head;
    there's no ledger before r1.
  - `409 rollback_crosses_legacy` with `details.newest_legacy_revision`: the range holds a
    legacy activation. You can roll back to it, not past it.
  - `409 change_set_open`: finish or discard the open set first. Checked under the change-set
    lock.
  - While a rollback is staged, other staging answers `409 rollback_in_progress`: a rollback is
    its set's only change.
  - `422 nothing_to_roll_back`.
  - `403 forbidden`: needs `config.rollback`.

**Catalog generations (#65, domain `a01cf95f`).** A change to a profile's or override's
`catalog_revision_id` previews a `compatibility` check whose items carry a `reason` and a
`message` sentence:

- `catalog_change` `{spacecraft_ids, from, to}`: which spacecraft move to which revision (HOLD).
- `catalog_cancels_commands` `{requests: [{command_request_id, command_group_id, command_name,
  lifecycle_state}]}`: queued requests the change cancels (HOLD).
- `catalog_command_in_flight` `{requests}` and `catalog_configuration_pending`
  `{spacecraft_ids}`: **blocking**. The check then has `blocking: true`, and acknowledging holds
  doesn't let it apply.

Submitting while a blocking item stands answers `409 holds_blocking` with the preview as
`details` (show the blocking items: "can't apply yet"). Approving does too, when a blocking item
appeared after the submit (approve re-runs the checks); the set stays `in_review`, nothing is
recorded, and it can be approved once the item clears (#262; ux U79, amended in #374, words it). If a command starts during the apply
itself, nothing is applied and the answer is `409 catalog_command_in_flight` with `details:
{command_request_ids}`; submit again when it finishes. An unknown revision is a validation error
("That catalog revision doesn't exist").

**Conflict detail.** Each `conflicts` item's `paths` entries are `{path, base, live, staged,
changed_in, changed_by}`:
- `base` is the value when staged (for a rollback, what the reverted revisions left);
- `live` is the value now;
- `staged` is what the change writes;
- `changed_in` is the revision that changed it since, or `"outside"`;
- `changed_by` is `{kind, id, name}` of whoever applied that revision, or `null` for outside
  changes.

For example: "frame size is 1,024 now, not 900 as r8 left it (changed in r9 by Mira K.)".

**Display fields.** Previews (set, ops and rollback) and revisions carry names for the console's
sentences:
- conflict items, preview diffs, revision entries and compare entries have `entity_name`: the entity's name, a
  spacecraft's name for overrides and routes, or `null`;
- each `paths[]` / `fields[]` entry has the kind schema's `label` and `unit`, or `null` when the
  path isn't a schema field. Kinds without an edit schema use their editors' labels: profile paths
  the profile schema's (`frame_parameters.frame_size` → "TM frame length", `bytes`), override
  paths the overridden field's (`…/frame_size.value`; `.reason` → "… override reason"), and
  spacecraft paths Name, SCID, NORAD ID, Profile, Profile version. An entry may also carry
  `format: "version"` (show `4` as "v4").

## Transport provider options (comms parity 2)

`GET …/config/kinds/transport/provider-options?provider_id=&service_profile_id=&delivery_profile_id=`
(each optional; needs `config.stage`). The provider-managed transport form's dependent choices
and its derived preview; nothing is written.

```json
{"data": {
  "providers": [{"id": "…", "version": 2, "name": "Simulator"}],
  "services": [{"id": "service-downlink", "version": 3, "name": "Realtime telemetry"}],
  "deliveries": [{"id": "delivery-cadence", "version": 7, "name": "Cadence primary ingress"}],
  "preview": {"configuration": [{"label": "Endpoint", "value": "127.0.0.1:5100"}, …],
              "direction_capability": "inbound", "provider_version": 2,
              "summary": [{"label": "Endpoint", "value": "127.0.0.1:5100"}, …]},
  "errors": []}}
```

- `services` is `[]` until a provider is chosen; `deliveries` is `[]` until a service is chosen
  (only ready downlink deliveries that support the service and that the transport kind can use).
- `preview` is `Management.Transports.derive/3` (the derivation a change set's apply stores),
  rendered as rows of strings in display order; `null` until all three are chosen, or when derive
  refuses.
- `errors`: `[{path, message}]`, `path` one of `mission_provider_id`, `mission_provider_version`,
  `service_profile_ref`, `delivery_profile_ref`, or `null` (a general error). A chosen id that
  isn't on offer is reported on its field.
- Stage `origin: "provider_managed"`, `display_name`, `mission_provider_id`,
  `mission_provider_version` and the exact refs `service_profile_ref` / `delivery_profile_ref`
  (`{id, version}`); `configuration` and `direction_capability` are derived, never staged.
- Errors: `403 forbidden` without `config.stage`; `422 invalid_params` for a non-text query value.
