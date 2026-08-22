# Stage 3 Durable Provider Integration Semantics

- Status: accepted for implementation
- Created: 2026-07-15
- Scope: organization-owned Provider Accounts, durable provider-event ingestion,
  mission delivery policy, reservation changes and approvals, production secret
  handling, and complete provider audit evidence
- Parent design:
  [Contact Scheduling and External Ground Network Simulation](2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)
- Stage 2 baseline:
  [Simulator Provider Contract v1](2026-07-13-simulator-provider-contract-v1.md)
- Implementation plan:
  [Stage 3 Durable Integration Semantics](../plans/2026-07-15-contact-scheduling-stage-3-durable-integration-semantics.md)

## Summary

Stage 3 turns the Stage 2 provider boundary into durable operational
infrastructure. Provider identity and credentials become organization-owned.
Missions receive explicit grants and retain mission-owned delivery policy.
Provider events are authenticated, bounded, sanitized, and stored before they
can affect mission state. Reservation changes are classified against the exact
policy version used for the contact, and material changes require an explicit
operator decision. Every request, observation, policy decision, approval, and
state transition has append-only, secret-free audit evidence.

The simulator remains a separate provider application. Cadence exercises the
same Provider Account, mission grant, event, change, approval, reconciliation,
Transport, and telemetry paths that a commercial adapter must use.

## North Star

> After either process restarts, Cadence can explain which provider account and
> credential version were used, what the provider sent, which policy was
> evaluated, who approved any material change, which execution schedule became
> effective, and why no provider mutation or Scheduled Contact was duplicated.

## Stage 2 Baseline

Stage 2 already provides:

- mission-scoped, versioned `MissionProvider` setup;
- provider-neutral clients and a Simulator HTTP adapter;
- capability, inventory, Service Profile, and Delivery Profile synchronization;
- exact Provider, Transport, Routing Rule, and profile bindings on a durable
  `ProviderReservation`;
- separate Contact, pass, and delivery state;
- status polling as the authoritative reconciliation path;
- native-idempotency and client-reference recovery;
- an end-to-end HTTP control-plane and TCP/CCSDS data-plane proof.

Stage 3 preserves those semantics. It moves shared account configuration above
the mission binding, adds durable ingestion and decisions, and makes accepted
provider changes executable without weakening exact Transport validation.

## Goals

- Share one provider account safely across explicitly granted missions.
- Store only stable, non-secret credential references in Cadence configuration.
- Support secret creation, validation, rotation, revocation, and ephemeral
  resolution through an approved secret backend.
- Ingest polling events durably with restart-safe cursors and an explicit
  quarantine path.
- Reuse the same durable inbox for capability-gated webhook adapters.
- Keep provider events advisory and authoritative reconciliation idempotent.
- Detect reservation changes as explicit, versioned proposals or observations.
- Apply mission-owned delivery tolerances consistently.
- Require explicit approval for material, still-actionable changes.
- Distinguish a rejectable proposal from a provider change that is already a
  fact and can only be acknowledged or mitigated.
- Preserve requested, provider-confirmed, accepted, and actually delivered
  values instead of overwriting one field.
- Produce append-only, organization-scoped audit evidence with mission-scoped
  timeline projections.

## Non-Goals

- Contact Requirements, Contact Plans, or automated fleet planning
- Multi-provider optimization or budget allocation
- A general approval framework spanning unrelated product domains
- A general provider plugin packaging model
- AWS request signing, EventBridge emulation, or Leaf wire emulation
- Treating provider events as high-rate telemetry
- Storing raw secret material in Cadence database rows, metadata, logs, audit
  documents, LiveView assigns after an action completes, or provider evidence
- Automatically approving protocol, endpoint, framing, spacecraft, direction,
  or credential changes returned by a Contact
- Removing authoritative status polling

## Locked Decisions

### Ownership hierarchy

```text
Organization
└── Provider Account
    ├── provider identity, endpoint, environment, and credentials
    ├── organization guardrails and ingestion configuration
    └── Mission Grants
        └── Mission Provider
            ├── mission spacecraft mappings
            ├── mission delivery policy
            ├── Service and Delivery Profile selections
            └── provider-managed Transports
```

A Provider Account is organization-owned. A Mission Provider is the
mission-owned binding to a granted account. A Transport remains mission-owned
executable data-plane configuration.

### Delivery policy is mission-scoped

Organization guardrails define the maximum allowed security and network
envelope. A Mission Provider defines the delivery policy and substitution
tolerances for its mission. A future Contact Requirement may narrow that policy
for one requirement, but may never widen it.

### Credential rotation is not mission configuration

Provider Accounts store a stable secret-manager reference. Rotating material
behind that reference does not create new Mission Provider or Transport
versions. Each provider operation records the resolved credential registry and
backend version when available, never the secret.

Revocation blocks new provider control-plane operations and marks ingestion and
reconciliation unhealthy. It preserves Provider Accounts, mission grants,
Transports, reservations, contacts, and historical evidence.

### Durable inbox and audit ledger are different records

The provider event inbox records what Cadence received and whether it has been
processed. The provider audit ledger records what Cadence decided or changed.
The inbox is an operational queue with mutable processing state. Audit entries
are append-only evidence and are never used as a job queue.

### Events are advisory triggers

An event can trigger immediate reconciliation, but it does not overwrite a
reservation directly. `describe_contact` or another capability-declared
authoritative read supplies the normalized state that Cadence evaluates.
Safety polling continues to repair missing, duplicated, delayed, or out-of-order
events.

### Provider changes do not silently rewrite execution

Cadence compares a new provider-confirmed snapshot with the last accepted
snapshot. Observations are recorded automatically. Actionable changes are
classified by the exact Mission Provider delivery-policy version. Accepted
execution changes create an append-only Scheduled Contact revision and update
the current execution projection transactionally.

### Configuration and security mismatches are never approvable from a Contact

A changed protocol, network endpoint, framing, spacecraft, direction,
credential, Service Profile, or Delivery Profile is a configuration or security
failure. The reservation remains durable and visible, execution is blocked,
and an administrator must create or select approved setup. Approval cannot turn
untrusted provider response data into a Transport.

## Product Journeys

### Organization administrator creates a Provider Account

1. Open **Provider Accounts** from the organization surface.
2. Choose a Provider Type and enter account identity, endpoint, environment,
   secret reference, ingestion mode, and organization guardrails.
3. Register existing secret material or use a write-capable secret backend to
   create it.
4. Test credentials and capabilities without exposing resolved material.
5. Save an active Provider Account version.
6. Grant the account to one or more missions.

The page shows health, credential status and version, event-ingestion health,
cursor age, quarantined-event count, grants, and sanitized administrator
diagnostics.

### Mission administrator enables a granted provider

1. Open **Comms → Providers** inside the mission.
2. Select an organization Provider Account already granted to the mission.
3. Map mission spacecraft to provider spacecraft.
4. Select Service Profiles, Delivery Profiles, stations or service pools, and
   provider-managed Transports.
5. Configure the mission delivery policy and substitution tolerances.
6. Validate and activate a new Mission Provider version.

The mission never copies or displays account credentials. Mission Provider
configuration may narrow organization guardrails but cannot widen them.

### Mission operator schedules and observes a Contact

The Stage 2 **Ops → Contacts** journey remains. A reservation additionally
snapshots the Provider Account, mission grant, Mission Provider, delivery
policy, Transport, and profile versions. The operator normally sees provider,
station, time, service, delivery summary, lifecycle, and readiness. Account and
protocol details remain administrator diagnostics.

### Cadence receives a provider event

1. A polling worker or webhook endpoint authenticates and bounds the delivery.
2. Cadence sanitizes it and computes an integrity hash.
3. Cadence inserts the inbox entry before acknowledging a webhook or advancing
   a polling cursor.
4. Duplicate deliveries converge on the same provider event identity.
5. A processor resolves the exact account, mission, and reservation.
6. The processor performs an authoritative provider read when required.
7. Cadence applies an idempotent observation, creates a change decision, or
   quarantines the entry.
8. Cadence appends audit evidence for the decision and marks inbox processing
   state.

### Operator reviews a provider change

1. A provider response differs from the last accepted reservation snapshot.
2. Cadence shows the requested, currently accepted, and proposed values plus
   operational impact and provider deadline.
3. Policy-approved substitutions are already marked accepted with the exact
   rule and policy version.
4. Material proposals remain `approval_pending` until an authorized mission
   approver accepts or rejects them with a reason.
5. Acceptance writes a Scheduled Contact revision and current projection in one
   transaction.
6. Rejection calls a provider modification/rejection operation only when the
   adapter declares that capability; otherwise it records the local decision
   and reconciles provider truth.

If the provider already made the change effective, Cadence does not offer a
misleading reject action. It records the external fact, blocks or revises unsafe
execution, and requests acknowledgment or contingency action.

### Organization administrator rotates or revokes credentials

Rotation creates a credential lifecycle event and increments the non-secret
credential version. Provider Account identity, grants, Mission Providers, and
Transports remain unchanged. A validation request proves the new material can
be resolved and used. Revocation prevents subsequent control-plane operations
and surfaces affected reconciliation as degraded without deleting history.

## Target Model

### Provider Account and versions

`Cadence.GroundNetworks.ProviderAccount` is a stable organization-owned
identity. Immutable effective configurations are stored as Provider Account
versions.

The stable account contains:

```text
provider_account_id
organization_id
display_name
lifecycle_state
active_version
credential_status
event_ingestion_status
last_validated_at
metadata
```

Each version contains:

```text
provider_account_id
organization_id
version
provider_type
client_key
base_url
region and environment references
credential_ref
event_ingestion_mode and bounded configuration
request timeout, retry, and rate-limit policy
approved protocols and security requirements
permitted delivery destinations and network ranges
provider-specific non-secret configuration
created_by and created_at
```

Endpoint, environment, provider type, or organization guardrail changes create
a new account version. Routine secret rotation behind a stable reference does
not.

### Provider Account credential

The credential registry stores only:

```text
credential_ref
organization_id
provider_account_id
status
registry_version
backend_key
backend_reference
last_rotated_at
revoked_at
non-secret metadata
```

Resolution returns an ephemeral value containing material, registry version,
backend version or fingerprint when supplied, and expiry when supplied.
Material is handed directly to the adapter call and discarded. Resolution,
validation, rotation, failure, and revocation append sanitized audit entries.

Local `env://` resolution remains an explicitly local backend. Production
configuration must use an approved configured backend and must reject enabled
Provider Accounts whose credential backend is unavailable.

### Mission grant

A versioned `ProviderAccountGrant` authorizes one mission to bind one Provider
Account version. It contains:

```text
provider_account_grant_id
organization_id
mission_id
provider_account_id and provider_account_version
version and lifecycle state
allowed services, directions, stations, and delivery kinds
quota or commercial restrictions when known
granted_by, granted_at, and reason
revoked_by, revoked_at, and reason
```

A grant can only narrow Provider Account guardrails. Revoking a grant blocks new
search and reservation operations for that mission. It does not delete
historical Mission Providers or active reservation evidence. The UI must
explain any already-committed contacts requiring operator handling.

### Mission Provider

`MissionProvider` gains exact account and grant references and stops owning
provider credentials or shared endpoint identity:

```text
provider_account_id and provider_account_version
provider_account_grant_id and provider_account_grant_version
delivery_policy_document
spacecraft mappings
enabled Service and Delivery Profile references
permitted station or service-pool subset
preferred provider-managed Transport references
mission scheduling and fallback policy
```

Historical Mission Provider versions remain resolvable. Provider context is
assembled from the exact Mission Provider, grant, and Provider Account versions
plus the current credential lifecycle record.

### Delivery policy

The policy is normalized and validated before a Mission Provider version is
activated. Its initial vocabulary supports:

```text
maximum earlier and later start shift
maximum earlier and later end shift
minimum retained duration
minimum retained estimated capacity or volume
approved station or service-pool substitutions
approved equivalent antenna/resource substitutions
maximum cost delta when provider evidence supplies cost
changes that always require approval
deadline behavior when no approver responds
whether policy-approved changes may revise execution automatically
```

Unknown policy fields are rejected unless they live under a bounded extension
document. Policy evaluation is deterministic and returns a decision plus
machine-readable reasons; it does not perform external calls.

### Provider event cursor

One cursor exists per Provider Account version, environment, adapter event
channel, and polling stream. It contains the opaque provider cursor, last
successful fetch and advance times, health, lease information, and bounded
error evidence.

Workers claim cursor leases so only one poll advances a stream at a time. A
poll response is committed transactionally:

1. insert every bounded inbox entry or record its duplicate/collision outcome;
2. persist evidence for invalid but attributable entries as quarantine records;
3. advance the opaque cursor.

Event processing may happen after this transaction. Therefore one poison event
cannot prevent later events from being ingested.

### Provider event inbox

`ProviderEventInboxEntry` contains:

```text
provider_event_inbox_id
organization_id
provider_account_id and version
environment and channel references
provider_event_id, schema version, type, and sequence when supplied
provider resource and correlation references
provider occurred_at and Cadence received_at
sanitized payload document and integrity hash
evidence reference
processing state, attempt count, last attempted_at, and bounded error
resolved mission, Mission Provider, reservation, and Contact references
```

The unique deduplication identity is Provider Account, environment/channel, and
provider event ID. The same identity with the same hash is a duplicate. The
same identity with a different hash is an identity collision and is quarantined
as a security/integration failure; neither payload overwrites the other.

Processing states are:

```text
received -> processing -> processed
                    |-> quarantined -> reprocessing -> processed
```

The received payload and hash are immutable. Processing fields are mutable
operational state. Quarantine resolution appends audit evidence.

### Webhook delivery

Webhook routes are adapter-owned authentication boundaries over the common
inbox. They enforce body-size limits, signature or bearer authentication,
timestamp/replay rules, content type, and account/environment binding before
returning success. An authenticated, attributable, bounded but semantically
invalid event is durably quarantined and acknowledged so it cannot create an
infinite provider retry loop. Authentication failures and oversized requests
are rejected and recorded as bounded security evidence when an account can be
identified.

The simulator polling feed is the Stage 3 reference path. A webhook is enabled
only when a Provider Type declares an authenticator and normalization contract;
there is no generic unauthenticated JSON webhook.

### Reservation snapshots and changes

A Provider Reservation preserves four different truths:

```text
requested snapshot
latest provider-confirmed snapshot
latest Cadence-accepted execution snapshot
actual Contact Result observations
```

`ProviderReservationChange` represents a difference between confirmed and
accepted state. It contains:

```text
provider_reservation_change_id
organization_id and mission_id
provider_reservation_id
source: operator | provider | poller | webhook | reconciler
provider revision and event/evidence references
change kind and normalized before/after documents
operational impact and provider deadline
delivery-policy reference, evaluation result, and reasons
review kind: none | approval | acknowledgment
disposition and lifecycle
accepted Scheduled Contact revision when applicable
```

Duplicate descriptions of the same provider revision and normalized change
converge on one change identity.

### Approval decisions

`ProviderChangeApproval` is an append-only decision attached to one change. It
stores the human actor, decision, reason, decision time, proposed-change hash,
and exact policy version. An approval is invalid if the proposal hash is no
longer current. Self-approval restrictions can be added by mission policy; the
initial implementation requires an authenticated user with the existing
organization-admin capability.

The initial disposition states are:

```text
observed
policy_accepted
approval_pending -> approved | rejected | expired
acknowledgment_required -> acknowledged
applying -> applied | apply_failed | superseded
```

### Scheduled Contact revisions

An accepted change that affects execution appends a
`ScheduledContactRevision` containing the complete executable schedule and
routing snapshot. The stable Scheduled Contact row remains the current runtime
projection and points to its active revision. Updating the current projection,
appending the revision, transitioning the Provider Reservation change, and
appending audit evidence happen in one database transaction.

No schedule revision is allowed after realization has begun. A provider change
reported after realization becomes an observation or contingency requiring
operator acknowledgment; it does not rewrite a running contact.

### Provider evidence and audit entries

Provider request, response, event, policy, and approval documents are sanitized
and bounded before persistence. Reusable evidence artifacts contain a stable
reference, media/schema type, captured time, byte count, SHA-256 hash, and the
sanitized document or approved external object reference.

`ProviderAuditEntry` is append-only and contains:

```text
provider_audit_entry_id
organization_id and optional mission_id
Provider Account, grant, Mission Provider, reservation, change, Contact,
  and Scheduled Contact references when applicable
source and actor document
action and outcome
provider occurred_at, Cadence recorded_at, and effective_at
correlation, request, client, provider event, and causation references
sanitized previous, current, decision, and policy documents
credential reference plus registry/backend version, never material
evidence references and integrity hashes
```

Current-state tables are operational projections. Corrections create new audit
entries; there is no update or delete API for audit entries. Mission-scoped
entries may project into the existing operational-event spine and mission
timeline, but those projections are not the provider audit source of truth.

## Change Classification

### Automatic observations

These are evidence and do not require approval:

- Contact status and pass-phase transitions
- delivery status and health
- measured acquisition and loss-of-signal times
- received or transmitted bytes, frames, packets, and objects
- provider diagnostics and final result counters

They never change an approved Transport or future execution window.

### Policy-approved substitutions

These may be accepted automatically only when the exact Mission Provider policy
allows them:

- bounded start or end shifts
- retained duration or capacity above configured minima
- antenna changes inside an approved equivalent resource pool
- station or service-pool changes inside an explicit allow list
- bounded cost deltas when cost evidence is available

Every automatic acceptance records the exact rule, inputs, result, and policy
version. Missing data evaluates conservatively and cannot satisfy a tolerance.

### Explicit approval

These require approval while the provider proposal is still actionable:

- shifts beyond mission tolerance
- a station or resource outside the preapproved pool
- reduced duration, capacity, or expected volume below policy
- increased cost beyond policy
- a provider counteroffer that changes the operational window materially
- replacement or cancellation that risks losing committed capacity

Changing Service Profile or Delivery Profile requires new approved setup and
reservation handling; it cannot be approved as an in-place Contact descriptor
change.

### Already-effective provider changes

Cadence records already-effective provider cancellation, reduction, or timing
changes as external facts. It must not imply that rejecting a UI prompt can
undo provider state. Cadence fails closed for unsafe execution, reconciles the
canonical reservation, and creates an acknowledgment or contingency item for
operators.

### Never approvable

The following always block execution and require configuration remediation:

- protocol or endpoint changes
- framing-family or frame-size changes
- spacecraft or direction changes
- credential material or credential-reference changes
- a delivery descriptor inconsistent with the exact Transport
- an account, grant, Service Profile, or Delivery Profile outside the
  reservation snapshot

## Consistency and Failure Semantics

- External provider calls never occur inside a database transaction.
- Cadence persists mutation intent and idempotency evidence before the call.
- Cursor advancement and inbox storage are one transaction.
- Inbox processing and domain changes are individually idempotent.
- Domain transition and matching audit entry are one transaction.
- An audit persistence failure fails the domain transition.
- An operational-event projection failure can be retried from audit evidence
  without losing the canonical provider decision.
- Provider event ordering is evidence, not permission to regress canonical
  lifecycle state.
- Safety polling remains active when event ingestion is healthy.
- Revoked credentials or grants stop new work but do not delete or mutate
  historical evidence.
- Configuration mismatch fails closed and never materializes a runtime from
  unapproved provider data.

## Security and Tenancy

- Every record is organization-scoped; mission records also require matching
  organization and mission scope.
- Provider Account writes, grants, credential lifecycle actions, quarantine
  resolution, and material change approvals require explicit authorization.
- Provider evidence uses the existing recursive secret-detection and
  sanitization policies, extended for provider-specific sensitive keys.
- Raw request bodies are not logged on webhook or secret-management routes.
- Webhook credentials are separate from provider control-plane and data-plane
  credentials unless the Provider Type explicitly proves otherwise.
- Secret material resolution is ephemeral and instrumented without values.
- User-provided strings are matched through allow lists; they are never passed
  to `String.to_atom/1`.
- Provider timestamps and Cadence receipt timestamps are both retained in UTC.

## Authenticated Route Placement

Organization Provider Account pages belong in the existing authenticated
browser scope under a stricter `live_session :provider_accounts`:

```text
/provider-accounts
/provider-accounts/new
/provider-accounts/:provider_account_id
```

They use the organization sidebar and the same organization-scope mount hook,
plus a router-mounted organization-admin authorization hook. The current
organization comes from `current_scope`, the account can serve multiple
missions, and credentials are not mission setup. Context write APIs receive
`current_scope` as their first argument.

Mission Provider and Transport pages remain in authenticated
`live_session :comms` with `Layouts.mission_sidebar`:

```text
/missions/:mission_id/comms/providers
/missions/:mission_id/comms/providers/:provider_id
/missions/:mission_id/comms/transports
```

They remain there because grants are bound into mission configuration and
delivery policy is mission-scoped.

Contact timelines, changes, acknowledgments, and approval actions remain in
authenticated `live_session :ops` with `Layouts.ops`:

```text
/missions/:mission_id/ops/contacts
/missions/:mission_id/ops/contacts/:provider_reservation_id
```

They belong in Ops because they affect a scheduled or active mission operation.

Capability-gated provider webhooks, when implemented, use a dedicated API
pipeline rather than browser or user-session authentication:

```text
/api/provider-webhooks/:provider_account_id/:endpoint_ref
```

The pipeline enforces provider-specific authentication, replay protection,
body limits, and account binding before the controller can persist an inbox
entry. There is no route until a Provider Type supplies those semantics.

## UI Requirements

### Organization Provider Account

- stable navigation from the organization surface;
- account identity, active version, provider type, endpoint/region summary;
- credential status and version without secret values;
- Validate, Rotate, Revoke, and Restore actions when supported;
- mission grants with grant/revoke actions;
- ingestion mode, cursor age, last event, health, backlog, and quarantine count;
- bounded audit timeline and administrator diagnostics.

### Mission Provider

- select only Provider Accounts granted to the current mission;
- show account and grant identity without credentials;
- progressively render delivery-policy fields;
- explain organization guardrails and why mission values cannot exceed them;
- show exact active Provider Account, grant, Provider, profile, and Transport
  versions;
- retain stable DOM IDs for forms and dynamic regions.

### Ops Contacts

- separate requested, provider-confirmed, accepted, and actual values;
- show policy-accepted changes without unnecessary prompts;
- show approval or acknowledgment queue with impact and deadline;
- never show reject for a provider fact that is already effective;
- show configuration failures as remediation, not approval;
- provide a chronological provider and Cadence audit timeline;
- place protocol, endpoint, framing, credential version, and provider-native
  identifiers under administrator diagnostics.

LiveView collections use streams over domain structs with stable IDs. Raw
provider wire maps are never streamed directly.

## Observability

Required metrics include:

- provider credential resolution, validation, rotation, and failure counts;
- event polling latency, cursor age, pages, events, duplicates, collisions, and
  cursor advancement;
- webhook authentication failures and accepted/quarantined deliveries;
- inbox backlog, processing lag, attempts, and quarantine age;
- event-triggered versus safety-poll reconciliation latency;
- changes by classification and policy decision;
- approval wait time, expiry, accept/reject outcome, and apply failure;
- Provider Account and grant health;
- audit persistence failures and operational-event projection lag.

Metrics and logs carry only opaque references and bounded reason categories.

## Acceptance Criteria

- One organization Provider Account can be explicitly granted to two missions
  without copying credentials.
- A mission without a grant cannot validate, search, reserve, reconcile, or
  inspect account secrets.
- Routine credential rotation changes the recorded credential version used by
  later calls without recreating Mission Providers or Transports.
- Credential revocation blocks new operations while preserving historical
  contacts and audit evidence.
- The simulator event feed is consumed through a durable cursor and inbox.
- Restart after inbox commit and before processing neither loses nor duplicates
  a canonical transition.
- Restart after processing and before marking the inbox entry converges without
  duplicating a decision, change, or Scheduled Contact revision.
- Duplicate and out-of-order events do not regress reservation state.
- An event ID reused with different content is quarantined and visible.
- A missing event is repaired by safety polling.
- A policy-approved timing or resource substitution records its rule and
  updates exactly one Scheduled Contact revision.
- A material actionable change waits for an authorized human decision.
- A stale approval cannot apply a superseded proposal.
- An already-effective provider change is represented as fact plus contingency,
  not a rejectable proposal.
- A changed endpoint, protocol, framing, spacecraft, direction, or credential
  fails closed and cannot be approved.
- Every provider mutation, event decision, policy result, approval, schedule
  revision, credential lifecycle action, and terminal result has append-only
  audit evidence.
- Audit and evidence documents contain no raw credentials.
- Mission-scoped audit entries project into the operational timeline without
  becoming the audit source of truth.
- The separate simulator HTTP and TCP/CCSDS boundary proof remains green.
- Root `mix precommit` passes.

## Deferred Beyond Stage 3

- Contact Requirements and versioned Contact Plans
- Requirement-specific policy narrowing and planning approvals
- Fleet-scale multi-provider scheduling and reservation sagas
- Commercial-provider-specific webhook receivers
- Provider-connects UDP, object delivery, and Leaf MQTT runtime implementations
- Formal adapter/plugin packaging
- Compliance exports, external immutable audit archives, and retention policy
  automation beyond the append-only application contract
