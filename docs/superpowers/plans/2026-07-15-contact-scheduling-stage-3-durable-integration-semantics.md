# Stage 3 Durable Integration Semantics Implementation Plan

**Status:** in progress

**Progress (2026-07-15):** Tasks 1 through 3 are complete. Provider events now
normalize into bounded, sanitized `ProviderEvent` structs, Provider Contacts
carry monotonic revisions, and the separate simulator exposes revision-aware,
idempotent Contact modification with contract fixtures. Provider evidence is
now recursively sanitized, deterministically content-addressed, bounded, and
deduplicated per organization and Provider Account, with credential-free
external object references supported. The append-only provider audit ledger
supports organization-only and optional mission scope, exact domain and
causality references, bounded decision evidence, transaction composition via
`Ecto.Multi`, and idempotent mission operational-event projections. Secret
resolution now uses a shared capability-based backend contract with local-only
environment and bounded, HTTPS-by-default Req adapters; the dashboard modules
remain compatibility delegates. Organization/Provider Account-scoped
credential records support stable references, ephemeral resolution, rotation,
revocation, version-only audit evidence, and Stage 2 adapter compatibility.
Root `mix precommit` passes with 3,053 tests passed and 93 browser-tagged tests
excluded. Task 4, organization Provider Accounts and mission grants, is next.

**Goal:** Promote Stage 2 mission Provider setup into an organization-owned,
secret-safe integration model; ingest provider events durably; classify and
apply reservation changes through mission policy and explicit approval; and
preserve complete append-only evidence without weakening status polling,
Transport validation, or the separate simulator boundary.

**Design sources:**

- [Stage 3 Durable Provider Integration Semantics](../specs/2026-07-15-contact-scheduling-stage-3-durable-integration-semantics-design.md)
- [Contact Scheduling and External Ground Network Simulation](../specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)
- [Simulator Provider Contract v1](../specs/2026-07-13-simulator-provider-contract-v1.md)
- [Stage 2 Provider and Delivery Contract](2026-07-13-contact-scheduling-stage-2-provider-delivery-contract.md)

## Outcome

After Stage 3, the normal flow is:

1. An organization administrator creates and validates one Provider Account.
2. Cadence stores a stable secret reference and resolves material only through
   an approved backend.
3. The administrator grants an exact Provider Account version to a mission.
4. A mission administrator creates a Mission Provider from that grant and
   defines mission delivery tolerances.
5. Contact scheduling snapshots the exact account, grant, Provider, policy,
   Transport, Service Profile, and Delivery Profile versions.
6. A durable account-level poller stores provider events and advances its cursor
   transactionally.
7. Inbox processors reconcile the exact reservation using authoritative
   provider reads.
8. Observations apply idempotently, policy-approved substitutions create one
   Scheduled Contact revision, and material proposals wait for approval.
9. The Ops Contact timeline explains provider evidence, policy, approval,
   execution revision, and delivery outcome.
10. Credential rotation changes later credential-use evidence without
    recreating mission setup.

## Locked Decisions

- Provider Accounts and credentials are organization-owned.
- Mission grants are explicit and versioned.
- Mission Providers own spacecraft mappings, selected provider profiles, and
  mission delivery policy.
- Organization guardrails can be narrowed by a mission but never widened.
- A stable credential reference survives rotation; secret values never enter
  durable configuration or audit documents.
- The durable provider inbox is not the append-only audit ledger.
- A polling cursor advances after every attributable event is durably inserted,
  deduplicated, or quarantined, not after all domain processing completes.
- Events trigger reconciliation; authoritative Provider Client reads remain the
  source of normalized reservation state.
- Safety polling remains enabled.
- Requested, provider-confirmed, Cadence-accepted, and actual values remain
  separate.
- Observations are automatic, bounded substitutions may be policy-approved,
  material proposals require explicit approval, and already-effective provider
  facts require acknowledgment or contingency rather than a fictional reject.
- Protocol, endpoint, framing, spacecraft, direction, credential, and exact
  profile mismatches are never approvable.
- Accepted execution changes append Scheduled Contact revisions.
- Provider audit entries are append-only and are the source for mission
  operational-event projections, not the reverse.
- The simulator remains a separate application and reference provider.
- No general plugin or approval framework is introduced.

## Authenticated Route Placement

All browser routes remain inside the existing scope that pipes through
`[:browser, :require_authenticated_scope]`, so `current_scope` is loaded before
LiveView mount and unauthenticated users are redirected at the router.

Add a stricter organization-admin LiveView session using the organization
sidebar:

```text
live_session :provider_accounts
  /provider-accounts
  /provider-accounts/new
  /provider-accounts/:provider_account_id
```

Its `on_mount` chain requires organization scope, the existing
`:organization_admin` capability, and the authenticated user menu. These routes
belong at organization scope because one account and credential can be granted
to several missions. They do not belong under platform `/admin`, which manages
the Cadence installation rather than one customer's provider integration.

Provider and Transport setup routes remain inside authenticated
`live_session :comms` with `Layouts.mission_sidebar`:

```text
/missions/:mission_id/comms/providers
/missions/:mission_id/comms/providers/new
/missions/:mission_id/comms/providers/:provider_id
/missions/:mission_id/comms/transports
/missions/:mission_id/comms/transports/:transport_id
```

They remain mission-scoped because a Mission Provider, delivery policy,
spacecraft mappings, and provider-managed Transport express mission intent.

Contact scheduling, changes, approvals, acknowledgments, and timelines remain
inside authenticated `live_session :ops` with `Layouts.ops`:

```text
/missions/:mission_id/ops/contacts
/missions/:mission_id/ops/contacts/:provider_reservation_id
```

They belong in Ops because they affect scheduled or active mission operations.
All authorized operators may inspect state; approval and acknowledgment events
perform an explicit capability check using `current_scope`.

No webhook route is added for the simulator. A future adapter that declares a
webhook authenticator gets a route under a dedicated provider-webhook API
pipeline, never the browser pipeline or user-session API pipeline.

## Bounded Scope

### Included

- Provider Account and version persistence
- provider credential lifecycle and production-shaped secret backend
- explicit mission grants
- Mission Provider ownership migration
- mission-scoped delivery policy
- provider evidence artifacts and append-only audit entries
- durable event cursors, inbox, deduplication, quarantine, and bounded workers
- provider-event normalization and authoritative reconciliation triggers
- simulator contact modification and deterministic provider-initiated changes
- provider-neutral modification capability and normalized snapshots
- change classification, approval, acknowledgment, and application
- Scheduled Contact revisions
- Provider Account, Mission Provider, and Ops Contact UI journeys
- restart, duplicate, out-of-order, collision, missing-event, stale-approval,
  rotation, revocation, and separate-app proofs

### Excluded

- Contact Requirements and Contact Plans
- multi-provider and fleet planning
- AWS or Leaf adapters
- commercial-provider webhook implementations
- provider-connects UDP, MQTT, or object-delivery runtimes
- general plugin packaging
- a cross-domain approval framework
- external compliance archive and retention automation
- automatic provider account deduplication during migration

## Migration Strategy

The application is still pre-public, but the Stage 2 data model contains useful
test and development state. Migrate it deliberately:

1. Create Provider Account, credential, grant, evidence, audit, inbox, cursor,
   change, approval, and Scheduled Contact revision tables.
2. For each active Stage 2 Mission Provider, create one organization Provider
   Account and one mission grant. Do not merge rows based only on a matching URL
   or credential reference; shared ownership cannot be inferred safely.
3. Backfill exact account and grant references onto every Mission Provider
   version and Provider Reservation.
4. Backfill an initial delivery policy that requires approval for all material
   schedule or resource changes.
5. Backfill Scheduled Contact revision 1 from each existing row and set the
   current revision pointer.
6. Validate all backfilled references and only then make new columns required.
7. Remove `base_url`, `credential_ref`, and `environment_ref` from Mission
   Provider product ownership after every Provider Context reads through the
   account binding.

Historical rows stay readable throughout the migration. There is no temporary
code path that copies resolved secret material into the new tables.

## Task 1: Extend the executable Provider contract

Add normalized provider types:

```text
apps/cadence/lib/cadence/ground_networks/provider_event.ex
apps/cadence/lib/cadence/ground_networks/provider_contact_snapshot.ex
apps/cadence/lib/cadence/ground_networks/provider_contact_change.ex
```

Modify:

```text
apps/cadence/lib/cadence/contacts/provider_client.ex
apps/cadence/lib/cadence/contacts/provider_clients/simulator_http.ex
apps/cadence/lib/cadence/ground_networks/provider_capabilities.ex
apps/cadence/lib/cadence/ground_networks/provider_contact.ex
```

Normalize every event at the adapter boundary. Required values include stable
provider event identity, schema version, event type, provider occurrence time,
resource type/reference, provider request/correlation references, and a bounded
string-keyed data document. Do not pass wire maps into LiveView streams.

Add an optional capability-gated callback:

```elixir
modify_contact(context, provider_contact_ref, attrs, opts)
```

Modification requests include a client reference and expected provider
revision when the provider supports optimistic concurrency. A Contact snapshot
separates schedule, resources, service/delivery references, lifecycle, pass,
delivery, and result observations. Adapters reject unsupported or malformed
revisions rather than inventing order.

Extend the simulator provider contract and fixtures:

```text
apps/cadence_simulator/test/fixtures/provider_contract/v1/event_page.json
apps/cadence_simulator/test/fixtures/provider_contract/v1/contact_modified.json
apps/cadence_simulator/test/fixtures/provider_contract/v1/contact_counteroffer.json
apps/cadence_simulator/test/fixtures/provider_contract/v1/event_identity_collision.json
```

The simulator keeps `/provider/v1`. Add `PATCH /provider/v1/contacts/:id`,
provider revision and modification evidence, deterministic counteroffers, and
provider-initiated schedule/resource/cancellation changes driven only by
scenario behavior or `/admin/v1` fault controls. Cadence never calls those
administrator controls.

Update the contract document so cursor advancement means inbox durability, not
synchronous domain application.

Tests cover capability declaration, normalized events, bounded payloads,
unknown event types, optimistic conflict, idempotent modification, contact
revision, and secret sanitization.

Run:

```bash
cd apps/cadence_simulator
mix test test/cadence_simulator/provider/contract_test.exs
mix test test/cadence_simulator/provider

cd ../cadence
mix test test/cadence/contacts/provider_clients/simulator_http_test.exs
mix test test/cadence/ground_networks/provider_event_test.exs
```

## Task 2: Add provider evidence and the append-only audit ledger

Create:

```text
apps/cadence/lib/cadence/ground_networks/provider_evidence.ex
apps/cadence/lib/cadence/ground_networks/provider_evidence_store.ex
apps/cadence/lib/cadence/ground_networks/provider_audit_entry.ex
apps/cadence/lib/cadence/ground_networks/provider_audit.ex
apps/cadence/lib/cadence/persistence/schemas/provider_evidence_row.ex
apps/cadence/lib/cadence/persistence/schemas/provider_audit_entry_row.ex
apps/cadence/priv/repo/migrations/*_create_provider_evidence_and_audit.exs
```

Evidence storage:

- recursively sanitizes before persistence;
- rejects secret-like keys and oversized documents after sanitization;
- stores schema/media type, captured time, byte count, and SHA-256 hash;
- deduplicates exact organization-scoped content without conflating evidence
  from different accounts;
- supports an approved external-object reference without storing its access
  credential.

Audit entries include organization scope, optional mission scope, exact account,
grant, Provider, reservation, change, Contact, and Scheduled Contact references;
actor and source; action and outcome; provider/Cadence/effective times;
correlation and causation; before/after/decision/policy documents; credential
reference/version; and evidence references.

Provide `Ecto.Multi` helpers so domain changes and audit entries commit in the
same transaction. An audit insert failure rolls back its matching domain
transition. Expose no update or delete API. Corrections append superseding
entries with causation links.

Project mission-scoped provider audit entries into `OperationalEvents` using
the audit entry as `source_record_kind` and `source_record_id`. Treat this as a
rebuildable/read projection. Organization-only credential and account events
remain available through the provider audit query without forcing a fake
mission ID.

Tests prove scope isolation, deterministic hashing, redaction, document bounds,
append-only APIs, transaction rollback, idempotent projections, and exact
causality.

Run:

```bash
cd apps/cadence
mix test test/cadence/ground_networks/provider_evidence_store_test.exs
mix test test/cadence/ground_networks/provider_audit_test.exs
```

## Task 3: Generalize secret resolution and add provider credential lifecycle

The dashboard source-credential subsystem already has environment and external
secret backends. Extract the reusable contract instead of creating a second
incompatible secret mechanism.

Create or extract:

```text
apps/cadence/lib/cadence/secrets/backend.ex
apps/cadence/lib/cadence/secrets/resolved_secret.ex
apps/cadence/lib/cadence/secrets/resolver.ex
apps/cadence/lib/cadence/secrets/material_policy.ex
apps/cadence/lib/cadence/secrets/env_backend.ex
apps/cadence/lib/cadence/secrets/external_backend.ex
apps/cadence/lib/cadence/ground_networks/provider_credential.ex
apps/cadence/lib/cadence/ground_networks/provider_credentials.ex
apps/cadence/lib/cadence/persistence/schemas/provider_credential_row.ex
apps/cadence/priv/repo/migrations/*_create_provider_credentials.exs
```

Keep compatibility delegates for existing dashboard modules and run their
focused suites. The shared secret behavior supports ephemeral resolution and
capability-gated create, rotate, and revoke operations. Use `Req` for the
external backend. Disable request/response body logging, require HTTPS outside
explicit local configuration, bound timeouts, sanitize errors, and never
persist returned material.

`ProviderCredential` stores a stable reference, organization/account scope,
status, registry version, backend key/reference, lifecycle timestamps, and
non-secret metadata. Resolution returns material plus registry version,
backend-reported version/fingerprint, and expiry when available. Provider call
audit entries record those versions and outcome only.

Replace the Stage 2 provider `CredentialResolver` implementation with a narrow
delegate into this registry while preserving injectable resolvers for tests.
`env://` remains local-only. Production startup or Provider Account activation
fails when no approved secret backend can resolve the registered reference.

Tests prove create/resolve/rotate/revoke, rotation without reference changes,
revocation blocking, account scope, ephemeral material handling, HTTPS policy,
Req request shape, redacted failures, audit entries, and dashboard compatibility.

Run:

```bash
cd apps/cadence
mix test test/cadence/secrets
mix test test/cadence/ground_networks/provider_credentials_test.exs
mix test test/cadence/dashboards/source_credentials_test.exs
mix test test/cadence/dashboards/source_credentials
```

## Task 4: Persist Provider Accounts, mission grants, and ownership migration

Create:

```text
apps/cadence/lib/cadence/ground_networks/provider_account.ex
apps/cadence/lib/cadence/ground_networks/provider_account_version.ex
apps/cadence/lib/cadence/ground_networks/provider_accounts.ex
apps/cadence/lib/cadence/ground_networks/provider_account_grant.ex
apps/cadence/lib/cadence/ground_networks/provider_account_grants.ex
apps/cadence/lib/cadence/persistence/schemas/provider_account_row.ex
apps/cadence/lib/cadence/persistence/schemas/provider_account_version_row.ex
apps/cadence/lib/cadence/persistence/schemas/provider_account_grant_row.ex
apps/cadence/priv/repo/migrations/*_create_provider_accounts_and_grants.exs
apps/cadence/priv/repo/migrations/*_bind_mission_providers_to_accounts.exs
```

Public user-driven context functions receive `current_scope` first and call
`Cadence.Auth.Policy` before persistence. Background-worker functions are
separate internal APIs that require explicit organization/account scope and a
system actor document.

Provider Account versions own provider type, client key, endpoint, region,
environment, stable credential reference, event configuration, request policy,
and guardrails. Account operational health stays on the stable account
projection and does not create configuration versions.

Mission grants are versioned and can only narrow account guardrails. Revoke
blocks new mission operations and records affected nonterminal reservations for
operator review without deleting them.

Modify:

```text
apps/cadence/lib/cadence/ground_networks/mission_provider.ex
apps/cadence/lib/cadence/ground_networks/mission_providers.ex
apps/cadence/lib/cadence/ground_networks/provider_context.ex
apps/cadence/lib/cadence/persistence/schemas/mission_provider_row.ex
apps/cadence/lib/cadence/contacts/provider_reservation.ex
apps/cadence/lib/cadence/persistence/schemas/provider_reservation_row.ex
apps/cadence/lib/cadence/contacts/provider_booking.ex
apps/cadence/lib/cadence/contacts/provider_reservation_reconciler.ex
```

Mission Provider versions bind exact account and grant versions. Provider
Reservations snapshot those versions before a provider mutation. Provider
Context resolution validates the exact historical chain, then resolves the
current active material behind the stable credential reference.

Backfill each Stage 2 Mission Provider into its own account and grant. Do not
infer sharing. Remove mission ownership of endpoint/environment/credential only
after every adapter path and test uses the account binding.

Tests prove organization and mission isolation, exact version resolution,
guardrail narrowing, grant/revoke behavior, backfill, historical reads,
credential rotation independence, and reconciliation through the new chain.

Run:

```bash
cd apps/cadence
mix test test/cadence/ground_networks/provider_accounts_test.exs
mix test test/cadence/ground_networks/provider_account_grants_test.exs
mix test test/cadence/ground_networks/mission_providers_test.exs
mix test test/cadence/contacts/provider_booking_test.exs
mix test test/cadence/contacts/provider_reservation_reconciler_test.exs
```

## Task 5: Add organization Provider Account and updated mission setup journeys

Modify the router inside the existing authenticated browser scope. Add the
`:provider_accounts` LiveView session described above and leave the existing
`:comms` and `:ops` sessions in place.

Create:

```text
apps/cadence_web/lib/cadence_web/live/provider_account_list_live.ex
apps/cadence_web/lib/cadence_web/live/provider_account_new_live.ex
apps/cadence_web/lib/cadence_web/live/provider_account_show_live.ex
```

Extend `CadenceWeb.OrganizationAuth` with a router-mounted
`:require_organization_admin` hook. Every mutating event still passes
`current_scope` to the authorized context API; the hook is not a substitute for
context authorization.

Add **Provider Accounts** to the organization navigation. The list/detail flow
shows account identity, active version, health, credential status/version,
event mode and cursor health, grants, quarantined count, and recent audit
entries. Create, validate, rotate, revoke, grant, and revoke-grant actions use
stable DOM IDs and never render a secret value back to the browser. If a backend
accepts material creation or rotation, use a one-way password input and clear
the form immediately after the action.

Update the existing **Comms → Providers** flow:

- select only accounts granted to `@mission`;
- remove endpoint, environment, and credential fields;
- show account and grant summaries;
- progressively render mission delivery-policy fields;
- display account guardrails and validation errors when the mission attempts to
  widen them;
- retain Service/Delivery Profile sync and provider-managed Transport behavior.

All templates begin with the correct `Layouts.app` wrapper and pass
`current_scope`. Forms use `to_form/2`, `<.form>`, and `<.input>`. Collections
use streams over structs, not wire maps.

LiveView tests assert stable IDs and outcomes rather than raw HTML text.

Run:

```bash
cd apps/cadence_web
mix test test/cadence_web/live/provider_account_live_test.exs
mix test test/cadence_web/live/comms_provider_live_test.exs
mix test test/cadence_web/live/comms_transport_live_test.exs
```

## Task 6: Add durable provider event cursors, inbox, and workers

Create:

```text
apps/cadence/lib/cadence/ground_networks/provider_event_cursor.ex
apps/cadence/lib/cadence/ground_networks/provider_event_cursors.ex
apps/cadence/lib/cadence/ground_networks/provider_event_inbox_entry.ex
apps/cadence/lib/cadence/ground_networks/provider_event_inbox.ex
apps/cadence/lib/cadence/ground_networks/provider_event_poller.ex
apps/cadence/lib/cadence/ground_networks/provider_event_processor.ex
apps/cadence/lib/cadence/ground_networks/provider_webhook_authenticator.ex
apps/cadence/lib/cadence/persistence/schemas/provider_event_cursor_row.ex
apps/cadence/lib/cadence/persistence/schemas/provider_event_inbox_row.ex
apps/cadence/priv/repo/migrations/*_create_provider_event_ingestion.exs
```

Use one bounded supervisor/worker lane over active accounts; do not allocate a
process per idle spacecraft or reservation. Pollers claim database leases on
account/environment/channel cursors. Use `Task.async_stream/3` with bounded
concurrency and `timeout: :infinity` for account batches.

For each polling page:

1. fetch outside a transaction using the exact account version and an ephemeral
   credential;
2. normalize, bound, sanitize, and hash every event;
3. transactionally insert/deduplicate/quarantine entries and advance the opaque
   cursor;
4. enqueue processing through durable inbox state;
5. append account-level audit evidence for page/cursor outcomes.

The inbox unique identity is account, environment/channel, and provider event
ID. Same identity and hash is a duplicate. Same identity and different hash
creates immutable collision evidence and quarantine. Unknown event types are
quarantined without creating atoms from input.

Processors claim inbox rows with database locking, resolve exact correlation,
and trigger authoritative reconciliation. State transition plus audit entry is
transactional; marking the inbox row processed may be retried. Reprocessing a
committed decision converges using provider revision/change identity and domain
idempotency.

Keep `ProviderReservationReconciler` safety polling. Event-triggered work may
make a reservation immediately due, but must not disable or bypass the repair
loop.

Define the webhook authenticator behavior and common persistence entry point,
but add no exposed simulator webhook route. Unit tests prove that a route cannot
be enabled without an explicit Provider Type authenticator.

Tests cover first page, restart before cursor commit, restart after inbox commit,
restart after domain commit, duplicate page, out-of-order event, identity
collision, poison event, quarantine/reprocess, revoked credential, grant scope,
lease expiry, bounded concurrency, and missing-event polling repair.

Run:

```bash
cd apps/cadence
mix test test/cadence/ground_networks/provider_event_cursors_test.exs
mix test test/cadence/ground_networks/provider_event_inbox_test.exs
mix test test/cadence/ground_networks/provider_event_poller_test.exs
mix test test/cadence/ground_networks/provider_event_processor_test.exs
mix test test/cadence/contacts/provider_reservation_reconciler_test.exs
```

## Task 7: Add simulator and Provider Client modification semantics

Extend simulator Contact persistence with a monotonically increasing provider
revision and immutable modification history. `PATCH /provider/v1/contacts/:id`
supports only capability-declared schedule/resource dimensions, validates an
expected revision, and uses native idempotency or client-reference recovery as
declared by the environment.

Extend simulator scenario behavior and administrator fault controls for:

- bounded earlier/later timing shifts;
- antenna substitution inside and outside an equivalent pool;
- station substitution;
- duration/capacity reduction;
- counteroffer with expiry;
- provider-initiated cancellation;
- event omission, duplication, delay, reordering, and identity collision.

Every change updates the authoritative Contact, appends provider-side history,
and emits the corresponding event. Event data is useful evidence, but Cadence
must still describe the Contact.

Implement `modify_contact/4` in `SimulatorHTTP` using `Req`, structured errors,
correlation IDs, idempotency capability, and optimistic revision. Expand the
fake client without process-global mutable configuration.

Tests prove deterministic scenario replay, capacity accounting, revision
conflict, idempotent modify, response loss after commit and recovery, provider
change events, cancellation, event faults, and redaction.

Run:

```bash
cd apps/cadence_simulator
mix test test/cadence_simulator/provider/contacts_test.exs
mix test test/cadence_simulator/provider/contact_lifecycle_test.exs
mix test test/cadence_simulator/provider/provider_integration_test.exs

cd ../cadence
mix test test/cadence/contacts/provider_clients/simulator_http_test.exs
mix test test/cadence/contacts/provider_client_contract_test.exs
```

## Task 8: Add delivery policy, reservation changes, approvals, and revisions

Create:

```text
apps/cadence/lib/cadence/ground_networks/delivery_policy.ex
apps/cadence/lib/cadence/ground_networks/delivery_policy_evaluator.ex
apps/cadence/lib/cadence/contacts/provider_reservation_change.ex
apps/cadence/lib/cadence/contacts/provider_reservation_changes.ex
apps/cadence/lib/cadence/contacts/provider_change_approval.ex
apps/cadence/lib/cadence/contacts/provider_change_approvals.ex
apps/cadence/lib/cadence/contacts/scheduled_contact_revision.ex
apps/cadence/lib/cadence/contacts/scheduled_contact_revisions.ex
apps/cadence/lib/cadence/persistence/schemas/provider_reservation_change_row.ex
apps/cadence/lib/cadence/persistence/schemas/provider_change_approval_row.ex
apps/cadence/lib/cadence/persistence/schemas/scheduled_contact_revision_row.ex
apps/cadence/priv/repo/migrations/*_create_provider_reservation_changes.exs
apps/cadence/priv/repo/migrations/*_create_scheduled_contact_revisions.exs
```

Add requested, provider-confirmed, and Cadence-accepted snapshot documents plus
provider revision to Provider Reservation. Backfill them from existing request
and response evidence.

The pure delivery-policy evaluator returns:

```text
observation
policy_accept with exact rule/reasons
approval_required with impact/deadline
acknowledgment_required for already-effective facts
configuration_failure with remediation reason
```

Missing inputs fail conservatively. Configuration fields are checked before
tolerance evaluation. A provider revision plus normalized before/after hash
forms the idempotent change identity.

Approval writes require `current_scope`, an authenticated user actor, existing
organization-admin authorization, a reason, and the current proposed-change
hash. A stale or superseded proposal cannot be approved. Do not reuse command
approval rows; the provider change lifecycle and evidence are different.

Policy acceptance or human approval performs one transaction that:

1. locks the current reservation, change, and Scheduled Contact;
2. rechecks provider revision, proposal hash, policy version, grant, and
   pre-realization state;
3. appends Scheduled Contact revision N+1 when execution changes;
4. updates the stable Scheduled Contact current projection/pointer;
5. updates the reservation accepted snapshot;
6. transitions the change;
7. appends provider audit evidence.

No schedule rewrite is allowed after realization begins. Reject only a proposal
the provider can still honor. Already-effective changes reconcile provider
truth, fail closed where necessary, and create acknowledgment/contingency work.
Never materialize endpoint, protocol, framing, spacecraft, direction,
credential, Service Profile, or Delivery Profile changes from Contact data.

Tests cover every classification, boundary equality, missing data, policy
version, auto-accept disabled, exact revision application, concurrent approval,
stale approval, supersession, rejection capability, already-effective
cancellation, post-realization change, configuration mismatch, transaction
rollback, and exactly-one schedule revision.

Run:

```bash
cd apps/cadence
mix test test/cadence/ground_networks/delivery_policy_test.exs
mix test test/cadence/ground_networks/delivery_policy_evaluator_test.exs
mix test test/cadence/contacts/provider_reservation_changes_test.exs
mix test test/cadence/contacts/provider_change_approvals_test.exs
mix test test/cadence/contacts/scheduled_contact_revisions_test.exs
```

## Task 9: Complete Ops journeys and end-to-end recovery proofs

Split the existing broad Ops Contact LiveView as needed, keeping the route in
authenticated `live_session :ops`. Add a reservation detail route and stable
navigation from each row.

The detail surface shows:

- requested, provider-confirmed, accepted, and actual values;
- Provider Account, grant, Mission Provider, policy, Transport, Service
  Profile, and Delivery Profile versions;
- Contact, pass, delivery, and Cadence lifecycle independently;
- pending approvals and acknowledgments with impact and deadline;
- approve/reject only for actionable proposals;
- acknowledge/contingency language for already-effective provider facts;
- configuration remediation for never-approvable changes;
- chronological provider audit entries and linked evidence;
- protocol, endpoint, framing, credential version, provider-native identifiers,
  and quarantine links only in administrator diagnostics.

Use LiveView streams for changes and audit entries. Stream domain structs or
configure explicit `dom_id` functions before insertion. Add stable IDs for
detail, timeline, approval form, rejection form, acknowledgment action, and
diagnostic disclosure. Forms use `to_form/2` and `<.input>`.

Add separate-app integration proofs:

1. organization account → mission grant → Mission Provider → Transport →
   opportunity → reservation → event inbox → authoritative reconcile → TCP/CCSDS
   telemetry → audit/result;
2. credential rotation between two calls without recreating mission setup;
3. restart after event inbox commit and before processing;
4. policy-approved provider timing shift creates one schedule revision;
5. material counteroffer waits for approval and stale approval cannot apply;
6. provider-effective cancellation becomes a fact and contingency;
7. endpoint/framing mismatch fails closed;
8. response lost after modification commit recovers by client reference or
   authoritative describe without replaying a mutation.

Tests may share a BEAM, but workflow operations cross simulator HTTP and
high-rate telemetry crosses the ordinary TCP path. Cadence never calls
`/admin/v1` after test setup and never injects simulator telemetry directly.

Run:

```bash
cd apps/cadence_web
mix test test/cadence_web/live/provider_account_live_test.exs
mix test test/cadence_web/live/comms_provider_live_test.exs
mix test test/cadence_web/live/ops_contact_schedule_live_test.exs
mix test test/cadence_web/live/ops_contact_detail_live_test.exs

cd ../cadence_simulator
mix test test/cadence_simulator/contact_scheduling_integration_test.exs

cd ../cadence
mix test test/cadence/contacts/provider_stage_3_boundary_test.exs
```

## Task 10: Documentation, migration audit, and final gates

Update:

```text
docs/ground-network-simulator.md
docs/simulator_provider_integration_flow.md
docs/how-to/add-a-provider-adapter.md
docs/superpowers/specs/2026-07-13-simulator-provider-contract-v1.md
docs/superpowers/specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md
```

Document Provider Account creation, secret backend configuration, mission
grants, delivery policy, event ingestion, cursor/quarantine recovery,
reservation changes, approval versus acknowledgment, audit evidence, simulator
fault scenarios, and operational diagnostics. Remove Stage 2 wording that
places endpoint, environment, or credential ownership on Mission Provider.

Audit migrations using both a clean database and a Stage 2-shaped fixture
database. Prove every historical Mission Provider, Provider Reservation, and
Scheduled Contact resolves through exact backfilled account, grant, policy, and
schedule revision references.

Run all focused suites from their owning applications, then run from the
umbrella root:

```bash
mix precommit
```

Record exact test counts and any explicitly excluded browser tags in this plan
when implementation finishes.

## Definition of Done

- Provider Account and credentials are organization-owned.
- Mission access requires an explicit, exact grant.
- Mission Provider no longer owns shared endpoint/environment/credential
  fields.
- Delivery policy is mission-scoped and cannot widen account guardrails.
- Public write APIs receive and authorize `current_scope` first.
- Production provider credentials resolve through an approved backend.
- Raw secret material is never persisted, rendered back, or written to logs,
  evidence, or audit.
- Rotation does not recreate Mission Providers or Transports.
- Revocation blocks new operations and preserves history.
- Provider evidence is sanitized, bounded, and integrity-hashed.
- Provider audit entries are append-only and transactionally paired with domain
  decisions.
- Provider events are normalized into structs at the adapter boundary.
- Polling cursor advancement is transactionally paired with inbox durability.
- Duplicate, out-of-order, colliding, malformed, and missing events converge or
  quarantine safely.
- Event processing triggers authoritative reconciliation and cannot regress
  lifecycle state.
- Safety polling remains green.
- Provider modifications are capability-gated, idempotent, revision-aware, and
  recoverable after ambiguous outcomes.
- Requested, confirmed, accepted, and actual snapshots remain distinct.
- Policy-approved changes record exact rule and policy version.
- Material proposals require a current authorized approval.
- Already-effective provider facts use acknowledgment/contingency semantics.
- Configuration/security mismatches are never approvable and fail closed.
- Accepted execution changes append exactly one Scheduled Contact revision.
- Organization, Comms, and Ops routes use the router scopes and layouts defined
  in this plan.
- Provider Account, Mission Provider, and Contact journeys have stable
  navigation and tested DOM IDs.
- The separate-app HTTP plus TCP/CCSDS proof remains green.
- Focused suites and root `mix precommit` pass.

## Follow-On After Stage 3

1. Contact Requirements and versioned Contact Plans.
2. Requirement-specific policy narrowing and plan approval.
3. Multi-provider opportunity comparison and unsatisfied-requirement reporting.
4. Fleet scheduling and bounded reservation sagas.
5. The first commercial provider adapter and its authenticated webhook path.
6. A plugin-packaging decision based on the commercial adapter proof.
