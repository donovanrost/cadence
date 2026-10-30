# Reconcile prepared physical sends

Use `Cadence.Control.Commanding.review_prepared_send(scope, mission_id,
preparation_id)` and `reconcile_prepared_send(scope, mission_id, preparation_id,
attrs)` from an authenticated mission administrator or authorized service. These
are application APIs; no HTTP routes are added.

Review returns `basis_sha256`, a versioned hash manifest, the selected preparation,
all prepared sends on its resource, and exact `frame_occurrences`. It reads the
complete durable stream history, without the operational review's 100-row limit.
The basis includes original attempt records, send bytes and counter transitions,
session/configuration provenance, transport observations, timers, checkpoint
revisions and restoration markers, and preceding reconciliation audits.

Submit string-key attributes:

```elixir
%{
  "resolution_id" => "investigation-123/frame-review-1",
  "basis_sha256" => review.basis_sha256,
  "source" => "operator_evidence",
  "reference" => "incident/123/receipt",
  "evidence_sha256" => receipt_content_sha256,
  "session_ref" => review.preparation.metadata["incarnation"],
  "observed_at" => DateTime.to_iso8601(observation_time),
  "frames" => [
    %{"ordinal" => 0, "frame_id" => original_frame_id, "outcome" => "unknown"}
  ]
}
```

Each frame claim identifies an occurrence within this preparation. Copy its
ordinal and frame ID from review; equal bytes, frame hashes or sequence numbers
across different preparations do not establish that they are the same logical
frame. Partial batches are allowed. Never infer completion of a multi-frame
command from one preparation or acknowledgement.

Outcomes are `unknown`, `not_sent`, `rejected`, `protocol_acknowledged`, and
`outstanding`. Rejection requires `acceptance_stage` of `provider_acceptance` or
`protocol_acceptance`; acknowledgement requires `protocol_acceptance`. Outstanding
records an observation, **not permission to retransmit**. There is no command
execution outcome here. Sources are `operator_evidence`, `provider_receipt`,
`protocol_ack`, `status_query`, or `timeout`; timeout can only support unknown.
Observation times must be UTC and cannot be in the future. Optional `note` is
bounded. Caller-supplied actors, dispositions and review manifests are rejected.

For evidence in `Cadence.GroundNetworks.ProviderEvidenceStore`, optionally supply
`provider_evidence_id`; the API verifies organization scope and the stored content
hash against `evidence_sha256`. An external reference/hash without this ID is an
administrator's attestation, not a receipt fetched or independently verified by
Cadence. Keep secrets out of references and notes. A stored receipt alone does not
prove provider/session correlation or fencing.

The transaction serializes resource audits and locks existing prepared sends.
A changed basis returns `:stale_reconciliation_basis`; review again. Exact retries
of the same resolution ID and payload return the original audit entry, even after
later observations. Reusing that ID with changed evidence returns
`:resolution_id_conflict`. IDs are scoped to the preparation. Each preparation
retains up to 200 entries; reaching the limit rejects further submissions without
removing evidence.

Audit entries live in `transport_action_requests.reconciliation_evidence`. They
contain the server-derived actor/time, submitted evidence, full hash manifest,
and disposition. Local `send_status`, request bytes, and counter snapshots remain
unchanged, so audit writes do not invalidate existing protocol checkpoints.

Unknown, partial, uncorrelated, and contradictory evidence is retained with a
corresponding held disposition. Contradictory claims never overwrite earlier
interpretations. Fully correlated claims are recorded as
`recorded_pending_qualified_recovery`; this is an audited interpretation, not a
provider qualification or a protocol-state transition.

All existing lane and stream holds remain in force. Any audited preparation also
conservatively holds its stream, including locally committed sends, until qualified
recovery can apply an explicit validated revision. This API does not complete or
cancel attempts, publish verifier signals, replay frames, advance counters, arm
timers, issue permits, or grant session readiness. Use the existing separately
reviewed uncertain-attempt resolution contract when sufficient command-level
evidence exists. Provider-specific interpretation, logical-frame correlation
across retransmissions, validated recovery commit, and external session fencing
remain required before automatic uplink takeover can be qualified.
