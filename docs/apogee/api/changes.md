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
| `POST /change-sets/:id/review` | `review/5` | `{decision: approve \| send_back, comment, expected_version}` | `{state: applied \| open, …}` |
| `POST /changes/:change_id/withdraw` | `withdraw/3` | | `{change_set_id, version, state}` |
| `POST /ops/:op_id/rebase` | `rebase/4` | `{choice: keep_mine \| take_live}` | `{change_set_id, version, state}` |
| `GET /revisions?limit=&before=` | `list_revisions/3` | | `{revisions: [revision_summary]}` (newest first; `limit` 1–100) |
| `GET /revisions/:n` | `get_revision/3` | | revision_summary + `entries` |
| `GET /compare?from=&to=` | `compare/4` | | `{from, to, entries}` |

`op` = `{kind: "ground_station" | "transport" | "spacecraft" | "spacecraft_profile", action:
"create" | "update" | "delete", entity_id?, document?, changes?: [{path, value}], options?}`. Unknown
top-level keys are ignored; documents, values and options pass through as JSON.

Wire encoding: the facade shapes with string keys. Atoms become lowercase strings, times are
ISO-8601, revision numbers are integers (render them as `rN`), and actors are `{kind, id, name}`.

## Errors

`code` is the facade's tag, so switch on it.

| Status | Codes |
| --- | --- |
| 409 | `frozen_in_review`, `change_set_changed`, `path_already_staged` (details = `{change_id, author, kind, entity_id, path, value}`), `reviewer_is_author`, `activation_policy_changed`, `entity_gone` |
| 422 | `invalid_op` (details = `{index, errors: [{path, message}]}`), `reason_required`, `comment_required`, `nothing_staged`, `not_in_review`, `checks_failed` and `holds_not_acknowledged` (details = the preview), `invalid_range`, `invalid_params` (malformed body; details keyed by field) |
| 403 | `forbidden` |
| 404 | `change_set_not_found`, `revision_not_found`, `change_not_found`, `op_not_found`, `mission_not_found` |
| 503 | `apply_interrupted` (submit/approve: nothing changed; safe to retry) |

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
  reconciler keeps retrying. If the connection drops during the apply itself, the server checks
  whether it landed: if it did, the normal applied result with `runtime: "degraded"`; if not,
  `503 apply_interrupted` ("did not take effect"), which is safe to retry. Any other 5xx on
  submit means "unclear": refetch the change set and head before telling the operator it failed.

## Permissions

`GET /config` returns the mission's `permissions` (`config.stage`, `config.apply`, `config.review`,
`config.rollback`, `config.discard_any`). Gate staged-bar actions on them; the server enforces
them anyway.

## Batch spacecraft creation

There are no dedicated batch endpoints. Stage N `spacecraft` create ops in one `POST /stage`. Use
`POST /preview {ops}` as the server-side validation step first: it runs the ops in a sandbox in
order, so a SCID repeated **within the batch** fails validation for the later op (`no_go`, with a
`validation` item on `scid`), as does a SCID already used in the mission.
