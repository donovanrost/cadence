# Stage 2 Provider and Delivery Contract Implementation Plan

**Status:** in progress

**Progress (2026-07-14):** Simulator Provider Contract v1 now includes
environment-scoped, idempotent Delivery Profile provisioning; paginated
opportunity search through Service Profiles; profile-backed Contact creation,
lookup, cancellation, and recovery; independent Contact status, pass phase, and
delivery state; bounded Contact Results; and versioned environment-scoped
events. A profile-backed Contact now has an executable proof that opens the
provisioned TCP destination, streams CCSDS telemetry, and records delivery
counters. Contract fixtures cover opportunity, lifecycle, result, and event
documents. Cadence now has validated provider-neutral context, capability,
profile, opportunity, Contact, delivery-descriptor, and error types. Its Req
adapter uses `/provider/v1`, opaque credential references, capability-selected
idempotency, normalized pagination, and structured error classification.
Scheduling, booking, reconciliation, the fake client, and Ops reservation
payloads now use profile and correlation references instead of `run_id` or raw
endpoint fields. The separate-app boundary proof creates the environment
through `/admin/v1`, provisions a Delivery Profile, schedules through
`/provider/v1`, and still receives ordinary CCSDS telemetry over TCP. Legacy
simulator `/v1` routes have been removed. Task 6 adds versioned, mission-scoped
Provider persistence; opaque runtime credential resolution; validation and
bounded inventory/profile synchronization; and the authenticated Mission
Provider list, create, and detail journey. Task 7 adds explicit direct and
provider-managed Transport origins, an allow-listed Transport Kind registry,
exact Provider and profile version snapshots, provider-derived TCP runtime
materialization, and the progressive Transport journey. Task 8 binds provider
opportunity search and reservations to exact Routing Rule, Transport, Mission
Provider, Service Profile, and Delivery Profile versions; validates immutable
delivery descriptors before runtime use; persists pass and delivery observations
separately; and exposes the complete chain in Ops Contacts. Task 9 rewrites the
separate-app proof through real admin and provider HTTP boundaries, normal TCP/TM
ingress, durable reconciler restart, and client-reference recovery after a
response is lost following provider commit. Tasks 1-9 are complete; Task 10,
documentation and final gates, is next. The runtime Provider Profile remains
execution evidence, not control-plane identity.

**Goal:** Replace the Stage 1 TCP-shaped provider setup with an explicit mission
Provider control plane and provider-managed Transport. The simulator exposes
the accepted Provider Contract v1, contacts reference service and delivery
profiles, and the existing end-to-end TCP telemetry proof remains green without
putting raw endpoint fields in reservation requests.

**Design sources:**

- [Simulator Provider Contract v1](../specs/2026-07-13-simulator-provider-contract-v1.md)
- [Contact Scheduling and External Ground Network Simulation](../specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)
- [Comms Transport, Routing, and Spacecraft Profile UX](../specs/2026-06-01-comms-transport-routing-and-spacecraft-profile-design.md)

## Outcome

After Stage 2, the normal flow is:

1. A simulator administrator creates a scenario and run through `/admin/v1`.
2. A mission administrator configures a Simulator Provider through
   **Comms → Providers**.
3. Cadence validates the provider and synchronizes capabilities, inventory,
   Service Profiles, and Delivery Profiles through `/provider/v1`.
4. The administrator provisions or selects `Streaming to Cadence` as a Delivery
   Profile.
5. Cadence creates a provider-managed TCP Transport from that profile.
6. An operator searches and reserves through **Ops → Contacts**.
7. The reservation references the Service and Delivery Profiles.
8. Contact describe returns the exact delivery descriptor.
9. Cadence materializes the existing TCP runtime and receives normal CCSDS TM
   telemetry only while the contact is active.

The operator does not enter TCP fields during contact scheduling. Protocol,
endpoint, framing, and health remain available in administrator diagnostics.

## Locked Decisions

- The simulator is a canonical provider reference, not an AWS or Leaf wire
  emulator.
- Simulator administration and provider APIs have separate namespaces and
  credentials.
- Provider setup is control-plane configuration. It contains no TCP listener,
  framing, or reconnect fields.
- Transport setup owns the durable byte-moving capability.
- Transports declare `direct` or `provider_managed` origin while retaining an
  actual runtime kind such as `tcp_socket`.
- Service Profiles describe provider services. Delivery Profiles describe
  pre-provisioned destinations.
- Contact requests contain profile references, not a raw `data_plane` object.
- Reservation status, pass phase, and delivery status remain separate.
- Stage 1 durable status polling remains the correctness path. Events stay an
  advisory seam; durable cursor ingestion is not required for this stage.
- TCP is the only required runtime delivery protocol in Stage 2. The contract
  must not prevent later UDP, object, or MQTT delivery.
- The pre-public `/v1` simulator API has no compatibility promise. Stage 2
  removes it while changing the simulator, adapter, tests, and docs atomically.
- No general plugin framework is introduced.

## Authenticated Route Placement

Provider and Transport setup routes remain inside the existing authenticated,
mission-scoped `live_session :comms` using `Layouts.mission_sidebar`:

```text
/missions/:mission_id/comms/providers
/missions/:mission_id/comms/providers/new
/missions/:mission_id/comms/providers/:provider_id
/missions/:mission_id/comms/transports
/missions/:mission_id/comms/transports/new
/missions/:mission_id/comms/transports/:transport_id
```

They belong there because Providers and Transports are durable mission setup.
The session already requires organization scope, loads the mission, and
attaches the authenticated user menu.

`/missions/:mission_id/ops/contacts` remains in authenticated
`live_session :ops` with `Layouts.ops` because opportunity search, reservation,
and contact execution are operational workflows.

Every context call receives `current_scope.organization_id` first. Templates
derive the user only through `@current_scope.user`; no `current_user` assign is
introduced.

## Bounded Scope

### Included

- `/admin/v1` and `/provider/v1` separation
- Separate simulator credentials and provider environment selection
- Capability, inventory, Service Profile, and Delivery Profile resources
- Delivery Profile provisioning for provider-connects TCP
- Contact resources with separate pass and delivery state
- Native and client-reference idempotency behavior
- Normalized Cadence provider types and Simulator HTTP adapter
- Mission-owned Provider setup
- Direct versus provider-managed Transport origin
- Dynamic, progressive Transport form
- Provider-managed TCP materialization through the existing runtime
- Updated reservation evidence, readiness, and diagnostics
- Contract, LiveView, and end-to-end tests

### Excluded

- Organization-shared Provider Accounts and mission grants
- A production secret-store backend beyond a narrow credential-reference
  resolver
- Durable event cursor or webhook ingestion
- Contact modification
- Contact Requirements and Contact Plans
- Multi-provider search in one request
- Uplink and bidirectional execution
- UDP, MQTT, SLE, and object-delivery runtimes
- AWS or Leaf adapters
- Simulator console
- General provider plugin packaging

## Target Cadence Model

### Mission Provider

Introduce `Cadence.GroundNetworks.MissionProvider` as the mission-owned product
object for an enabled provider control plane.

Initial fields:

```text
provider_id
organization_id
mission_id
version
lifecycle_state
display_name
provider_type
client_key
base_url
credential_ref
environment_ref
capabilities_document
inventory_sync_document
last_validated_at
last_synced_at
metadata
```

`provider_type` and `client_key` use explicit allow lists. Never create atoms
from submitted strings.

`credential_ref` is durable. A raw API token is not stored, rendered back into
a form, or included in evidence. The Stage 2 resolver supports an injected test
resolver and an explicitly configured environment reference for local use.

This object is intentionally mission-owned. A future organization Provider
Account becomes an input to this mission binding without changing the Provider
Client or contact contract.

### Provider-managed Transport

Extend `Cadence.Comms.Transport` with:

```text
origin: direct | provider_managed
mission_provider_id, when provider_managed
mission_provider_version, when provider_managed
service_profile_ref, when provider_managed
delivery_profile_ref, when provider_managed
provider_configuration_snapshot, sanitized
```

`transport_kind` remains the actual data-plane kind. A synchronized TCP
Delivery Profile creates a Transport with:

```text
origin = provider_managed
transport_kind = tcp_socket
adapter_key = tcp_socket
```

TCP host, port, mode, framing, and readiness are derived from the Delivery
Profile and read-only on a provider-managed Transport. Direct TCP Transports
continue to use the existing typed `TCPSocket` behavior.

### Runtime compatibility

`Cadence.Contacts.ProviderProfile` remains an internal runtime compatibility
resource during Stage 2. It is no longer the product object shown at
**Comms → Providers**.

Persisting either Transport origin materializes the exact runtime Provider
Profile needed by the current path and contact runtime. Provider-managed
materialization uses the sanitized Delivery Profile snapshot.

Late-bound per-contact endpoints remain a future runtime extension. The Stage 2
simulator TCP profile is provisioned before reservation and stable for the
Transport version.

### Provider Reservation

Replace scheduling reliance on `provider_profile_id` with exact Mission
Provider and Transport versions. Add or replace fields so reservations own:

```text
provider_id
provider_version
transport_id
transport_version
service_profile_ref
delivery_profile_ref
delivery_descriptor_document
pass_phase
delivery_state
```

Keep provider-native documents bounded and string-keyed. An exact runtime
Provider Profile reference may remain as execution evidence, but it is not the
control-plane Provider identity.

## Task 1: Establish executable contract fixtures

Create JSON fixtures under:

```text
apps/cadence_simulator/test/fixtures/provider_contract/v1/
```

Include capabilities, Service Profile, Delivery Profile, opportunity page,
pending/confirmed/active/completed Contacts, Contact Result, event page, and
error examples.

Create `CadenceSimulator.Provider.Contract` to own:

- wire version;
- success, list, and error envelopes;
- cursor metadata;
- request ID propagation;
- bounded extension and diagnostic serialization.

Do not add a JSON-schema dependency. Use ordinary maps, explicit validators,
and ExUnit fixture assertions.

Create:

```text
apps/cadence_simulator/lib/cadence_simulator/provider/contract.ex
apps/cadence_simulator/test/cadence_simulator/provider/contract_test.exs
```

Cover every required field, string-keyed output, metadata, and secret
redaction. Run from `apps/cadence_simulator`:

```bash
mix test test/cadence_simulator/provider/contract_test.exs
```

## Task 2: Split simulator administration and provider routers

Keep `CadenceSimulator.Provider.Router` as the top-level Plug. It serves
`/health` and forwards to:

```text
apps/cadence_simulator/lib/cadence_simulator/provider/admin_router.ex
apps/cadence_simulator/lib/cadence_simulator/provider/api_router.ex
```

Add separate runtime configuration:

```text
CADENCE_SIMULATOR_ADMIN_API_TOKEN
CADENCE_SIMULATOR_PROVIDER_API_TOKEN
```

An explicitly local profile may omit either token. Production configuration
rejects an enabled unauthenticated API.

Move scenario/run routes under `/admin/v1`. Move inventory, profiles, search,
Contacts, and events under `/provider/v1`. Remove Stage 1 `/v1` routes after the
Cadence adapter changes in the same branch.

Admin run responses include `provider_environment_ref`. The provider router
resolves `X-Simulator-Environment-Ref`, verifies access, and passes a resolved
environment into operations. Provider request bodies no longer contain
`run_id`.

Test health independence, credential separation, environment authorization,
route isolation, correlation IDs, and production authentication validation.

## Task 3: Add capabilities and provider profiles

Split the broad `CadenceSimulator.Provider` responsibilities into:

```text
apps/cadence_simulator/lib/cadence_simulator/provider/capabilities.ex
apps/cadence_simulator/lib/cadence_simulator/provider/inventory.ex
apps/cadence_simulator/lib/cadence_simulator/provider/service_profiles.ex
apps/cadence_simulator/lib/cadence_simulator/provider/delivery_profiles.ex
apps/cadence_simulator/lib/cadence_simulator/provider/behavior.ex
```

Extend Scenario normalization with:

```text
provider_behavior
service_profiles
delivery_profile_policy
data_plane_defaults
```

The run snapshot freezes those values. Extend `Provider.Store` for versioned
Delivery Profiles. Persist only setup, lifecycle, bounded result summaries, and
events; high-rate observations remain outside DETS.

Delivery Profile provisioning:

- validates direction, protocol, mode, port, and framing through explicit
  mappings;
- supports idempotent `client_reference`;
- produces sanitized summaries and administrator diagnostics;
- never echoes credentials;
- emits a profile-created event;
- makes the profile discoverable for Transport setup.

The only required Stage 2 profile is provider-connects TCP downlink with
fixed-size CCSDS TM framing.

Test all built-in behavior capability documents, run snapshot determinism,
profile versioning, invalid endpoints, environment isolation, redaction, and
health.

## Task 4: Add Contact and delivery lifecycles

Create or extract:

```text
apps/cadence_simulator/lib/cadence_simulator/provider/opportunities.ex
apps/cadence_simulator/lib/cadence_simulator/provider/contacts.ex
apps/cadence_simulator/lib/cadence_simulator/provider/contact_lifecycle.ex
apps/cadence_simulator/lib/cadence_simulator/provider/contact_results.ex
```

Change the wire resource from `/contact-reservations` to `/contacts`. Rename the
DETS kind while the API is pre-public unless a smaller internal migration has a
clear benefit.

Search requires a Service Profile. Contact creation requires opportunity,
service, delivery, spacecraft, and client references. It rejects `host`,
`port`, `tm_frame_size`, `definitions_path`, and a raw `data_plane` object.

Contacts snapshot Service and Delivery Profiles and expose:

```text
status
pass_phase
delivery.status
delivery descriptor
status reason
provider extensions
```

Update `Provider.Orchestrator` so contact lifecycle drives pass phase, stream
health drives delivery state, and TCP workers start from the snapshotted
descriptor. Delivery failure does not erase Contact state. Completion records
bounded delivery counters. Every visible transition emits a versioned event.

Test native idempotency, client-reference recovery, response loss after commit,
event duplication/omission, cancellation uncertainty, delivery degradation,
and polling repair. Preserve existing capacity, acquisition, loss, latency, and
teardown coverage.

## Task 5: Expand the normalized Cadence Provider Client

Introduce provider-neutral types under `Cadence.GroundNetworks`:

```text
provider_context.ex
provider_capabilities.ex
service_profile.ex
delivery_profile.ex
opportunity.ex
provider_contact.ex
delivery_descriptor.ex
provider_error.ex
```

Every type validates external maps at the adapter boundary. Native values stay
under sanitized evidence or extensions.

Change `Cadence.Contacts.ProviderClient` callbacks to accept a
`ProviderContext` rather than a runtime `ProviderProfile`:

```elixir
validate_connection(context, opts)
capabilities(context, opts)
list_spacecraft(context, params, opts)
list_ground_stations(context, params, opts)
list_service_profiles(context, params, opts)
list_delivery_profiles(context, params, opts)
provision_delivery_profile(context, attrs, opts)
search_opportunities(context, params, opts)
reserve_contact(context, attrs, opts)
describe_contact(context, provider_contact_ref, opts)
cancel_contact(context, provider_contact_ref, opts)
find_contact_by_client_reference(context, client_reference, opts)
events(context, cursor, opts)
```

Optional callbacks are capability-gated. Do not call unsupported operations.

Update `SimulatorHTTP` to use `/provider/v1`, send the environment header,
resolve credentials through an injected resolver, preserve request IDs,
normalize pagination, choose idempotency strategy from capabilities, parse
separate lifecycles and descriptors, and classify structured errors. Keep using
`Req`.

Extend `FakeProviderClient` for every new operation without process-global
mutable configuration.

## Task 6: Persist mission Provider setup

Create:

```text
apps/cadence/lib/cadence/ground_networks.ex
apps/cadence/lib/cadence/ground_networks/mission_provider.ex
apps/cadence/lib/cadence/ground_networks/mission_providers.ex
apps/cadence/lib/cadence/ground_networks/credential_resolver.ex
apps/cadence/lib/cadence/persistence/schemas/mission_provider_row.ex
apps/cadence/priv/repo/migrations/*_create_mission_providers.exs
```

The organization-scoped context API is:

```elixir
persist_provider/2
fetch_provider/3
fetch_provider_version/4
list_providers/2
version_provider/4
archive_provider/3
validate_provider/3
sync_provider/3
provider_context/3
```

`validate_provider/3` checks account/environment access and capabilities.
`sync_provider/3` stores a bounded cache of inventory and profile summaries. It
does not silently create Cadence spacecraft.

Replace the primary `/comms/providers` LiveViews with Mission Provider product
surfaces. They collect display name, provider type, base URL, credential
reference, and simulator environment reference. They offer **Validate** and
**Sync profiles** actions and show control-plane health, sync freshness,
profiles, capabilities, a simulated badge, and administrator diagnostics.

They do not render TCP mode, host, port, framing, reconnect, or TLS inputs.

The routes stay in authenticated `live_session :comms`; change their parameter
from `provider_profile_id` to `provider_id`. Delete obsolete Provider Profile
form code rather than preserving overlapping product surfaces.

## Task 7: Add Transport origin and progressive configuration

Modify:

```text
apps/cadence/lib/cadence/comms/transport.ex
apps/cadence/lib/cadence/comms/transport_kind.ex
apps/cadence/lib/cadence/comms/transport_store.ex
apps/cadence/lib/cadence/comms/transport_kinds/tcp_socket.ex
apps/cadence/lib/cadence/persistence/schemas/comms_transport_row.ex
apps/cadence/priv/repo/migrations/*_add_provider_origin_to_comms_transports.exs
```

Add a Transport Kind registry. It maps allow-listed form values to behavior
modules and provides form metadata without converting user input to atoms.

Change `CommsTransportNewLive` into a progressive form:

1. Identity
2. Origin: Direct or Ground Station Provider
3. Direct kind or Mission Provider selection
4. Kind-specific direct fields or Delivery Profile selection
5. Framing/reliability fields only when user-configurable
6. Summary and administrator diagnostics

Direct TCP retains the current endpoint, framing, reconnect, and TLS fields.

Provider-managed setup selects a validated Mission Provider and compatible
Service and Delivery Profiles, derives the actual kind/configuration, renders
normal fields read-only, and persists the exact versions. Raw protocol details
live under a diagnostic disclosure.

Give every key form region and control a stable DOM ID. LiveView tests use
those IDs with `element/2` and `has_element?/2`, not raw HTML assertions.

List and detail pages show origin, provider, operator summary, and readiness.
They never label setup as connected.

## Task 8: Bind scheduling to Provider and Transport versions

Modify:

```text
apps/cadence/lib/cadence/contacts/provider_scheduling.ex
apps/cadence/lib/cadence/contacts/provider_booking.ex
apps/cadence/lib/cadence/contacts/provider_reservation.ex
apps/cadence/lib/cadence/contacts/provider_reservations.ex
apps/cadence/lib/cadence/contacts/provider_reservation_reconciler.ex
apps/cadence/lib/cadence/persistence/schemas/provider_reservation_row.ex
apps/cadence/priv/repo/migrations/*_bind_provider_reservations_to_transport.exs
```

Readiness resolves:

```text
mission spacecraft mapping
  -> routing rule / exact path selection
  -> exact provider-managed Transport version
  -> exact Mission Provider version
  -> compatible Service Profile
  -> ready Delivery Profile
```

Direct Transports remain valid for authoritative local scheduling but do not
gain external opportunity search merely because they materialize a runtime
Provider Profile.

Persist exact Provider, Transport, service, and delivery references before the
provider mutation. Send only profile and correlation references over HTTP.

When describe returns a delivery descriptor, validate it against the selected
Transport/Profile, persist the sanitized immutable document, update separate
pass and delivery observations, and preserve Scheduled Contact materialization.
Never rewrite a versioned Transport from a Contact response.

If a descriptor conflicts with approved setup, leave the reservation durable
and visible as a provider/configuration failure. Do not silently connect to an
unapproved endpoint.

Update **Ops → Contacts** to show Provider, Service, Delivery, Contact status,
pass phase, delivery status, Transport summary, and administrator diagnostics.
The route remains in authenticated `:ops` and collections retain stable stream
IDs.

## Task 9: Preserve the separate-app TCP proof

Rewrite the existing contact scheduling integration test to use only the new
boundaries:

1. Create scenario/run through `/admin/v1` with the admin credential.
2. Persist a Mission Provider with a provider credential reference.
3. Validate and sync `/provider/v1` resources.
4. Provision a TCP Delivery Profile.
5. Persist a provider-managed Transport from the profile.
6. Persist ordinary spacecraft mapping and routing.
7. Search and reserve through Cadence.
8. Prove the request contains profile references and no raw endpoint.
9. Reconcile Contact and delivery descriptor.
10. Materialize exactly one Scheduled Contact.
11. Realize the current runtime.
12. Receive and interpret normal CCSDS TM telemetry through TCP.
13. Observe independent Contact, pass, and delivery completion.
14. Restart reconciliation and prove no duplicates.

Add a second boundary test for client-reference recovery with a
response-lost-after-commit fault. It proves Cadence does not assume provider
idempotency.

Tests may share a BEAM, but all workflow operations cross HTTP and all
high-rate telemetry crosses TCP.

## Task 10: Documentation and final gates

Update:

```text
docs/ground-network-simulator.md
docs/simulator_provider_integration_flow.md
docs/how-to/add-a-provider-adapter.md
docs/superpowers/specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md
```

Document actual environment variables, API paths, Provider setup, Delivery
Profile provisioning, Transport creation, Ops workflow, diagnostics, and the
two-BEAM smoke test. Remove instructions that configure scheduling inside a TCP
Provider Profile or send endpoint fields during every reservation.

Run focused suites from their owning applications:

```bash
cd apps/cadence_simulator
mix test test/cadence_simulator/provider
mix test test/cadence_simulator/contact_scheduling_integration_test.exs

cd ../cadence
mix test test/cadence/ground_networks
mix test test/cadence/comms/transport_store_test.exs
mix test test/cadence/contacts/provider_clients/simulator_http_test.exs
mix test test/cadence/contacts/provider_scheduling_test.exs
mix test test/cadence/contacts/provider_booking_test.exs
mix test test/cadence/contacts/provider_reservation_reconciler_test.exs

cd ../cadence_web
mix test test/cadence_web/live/comms_provider_live_test.exs
mix test test/cadence_web/live/comms_transport_live_test.exs
mix test test/cadence_web/live/ops_contact_schedule_live_test.exs
```

Then run from the umbrella root:

```bash
mix precommit
```

## Definition of Done

- Administration and provider APIs use separate namespaces and credentials.
- Cadence never calls simulator administration routes.
- Provider request bodies contain neither `run_id` nor raw endpoint fields.
- Mission Provider is the primary control-plane setup object.
- Provider Profile is no longer the primary Provider product form.
- Transport explicitly distinguishes direct and provider-managed origin.
- The Transport form progressively renders only relevant fields.
- Provider-managed protocol fields are derived and read-only.
- Capabilities and provider profiles synchronize through the Provider Client.
- Reservation references exact service, delivery, Provider, and Transport
  versions.
- Contact status, pass phase, and delivery state are separately observable.
- Native idempotency and client-reference recovery pass boundary tests.
- Ordinary TCP/TM runtime remains the telemetry path in the end-to-end proof.
- No raw credentials are persisted or rendered.
- Protocol details appear only as administrator diagnostics.
- Simulator production dependencies still exclude Cadence core.
- Focused suites and `mix precommit` pass.

## Follow-On After Stage 2

1. Provider-connects UDP with datagram framing and source validation.
2. Object delivery with manifest polling and PCAP ingestion.
3. Leaf MQTT TT&C after customer topic, QoS, and payload documentation exists.
4. Durable event cursors and webhooks once a commercial adapter makes their
   exact semantics concrete.
