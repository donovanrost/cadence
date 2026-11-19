# Resolving unconfirmed bookings (DECISIONS #52–#54)

## When a booking is unconfirmed

Plan execution places each pass with the provider. If the provider hasn't answered, the item is
`uncertain` and the plan keeps `executing`; it settles by itself when the provider confirms
(`BookingOutcomes.booking_settled`). Past the confirmation window
(`:provider_confirmation_window_ms`, 10 min, counted from placement `started_at`) the plan reads
`unconfirmed` (`Scheduling.plan_state`) and the item can be resolved by an operator.

## Resolving (`Contacts.BookingResolutions.resolve/6`)

Organization admins only (`:approve_contact_plans`). Every resolution writes one
`booking_resolutions` row: the audit entry (actor, note, provider reference, the provider's last
answer) and, later, any conflict.

1. **Re-read the provider first** (`ProviderReservationReconciler.reconcile_reservation`). A
   decisive answer (confirmed, active, completed, rejected, failed, canceled) settles the item
   from that answer; outcome `provider_answered`, nothing attested.
2. **Mark booked** (provider reference and note required). The reservation keeps the provider's
   lifecycle (`pending`) and carries `metadata.operator_resolution`; that makes it materializable,
   so the scheduled contact exists with `metadata.booking_evidence = "operator_attested"`. Per #46
   D1 it has no `:command_window`: its uplink reads `"uplink unconfirmed"` until the provider itself
   confirms the leg. The item becomes `reserved`; outcome `attested`.
3. **Mark not booked** (note required). The decision and the reservation marker are written first,
   then Cadence sends the provider cancel, then the item fails with `operator_not_booked`. That
   feeds repair like `booking_lost`. Outcome `not_booked`.

## Later provider answers (`provider_answered/1`, `provider_answer_refused/4`)

Checked only for reservations carrying `operator_resolution`. Nothing is ever re-booked silently.

| Resolution | Provider later says | Result |
| --- | --- | --- |
| attested | confirmed / active / completed | answer recorded; an open conflict resolves (by the provider) |
| attested | canceled / failed / rejected | conflict `contradicts_attestation`; the item fails `booking_lost` and the contact is canceled |
| not booked | confirmed (cancel had failed) | conflict `late_confirmation`; the pass is **not** scheduled |
| not booked | confirmed (after our cancel) | the transition is refused (canceled is terminal); conflict `late_confirmation` |
| not booked, cancel failed | canceled | `cancel_failed` resolves (by the provider, action `canceled`) |

A failed cancel raises `cancel_failed` at once.

## Attention (`Reads.Attention`, #54)

Mission-level "needs acknowledgment" items across sources. `pass_resolution` is the only source
today; another joins by implementing `source/0`, `items/2`, `resolved_since/3` and `counts/2`.

- `load(scope, mission)` returns `items` (open and acknowledged), `resolved` (last 60 s, with
  `resolved_by {kind: user | provider, id, name?}` and `action`) and `counts {open, acknowledged}`.
- `counts(org, mission)` is one grouped query per source, for `/counts`.
- Actions: `BookingResolutions.Attention.acknowledge/3` (stays listed, sorted last) and
  `resolve/4` (closed by a user, with an action text).
- Changes publish `:attention_changed` on the mission's read updates.

Names (spacecraft, station, provider) are resolved by the API layer; the read carries ids.

## Late uplink confirmation (#55, `Contacts.LateUplink`)

When the provider confirms an attested booking **including** its uplink leg (`uplink.status`
`included`), the contact gains the uplink path templates and `:command_window` as a new
scheduled-contact revision (reason `uplink_confirmed`), but only before AOS. After AOS the
confirmation is recorded on the resolution (`provider_answer_document.uplink = "after_aos"`)
and the contact stays as it flew. A confirmation without uplink service changes nothing.

A repeated resolve returns `{:booking_already_resolved, actor}` so the UI can name who did it.
