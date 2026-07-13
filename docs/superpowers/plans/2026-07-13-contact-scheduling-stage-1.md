# Stage 1 Contact Scheduling Implementation Plan

**Status:** ready for implementation

**Goal:** Deliver one provider-backed downlink contact end to end: an operator
searches opportunities under mission Ops, reserves one through a durable saga,
Cadence creates and realizes the canonical Scheduled Contact, and simulator
telemetry enters the normal mission runtime.

**Design source:**
[Contact Scheduling and External Ground Network Simulation](../specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)

## Locked Product Decisions

- Stage 1 books directly from Opportunity to Provider Reservation to Scheduled
  Contact. It does not create a Contact Plan.
- The product surface lives at `/missions/:mission_id/ops/contacts` inside the
  existing authenticated `:ops` LiveView session and ops layout.
- Stage 1 is downlink-only. Uplink, bidirectional contacts, and COP-1 execution
  are follow-on work.

## Architecture

Stage 1 adds one first-class durable integration resource:
`Cadence.Contacts.ProviderReservation`.

The reservation is created with an idempotency key before Cadence calls the
external provider. It records the selected opportunity, the exact provider and
routing versions, the future Scheduled Contact ID, provider evidence, and the
current reconciliation state. A provider response or later describe call can
confirm the reservation and materialize the Scheduled Contact idempotently.

No database transaction spans an HTTP request.

For this first slice, Cadence derives provider readiness from existing durable
comms configuration:

- the selected `Spacecraft` is canonical mission identity;
- a spacecraft-bound `SourceEndpoint.source_ref` is the provider spacecraft
  reference;
- an active downlink `PathTemplate` selects the source endpoint and routing
  intent;
- a referenced active `ProviderProfile` with scheduling configuration selects
  the Provider Client;
- the provider profile's TCP configuration remains the contact-time data plane.

This is intentionally narrower than the idealized provider-account and explicit
provider-spacecraft-mapping model. It proves the workflow without creating a
second mapping system. A later provider-account slice can migrate the mapping
without changing Provider Reservation or Scheduled Contact semantics.

Provider lifecycle convergence uses durable status polling in Stage 1. A
supervised reconciler describes nonterminal reservations and applies idempotent
transitions. Durable event cursors and webhooks remain Stage 2 optimizations;
process memory is never the only source of reservation truth.

## Stage 1 Lifecycle

Cadence reservation states:

```text
requesting -> pending -> confirmed -> active -> completed
     |           |          |
     +--------> unknown      +-> canceling -> canceled
     +--------> rejected     +-> failed
```

Provider-native statuses are retained separately as evidence. The simulator
mapping for Stage 1 is:

| Simulator status | Cadence reservation state | Scheduled Contact action |
| --- | --- | --- |
| `pending` | `pending` | none |
| `scheduled` or `acquiring` | `confirmed` | materialize idempotently |
| `active` | `active` | ensure materialized |
| `completed` | `completed` | preserve result evidence |
| `rejected` | `rejected` | do not materialize |
| `canceled` | `canceled` | cancel materialized contact if present |
| `failed` or `terminated_early` | `failed` | cancel materialized contact if still scheduled |

`unknown` represents an ambiguous mutation outcome. The reconciler describes
the provider contact with the same durable idempotency context before any retry.

## Explicitly Out of Scope

- Contact Requirements and Contact Plans
- automatic opportunity scoring or optimization
- multi-provider search in one submission
- provider-account sharing across missions
- a second provider-spacecraft mapping table
- organization secret-store integration
- webhooks and durable provider event cursors
- modification or provider counteroffers
- uplink and bidirectional contacts
- a simulator console
- a general provider plugin system

## File Structure

### Cadence domain and persistence

- Create: `apps/cadence/lib/cadence/contacts/provider_reservation.ex`
- Create: `apps/cadence/lib/cadence/contacts/provider_reservations.ex`
- Create: `apps/cadence/lib/cadence/contacts/provider_scheduling.ex`
- Create: `apps/cadence/lib/cadence/contacts/provider_reservation_reconciler.ex`
- Modify: `apps/cadence/lib/cadence/contacts/provider_booking.ex`
- Modify: `apps/cadence/lib/cadence/contacts/provider_client.ex`
- Modify: `apps/cadence/lib/cadence/contacts/provider_clients/simulator_http.ex`
- Modify: `apps/cadence/lib/cadence/contacts/known_atom.ex`
- Modify: `apps/cadence/lib/cadence.ex`
- Modify: `apps/cadence/lib/cadence/application.ex`
- Create: `apps/cadence/lib/cadence/persistence/schemas/provider_reservation_row.ex`
- Create: `apps/cadence/priv/repo/migrations/20260713000000_create_provider_reservations.exs`
- Delete after replacement:
  `apps/cadence/lib/cadence/contacts/provider_contact_reconciler.ex`

### Cadence tests

- Create: `apps/cadence/test/cadence/contacts/provider_reservations_test.exs`
- Create: `apps/cadence/test/cadence/contacts/provider_scheduling_test.exs`
- Create:
  `apps/cadence/test/cadence/contacts/provider_reservation_reconciler_test.exs`
- Modify: `apps/cadence/test/cadence/contacts/provider_booking_test.exs`
- Modify:
  `apps/cadence/test/cadence/contacts/provider_clients/simulator_http_test.exs`
- Modify: `apps/cadence/test/support/fake_provider_client.ex`

### Cadence web

- Create: `apps/cadence_web/lib/cadence_web/live/ops_contact_schedule_live.ex`
- Create:
  `apps/cadence_web/lib/cadence_web/live/ops_contact_schedule_live/components.ex`
- Create:
  `apps/cadence_web/lib/cadence_web/live/ops_contact_schedule_live/live_deps.ex`
- Create:
  `apps/cadence_web/lib/cadence_web/live/ops_contact_schedule_live/opportunity_token.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Modify: `apps/cadence_web/lib/cadence_web/components/ops_shell.ex`
- Modify: `apps/cadence_web/lib/cadence_web/live/ops_shell_hook.ex`
- Create:
  `apps/cadence_web/test/cadence_web/live/ops_contact_schedule_live_test.exs`
- Modify: `apps/cadence_web/test/support/fixtures.ex` only if a compact comms
  readiness fixture removes repeated setup from the new LiveView tests.

### Simulator integration proof

- Create:
  `apps/cadence_simulator/test/cadence_simulator/contact_scheduling_integration_test.exs`
- Modify: `docs/simulator_provider_integration_flow.md`
- Modify: `docs/ground-network-simulator.md`

## Task 1: Persist Provider Reservation attempts

### Domain shape

Create `Cadence.Contacts.ProviderReservation` with these fields:

```elixir
provider_reservation_id
organization_id
mission_id
provider_profile_id
provider_profile_version
scheduled_contact_id
provider_opportunity_ref
provider_contact_ref
idempotency_key
lifecycle_state
provider_status
spacecraft_id
provider_spacecraft_ref
source_endpoint_refs
path_template_ids
starts_at
ends_at
request_document
response_document
last_error_document
attempt_count
last_reconciled_at
metadata
```

Keep provider-native documents string-keyed and bounded. Do not place raw
credentials or the provider profile's full configuration in reservation
evidence.

### Migration and constraints

Create `provider_reservations` with a string primary key and
`:utc_datetime_usec` timestamps. Add:

- unique `(mission_id, provider_reservation_id)` scope index;
- unique `(mission_id, provider_profile_id, idempotency_key)` index;
- partial unique `(mission_id, provider_contact_ref)` index where the external
  reference is non-null;
- `(organization_id, mission_id, lifecycle_state, last_reconciled_at)` index for
  due reconciliation;
- `(organization_id, mission_id, scheduled_contact_id)` index for contact detail
  lookup.

Follow the repository's existing organization-scope convention rather than
adding isolated authorization logic to this table.

### Persistence API

`Cadence.Contacts.ProviderReservations` owns row access and transitions. Its
initial public API should be:

```elixir
create_attempt/2
fetch/3
fetch_by_idempotency_key/4
fetch_by_provider_contact_ref/3
list_for_mission/2
list_due_for_reconciliation/2
record_provider_response/4
record_provider_error/4
mark_canceling/3
materialize_scheduled_contact/3
apply_provider_status/4
```

Every public function takes organization scope first. State transitions validate
the current state and are idempotent when the requested result already exists.

`materialize_scheduled_contact/3` uses `Ecto.Multi` to update the reservation and
insert the preallocated Scheduled Contact together. It uses the selected source
endpoint and path-template references stored on the attempt. Repeated calls
return the same records.

### Tests

Add isolated tests for:

- organization and mission scoping;
- idempotent creation by provider profile and idempotency key;
- rejection of a conflicting payload under the same idempotency key;
- provider-contact-reference uniqueness;
- allowed and rejected state transitions;
- idempotent Scheduled Contact materialization;
- atomic rollback when the Scheduled Contact is invalid;
- due-reconciliation ordering and filtering.

Run:

```bash
mix test apps/cadence/test/cadence/contacts/provider_reservations_test.exs
```

Do not proceed until migration and domain tests pass.

## Task 2: Convert Provider Booking into a durable saga

Replace the current reserve-first/in-memory compensation flow in
`ProviderBooking.book/5` with these phases:

1. Resolve the exact active Provider Profile version.
2. Validate and normalize selected route and opportunity attributes.
3. Preallocate `provider_reservation_id`, `scheduled_contact_id`, and
   idempotency key.
4. Persist the `requesting` attempt.
5. Return the existing attempt without another provider mutation when the
   idempotency key already exists with the same normalized payload.
6. Call `reserve_contact/3` outside a database transaction.
7. Persist the normalized response and provider evidence.
8. Materialize the Scheduled Contact immediately only when the normalized
   provider status is confirmed or active.
9. Persist definitive rejection/failure or ambiguous `unknown` state.

Rename the primary operation to `reserve/5`. Keep `book/5` as a documented
delegate during Stage 1 only if existing callers require it.

Provider error handling must distinguish:

- definitive HTTP rejection: persist `rejected` or `failed`;
- transport error before any request is sent, when knowable: persist `failed`;
- timeout, disconnect, or uncertain response: persist `unknown`;
- malformed success response: persist `unknown` with sanitized evidence.

Do not automatically submit a second reservation after an ambiguous outcome.

Add `cancel/4` by Provider Reservation ID. It marks the row `canceling` before
the external call, records the provider response, and idempotently cancels an
existing Scheduled Contact only after provider cancellation is known.

### Tests

Expand the fake provider client so each test can supply deterministic search,
reserve, describe, and cancel responses without process-global race conditions.

Cover:

- attempt exists before the fake client observes the request;
- repeated reserve call makes one provider mutation;
- pending response does not create a Scheduled Contact;
- confirmed response creates exactly one Scheduled Contact;
- provider rejection remains durable and creates no contact;
- ambiguous timeout becomes `unknown`;
- malformed provider times do not lose the attempt;
- cancellation passes through `canceling` and cancels the canonical contact;
- cancellation ambiguity leaves the contact intact and reconcilable.

Run:

```bash
mix test apps/cadence/test/cadence/contacts/provider_booking_test.exs
```

## Task 3: Normalize provider reservation status

Extend the Provider Client contract so reservation-returning operations have a
documented normalized minimum:

```text
id
status
starts_at
ends_at
provider_contact_ref, when distinct
provider-native evidence or extension map
```

Keep the current Provider Client behaviour provider-neutral. Status mapping
belongs in each adapter, not in the LiveView.

Update `SimulatorHTTP` to:

- preserve provider event envelopes as it does now;
- validate successful reservation and describe responses;
- return canonical status values or an explicit adapter normalization helper;
- classify HTTP and Req failures for the booking saga;
- never read global simulator configuration;
- keep using Req and the mission Provider Profile's scheduling configuration.

If status remains provider-native in the returned map, expose one adapter
callback or common normalized result struct rather than matching simulator
strings throughout Cadence.

### Tests

Add focused client tests for pending, scheduled, active, terminal, malformed,
HTTP rejection, rate limit, and ambiguous Req failures.

Run:

```bash
mix test apps/cadence/test/cadence/contacts/provider_clients/simulator_http_test.exs
```

## Task 4: Add durable reservation reconciliation

Replace the process-local `ProviderContactReconciler` with
`ProviderReservationReconciler`.

The reconciler:

- queries durable nonterminal or unknown reservations;
- fetches the exact Provider Profile version recorded on each attempt;
- resolves its Provider Client through the registry;
- calls `describe_contact/3` when a provider contact reference is known;
- uses an idempotency-aware recovery lookup when the adapter supports one and an
  ambiguous attempt has no provider reference;
- applies provider state through `ProviderReservations`;
- materializes or cancels Scheduled Contacts idempotently;
- records reconciliation time and sanitized errors;
- uses `Task.async_stream/3` with bounded concurrency and
  `timeout: :infinity`;
- applies backoff so an unavailable provider is not hammered.

The GenServer owns only polling cadence and triggering. Correctness remains in
the database-backed service functions, so restart loses no reservation truth.

Add application configuration:

```elixir
config :cadence, :provider_reservation_reconciler,
  enabled: true,
  safety_poll_interval_ms: 5_000,
  max_concurrency: 4
```

Disable automatic startup in `config/test.exs`; tests start a named reconciler
or call a pure `reconcile_due/2` entry point explicitly.

Place the child in `Cadence.Application` beside other safety reconcilers. It is
provider-neutral Cadence infrastructure, not simulator supervision.

### Tests

Cover:

- pending to confirmed creates the preallocated Scheduled Contact;
- replayed confirmed state creates no duplicate;
- active and completed states converge;
- rejected, canceled, failed, and terminated-early states converge;
- an unavailable provider records an error and remains due after backoff;
- mission and organization scope are preserved;
- one slow reservation does not prevent other due reservations from running;
- process restart re-reads durable work instead of depending on an in-memory
  cursor.

Run:

```bash
mix test apps/cadence/test/cadence/contacts/provider_reservation_reconciler_test.exs
```

## Task 5: Add provider scheduling readiness and search

Create `Cadence.Contacts.ProviderScheduling` to keep comms graph resolution out
of the LiveView.

### Ready route model

For a selected spacecraft, `list_ready_downlink_routes/3` returns view models
containing:

```text
spacecraft and provider spacecraft reference
source endpoint ID
path template ID and version
provider profile ID and version
provider display name
route display name
adapter/client capability
```

A route is ready when:

- the spacecraft exists in organization and mission scope;
- a Source Endpoint belongs to it and has a non-empty `source_ref`;
- an active downlink Path Template references that endpoint;
- the template references an active Provider Profile;
- the provider configuration enables a known scheduling client;
- the provider has a delivery host, port, and valid framing needed for Stage 1.

Return structured readiness findings for missing source reference, downlink
route, provider, scheduling client, run scope, or data-plane configuration. The
Ops page should link configuration failures back to the relevant Comms page.

### Search operation

`search_opportunities/5` accepts a validated ready-route key and a UTC window. It
constructs provider parameters with the Source Endpoint's `source_ref` as the
provider spacecraft ID, calls `ProviderBooking.search/5`, and returns normalized
opportunities plus the exact routing context required for reservation.

Validate:

- start precedes end;
- start is not materially in the past;
- horizon is bounded for Stage 1;
- returned opportunity spacecraft matches the requested provider reference;
- returned times lie within the requested window;
- opportunity IDs are present;
- no more than the configured UI result limit is returned.

### Tests

Cover one ready route and each readiness blocker separately. Prove that a route
cannot cross organization or mission scope and that provider result validation
rejects mismatched spacecraft or malformed times.

Run:

```bash
mix test apps/cadence/test/cadence/contacts/provider_scheduling_test.exs
```

## Task 6: Add the authenticated Ops route and navigation

Add these routes inside the existing `live_session :ops` block:

```elixir
live "/missions/:mission_id/ops/contacts", OpsContactScheduleLive, :index
```

This location is mandatory because the page is an authenticated mission
operations workflow and needs the assigns installed by:

- `OrganizationAuth.require_organization_scope`;
- `MissionAuth.load_mission`;
- `UserAuth.attach_user_menu`;
- `OpsShellHook`.

Do not create a public controller route or place the page in the Comms
`live_session`. Comms owns durable setup; Ops owns scheduling and execution.

Add an enabled `Contacts` rail link in the `Modes` section of `OpsShell`, using
the imported `<.icon>` component and `ops_nav_item == :contacts`. The contact
LiveView assigns `:ops_nav_item` to `:contacts` on mount.

Start the LiveView with:

```heex
<Layouts.ops ...>
```

only if the project layout convention requires the LiveView itself to invoke
the layout. The current `:ops` live-session layout already wraps its children;
do not double-wrap the page. Preserve the existing `current_scope` contract.

### First route tests

Before adding search behavior, prove:

- signed-in mission member can mount `#ops-contacts-page`;
- anonymous user redirects to sign-in;
- user outside the organization cannot load the mission;
- Contacts rail link is present and active;
- page shows an empty scheduled/reservation state;
- Comms provider setup remains outside the Ops page.

Use element IDs and `has_element?/2`, not raw HTML comparisons.

Run:

```bash
mix test apps/cadence_web/test/cadence_web/live/ops_contact_schedule_live_test.exs
```

## Task 7: Implement opportunity search in LiveView

The initial page contains:

- page heading and concise downlink-only scope copy;
- spacecraft select;
- ready downlink route/provider select;
- UTC start and end inputs;
- Search button;
- streamed Opportunity results;
- streamed current Provider Reservations/Scheduled Contacts;
- readiness empty state with Comms remediation link.

Use `to_form/2`, `<.form for={@search_form}>`, and existing `<.input>`
components. Give key elements stable IDs:

```text
#ops-contacts-page
#contact-opportunity-search-form
#contact-spacecraft
#contact-route
#search-contact-opportunities
#contact-opportunities
#provider-reservations
```

Use LiveView streams for opportunities and reservation/contact rows. Track
counts and empty flags in separate assigns. Do not enumerate a stream to find a
booking candidate.

Search runs through `start_async/3` so provider latency does not block the
LiveView process. Disable repeated submission while the same search is active
and ignore stale results using a search reference.

### Signed opportunity tokens

Each streamed Opportunity includes a short-lived signed booking token produced
by `OpportunityToken`. The token contains:

- organization and mission IDs;
- provider profile ID and version;
- path template ID and version;
- source endpoint ID;
- provider spacecraft reference;
- normalized opportunity snapshot;
- issued-at context.

Booking verifies the token with a short maximum age and re-resolves the route in
current scope. Never trust client-submitted station, time, provider, or route
fields directly, and do not keep a second enumerable opportunity collection in
socket assigns.

`LiveDeps` supplies narrow functions for readiness, search, reserve, cancel, and
list operations. Production defaults call Cadence contexts. Tests inject fakes
through the existing application-config pattern used by other Ops LiveViews.

### Search tests

Cover:

- readiness options load for the selected spacecraft;
- invalid or inverted window shows form feedback;
- async search renders streamed opportunities;
- no-results state;
- provider error state with retry action;
- stale async result does not overwrite a newer search;
- opportunities cannot cross mission scope;
- expired or tampered booking token is rejected.

Use `render_async/1` where required by LiveView async behavior.

## Task 8: Implement reservation, status, and cancellation UI

Clicking Reserve:

1. verifies the signed opportunity token;
2. revalidates current route readiness;
3. starts an async durable reservation saga;
4. disables only that opportunity's action;
5. streams the resulting Provider Reservation row;
6. shows pending, confirmed, failed, or unknown status without claiming more
   certainty than Cadence has;
7. refreshes canonical Scheduled Contact linkage after reconciliation.

The page schedules a lightweight database refresh while connected and while any
visible reservation is nonterminal. It must not poll the provider from the
LiveView. Provider polling belongs to `ProviderReservationReconciler`.

Reservation rows show:

- spacecraft;
- provider and station;
- confirmed time range;
- provider state;
- Cadence Scheduled Contact state when present;
- last reconciliation time or error;
- cancellation action when allowed.

Cancellation calls the durable saga asynchronously. A `canceling` or `unknown`
row remains visible until reconciliation proves the provider result.

### UI tests

Cover:

- one Reserve click creates one attempt;
- double click or replayed event creates no duplicate provider mutation;
- pending reservation displays without a Scheduled Contact;
- confirmed reconciliation links a Scheduled Contact;
- rejected and acquisition-failed states remain visible;
- cancellation transitions through provider state correctly;
- refresh updates stream rows with `reset: true` rather than enumerating streams;
- all interaction tests use key element IDs and outcome assertions.

Run the complete page file after each interaction slice:

```bash
mix test apps/cadence_web/test/cadence_web/live/ops_contact_schedule_live_test.exs
```

## Task 9: Prove realization and simulator telemetry end to end

Add an integration test in `cadence_simulator`, where Cadence is already a
test-only dependency.

The test must use the simulator's provider HTTP boundary for scenario, run,
search, reservation, describe, and cancellation operations. It may start a
test Bandit endpoint in the test BEAM, but must not call `CadenceSimulator.Provider`
directly for workflow actions.

The test setup persists normal Cadence resources:

- organization and mission;
- spacecraft and spacecraft-bound Source Endpoint whose `source_ref` matches
  simulator inventory;
- active downlink Provider Profile with simulator scheduling configuration and
  TCP listener data plane;
- active downlink Path Template;
- telemetry catalog/profile required by the normal runtime.

The proof then:

1. creates a simulator scenario and run through HTTP;
2. searches through `Cadence.Contacts.ProviderScheduling`;
3. reserves through the durable booking saga;
4. advances or waits for simulator provider confirmation;
5. invokes durable reservation reconciliation;
6. verifies exactly one canonical Scheduled Contact;
7. invokes the existing contact scheduler at the due time;
8. verifies one Realized Contact and active downlink path;
9. receives CCSDS TM frames through the normal TCP provider runtime;
10. verifies Cadence raw evidence and interpreted telemetry for the mission
    spacecraft;
11. completes the provider contact and verifies terminal reconciliation;
12. restarts the reconciler and verifies no duplicate reservation or contact.

Keep direct provider-domain tests in `provider_test.exs`; this new test is a
boundary proof, not another simulator unit test.

Run:

```bash
mix test apps/cadence_simulator/test/cadence_simulator/contact_scheduling_integration_test.exs
```

Add a separate manual two-BEAM smoke recipe to the integration guide. The
automated proof may share a BEAM for test practicality, but all simulator
workflow communication crosses HTTP and all telemetry crosses the configured
data plane.

## Task 10: Documentation, compatibility cleanup, and final gates

Update the simulator integration guide with the actual Ops workflow and the
final provider configuration fields.

Update the end-state spec's Current Baseline when Stage 1 is complete, but do
not mark later planning, provider-account, secret, or webhook stages complete.

Remove the old process-local `ProviderContactReconciler` and migrate its focused
tests to durable reservation reconciliation. Keep the Provider Client `events/3`
callback only if the Stage 2 event-cursor design will use it; otherwise document
it as provisional rather than supervising an unused process.

Run focused gates first:

```bash
mix test apps/cadence/test/cadence/contacts/provider_reservations_test.exs
mix test apps/cadence/test/cadence/contacts/provider_booking_test.exs
mix test apps/cadence/test/cadence/contacts/provider_reservation_reconciler_test.exs
mix test apps/cadence/test/cadence/contacts/provider_scheduling_test.exs
mix test apps/cadence_web/test/cadence_web/live/ops_contact_schedule_live_test.exs
mix test apps/cadence_simulator/test/cadence_simulator/contact_scheduling_integration_test.exs
```

Then run:

```bash
mix precommit
```

The slice is complete only when the full gate passes and the end-to-end test
proves the ordinary provider and telemetry boundaries.

## Definition of Done

- Provider Reservation is first-class, mission-scoped, durable, and idempotent.
- No HTTP request occurs inside a database transaction.
- Ambiguous provider outcomes remain recoverable without duplicate booking.
- Provider status reconciliation survives process restart.
- Confirmed reservations create exactly one Scheduled Contact.
- The existing contact scheduler realizes that contact without a simulator
  shortcut.
- The Ops Contacts page is in the authenticated `:ops` LiveView session and
  passes `current_scope` through all context calls.
- Collections on the LiveView use streams with stable DOM IDs.
- Operator input cannot forge provider opportunity or route details.
- Downlink telemetry enters the normal TCP provider and mission interpretation
  pipeline only while the contact is active.
- Rejection, acquisition failure, early termination, cancellation, and provider
  uncertainty are visible rather than collapsed into generic errors.
- Simulator production dependencies still exclude Cadence.
- `mix precommit` passes.
