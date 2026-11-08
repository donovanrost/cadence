---
title: Inspect Uplink Session Readiness
tags: [how-to, operations, commanding, providers]
status: active
created: 2026-10-27
updated: 2026-10-28
---

# Inspect Uplink Session Readiness

Real TCP uplink now starts blocked, including on reconnect and provider/transport
restart. Capture may remain active while uplink is blocked. The default policy
qualifies no provider: a connected socket, active path, or ready mission partition
does not enable sending. Provider-less protocol simulation has no physical
provider delivery and does not grant a TCP session readiness.

Inspect `provider_runtimes[*].uplink_session` and
`transport_runtimes[*].uplink_session` in the existing path runtime snapshot.
Snapshots report status, blocking reason, resource/connection identity, basis
hash, and pending delivery count when a session is attached. A transport that has
not attached yet reports `session_not_attached`; a disconnected provider reports
its connection/gate blocking reason. An attempted admission or explicit session
review attaches the transport to its current provider connection. A newly
registered transport invalidates shared readiness.

Declare a canonical `uplink_resource_id` in TCP provider configuration. Use the
same identity wherever bindings share the actual exclusive external uplink
resource. Missing identity blocks sending. Two live connections claiming that
resource within one Runtime root invalidate readiness and reject the second
registration; this phase does not implement multi-path socket sharing. Across
roots or nodes, the provider policy must enforce external exclusivity.

## Trusted qualification boundary

`RootComposition.new!/1` and `from_application/1` accept an explicit
`uplink_session_policy` module dependency, captured at root startup. The default
`Cadence.Runtime.SessionQualification` supports no provider. This dependency is
trusted runtime code, not a request parameter or an operator risk-acceptance
switch. There is no HTTP route or generic ready flag.

A provider-specific implementation must verify these callbacks against actual
provider/peer evidence and the supplied exact resource/connection/configuration
basis:

- `verify_fencing(basis, evidence)` proves the previous sender is externally
  fenced, including the provider's treatment of buffered/in-flight old data.
- `verify_recovery_exchange(basis, fencing, exchange, evidence)` permits one exact
  recovery operation, purpose, provider binding, and payload. It cannot grant
  unrestricted command delivery.
- `verify_protocol_recovery(basis, fencing, evidence)` proves the applicable
  protocol state is restored or resynchronized and outstanding effects reconciled.

Callbacks must be bounded and must not call the gate recursively. Production
implementations are still pending. The test policy in `test/support` is only a
fixture, not a qualification of raw TCP or spacecraft protocol recovery.

## Runtime recovery interface

`Cadence.Runtime.TransportRuntime` exposes the internal receiver-owned interface:

1. `session_review(runtime)` returns the current session basis. It may attach a
   previously unattached transport; registration itself grants no readiness.
2. `begin_session_recovery(runtime, fencing_evidence)` verifies fencing and enters
   `recovering`. Ordinary commands remain blocked.
3. Review again: fencing changes the recovery generation. Each evidence map needs
   atom keys `:basis_sha256`, `:reference`, and `:valid_until` (a UTC `DateTime`).
   The expiry must be in the future and at most five minutes away. The policy
   must verify that the claimed expiry is supported by external evidence.
4. If the qualified recovery procedure needs wire exchanges, construct an exact
   `%Cadence.Runtime.RecoveryExchange{operation_id: ..., purpose: ...,
   provider_binding_id: ..., provider_adapter_key: ..., payloads_base64: ...}`.
   `permit_recovery_exchange(runtime, exchange, evidence)` returns an opaque,
   short-lived, one-use permit; `recovery_exchange(runtime, exchange, permit)`
   delivers only that exchange. Changed bytes/purpose/identity are rejected.
   Reissuing a consumed operation ID cannot authorize another send. Recovery
   payloads are bounded to 64 KiB and 256 payloads per exchange.
5. `complete_session_recovery(runtime, protocol_evidence)` verifies recovery and
   enters `ready`. Ordinary command admission is then permitted for that exact
   runtime/session generation. Expiry uses the earlier fencing/recovery deadline.
6. `block_session(runtime, reason)` revokes local readiness and queued permits.
   Its result reports still-pending deliveries; it is not proof of external
   revocation or non-delivery. Fresh proof is required to recover again.

Admission tokens are consumed when an interaction finishes, including failed
framing; a completed request cannot reuse its admission. Blocking or beginning
recovery cancels prior runtime timers. Completing recovery does not rearm those
timers; a future qualified protocol-restoration path must recreate appropriate
deadlines explicitly.

A replaced connection requires fresh transport registration/recovery; this phase
fails closed on the old handle rather than silently rebinding old protocol state.
A transport restart, gate loss, quiescence, changed membership/configuration, or
evidence expiry invalidates readiness. Late work cannot inherit a replacement's
permission. Read-only observations can continue, but any generated send must
pass the current gate. TCP checks before each payload in a multi-payload delivery.

## Failure behavior and remaining work

Command release obtains admission before creating its durable attempt. A blocked
session leaves the queue entry pending and request queued. After a claim exists,
ambiguous failure keeps existing attempt/lane-hold semantics. Direct adapter
calls without a valid exact delivery permit are rejected, even when connected.
Returned delivery failures or state-persistence failures after delivery block
further sends; runtime death also invalidates readiness through monitoring.

Physical sends now require durable preparation in the existing transport action
table before any socket write. This includes retransmissions, bypass frames, and
recovery exchanges. Optional runtime-history settings cannot disable preparation.
`TransportRuntime.session_review/1` also returns `transport_sends`, up to 100 recent
preparations, with exact frame bytes, stable frame identities, original attempt
links, session basis, and before/after protocol state. Protocol state includes an
external-term base64 evidence snapshot; it is not automatically deserialized or
restored. Ordinary transport history and provider delivery metadata reference the
preparation ID. Prepared records have no verifier acceptance signal.

Send status is `prepared`, `sending`, `local_write_completed`,
`transport_committed`, or `unknown`. Only `transport_committed` means the local
write and resulting transport records completed. It does not mean the provider or
spacecraft accepted the command. Every other status is potentially sent and
blocks ordinary sends and completion of session recovery, even after a process or
gate restart. Failure to save an uncertainty observation cannot erase that hold.
A replacement transport also remains blocked with `protocol_state_restore_required`
when prior ordinary sends require restoring its counters and protocol state.

Versioned COP-1 checkpoint export and blocked installation are implemented:

```elixir
{:ok, checkpoint} = TransportRuntime.export_protocol_checkpoint(runtime)
# After a restart, discover a complete durable basis without installing it:
{:ok, checkpoint} = TransportRuntime.latest_protocol_checkpoint(replacement)
{:ok, installed} = TransportRuntime.restore_protocol_checkpoint(replacement, checkpoint["checkpoint_id"])
# installed.status == :installed_pending_reconciliation
```

Use these internal Runtime APIs only with a correctly scoped runtime. An export
requires attached COP-1 and complete durable runtime history. Supported sessions
also checkpoint automatically in the same transaction as transport records and
send confirmation. Existing external-term snapshots are not importable
checkpoints. Version 1 requires exact scope/configuration and clock compatibility,
validates the complete predecessor/evidence chain and send/observation basis,
and rejects stale proposals. Do not select a checkpoint from the limited 100-row send review.
Checkpoint/predecessor retention is currently required; there is no automatic
migration, replay, or reclamation.

Restoration revokes admission before validation. It installs exact protocol state
only after recording the validated installation durably; repeated installation of
the same checkpoint in one unchanged runtime/session basis is idempotent. A durable
`committed_pending_installation` marker is not proof that a process installed
state; only the live snapshot reports `installed_pending_reconciliation`.
Inspect `protocol_restoration` in the runtime snapshot for the installed checkpoint/revision and unarmed timer
intents. Expired deadlines are reported at installation, not fired. An invalid
checkpoint or failed durable installation leaves the runtime blocked without
installing the requested state. A process restart still requires a new blocked
installation; it cannot inherit a prior runtime's authority.

Direct/bypass modes and pending BC/BD directives/wait-queue requests are unsupported
in this initial version. Frame acknowledgement, provider acceptance, and command
execution remain distinct. Provider-specific reconciliation, protocol exchanges,
reset/initialization policy, and readiness qualification remain unimplemented.
There is no automatic resend or hold-clearing override. Resolving a command
attempt does not resolve a shared stream's prepared sends, and installing a
checkpoint does not clear either hold or permit ordinary work. Qualified
recovery-only exchanges may collect evidence while ordinary work remains blocked;
their prepared operation IDs cannot be blindly repeated, including after gate
restart. Do not edit send statuses, delete history, or reset counters to clear holds.

See the [restoration foundation and remaining recovery contracts](../multi-node-runtime-plan.md#versioned-cop-1-checkpoints-and-blocked-restoration-implemented-foundation).
Automatic takeover remains blocked until a concrete provider's external fencing
and recovery path has been qualified across real nodes; simulator success alone
does not qualify it.

External fencing is required to stop an isolated old sender or settle its already
admitted writes. Journal replication and cross-node journal handoff remain
outside scope.
