# L15 single bookings: console endpoints (proposal)

fe-ops, 2026-11-13, for api (cc domain, lead). Spec: ux `screens/Contacts.md` § Book a pass. Backlog §11 L15
(user #75: keep; lead rulings 11-13: off-plan bookings are fixed occupancy for drafts and repairs, not counted
toward requirements; cancel by the booker, else `manage_missions`, todo(authz)). All paths under
`/api/v1/missions/:mission_id`. Problem envelope errors. Invalidation: `contacts`.

## What exists (read of the domain, 2026-11-13)
- `Contacts.SingleBookings` exists with `live/4` only (plan-less live reservations for FleetRepairs).
- `ScheduleCommands.execute(scope, mission, "search" | "reserve" | "cancel", input)`; search and reserve need
  `:operate_mission`, cancel `:manage_missions`.
  - Search is **per route** (`route_key` + `route_evidence`) over `{spacecraft_id, starts_at, ends_at}` (not in
    the past, ≤ 7 days). Opportunities: `id, starts_at, ends_at, expires_at (≤ now + 15 min), availability,
    synthetic, station, antenna, cost, token`. No provider name, no uplink capability, no max elevation;
    60 KB cap with `truncated`.
  - Reserve is by `token` alone, idempotent (identity hashed from the opportunity), and already attaches the
    uplink leg (`UplinkLegs.for_booking`).
- Routes: `ProviderScheduling.list_ready_downlink_routes/3` → `{routes, findings}` (why a route isn't ready).
- Durable status: `ScheduleOperations` (reserve/cancel enqueued; `accepted | unconfirmed | completed | rejected`;
  reconcile re-reads, never resends).
- Console today: only cancel, as `POST /passes/:id/release {expected_provider_revision}` (409 `pass_changed`,
  `pass_not_releasable`).

## Proposed shapes

### `POST /single-bookings/search` (operate_mission)
Body `{spacecraft_id, from, to, direction: "downlink" | "uplink", station_ids?: [id]}`. The server fans out over
the spacecraft's ready routes and merges, so the console never sees route keys or evidence (they ride inside the
signed token).
```
{spacecraft: {id, name, scid},
 window: {from, to},
 offers: [{id, token, expires_at, starts_at, ends_at,
           station: {id, code, name}, antenna: {id, label} | null,
           provider: {id, name}, availability: "available" | "limited",
           uplink_capable: boolean, synthetic: boolean, cost: number | null,
           overlaps: {reservation_id, spacecraft: {id, name}, station_code, starts_at,
                      reason: "same_spacecraft" | "same_antenna"} | null}],   // sorted by starts_at
 hidden: {no_uplink_route: n},          // with direction "uplink", stations left out (ux: "3 stations hidden…")
 not_ready: [{code, message}],          // route findings in words; offers can still come from ready routes
 truncated: boolean}
```
- `uplink_capable`: whether `UplinkLegs.for_booking` resolves for that station and provider.
- `overlaps`: the fixed-occupancy rule (lead 11-13), so the console can disable the row with its reason.
- Errors: `422 invalid_params` (window in the past, over 7 days, unknown spacecraft), `503 search_unavailable`.
  No ready route at all is **not** an error: `offers: []` with `not_ready` explaining why.

### `POST /single-bookings` (operate_mission): reserve
Body `{token, note?}` (note ≤ 500 characters). Idempotent per token: a retry returns the same booking.
```
{outcome: "confirmed" | "requested" | "unconfirmed" | "rejected",
 reason: token | null, reason_message: string | null,    // rejected: the K1 reason table's keys
 provider_reference: string | null,
 pass: <the /passes row> | null}                          // null only when rejected
```
- Waits for the provider's first answer up to a few seconds, then returns `requested` (the bar shows as
  requested and settles over `contacts` invalidation, like plan bookings).
- Errors: `409 opportunity_expired` (gone or past its token expiry: "Search again."), `409 route_changed`,
  `422 token_invalid`, `403 forbidden`, `503` → the console says "unclear" and offers Try again.

### The `/passes` row gains `off_plan` (plan bookings: null)
```
off_plan: {booked_by: {id, name} | null, booked_at, note: string | null} | null
```
D2/D3 tag OFF-PLAN; D2 reads "Booked outside a plan by Mira K. at 02:10Z: “note” · doesn't count toward contact
rules." `releasable` stays the per-viewer answer (booker or org admin for off-plan).

### Release: the existing `POST /passes/:id/release`
Same verb for both kinds (ux). For an off-plan booking the booker may release it, else `manage_missions`
(todo(authz)). `409 pass_changed` carries `details.pass` (the current row) so D2 reloads ("This booking changed
since you opened it. Review it, then release again.").

### Timeline
A `contact` event "Booked outside a plan: EARENDIL-312 · SVA 03:10Z" with the note in `detail`, and the actor.

## Error vocabulary
Lead's closed set maps onto the console codes above: `route_not_ready` → `not_ready[]` (not an error),
`route_changed`, `opportunity_expired` (← `opportunity_expired_or_unavailable`, `expired_opportunity_capability`),
`token_invalid` (← `malformed_opportunity_token`, `invalid_opportunity_capability`, `opportunity_scope_mismatch`),
`search_unavailable`, `booking_changed` (← console `pass_changed`), `not_cancellable` (← `pass_not_releasable`),
`forbidden`. Say if you'd rather rename the existing pass codes to the facade's names; the console reads either.
