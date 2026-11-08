---
title: Resolve Uncertain Provider Effects
tags: [how-to, operations, commanding, providers]
status: active
created: 2026-10-27
updated: 2026-10-27
---

# Resolve Uncertain Provider Effects

Use the Control APIs to record evidence against an existing command release
attempt or provider reservation. Resolution does not transmit or resubmit work.
Apply the `20261027000000_add_attempt_resolution_evidence` migration before using
these APIs. There are no new HTTP routes or operator screens.

The caller needs an authenticated `Cadence.Auth.Scope` with mission administration
and operation authority. Organization and mission scope are checked before any
record is read or changed. Actor identity and recording time are generated from
the authenticated scope; they cannot be supplied in the evidence.

## Review and resolve a command attempt

First review the exact original attempt. Inspect the encoded bytes, target,
request, model revision, existing evidence, and applicable session incarnation.
Obtain a provider receipt, protocol acknowledgement, or reviewed operator evidence
for that operation. A local socket write alone does not establish acceptance.

```elixir
alias Cadence.Control.Commanding

{:ok, review} =
  Commanding.review_release_resolution(scope, mission_id, attempt_id)

evidence = %{
  "resolution_id" => "incident-123-observation-1",
  "basis_sha256" => review.basis_sha256,
  "outcome" => "unknown",
  "source" => "operator_evidence",
  "reference" => "incident/123/evidence/1",
  "observed_at" => "2026-10-27T12:00:00Z",
  "session_ref" => "original-provider-session-incarnation",
  "note" => "Receipt unavailable; delivery remains unknown"
}

{:ok, result} =
  Commanding.resolve_release_attempt(scope, mission_id, attempt_id, evidence)
```

`observed_at` must be an actual observation time in UTC, no later than the current
time. Evidence uses JSON string keys. Use a stable `resolution_id` for retries of
the same observation: identical retries return the recorded disposition without
repeating completion. Changing evidence under the same ID returns
`:resolution_id_conflict`; new evidence needs a new ID. A changed immutable basis
returns `:command_resolution_basis_changed` and requires a fresh review.

Supported outcomes:

| Outcome | Command behavior |
| --- | --- |
| `unknown` | Persist `release_uncertain`; keep the original request queued and lane held. |
| `accepted` | Complete the original attempt and create its original revision's verifiers once. Require `acceptance_stage` of `provider_acceptance` or `protocol_acceptance`. Acceptance does not establish execution or verifier success. |
| `not_sent` or `rejected` | Fail the attempt and cancel its queue entry and request; never automatically resend or requeue. Any new operation needs normal authorization and admission. |

If the original verification basis is unavailable, accepted evidence is retained
with disposition `held_verification_basis_unavailable`; the lane stays held.
Terminal outcomes are preserved. Late contradictory evidence is appended with
`contradictory`, without overwriting established success or failure.

Every command observation requires `session_ref` identifying the applicable
original session. This is an audited assertion by the authorized resolver;
Cadence does not independently validate the receipt or contact the provider.

## Resolve a provider reservation

```elixir
alias Cadence.Control.Contacts

{:ok, review} =
  Contacts.review_provider_reservation_resolution(scope, mission_id, reservation_id)

{:ok, result} =
  Contacts.resolve_provider_reservation(scope, mission_id, reservation_id, %{
    "resolution_id" => "incident-456-provider-query-1",
    "basis_sha256" => review.basis_sha256,
    "outcome" => "accepted",
    "acceptance_stage" => "provider_acceptance",
    "source" => "status_query",
    "reference" => "incident/456/provider-query/1",
    "observed_at" => "2026-10-27T12:00:00Z",
    "provider_response" => %{
      "client_reference" => review.reservation.idempotency_key,
      "provider_contact_ref" => "provider-contact-456",
      "status" => "confirmed"
    }
  })
```

Supply the provider's actual response and operation correlation. Acceptance must
match the original idempotency key through `client_reference`, or the already
known provider contact reference. Supplied identifiers must not contradict any
known identifier. Supported accepted statuses are `pending`,
`confirmed`, `scheduled`, `acquiring`, `active`, `completed`, and `canceled`.
Existing provider status validation and Contact materialization still apply.

Unknown outcomes remain unresolved. Definitive non-delivery can close an
unconfirmed booking. If a provider contact is already known or a booking is
pending/canceling, non-delivery evidence is recorded as
`held_provider_status_required`: a failed cancellation does not prove the booking
failed. Obtain correlated provider status. Established terminal booking outcomes
are retained, with contradictions audited for review.

## Evidence limits and recovery boundaries

Sources are `provider_receipt`, `protocol_ack`, `operator_evidence`, `status_query`,
and `timeout`. Timeout evidence can only say `unknown`. Each observation needs a
nonempty external `reference`. Payloads are limited to 64 KiB and each record to
200 observations; exceeding the limit rejects the entire transaction, including
any completion. Audit entries live on the existing attempt/reservation records.
Ordinary save operations cannot replace them.

These APIs are an administrative resolution boundary, not automatic provider
failover. They neither acquire external send authority nor restore protocol
state. Automatic uplink takeover remains gated on verified session fencing and
protocol recovery. Node-local journals remain bounded buffers; resolution does
not replicate or hand off their contents.
