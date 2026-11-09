# S9 · Pass results (feeds K3 "Close the books")

Owner: **domain**. Status: **draft for review** (2026-11-09). Reviewers: director, api-ops,
fe-setup (K3, DECISIONS #43). `L` = `apps/cadence/lib/cadence`.

## Why

K3 needs, per contact, the planned window, actual AOS/LOS, minutes flown, downlink volume
against plan, an outcome, and a cause. Today none of that is persisted on Cadence records:

- actual AOS/LOS exist only inside a reservation's provider evidence;
- volume isn't stored at all;
- the provider's contact result (`GET /provider/v1/contacts/:id/result`, event
  `contact.result_updated`) is never fetched.

"Realized %" without these numbers would be invented. That's why K3 waits on S9.

## Model: one pass result per booked pass

```
contact_pass_results
  provider_reservation_id PK, org, mission, provider_id, scheduled_contact_id,
  realized_contact_id NULL, spacecraft_id, ground_station_ref,
  planned_aos, planned_los                         -- from the reservation (what we booked)
  actual_aos NULL, actual_los NULL                 -- provider-reported
  planned_seconds, flown_seconds NULL
  provider_bytes NULL, provider_frames NULL        -- provider-reported delivery
  observations map                                 -- loss / duplication / corruption / disconnects
  received_bytes NULL, received_frames NULL        -- what Cadence ingested for the realized contact
  outcome  realized | partial | missed | failed | canceled | pending_report
  cause NULL, cause_source  provider | delivery | station | cadence
  provider_reported_at NULL, provider_revision NULL
  closed_at NULL                                   -- set when the provider's result is final
  index (mission, planned_aos), (mission, ground_station_ref, planned_aos), (provider_id, closed_at)
```

**Outcome** is derived, and the derivation is stored with its inputs so K3 can explain it:

| Condition | `outcome` |
| --- | --- |
| reservation canceled or rejected before AOS | `canceled` (not counted against realization) |
| provider says failed, or no AOS before LOS + grace | `missed` (station or provider cause) or `failed` (delivery cause) |
| flown ≥ 95% of planned, and provider bytes > 0 or received bytes > 0 | `realized` |
| flown < 95% of planned, or nothing received while the provider reported delivery | `partial` |
| past LOS, no provider result yet | `pending_report` (provisional) |

The 95% threshold is a mission setting (`cadence.pass_review.realized_ratio`, default 0.95).
Station outages from S7 that overlapped the window become `cause_source: station`.

**Two volumes, never merged.** `provider_*` is what the provider says it delivered.
`received_*` is what Cadence's ingress archive recorded for the realized contact (bytes from
`ingress_archive_evidence_entries.raw_size_bytes`, frames from the protocol archive). K3 shows
both; a large gap is itself a finding (e.g. delivered but not ingested).

## How results arrive

1. **Event path.** `contact.result_updated` is already a known inbox event. The processor calls
   `PassResults.record(reservation)`, which fetches the provider's result through a new
   optional client callback, `fetch_contact_result/3` (simulator:
   `GET /provider/v1/contacts/:id/result`), and upserts the row.
2. **Close-out sweep.** The reservation reconciler's existing loop also closes completed
   reservations that have no result X minutes after LOS. It fetches the result, or marks the
   pass `pending_report` and counts it as a missing report.
3. **Cadence-only fallback.** Providers that report no results still get a row from the
   reservation's terminal state plus Cadence's received volume, with `provider_reported_at: nil`.
   K3 marks those provisional.

Writes publish `:contacts_changed` (and a new `:pass_results_changed`) after commit.

## Freshness (K3 "Provider report freshness / provisional")

`PassResults.freshness(org, mission)` returns, per provider:

- `last_report_at`;
- `pending_reports` (past LOS, no result);
- `oldest_pending_los`;
- whether the event cursor is healthy (`provider_event_cursors`).

## Facade (for api-ops; reads under `L/reads/pass_review.ex`)

```elixir
PassReview.rows(scope, mission_id, from, to, filters)   # per pass, with outcome + inputs
PassReview.summary(scope, mission_id, from, to)         # realized % (realized / (planned − canceled)),
                                                        # by station, by cause, flown vs planned minutes
PassReview.daily(scope, mission_id, from, to)           # R3 30-day series
PassResults.freshness(scope, mission_id)
```

Authorization: `operate_mission`. Money and billing (R5) are out of scope: no provider reports
prices.

## Placement

- `L/contacts/pass_results*`: contacts context; the table is keyed by reservation.
- `L/reads/pass_review.ex`: reads, for aggregates.
- The client callback lives with the provider clients (ground_networks).
- The event hook goes in `Control.Contacts.ProviderEvents`.

## Questions

- **director:** is the 95% realized threshold as a mission setting OK? Should canceled-before-AOS
  passes stay out of the realization denominator? I propose they do: they're K2's concern, not
  realization.
- **fe-setup/api-ops:** does `rows/summary/daily/freshness` cover K3's regions R1–R4 and the h1?
