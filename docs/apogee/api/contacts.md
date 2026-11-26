# Contacts endpoints (passes, stations)

Owner: **api-ops** for passes (ops M7 = scheduling S1, DECISIONS #25/#26). Stations are api's
`GET /missions/:mission_id/ground-stations` ([setup.md](setup.md)). Scheduling actions (S2–S6,
S8) are api's: [scheduling.md](scheduling.md). Conventions: [README.md](README.md).

| Ask | Endpoint | Status |
| --- | --- | --- |
| M7 / S1 | `GET /missions/:mission_id/passes` | **implemented** (booked contacts; opportunities not yet) |
| S7 | `GET/POST /missions/:mission_id/station-availability…` | **implemented** (api-ops on domain's facades, DECISIONS #39/#44) |
| S9 | `GET /missions/:mission_id/pass-review[/rows|/daily]` | **implemented** (K3) |
| S10 | `contacts` and `contact_plans` on the `mission:<id>` `invalidate` event | **implemented** (contact facts + reservation changes; plans and fleet runs) |

## `GET /api/console/v1/missions/:mission_id/passes`

One row per **provider reservation** whose window overlaps `[from, to)`, oldest start first
(`order=desc`: newest first). Every reservation row carries `booked: true`.

Query: `from`, `to` (ISO-8601; default `from` = now, `to` = `from` + 24 h; at most 7 days),
`spacecraft_id`, `station` (matches the row's `station.ref`, `station.id` or `station.code`),
`states` (comma list of reservation states, below, plus a hand-started contact's `defined` and
`stopped`), `order` (`asc` | `desc`), `include=hand_started` (U78, below). `spacecraft_id` and
`states` apply in SQL before the 500-row cut; `station` applies after it. Bad values:
`422 invalid_params` with `details` keyed by parameter.

**Hand-started contacts (U78, opt-in `include=hand_started`; History sends it).** A realized
contact with no scheduled contact (started by hand, #84) whose time overlaps the window joins as a
`booked: false` row. Without `include` no such row ever appears. It's a contact, not a pass:
- `id` = `realized_contact_id` (also on the row), `kind: "contact"`, `booked: false`;
- `state` is the contact's own word: `defined | active | stopped | completed` (`defined` and
  `stopped` appear only on these rows);
- `starts_at`: when it went live (when it was realized if it never did); `ends_at`: when it was
  stopped, completed or closed as never started, `null` while open;
- `spacecraft` `{id, name, scid}` from its source endpoints, `null` when they name none or several;
  `station` from its `ground_station_ref`, the same shape as a booking's;
- `started_by: {kind: user | service | system, id, name} | null` (name only for a user);
- `not_started: boolean` (ux U78): `true` when it never went live: still `defined`, or closed by
  Cadence's never-started sweep (`stopped`; `ends_at` is the close). Only on `booked: false` rows;
- `reservation_id`, `scheduled_contact_id`, `plan`, `requirement`, `provider_revision`,
  `pass_phase`, `delivery_state`, `antenna`, `source`, `cost`, `max_elevation_deg`,
  `uplink_capable`, `booking_evidence`, `attested_by`, `uplink_confirmed`, `off_plan`, `ended_by`,
  `attention`, `uplink_readiness`, `contact_action`, `contact_ended`: `null`; `releasable: false`.

Both halves are read in the requested order, merged by `starts_at` (then `id`) and cut to 500, so
the rows kept are always the first 500 of the whole list; `truncated: true` when either half or the
merge passed 500.

```json
{"data": {
  "from": "2026-11-08T02:00:00.000Z", "to": "2026-11-09T02:00:00.000Z", "truncated": false,
  "passes": [{
    "id": "provider_reservation_…", "kind": "contact",
    "state": "confirmed", "pass_phase": "scheduled", "delivery_state": "pending",
    "spacecraft_id": "spacecraft-earendil-312",
    "spacecraft": {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312},
    "station": {"ref": "SVL", "id": "ground_station_…", "code": "SVL", "name": "Svalbard"},
    "antenna": {"id": "ant-3", "label": null},
    "starts_at": "…", "ends_at": "…",
    "uplink_capable": null,
    "source": {"provider": "provider_…", "provider_name": "Simulator", "synthetic": true},
    "max_elevation_deg": null,
    "cost": null,
    "plan": {"id": "contact_plan_…", "version": 42},
    "reservation_id": "provider_reservation_…",
    "scheduled_contact_id": "scheduled_contact_…",
    "ended_by": null,
    "replaced_by": null
  }]
}}
```

- `spacecraft`: identity on every line (R01). `name` and `scid` are `null` if the spacecraft was
  deleted since the booking.
- `kind` is always `contact` for now. **Opportunities** (provider windows not yet booked) need a
  live provider search per spacecraft and route; they come with scheduling S4 (alternatives), not
  this read.
- `state` is the reservation lifecycle: `requesting | pending | confirmed | active | completed |
  unknown | rejected | canceling | canceled | failed`. `pass_phase` and `delivery_state` are the
  provider's pass and delivery progress, `null` until the provider reports them. The UI's state model (Requested / Confirmed / In contact /
  Realized / …) is a client decoding of these three fields (lead's `features/scheduling/contact.ts`).
- `station`: from the reservation's newest snapshot (Cadence-accepted, then provider-confirmed,
  then requested). `ref` is the provider's station reference. `id`, `code` and `name` are filled
  when `ref` matches a Cadence ground station (by id, `metadata.code` or
  `metadata.provider_station_ref`), and are `null` otherwise. Show `ref` then.
- `antenna`: `null` unless the provider names one. `label` is always `null` (providers only give a ref).
- **Nothing is derived** (DECISIONS #4, no propagation): `max_elevation_deg`, `uplink_capable` and
  `cost` are `null` unless the provider supplied them in the snapshot (`cost` is then `{amount,
  currency}`). `source.synthetic` is `true` for the simulator's deterministic windows. Say so in the
  UI. `source.provider_name` and `source.synthetic` are `null` when the snapshot doesn't say.
- `plan`: the contact plan revision that booked it, or `null` for direct bookings.
- `listener_overlap` (U58 (b), #361): `null`, or `{with: {spacecraft: {id | null, name | null},
  station: {code, name} | null, starts_at, state: "booked" | "planned"}, seconds | null, loses: "this" |
  "other" | "either", direction: "downlink" | "uplink", listener: {host, port}, count}`. The pass
  loses its start (or would) to another pass of the mission on a station listener that takes one
  connection at a time. The rule is the runtime's own: a listen binding with a fixed port that binds
  its own socket (everything but a `listener: "shared"` downlink) on a colliding host:port
  (`ListenClaims`). The later start loses from its start to the earlier pass's end, capped at its
  own end; an equal start is a race (`either`). `seconds` is `null` when neither pass has an end
  (unmeasurable, not absent). With several, it names the pass's OWN loss first (`this`, then
  `either`, most seconds), and only when it loses nothing the costliest it causes (`other`), so a
  pass that loses time always reads as the loser; `count` is how many passes it overlaps (1 when
  single). `spacecraft.id` is null only when the other pass's record doesn't say. `listener` is for Technical details only (U58: no port in
  sentences). Another mission can never hold the listener: `ListenClaims` refuses another
  mission's endpoint at save. Advisory: nothing is refused.
- `ended_by` (qa #30): who ended a `canceled`, `rejected` or `failed` booking, else `null`.
  `{kind: "user", id, name}` for a cancel from the contact workspace or an operator's #53
  "not booked" resolution; otherwise `{kind: "provider", id, name}`.
- `replaced_by` (qa #30, DECISIONS #56): on a lost booking that something replaced, else `null`.
  `{kind: "repair", plan_id, reservation_id}` when an applied repair re-booked it
  (`reservation_id` is `null` until that pass is placed), or `{kind: "single_booking", plan_id:
  null, reservation_id}` when a live single booking (contact workspace `actions/reserve`) covers
  it. A lost row with `replaced_by: null` is still lost: that's what re-plan's Impact shows.
  Replacement is persisted when the repair plan is created and never re-derived.
- `truncated: true`: more than 500 rows overlap the window (with the filters that apply in SQL).
  The rows kept are the first 500 in the requested order. Narrow it.
- Refetch on `invalidate` with `contacts` (below). AOS/LOS happen without an event; refresh a
  "now" line on a timer if you draw one.

Errors: `422 invalid_params`, `404 mission_not_found`.

### Booking evidence and attention on pass rows (U32, DECISIONS #53/#54/#55)

Every row gains four fields:

- `booking_evidence`:
  - `provider` when the provider confirmed the booking (`state` `confirmed | active | completed`);
  - `operator_attested` when an org admin marked it booked (#53) and the provider hasn't confirmed;
  - otherwise `null` (not booked, or lost).
- `attested_by`: `{kind, id, name}` of who marked it booked, when `booking_evidence` is
  `operator_attested`; otherwise `null`. Reads "BOOKED · ATTESTED BY MIRA K.".
- `uplink_confirmed`:
  - `true` when the provider confirmed the booking's uplink leg;
  - `false` when an uplink leg was requested but isn't confirmed (always for an attested booking,
    while #46 D1 holds). The UI reads "UPLINK UNCONFIRMED".
  - It turns `true` when the provider confirms before AOS (#55).
  - `null` when no uplink leg was requested (a downlink-only booking), so there's nothing to
    confirm.
- `attention`: this booking's open or acknowledged attention item, the same object as the action
  queue's `attention` (ops.md), or `null`. It's also `null` for a viewer who can't operate the
  mission. The action queue's object also gains `reservation_id`, the pass row's `id`. A conflict
  on a booking that never got a scheduled contact (`cancel_failed`, `late_confirmation`) has
  `contact_id: null`, so link by `reservation_id`.
- An attention change (`invalidate` `attention`) also invalidates `contacts`, since rows carry
  their item.

### `GET /api/console/v1/missions/:mission_id/passes/:id`

One pass by its reservation id (the row `id`, or the attention object's `reservation_id`), in the
same row shape including `attention`, whatever its window. Review opens passes days out with it.
Returns `{data: <row>}`. Errors: `404 pass_not_found`, `404 mission_not_found`.

U78: `:id` may also be a **scheduled contact id** (the reservation that booked it) or a **realized
contact id** (the pass of the scheduled contact it realized, or, for a hand-started contact, its
`booked: false` row with the detail fields below). Reservation ids are tried first, then scheduled,
then realized. A scheduled id never gives a `booked: false` row; a scheduled contact nothing booked
is `404`. The row keeps its own `id` (a reservation id for a booking): key on `data.id`. Scoped to
the mission like a reservation id. Writes (`release`, `recover-uplink`, `cancel-contact`,
`end-contact`) take reservation ids only: a contact id is `404 pass_not_found`. For a
`booked: false` row the detail has `queued_command_groups: {count: 0, next_pass: null}`,
`provider_changes: []`, `window_moves: []`, plan and requirement names `null`, and
`telemetry_stored`, `incomplete_at_end`, `second_connections_refused` and `queued_commands`
from the contact.

This read alone adds `queued_command_groups: {count, next_pass}` for the D2 Release sheet (ux):
- `count` is how many queued, unfinished command groups release on this pass, whatever its
  readiness;
- `next_pass` (`{reservation_id, contact_id, station, starts_at, ends_at}` or `null`) is the
  spacecraft's next commandable pass after it, where they'd go if this one were released.

U74 'Booked' row: pass rows carry `requirement: {id, version} | null` (the requirement it was
booked for), and pass detail (`GET /passes/:id`) names both: `plan: {id, version, day}` (`day` =
the plan's UTC day, the day of its earliest selected pass, as plan detail derives it) and
`requirement: {id, version, name}` (`name` as plan history's `requirement_label`: template name,
else the rule in words). Both `null` for a pass booked outside a plan.

### `GET /api/console/v1/missions/:mission_id/passes/:id/reservation` (L14 / A11, owner: api)

The pass's reservation for the drawer's Technical details (what the legacy reservation review
showed):

```json
{"data": {"reservation": {"id", "provider_revision", "lifecycle_state", "provider": {"id", "version"},
  "transport": {"id", "version"} | null, "plan": {"id", "version"} | null,
  "requirement": {"id", "version"} | null, "scheduled_contact_id": null, "last_reconciled_at": null},
 "values": [{"field": "starts_at", "requested_json": "\"…\"", "confirmed_json": "\"…\"",
   "accepted_json": "\"…\"", "restricted": false, "differs": true}],
 "audit": {"entries": [{"id", "action", "outcome", "recorded_at", "change_id"}], "next_cursor": null}}}
```

- `values`: the 13 provider fields, in this order: `provider_contact_ref, opportunity_ref,
  spacecraft_ref, ground_station_ref, antenna_or_service_pool_ref, service_profile_ref,
  delivery_profile_ref, starts_at, ends_at, status, pass_phase, delivery_state, status_reason`.
  Each `*_json` is the JSON value, `null` = not set. A structured or oversized (over 512 bytes)
  value is withheld: its cell is `null` and the row says `restricted: true`. `differs`: the
  three aren't all equal (a missing value counts; withheld cells compare as withheld).
- `lifecycle_state`, `action`, `outcome` are the store's and provider audit's own words (shown as
  said; `action`/`outcome` at most 120 characters).
- `audit`: newest first, 25 per page; `?audit_cursor=<next_cursor>`. A cursor not on this
  reservation → `422 invalid_params` (`details.audit_cursor`). `404 pass_not_found`.

### `GET /api/console/v1/missions/:mission_id/contacts/:contact_id/record` (L14 / A13, owner: api)

A contact's record for the drawer's Technical details (what the legacy contact record showed).
`contact_id` is a scheduled OR a realized contact id; both sides of the pair come back.

```json
{"data": {"subject": {"id", "kind": "scheduled" | "realized"},
 "scheduled": {"id", "current_revision", "lifecycle_state", "starts_at", "ends_at", "realized_id",
   "provider_contact_ref"} | null,
 "realized": {"id", "scheduled_id", "lifecycle_state", "clock_mode", "realized_at", "initial_time"} | null,
 "paths": [{"side": "scheduled" | "realized", "id", "direction", "selection", "source_endpoint_ref",
   "provider_bindings": [{"id", "adapter_key"}], "transport_bindings": [{"id", "family_key", "target_scope"}]}],
 "sources": [{"id", "side": "reviewed_schedule" | "realized"}],
 "intents": [{"id", "side": "current_schedule" | "realized"}],
 "revisions": {"entries": [{"revision", "created_at", "created_by": {"kind", "id", "name"} | null,
   "provider_change_id", "starts_at", "ends_at", "lifecycle_state"}], "next_cursor": null},
 "truncated": false}}
```

- `revisions`: the schedule history, newest first, 25 per page; `?revisions_cursor=<next_cursor>`.
  Each carries its window and state, so "Review current revision" is picking one (the first is
  current). `created_by` is a person, `{kind: "system", name: "Cadence"}`, or `{kind: null, id}`.
- Provider bindings name their `adapter_key` (they have no family key); transport bindings their
  `family_key` and `target_scope`. State and key words are the store's (shown as said).
- Caps: 100 paths, 200 sources, 200 intents, then `truncated: true`. `404 contact_not_found`;
  a bad cursor → `422 invalid_params` (`details.revisions_cursor`).

### Provider changes (§11 L14): the `provider_change` attention source

A provider changed a booked pass (`ProviderReservationChange`) and someone must decide. One item
per open change, `id` = the change id, `conflict`:

- `approval_required` (state `pending_approval`): approve or reject before `deadline_at`;
- `acknowledgment_required`: the provider already applied it, so acknowledge it;
- `configuration_failure`: shown only, with nothing to decide here.

The item carries the usual `contact_id`, `station`, `provider`, `starts_at` and `raised_at`, plus
`deadline_at` and `provider_change: {id, classification, state, deadline_at, provider_revision,
proposal_hash, already_effective, expired, fields: [{field, label, before_json, after_json}]}`
(`expired`: pending when its pass ended, below). Values are JSON text, so they're 64-bit safe.
- `label` is the server's word for the known keys: `starts_at` "AOS", `ends_at` "LOS", `ground_station_ref` "Station", `antenna_or_service_pool_ref` "Antenna",
  `service_profile_ref` "Service profile", `delivery_profile_ref` "Delivery profile",
  `spacecraft_ref` "Spacecraft", `pass_phase` "Pass phase", `status` "Status". It's null for any
  other key.
- The item resolves when the change is decided (`action` `approved | rejected | acknowledged`,
  `resolved_by` the user, `note` = the decision's reason) or superseded (`system`, `note` null).
- **Once the pass ends** (its `ends_at` is past; domain fb09ac755) the change leaves Now. A
  pending one then reads `state: "expired"`: it can't be decided, and approve or reject answers
  `409 provider_change_expired` ("The pass has ended, so this change can't be decided any more.",
  `details.item`). An acknowledgment still works from the pass. Pass rows keep their open changes
  after the pass ends.
- `GET /passes/:id` adds `provider_changes`: the pass's history (ux U44). That's every change,
  newest first, at most 50, as `provider_change` plus `raised_at` and `resolution: {action:
  approved | rejected | acknowledged | superseded | policy_accepted | observed | apply_failed,
  by: {id, name} | null, at, reason} | null` (null while open or expired; `action` is the change's
  decided lifecycle state). `state` is the lifecycle, or `expired`.
- **At the deadline Cadence does nothing by itself.** Approve and reject are refused from then on
  (`409 provider_change_deadline_passed`), and the change stays open until the provider's next
  revision supersedes it: the provider decides.
- Pass rows (`GET /passes`, `/passes/:id`) carry an open provider-change item in their
  `attentions` (below, Pass row attentions).

`POST …/attention/provider_change/:id/approve | reject | acknowledge {reason, proposal_hash}` →
`200 {data: {item: <the attention object> | null}}` (null once decided). Organization admins only:
`:approve_provider_changes`.

- `422 invalid_params`: `details.reason` ("Say why.") or `details.proposal_hash`.
- `409 provider_change_stale {item}`: the hash or revision moved, the policy changed, or reject
  isn't possible any more. `item` is the current one, or null.
- `409 provider_change_deadline_passed`. Hide Reject after the deadline.
- `403 forbidden` ("Org admins decide provider changes.").
- `404 attention_item_not_found`: not an open change of this mission.

Now (ops.md): approval rows are P2, due at `deadline_at`, and drop to P3 once it passes (the
provider decides then; ux U44). Acknowledgement and configuration-failure rows are P3.

### Pass row attentions (ux U45)

`GET /passes` rows and `GET /passes/:id` carry `attentions: [<attention object> + {priority,
due_at}]`: every open item of the pass (`pass_resolution`, `pass_release`, `provider_change`,
`contact_start`, `archive_quarantine`, and any later source whose item carries the booking's
`provider_reservation_id`; only `uplink_blocked` stays out, shown through `uplink_readiness`), in
Now's order: `priority` (1 first), then the soonest `due_at` (null last), then
`contact_start` on a tie. `attention` is `attentions[0]`, or `null`; `attentions` is `[]` when
there's none. Show the first as the tag with "+N" for the rest; the pass detail shows them all.

### A contact that didn't start: the `contact_start` source (ux U45)

Now and pass rows carry `source: "contact_start"`, `id` = the realized contact id (the scheduled
contact id for a pass that couldn't be realized, below), `conflict`:

- `not_started` while the pass's window is on: Cadence retries by itself (`retry: "automatic"`),
  at once when the holder frees the station and on every reconcile. **P1**, due at LOS
  (`ends_at`).
- `missed` once the window ended without a start. **P2**, due at `ends_at`; it stays until an
  operator marks it as seen (`acknowledge`).

The item's keys, flattened as for `contact_settlement`: `reason` (`listener_in_use |
listener_unavailable | connect_failed | ingress_pipeline_failed | uplink_session_failed |
no_runtime_spec | listen_endpoint_claimed | transport_archived | unknown`, or null; ux words
each), `holder`, `provider_profile_id`,
`provider_profile_name`, `realized_contact_id`, `contact_id`, `reservation_id`, `ends_at` (null
without a booking), `attempts`, `last_attempt_at`, `retry`, `failure_message` (raw, Technical
details only), `expires_at: null`, `reason_detail` (11-17, ux U91): for `no_runtime_spec`,
`no_configuration` (no configuration activated: the mission's to fix, Open Changes) or
`configuration_unverifiable` (the active configuration failed its integrity check: Cadence's to
fix, Open pass, never Open Changes); null for other reasons and for failures stored before it.

- `holder` (only for `listener_in_use`): the pass still holding the station listener,
  `{realized_contact_id, contact_id, reservation_id, spacecraft: {id, name}, station: <station
  object>, starts_at, ends_at} | null`.
- `transport_archived` (ux U45): the pass's path was pinned, at booking, to the provider profile
  of a transport archived since. `transport_id` and `transport_name` name that transport (its
  name when it was archived). Every try fails the same way; only that one pass is affected.
- **A pass that couldn't be realized** (U45, lead 11-17): Cadence refused to build its run (its
  paths didn't resolve: an archived or deleted profile, a missing template), so no realized
  contact exists. Until 11-17 it was silent. The failure is kept on the scheduled contact and the
  item is anchored on the booking: `id` and `contact_id` are the scheduled contact id,
  `realized_contact_id`, `provider_profile_*` and `holder` are null, `reason` is
  `transport_archived` or another key (usually `unknown`), and the scheduler retries every
  reconcile. It resolves `started` once realization succeeds; if that run then fails to start,
  the realized contact's own item takes over.
- Resolved: `action: "started"` by the system, or `"acknowledged"` by the operator who marked it
  as seen. Entries carry `realized_contact_id`: the ITEM's, as it was while open (null for a pass
  that couldn't be realized, even after it's later realized; never the new run's id). The console
  keys 'Set up at' (null) versus 'Started at' on it (fe-ops, ux U45).
- `POST …/attention/contact_start/:id/acknowledge` (no body; `operate_mission`): only on a
  `missed` item. `409 contact_start_not_missed` while it's still `not_started`; `403` "Operators
  mark missed passes as seen."; `404 attention_item_not_found`. `resolve` and `retry` are 404 for
  this source.

### Archive entries that couldn't be indexed: the `archive_quarantine` source (DECISIONS #88, ux U49)

Now (and the pass row, when the contact was a booked pass) carry `source: "archive_quarantine"`,
`conflict: "quarantined"`, `id` = `<realized_contact_id | "none">:<error_code>` (no source prefix):
one item per contact and cause. Their telemetry was still stored; their raw records weren't
archived. **P2**, `due_at: null` (nothing is lost, so it sorts after anything due). No acknowledge.

Flattened keys besides the shared ones (`state`, `contact_id`, `reservation_id`, `station`,
`provider`, `starts_at`, `raised_at`, `resolution`): `realized_contact_id`, `spacecraft_id`,
`ends_at`, `error_code` (`identity_conflict | data_rejected | unknown`; read as known text),
`error` (technical, ≤300, Technical details only), `counts {entries, frames, packets}`,
`stored_without_archive {frames, packets}`, `first_received_at`, `last_received_at` (the entries'
receipt span), `last_seen_at` (bumped while more keep arriving), `actions` (`["retry",
"discard"]`), `last_retry: null | {by: <actor>, at, indexed}`.

- `POST …/attention/archive_quarantine/:id/retry` (no body; `operate_mission`): re-indexes the
  entries now, synchronously. `200 {data: {item: <attention object>, indexed, still_failing}}`;
  `item.state` is `resolved` (`resolution.action: "retried"`) when `still_failing` is 0, else the
  open item with new counts and `last_retry`.
- Discard is `POST …/attention/archive_quarantine/:id/resolve {action_text}` (the reason,
  required, at most 200 characters): the entries leave the quarantine unarchived;
  `resolution.action: "discarded"`, `note` the reason.
- `acknowledge` answers `409 attention_item_not_open`. `403 forbidden` for non-operators, `404
  attention_item_not_found`, `422 invalid_params {action_text}` / `reason_required`, and `503
  attention_unavailable` when the archive can't be reached.

### A job Cadence stopped during: the `job_outcome_unknown` source (ux U54; director, lead 11-14)

Cadence stopped while a job that isn't safe to run again was running (a booking, a provider or TSDB
operation, a catalog import, an evaluation, a backfill), so nobody knows whether it finished.
Cadence doesn't run it again by itself; the job reads `outcome_unknown`. Now carries `source:
"job_outcome_unknown"`, `conflict: "outcome_unknown"`, `id` = `job_outcome_unknown:<job_id>:<attempt>`:
**one item per run**. A retried job that is cut off again raises a NEW open item beside the
resolved one; an item never reopens. **P2**, **P1** when the job's pass starts within 2 h or is
live. No acknowledge.

Flattened keys besides the shared ones (`state`, `contact_id`, `reservation_id`, `station`,
`provider`, `starts_at`, `raised_at`, `resolution`): `spacecraft_id`, `ends_at`, `job {id,
type_key, run_id, attempt, node: null}`, `words {noun, check_place, consequence}` (free text, never
a blank name: an unnamed provider is "the provider"), `started_at`, `found_at` (when the restart
found it; Cadence doesn't record when it stopped), `actions` (`["retry", "close"]`). The pass keys
are set when the job is tied to a booking, null otherwise.

- `POST …/attention/job_outcome_unknown/:id/retry {confirmed: true, note?}` (`operate_mission`):
  the job goes back in the queue, the only way it runs again. `202 {data: {item, run: {job_id,
  status: "queued"}}}`; `item.resolution.action: "retried"`. `422 invalid_params {confirmed}`
  without the confirmation.
- Close is `POST …/attention/job_outcome_unknown/:id/resolve {action_text}` (the note, required,
  at most 200 characters): the job stays as it is; `resolution.action: "closed"`, `note`.
- Retry and close are atomic on the item: of two operators at once, one wins and the other gets
  `409 attention_item_not_open`, and the job is queued at most once. `403 forbidden` for
  non-operators, `404 attention_item_not_found`.
- Jobs relabelled `outcome_unknown` after the 11-14 jobs fix raise no item (no Retry).

### A command group that expired before all of it went out: the `expired_group` source (ux U75, DECISIONS #97)

One item per command group (`id` = the group id), raised by its `expired` timeline event
(commanding.md), for 7 days or until marked as seen. **P2**; the queue row's `state` is `caution`
when part of the group went out (`sent > 0`), `info` when none did. Keys beside the shared ones:
`group {id, title}`, `spacecraft_id` (the target when the group has one, else null),
`target_count`, `sent`, `total`, `expired_at`, `actions: ["acknowledge"]`.

- `POST …/attention/expired_group/:id/acknowledge` (`operate_mission`): marks it as seen
  (`resolution.action: "acknowledged"`); it leaves Now. `404 attention_item_not_found` when it isn't
  open. No resolve.

### Connections a shared listener refused: the `listener_refusal` source (#87, ux U50)

Now and the pass row carry `source` and `conflict` `"listener_refusal"`, `id` =
`<realized_contact_id>:<provider_binding_id>`: one item per open pass on a SHARED listen profile
whose listener refused a connection in its window. Counted live (a restart starts the count again);
no actions, so acknowledge, resolve and retry answer `404 attention_item_not_found`.

- **P1** while the pass isn't connected, or its own connection is quiet, in the open window
  (domain's `p1`); else **P2**. Due at LOS (`ends_at`).
- Keys besides the shared ones (`contact_id`, `reservation_id`, `station`, `provider`,
  `starts_at`, `raised_at` = the first refusal): `realized_contact_id`, `path_id`, `spacecraft_id`,
  `ends_at`, `provider_profile_id`, `provider_profile_name`, `last_refused_at`, `refused_count`,
  `last_refusal {reason, scid, peer, at}` (`reason` `unregistered_scid | ambiguous_scid |
  unexpected_peer | unidentified | read_failed | second_connection | unknown`, read as known text;
  `peer` for Technical details only), `own_quiet_since` (or null), `connected`, `shared_with`
  (the other open passes' realized contact ids), `second_connections_refused`.
- Resolved: `action` `accepted` (the pass's own connection came) or `ended` (LOS), by the system.
- `GET /passes/:id` carries `second_connections_refused: integer | null`: connections refused
  while the pass's own was up (live, else as recorded at LOS), null without a realized contact.

Every recently resolved entry (all sources) also carries `reservation_id` (null without a booking)
and `booked` (true when it has one), so an ended item can say "the pass" or "the contact".

### Most frames carried another SCID: the `contact_scid_mismatch` source (ux U81 §2, DECISIONS #102)

One item per settled contact where MORE than half of its integrity-checked TM frames carried
another SCID (domain's `ScidMismatch.most?/1`, the same rule as the Timeline event). Now's row:
`id` `attention:contact_scid_mismatch:<realized_contact_id>`, `priority` 2 and `state` `caution`
always (the pass is over; no countdown: `due_at` is the pass start, in the past), `spacecraft`
`[member]`. The `attention` object: `id` = the realized contact id, `conflict` `null`, `state`
`open | resolved`, `acknowledged_by` `null`, `contact_id` (the scheduled contact, `null` when
started by hand), `realized_contact_id`, `reservation_id`, `station`, `starts_at` (the contact's
realized start), `raised_at` (settled at), plus:

- `spacecraft: {id, name, scid} | null`: the pass's craft (`name` null, never the id, when unknown).
- `scid_mismatch: {expected_scid, frames, frames_total, scids, scid_count}`: refused frames and
  every integrity-checked frame, summed over the paths; `scids` the observed SCIDs over all paths,
  sorted, at most 8; `scid_count` the larger of the largest per-path count and the list's size
  before the cap, so the list is complete exactly when `scid_count == scids.length < 8`.

'Open contact record' → History `?contact=<contact_id ?? realized_contact_id>` (`GET /passes/:id`
takes either). Lifecycle (no acknowledged-but-open state; `counts.acknowledged` is 0):

- `POST …/attention/contact_scid_mismatch/:id/acknowledge` (no body; `operate_mission`) marks it
  seen and RESOLVES it at once: it answers the attention object with `state: "resolved"` and
  `resolution: {action: "seen", actor: {kind: "user", id, name}, at, note: null,
  provider_reference: null}`; the resolved entry is `action: "seen"`, `resolved_by` the person.
  Not open (seen, retired or never raised): `404 attention_item_not_found`. `resolve` and `retry`
  are 404 for this source.
- Never seen, it retires 7 days after the settle: `action: "retired"`, `resolved_by: {kind:
  "system", id: null, name: null}`, `resolved_at` = settle + 7 d (the console words it 'Retired
  after 7 days without being seen', no actor).

### Cancel or end a pass's contact (ux U55/U56)

Pass rows (`GET /passes`, `GET /passes/:id`) carry:

- `contact_action: "cancel" | "end" | null`: `cancel` before the contact is live, `end` while it
  is, `null` once it ended, was canceled, or the window is over. Never both.
- `contact_ended: null | {kind: canceled | ended_early, cause, by {kind: user | system, id, name},
  at, reason, reason_code}`. `cause` (known text): `operator`, or `provider_failed |
  provider_canceled | provider_rejected` when Cadence canceled it because the reservation won't fly
  (`by` is `{kind: system, id: provider_reservation_reconciler, name: null}`). `reason` is the
  operator's reason, or the provider's own words (null when it gave none); `reason_code` the
  provider's code (null for an operator).
  Nullable (lead 11-14): `cause`, `by` and `at` are null ONLY for a contact canceled with no
  ending action record (legacy rows); every new cancel or end fills all three. `by` is null rather
  than a half actor when the recorded actor lacks its kind or id. With no action record, `at` is
  the contact's own lifecycle cancel time when it has one (`cause` and `by` stay null).

`GET /passes/:id` also carries:

- `queued_commands: {count, expiring_before_next: {count, earliest_at} | null, next_contact:
  {station, starts_at} | null} | null`: the spacecraft's queued command requests, how many expire
  before its next commandable contact, and that contact. `next_contact` is the next contact by the
  CORRECTED accepted window, after this pass, skipping canceled, phantom and uplink-dropped contacts;
  it is not "the next scheduled_contacts row". Neither action cancels queued requests: they wait
  for the next contact.
- `incomplete_at_end: {frame_bytes, packet_bytes} | null` (ux U67): bytes at the end of the pass
  that didn't form a complete frame or packet, so they weren't stored, summed over the contact's
  paths from domain's settlement (`realized_contacts.metadata.settlement.incomplete_at_end`).
  `null` when nothing was cut off or the contact hasn't settled; one side may be 0. A quiet note in
  the settlement view only ("6 bytes at the end of the pass didn't form a complete frame, so they
  weren't stored."); never on Now or the Timeline. Detail only.
- `scid_mismatch: {expected_scid, paths: [{station, frames, scids, scid_count, path_id,
  provider_binding_id}]} | null` (ux U81 §2, DECISIONS #102): TM frames whose header SCID wasn't
  the pass's, refused before reassembly, so they made no telemetry (the bytes stay in the journal
  as raw evidence). From domain's settlement (`realized_contacts.metadata.settlement.scid_mismatch`):
  one entry per path that refused a frame (`frames > 0`), most frames first. `station` is the
  contact's `ground_station_ref` resolved like the rows' (`{ref, id, code, name}`, or `null`);
  `scids` the observed SCIDs, sorted, at most 8; `scid_count` how many there were (≥ the list).
  `path_id` and `provider_binding_id` are for Technical details only. `null` when nothing was
  refused, the contact hasn't settled, or the record predates #102; never an empty list. The
  record line words it per station (ux U81 §2). Detail only.
- `telemetry_stored: {through, los, settled_at, text} | null` (ux U60): did this pass's data reach
  the store, and how close to LOS. From the latest `source_watermark_settled` event on the pass's
  realized contact: `through` = what's stored through, `los` = the pass's LOS, `settled_at` = when
  it settled, `text` = "EARENDIL-008 · SVB 03:10Z pass: telemetry stored through 03:19:40Z (LOS
  03:19:57Z)". `null` without a realized contact or before it settles (and until domain's
  coalescing writer ships). Detail only.
- `window_moves: [{at, before {starts_at, ends_at}, after {…}, classification: observed |
  acknowledgment_required | approval_required, provider_change_id}]`, newest first: the
  provider's moves of this pass. `before` and `after` are always objects: only a change that moved
  the window is listed (an approved change, `approval_required`, takes both windows from the
  contact's revisions).

Writes (operators, `operate_mission`; neither changes the provider booking, which is Release):

- `POST /passes/:id/cancel-contact {reason}`: before AOS (domain's scheduled-contact cancel).
- `POST /passes/:id/end-contact {reason}`: while live (domain's end-early).
- `reason` required, trimmed, at most 500 characters. `200` answers the pass row (`GET
  /passes/:id`).
- Errors: `422 invalid_params {reason}`; `409 contact_not_cancelable {state: active | ended |
  canceled}`; `409 contact_not_live {state: not_started | ended | canceled}`; `404
  no_scheduled_contact` (a booking with no contact in Cadence); `404 pass_not_found`; `403
  forbidden`.
- Each writes the contact action that the Timeline shows (`scheduled_contact_canceled`,
  `realized_contact_ended_early`, with the actor and reason) and an organization audit entry
  (`kind: contacts`).
- Hand-started contacts aren't pass rows, so they're out of this step: ending one from Uplink's
  contact view is a follow-up.

### `POST /api/console/v1/missions/:mission_id/attention/:source/:id/acknowledge` · `…/resolve`

`:source` and `:id` are the attention object's `source` and `id`: `pass_resolution` (the
resolution id), or `contact_settlement` (only a lost-telemetry item, acknowledge only; see
`domain/contact-settlement.md`). `POST …/attention/contact_settlement/:id/retry` starts a stopped
replay again (`409 retry_not_manual` otherwise). Members who can operate the mission (`operate_mission`); the actor is always the
signed-in user (#30).

- `acknowledge`: no body. The item stays listed, sorted last (U21).
- `resolve`: body `{"action_text": "Called Northlight; the cancel is confirmed, ticket 4471."}`
  (required, at most 200 characters). The text is shown as "Resolved: <action_text>" in history.
- Both return `{data: <attention object>}` (`state` `acknowledged` / `resolved`) and invalidate
  `attention` and `contacts`.
- Errors: `404 attention_item_not_found` (also an unknown `:source`), `409 attention_item_not_open`
  (already resolved, or acknowledging one that's acknowledged), `403 forbidden`,
  `422 invalid_params` (`details.action_text`), `422 actor_not_assignable` (the body names an
  actor field), `404 mission_not_found`.

### Uplink readiness (U33, DECISIONS #58/#59)

Readiness comes from domain's live view of uplink sessions (`Control.UplinkReadiness`). The
driver ticks every 15 s, so it can be up to 15 s stale. Every transition publishes `contacts`
and `attention`.

- **Pass rows** (`/passes`, `/passes/:id`) gain `uplink_readiness`:
  `{state: ready | qualifying | blocked, reason, since, command_groups_queued}`.
  - `reason` is a key (for example `protocol_state_restore_required`,
    `attestation_signature_invalid`, `cop1_awaiting_clcw` while qualifying). Map it to words;
    an unknown key falls back to sentence case.
  - `since` is when this state began.
  - `command_groups_queued`, only for `blocked`, is the number of queued groups it holds back:
    `> 0` crit, `0` caution. It's `null` for other states.
  - **Dropped uplink leg** (U46, DECISIONS #84): when Cadence has accepted terms without the
    uplink leg the booking asked for, the pass reads `{state: "blocked", reason:
    "uplink_leg_dropped", since: <when Cadence accepted the drop, or null>,
    command_groups_queued}` for its whole window, before its session too, and `uplink_confirmed`
    is `false`. Commands can't be released on it. Compose's preflight, the spacecraft uplink read
    and a group's next pass skip it. A group live on it when it dropped shows the same readiness
    on its `uplink`. Ended passes read `null` as usual.
  - The whole field is `null` when the pass has no live uplink session: a future pass before its
    session starts, a downlink-only pass, or one that isn't booked. Show no tag then, as for `ready`.
  - A pass row's `attention` is its first open item (Pass row attentions below). A blocked uplink
    shows through `uplink_readiness`, not `attention`.
- **Command groups** (list rows and show) gain `uplink`, set on `queued` groups that aren't
  `finished`, otherwise `null`:
  `{pass: {reservation_id, contact_id, station {ref, id, code, name}, starts_at, ends_at},
  readiness: {state, reason, since} | null, next_pass: <same pass shape> | null}`.
  - Groups queue per spacecraft lane, not per contact, so `pass` is the first target's live uplink
    pass (any readiness), else its next booked pass that can command (then `readiness` is
    `null`).
  - `next_pass` is the next commandable pass after a live one, where a blocked group goes next.
    When it's `null`, say "on the next ready pass" without naming one.
  - Expiry comes from the group's `release.expires_at`.
  - Recover posts to `pass.reservation_id`.
  - **U46 (named release, DECISIONS #84).** `uplink` is also set when the first target has a live
    hand-started contact and no booked pass, and it gains:
    - `spacecraft {id, name}`: the target the block describes (the group's first; `name` falls back
      to the id). Other targets' passes aren't in it.
    - `pass` gains `realized_contact_id` (null before the pass starts), `booked: true`,
      `started_by {kind: user | service | system, id, name} | null` (a user is named; `name` is null
      otherwise), `started_at` (null before it starts) and `armed_group_ids`.
    - `contact`: the target's live hand-started contact (not a booked pass), else `null`, with
      `{realized_contact_id, booked: false, reservation_id: null, contact_id: null, station,
      starts_at, ends_at: null, started_by, started_at, armed_group_ids}`.
    - `pass` is `null` only when `contact` isn't. With a hand start and a booked pass ahead, `pass`
      is that pass (`readiness` and `next_pass` `null`).
    - `armed_group_ids`: the mission's `queued` groups with members still queued for that
      spacecraft, oldest GO first. Send it as is to the named release (commanding.md); the viewed
      group is in it while it has unreleased members there. Empty means nothing to release.
- **`POST /api/console/v1/missions/:mission_id/passes/:id/recover-uplink`** (`:id` = the pass row
  `id`, a reservation). No body; `operate_mission`; audited; safe to repeat. It re-runs the pass's
  uplink qualification.
  - Returns `{data: {state: "ready", ready_at}}`.
  - Errors:
    - `409 uplink_recovery_refused` (`details.reason`, the key);
    - `409 uplink_not_blocked` (the pass is already `ready`; a `qualifying` pass is qualified
      again);
    - `403 forbidden`;
    - `404 pass_not_found` (also a pass with no scheduled contact);
    - `422 actor_not_assignable`.
  - `protocol_state_restore_required` and `provider_cannot_attest_uplink_sessions` are refused
    without trying (#59), so hide Recover for those reasons (ux).
- **Attention source `uplink_blocked`:** a pass that's `blocked` while command groups are queued
  for it. Queue rows have `source: "uplink_blocked"` and id `attention:uplink_blocked:<contact_id>`.
  They're P1 within 2 h of AOS or in progress, otherwise P2, with `due_at` = AOS. The `attention`
  object keeps the same envelope:
  - `id` (the scheduled contact id), `source`, `state: "open"` (it resolves by itself; no
    acknowledge), `contact_id`, `reservation_id`, `station`, `provider`, `starts_at`, `raised_at`
    (= `since`);
  - `conflict`, `provider_message`, `resolution` and `acknowledged_by` are `null`;
  - plus `uplink: {state: "blocked", reason, since, command_group_ids: [...]}` (`null` on
    `pass_resolution` items).
  - `resolved[]` entries: `resolved_by {kind: "system"}`, `action` `uplink recovered` or
    `pass ended` (at LOS). An item whose groups all leave simply stops being listed.
  - `/counts.attention` counts both sources. `POST /attention/uplink_blocked/…` answers
    `404 attention_item_not_found`, since these resolve by themselves.

## `GET /api/console/v1/missions/:mission_id/contact-findings` (M22, Contacts D4)

"Needs a decision": problems across the mission's live bookings (requesting, pending, confirmed,
active) in a window. Query: `from`, `to` (default now to +6 h, at most 7 days), `max_gap_s`
(coverage-gap threshold, 600–604800, default 14400 = 4 h).

```json
{"data": {"from": "…", "to": "…", "max_gap_s": 14400, "truncated": false,
  "counts": {"conflicts": 1, "gaps": 1},
  "findings": [
    {"id": "station_double_booked:…:…", "kind": "station_double_booked", "severity": "caution",
     "at": "…", "station": {"ref", "id", "code", "name"}, "spacecraft": null,
     "passes": [{"id", "spacecraft", "starts_at", "ends_at", "state"}, …], "overlap_s": 180,
     "message": "073 and 251 overlap by 3 minutes at SVB.", "fix": null},
    {"kind": "booked_into_outage", "severity": "critical", "station": {…}, "spacecraft": {…},
     "passes": [{…}], "message": "073's pass at SVB falls in a station outage.", "fix": null},
    {"kind": "coverage_gap", "severity": "critical", "spacecraft": {"id", "name", "scid"},
     "gap": {"from", "to", "seconds": 19860}, "passes": [],
     "message": "389 has no pass for 5h 31m.", "fix": null}
  ]}}
```

- `station_double_booked`: two live bookings at the same station overlap. Bookings on different
  named antennas of the station don't conflict. Bookings without a known station aren't compared.
- `booked_into_outage`: a live booking falls in a station outage or maintenance window (S7).
- `coverage_gap`: a spacecraft has no live pass for longer than `max_gap_s`. A pass up to
  `max_gap_s` before the window counts, so a gap is measured from the last pass, not from `from`.
- Every finding carries every key: `overlap_s` is `null` except on `station_double_booked`, and
  `station` is `null` on `coverage_gap`.
- `fix` is always `null` for now: proposals (another station, an opportunity) need a provider
  search. Show the problem and `Open in Plan`.
- Header counts: `counts.conflicts` (double-bookings + outage bookings), `counts.gaps`.
- `truncated: true`: the passes read hit its 500-row cap; narrow the window.
- Refetch on `invalidate` with `contacts` or `stations`.

### Contact drawer D2 actions: `Release` and `Swap station` (BACKLOG §8)

- **`Swap station`: hidden** (ux). K2 re-plans only lost bookings and keeps committed passes
  locked (S8), so it can't replace a healthy booking. A "replace this booking" operation is
  backlog with the director; until then there's no endpoint and no control.
- **`Release`** cancels the booking at the provider (danger confirm).
  - Pass rows gain `provider_revision` (integer) and `releasable` (boolean). `releasable` is true
    when `state` is `pending | confirmed | active` and the viewer may cancel bookings
    (organization admin, `:manage_missions`, as for the contact workspace's cancel). Members don't
    see the button; D2 shows "Org admins can release a booking." (ux).
  - `POST /api/console/v1/missions/:mission_id/passes/:id/release` with body
    `{"expected_provider_revision": <the row's provider_revision>}`. The server builds the
    cancellation evidence from the stored booking; a different revision means the provider
    changed it, so reload.
  - Returns `{data: <pass row>}` after the provider answers. `state` is `canceling` or
    `canceled`, and `ended_by` is the viewer.
  - `502 provider_cancel_failed`, `details: {outcome, reason, state}` (domain 4b18d046):
    - `outcome: refused | not_sent`: the cancel didn't happen and the booking is back in `state`
      (as before). Say "Nothing changed: <provider> refused the cancel" or "the cancel wasn't
      sent".
    - `outcome: unknown`: `state` is `unknown` until the provider's next answer settles it. Say
      it's unclear.
    - A `pass_release` attention item follows in Now and on the pass row (domain 548b8dd9):
      `conflict: cancel_failed`, `attention.release: {outcome, reason}` (`null` on other
      sources), no acknowledge. It stays open until the booking is canceled or ended, or the pass
      ends. `invalidate` `contacts` also invalidates `attention`, because that settle publishes
      only `contacts`.
  - Other errors:
    - `409 pass_changed`: revision mismatch; `details.pass` is the current row, so D2 reloads it.
    - `409 pass_not_releasable`: not `pending | confirmed | active`, or no provider contact ref.
    - `403 forbidden`, `404 pass_not_found`.
    - `422 invalid_params` (`details.expected_provider_revision`), `422 actor_not_assignable`.
  - Refetch on `invalidate` `contacts`.
  - An **off-plan** booking (L15) may be released by its booker as well as by organization admins
    (`releasable` says which, per viewer; todo(authz)).

### Book a pass: single bookings (§11 L15, DECISIONS #78)

Passes booked outside any plan. They're fixed occupancy: drafts and repairs plan around them and
never count them toward a requirement.

- A16b `GET /single-bookings/routes?spacecraft_id=` → `{spacecraft {id, name}, routes: [{key, name,
  provider {id, name}, transport {id, version, name}, service_name, station {ref, id, code, name} |
  null, uplink: true | false | null}], not_ready: [{code, message}], limits: {max_window_s,
  max_reach_s, reach_until}}` (`operate_mission`). `routes` are the spacecraft's ready routes, the
  set the search fans out over. `name` is the routing rule's name (the path label). `station` is set
  only when the route PINS one (its rule's station, else its transport's); `null` = the provider
  picks among its stations and each offer names its own. `uplink`: pinned → whether the spacecraft
  has a primary uplink path at that station via the provider; unpinned → `false` when it has none
  via the provider, `null` when it depends on the station (offers' `uplink_capable` decide).
  `limits`: the 7-day window, and how far ahead a search may reach (`max_reach_s`, server-set,
  default 14 days; `reach_until` = now + that). `404 spacecraft_not_found`.
- `POST /single-bookings/search` `{spacecraft_id, from, to, direction: "downlink" | "uplink",
  station_ids?, route_keys?}` (A16b `route_keys`: 1 to 50 route keys from `/routes`, searching only
  those; omitted = every ready route. A key that isn't ready now → `422 invalid_params`
  `details.route_keys`. A `to` past `reach_until` → `422 invalid_params` `details.to` "Search up
  to …") → `{spacecraft {id, name, scid}, window {from, to}, offers: [{id, token,
  expires_at, starts_at, ends_at, station {ref, id, code, name}, antenna {id, label} | null,
  provider {id, name}, availability, uplink_capable, synthetic, cost, overlaps {reservation_id,
  spacecraft {id, name}, station_code, starts_at, reason: same_spacecraft | same_antenna} |
  null, listener_overlap}], hidden {no_uplink_route}, not_ready: [{code, message}], truncated}`.
  `listener_overlap` as on a pass above (#361), against the mission's booked passes (offers are
  alternatives, never checked against each other); booking it is still allowed. The server fans out
  over the spacecraft's ready routes; route keys and evidence ride inside the signed `token`.
  `station.id`, `code` and `name` are `null` when the provider's station matches no Cadence
  station (`ref` is always set). `overlaps` covers every live booking, plan or not. No ready route
  is `offers: []` with `not_ready` saying why, not an error. Errors: `422 invalid_params` on the
  field (window in the past, over 7 days, end before start), `404 spacecraft_not_found`, `503
  search_unavailable` (every route's provider search failed).
- `POST /single-bookings` `{token, note?}` (note ≤ 500) → `{outcome: confirmed | requested |
  unconfirmed | rejected, reason, reservation_id, provider_reference, pass}`. Idempotent per booker
  and token: a retry returns the booking already asked for. It waits up to 3 s for the provider's
  first answer; `requested` settles over the `contacts` invalidation. `reason` is the K1 reason
  code. `pass` is the `/passes` row with `off_plan`, or `null` when rejected **or** while the
  provider job hasn't written the reservation yet (the bar appears on the next `contacts`
  invalidation). Errors: `409 opportunity_expired` ("Search again."), `409 route_changed`, `422
  token_invalid`, `422 invalid_params` (`note`), `403 forbidden`.
- Pass rows carry `off_plan: {booked_by {kind, id, name}, booked_at, note} | null` (`null` for
  plan bookings). Release is `POST /passes/:id/release` above.

## S10: `contacts` invalidation

`invalidate` with `contacts` fires when a scheduled or realized contact or a contact action is
committed (relayed from `Cadence.Contacts.Facts` by `CadenceWeb.Console.ContactChanges`), and on
the `:contacts_changed` read update, which every `ProviderReservations` writer publishes after
commit (domain `db8c9953`), so reservation-only transitions (for example `requesting → rejected`)
invalidate too.

### `contact_plans`

`invalidate` with `contact_plans` fires after commit when (`ContactPlanning.PlanUpdates`):

- a contact plan is created, gets a new version, or is submitted, approved or rejected;
- its execution projection changes (`executing`, `reserved`, `partially_reserved`, `failed`),
  including a booking the provider settles later (5b49faeb);
- a fleet planning run (draft or repair) is created, advances a phase, fails or is canceled;
  draft and execute progress (`scheduling_progress`) also mark it;
- a requirement or template is created, versioned, closed, canceled, activated or paused, since
  that can supersede a draft (`superseded` is computed on read);
- a placed booking passes the #52 confirmation window, so a plan can turn `unconfirmed` by time
  alone. This one is scheduled when the booking is placed. It's best effort: it doesn't survive a
  server restart, so refetch on reconnect.

Writes inside a transaction publish about a second later, after the commit. The channel
debounces bursts (500 ms). Refetch plan lists, plan detail and draft/repair reads on it; there's
no need to poll.

## Station availability (S7)

Over domain's `Cadence.Comms.StationAvailability` and `Cadence.Reads.StationImpact`
(`docs/apogee/domain/station-availability.md`). Station ids are api's
`GET /ground-stations` ids. Refetch on `invalidate` with `stations` (and `contacts`; every window
change publishes both).

- `GET /station-availability?at=` (default now) → `{at, stations: [status]}`, one row per station.
- `GET /station-availability/:station_id?from&to` (default now → +7 d, ≤ 31 d) →
  `{status, from, to, windows: [window]}`.
- `POST /station-availability/:station_id/windows` `{kind: outage | maintenance | degraded,
  starts_at, ends_at?, eta?, reason?, detail?}` → `201` window. Operator-entered
  (`source: operator`, `reported_by` = you).
- `POST /station-availability/windows/:window_id/clear` `{reason?}` → the window with `cleared_at`.
- `GET /station-availability/:station_id/impact?from&to` → `{ground_station_id, from, to, passes_hit,
  reservation_ids, spacecraft_ids, plans: [{id, version}], truncated}`. `plans` are the contact plan
  revisions that booked the hit passes (start a repair, S8, from them). `lost: {count, reservation_ids,
  spacecraft_ids, plans}` lists bookings at the station in the window that already ended without a
  pass (`canceled`, `rejected`, `failed`), for example ones a provider canceled because of the outage.
  Those are the ones K2 re-plans: live bookings at that station in the window (K2's
  "passes hit"). Reservations that never named a station can't be attributed and aren't counted.

```json
status = {"ground_station_id": "gs-…", "state": "up | degraded | down", "since": null, "eta": null,
          "source": "operator | provider | simulator | null", "reported_by": {…} | null,
          "reported_at": null, "basis": "no reported windows", "windows": [window]}
window = {"id": "station_window_…", "ground_station_id": "gs-…", "kind": "outage | maintenance | degraded",
          "from": "…", "to": "…" | null, "eta": "…" | null, "source": "operator | provider | simulator",
          "reported_by": {…}, "created_by": {…}, "reported_at": "…", "reason": "…" | null,
          "detail": {}, "cleared_at": null}
```

- `state`: `down` while an outage or maintenance window is active; `degraded` while a degraded one
  is; `up` means **nothing is reported**, not live telemetry. Say so (`basis`).
- `eta`: when it's expected back (`to`, or the reported ETA). `null` when unknown; never guess.
- `status.windows` lists active and upcoming windows (7 d).
- Provider-reported windows come from provider sync. A window the provider stops reporting is
  cleared. The simulator fault `station_outages` produces `source: simulator` windows.

Errors: `422 invalid_params` / `invalid_window`, `404 station_not_found` / `window_not_found`,
`409 window_overlaps` (same kind, same station) / `window_cleared`, `403 forbidden`.

## Pass review (S9, K3 "Close the books")

Over domain's `Cadence.Reads.PassReview` (`docs/apogee/domain/pass-review.md`, "As built";
DECISIONS #47/#48). One result per booked pass, filled by provider results and a once-a-minute
close-out. Refetch on `invalidate` with `pass_results`.

Window (all three reads): `from`/`to` (ISO-8601, ≤ 31 d), **or** `day` (`YYYY-MM-DD`, default today
UTC) + `span` (`day | week | month`, default `day`; `daily` defaults to `month`), ending at the close
of `day`. Optional `plan` (contact plan id) narrows to one plan.

### `GET /pass-review` (h1, stat strip, R1, R2, freshness)

`{from, to, planned, realized, partial, missed, failed, canceled, pending_count, realized_ratio,
threshold, target, provisional, missed_by_owner, partial_by_owner, by_station[], by_cause[], plans[],
volume, freshness[]}`:

- `realized_ratio = realized / (planned − canceled − pending_report)`. `null` when nothing counts yet.
- `threshold` is `pass_realized_threshold` (a pass counts as realized when flown ≥ that share of
  planned, default 0.95). `target` is `realization_target` (the fleet's target share, the h1 verdict
  and R3 line, default 0.98). Both are mission settings (ST1).
- `provisional: true` when any pass in the span awaits its provider report or a provider's event
  cursor is unhealthy. Say the % is provisional, in words.
- `missed_by_owner` / `partial_by_owner`: `{provider, us, weather, unknown}` counts (the strip caption),
  every key always present. `missed` **includes** `failed` (as on the strip); `failed` is also given alone.
- `volume` ("Downlink: received vs provider-reported"): span totals `{provider_bytes,
  provider_frames, received_bytes, received_frames, provider_reported_passes, received_known_passes}`.
  A total is `null` when no pass in the span has that figure; the `*_passes` counts say how many
  passes contributed it (unknown volumes are null, not 0).
- `by_station[]` (R1): station identity, provider, planned, realized, partial, missed, failed,
  canceled, flown and planned seconds. There's no billing, so billed minutes are absent.
- `by_cause[]` (R2): `{cause, cause_source, owner, missed, partial}`.
- `freshness[]` (h1 meta): per provider `{provider_id, provider {id, name, account_id} | null,
  last_report_at, pending_reports, oldest_pending_los, cursor_healthy}`. `cursor_healthy` is
  `null` when the provider's account has no event cursor; `provider` is `null` for a provider the
  mission no longer lists. Elsewhere in pass review `provider` is also `{id, name, account_id}`.

### `GET /pass-review/rows` (R4)

Query: the window, `outcome` (comma list of `realized | partial | missed | failed | canceled |
pending_report`; R4 uses `missed,partial`), `station`, `spacecraft_id`, `plan`, `limit` (1–500,
default 50), `cursor` (`next_cursor`). Returns `{from, to, rows[], total, disputable, next_cursor}`
(`next_cursor` is also in `meta`). For the footer, use "SHOWING n OF total · disputable DISPUTABLE".

Row: `{id, spacecraft {id, name}, station {ref, id, code, name}, provider {id, name}, antenna_ref,
plan {id, version} | null, planned_aos, planned_los, actual_aos, actual_los, planned_seconds,
flown_seconds, planned_bytes, provider_bytes, provider_frames, received_bytes, received_frames,
observations, outcome, cause, cause_source, owner, disputable, provisional, provider_reported_at,
realized_contact_id, scheduled_contact_id}`.

- Two volumes, never merged: `provider_*` is what the provider says it delivered, and `received_*` is
  what Cadence ingested. `received_*: null` means unknown (never realized), not 0. `planned_bytes`
  is `null` unless the provider supplies a number, so show received vs provider-reported, not "vs plan".
- `owner`: `provider | us | weather | unknown`. `disputable` = owner is the provider (show `Dispute`).
  A provider-reported station window counts as the provider's; an operator-declared one counts as ours.
- `provisional`: no provider report yet.
- `station` is all `null` (`ref` too) when the pass result has no ground station ref.

### `GET /pass-review/daily` (R3)

`{from, to, days: [{day, planned, realized, realized_ratio, top_cause, top_station, …}], target,
threshold}`.
Draw `target` as the dashed line. `top_cause`/`top_station` annotate dips.

Money (R5, disputes in $) is out of scope: no provider reports prices.
