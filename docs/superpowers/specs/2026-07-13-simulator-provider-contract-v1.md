# Simulator Provider Contract v1

- Status: accepted for Stage 2 implementation
- Created: 2026-07-13
- Scope: Define the external HTTP contract presented by the Cadence Ground
  Network Simulator and the normalized semantics consumed by Cadence provider
  adapters.
- Parent design:
  [Contact Scheduling and External Ground Network Simulation](2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)
- Implementation plan:
  [Stage 2 Provider and Delivery Contract](../plans/2026-07-13-contact-scheduling-stage-2-provider-delivery-contract.md)

## Summary

The simulator exposes two independent surfaces:

- an administration API for scenarios, runs, clocks, and faults;
- a customer-facing provider API for inventory, opportunity search, contact
  reservation, lifecycle reconciliation, and delivery negotiation.

Cadence uses only the provider API. It never creates simulator scenarios,
starts runs, advances simulation time, or activates faults.

The provider API does not make TCP the provider abstraction. A mission selects
a provider service profile and a provisioned delivery profile. A confirmed
contact returns or references an immutable delivery descriptor that Cadence
materializes into the ordinary contact and transport runtime.

TCP remains the first implemented data plane. The contract can also describe
UDP streams, object delivery, message buses, and provider-managed delivery
without changing contact scheduling semantics.

## North Star

> Cadence can replace the simulator with a commercial provider adapter without
> changing its operator contact workflow, canonical reservation semantics, or
> telemetry interpretation pipeline.

Provider-specific protocols and identifiers remain available as bounded
diagnostics. They are not required knowledge for an ordinary mission operator.

## Research Constraints

This contract reflects the documented differences between current providers:

- AWS Ground Station separates contact scheduling from Mission Profile and
  dataflow configuration. Contact confirmation is asynchronous, events are
  advisory, and data may be delivered through UDP-based dataflow endpoints,
  Ground Station Agent, or S3 recording.
- Leaf Space publicly describes a REST scheduling API with MQTT, TCP, UDP, and
  file-delivery options, while its detailed API and MQTT contracts are supplied
  during customer onboarding.

The simulator therefore models normalized provider behavior. It does not
attempt to reproduce AWS request signing, EventBridge, AWS packet formats, or
undocumented Leaf resources and MQTT topics.

Vendor-wire testing belongs in provider-specific adapter suites using official
digital twins, sandboxes, and sanitized fixtures.

## Locked Decisions

### Control plane and data plane are separate

The HTTP provider API carries low-rate control-plane resources and observations.
High-rate spacecraft data never travels through opportunity, contact, or event
JSON endpoints.

### Provider and Transport remain separate

A Provider is the external organization and control plane through which
capacity is discovered and reserved.

A Transport is a durable Cadence capability for moving bytes. It has one of two
origins:

- `direct`: configured by a Cadence administrator and usable without external
  scheduling;
- `provider_managed`: derived from a provider delivery profile and associated
  with an exact provider configuration version.

A provider-managed Transport still has an actual runtime kind such as TCP or
UDP. Its protocol fields are derived and normally read-only in Cadence.

### Service profiles and delivery profiles are distinct

A Service Profile describes what the provider supplies, such as realtime TT&C,
payload downlink, recording, or uplink.

A Delivery Profile describes where and how the supplied data is delivered. It
is provisioned before reservation and referenced by contacts. The exact
configuration is snapshotted for the contact.

### Contact state and delivery state are distinct

Provider reservation state, pass phase, and data-plane delivery state are
related but independently observable. A contact may enter pass while delivery
is degraded or failed.

### Polling remains authoritative

Events reduce latency but are advisory, at-least-once inputs. Describe and list
operations repair missing events and recover after restarts.

### The contract is versioned independently

`/provider/v1` is the simulator provider wire version. Cadence's normalized
Provider Client types have their own version. Vendor API versions remain inside
their adapters.

## API Surfaces

### Process health

`GET /health` reports only that the simulator process and HTTP listener are
available. It does not validate provider credentials, environment selection, or
run readiness.

### Administration API

The administration API is rooted at `/admin/v1` and uses an administrator
credential distinct from customer/provider credentials.

Initial resources are:

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/admin/v1/scenarios` | Create a reusable scenario version |
| `GET` | `/admin/v1/scenarios` | List scenario versions |
| `GET` | `/admin/v1/scenarios/:id` | Read a scenario version |
| `POST` | `/admin/v1/scenarios/:id/runs` | Start an immutable run snapshot |
| `GET` | `/admin/v1/runs` | List runs |
| `GET` | `/admin/v1/runs/:id` | Inspect a run |
| `POST` | `/admin/v1/runs/:id/pause` | Pause lifecycle advancement |
| `POST` | `/admin/v1/runs/:id/resume` | Resume lifecycle advancement |
| `POST` | `/admin/v1/runs/:id/stop` | Stop a run |

Creating a run returns a `provider_environment_ref`. Cadence stores that
reference as simulator-specific Provider Account configuration. It is not part
of an opportunity or contact request.

### Provider API

The customer-facing provider API is rooted at `/provider/v1`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/provider/v1/account` | Validate credentials and selected environment |
| `GET` | `/provider/v1/capabilities` | Read behavior, operation, and delivery capabilities |
| `GET` | `/provider/v1/spacecraft` | Discover provider spacecraft inventory |
| `GET` | `/provider/v1/ground-stations` | Discover stations and service pools |
| `GET` | `/provider/v1/service-profiles` | Discover provisioned provider services |
| `GET` | `/provider/v1/delivery-profiles` | Discover delivery destinations |
| `POST` | `/provider/v1/delivery-profiles` | Provision a destination when supported |
| `GET` | `/provider/v1/delivery-profiles/:id` | Read one delivery profile and health |
| `POST` | `/provider/v1/opportunities/search` | Search provider availability |
| `POST` | `/provider/v1/contacts` | Request provider capacity |
| `GET` | `/provider/v1/contacts` | Reconcile by client reference or bounded filters |
| `GET` | `/provider/v1/contacts/:id` | Read authoritative provider state |
| `PATCH` | `/provider/v1/contacts/:id` | Modify capability-declared schedule or resource fields |
| `POST` | `/provider/v1/contacts/:id/cancel` | Request cancellation |
| `GET` | `/provider/v1/contacts/:id/result` | Read delivered-contact summary when available |
| `GET` | `/provider/v1/events` | Consume advisory provider events |

The first implementation may select a simulator environment through an
`X-Simulator-Environment-Ref` header supplied by the simulator adapter. A
shared deployment may instead derive the environment from the credential. The
header is simulator-specific account context and must not leak into Cadence's
canonical contact model.

## Authentication and Correlation

The initial simulator uses bearer credentials, with separate configured values
for `/admin/v1` and `/provider/v1`.

Every request accepts `X-Request-ID`. The simulator returns it in response
metadata and includes it in provider events caused by that request.

Cadence stores credential references, not raw credentials, in durable provider
configuration. The local adapter may resolve an environment-backed credential
reference for development. Secrets are never returned in API evidence,
delivery descriptors, diagnostics, events, or logs.

## Envelopes

Successful singular responses use:

```json
{
  "data": {},
  "meta": {
    "contract_version": "1.0",
    "request_id": "request-123"
  }
}
```

List responses additionally include bounded pagination metadata:

```json
{
  "data": [],
  "meta": {
    "contract_version": "1.0",
    "request_id": "request-123",
    "next_cursor": null,
    "truncated": false
  }
}
```

Provider-native extension fields live under an `extensions` object. Cadence
retains bounded, sanitized extensions as provider evidence instead of promoting
every field into its canonical model.

## Capabilities

`GET /provider/v1/capabilities` returns the behavior of the selected simulator
environment, not merely all features the simulator binary knows how to run.

Minimum shape:

```json
{
  "contract_version": "1.0",
  "provider": {
    "type": "cadence_ground_network_simulator",
    "display_name": "Cadence Ground Network Simulator",
    "simulated": true
  },
  "operations": {
    "opportunity_search": true,
    "contact_reservation": true,
    "contact_modification": true,
    "contact_cancellation": true,
    "inventory_discovery": true,
    "delivery_profile_provisioning": true
  },
  "reservation": {
    "confirmation": "asynchronous",
    "idempotency": "native",
    "recovery": "client_reference"
  },
  "events": {
    "polling": true,
    "webhooks": false,
    "delivery_semantics": "at_least_once"
  },
  "search": {
    "spacecraft_batch_limit": 100,
    "station_batch_limit": 30,
    "page_size_limit": 100
  },
  "delivery": {
    "kinds": ["realtime_stream"],
    "protocols": ["tcp"],
    "directions": ["downlink"]
  }
}
```

The simulator can exercise these reservation modes:

- `native`: repeated mutations with the same provider idempotency key return
  the original resource; a conflicting payload returns `409`;
- `client_reference`: the provider has no native idempotency guarantee, but a
  timed-out request can be reconciled by a unique client reference or tag;
- `none`: Cadence cannot safely retry an ambiguous mutation automatically.

Cadence always creates a durable internal idempotency key. The adapter decides
whether the provider supports sending it, translating it into a client
reference, or retaining it only as local evidence.

## Inventory

Provider inventory identifiers are external references, never Cadence mission
identities.

Spacecraft responses include:

```text
id
display_name
supported_service_profile_refs
state
extensions
```

Ground-station responses include:

```text
id
display_name
region
service_pool_refs
antenna_count, when meaningful
state
extensions
```

Cadence maps these references explicitly to mission spacecraft and configured
provider use. It does not treat SCID as durable provider identity.

## Service Profiles

A Service Profile is provider-owned, reusable, and versioned.

Minimum shape:

```json
{
  "id": "service-realtime-ttc",
  "version": 1,
  "display_name": "Realtime TT&C downlink",
  "service_kind": "realtime_telemetry",
  "direction": "downlink",
  "supported_delivery_kinds": ["realtime_stream"],
  "data_families": ["ccsds_tm"],
  "minimum_duration_seconds": 30,
  "state": "active",
  "extensions": {}
}
```

Provider-specific names such as an AWS Mission Profile ARN or a Leaf service
configuration are adapter evidence. Cadence presents the operator summary and
keeps the external reference available in diagnostics.

## Delivery Profiles

A Delivery Profile is provisioned before contact reservation and versioned when
its effective destination changes.

Minimum read shape:

```json
{
  "id": "delivery-cadence-primary",
  "version": 1,
  "display_name": "Cadence primary telemetry ingress",
  "direction": "downlink",
  "delivery_kind": "realtime_stream",
  "supported_service_profile_refs": ["service-realtime-ttc"],
  "state": "ready",
  "operator_summary": "Streaming to Cadence",
  "diagnostics": {
    "protocol": "tcp",
    "framing_family": "ccsds_tm",
    "endpoint_health": "healthy"
  },
  "extensions": {}
}
```

Provisioning a TCP destination is a setup operation, not a reservation field:

```json
{
  "display_name": "Cadence primary telemetry ingress",
  "client_reference": "mission-123-primary-downlink",
  "direction": "downlink",
  "delivery_kind": "realtime_stream",
  "target": {
    "protocol": "tcp",
    "mode": "provider_connects",
    "host": "cadence.internal",
    "port": 4100
  },
  "framing": {
    "family": "ccsds_tm",
    "mode": "fixed_size",
    "frame_bytes": 1115
  }
}
```

Cadence normally shows `operator_summary` and readiness. Host, port, protocol,
framing, endpoint health, provider identifiers, and encryption metadata are
available under an administrator diagnostic disclosure.

Credentials are represented only by opaque credential references. A delivery
profile response never returns a secret, private key, password, or bearer token.

## Opportunity Search

Minimum request:

```json
{
  "spacecraft_refs": ["SC-001"],
  "ground_station_refs": [],
  "service_profile_ref": "service-realtime-ttc",
  "starts_at": "2026-07-13T12:00:00Z",
  "ends_at": "2026-07-14T12:00:00Z",
  "page_size": 100,
  "cursor": null
}
```

The selected capability profile may restrict searches to one spacecraft, one
station, or a smaller page. The adapter performs bounded fan-out when a real
provider has a narrower API.

Minimum opportunity shape:

```text
id
spacecraft_ref
ground_station_ref
antenna_or_service_pool_ref
service_profile_ref
starts_at
ends_at
expires_at
availability
estimated_capacity, when known
synthetic
extensions
```

Opportunity IDs are stable within an immutable run. An opportunity is still a
proposal: successful search never guarantees successful reservation.

## Contacts

Cadence's durable `ProviderReservation` is integration state. The external
provider resource is called a Contact in this API.

Minimum reservation request:

```json
{
  "opportunity_ref": "opportunity-123",
  "spacecraft_ref": "SC-001",
  "service_profile_ref": "service-realtime-ttc",
  "delivery_profile_ref": "delivery-cadence-primary",
  "client_reference": "cadence-reservation-123",
  "tags": {
    "cadence_mission_ref": "mission-123"
  }
}
```

The `Idempotency-Key` header is sent only when the selected environment
declares native idempotency. `client_reference` remains present for correlation
and recovery.

Minimum contact response:

```json
{
  "id": "contact-123",
  "revision": 2,
  "client_reference": "cadence-reservation-123",
  "opportunity_ref": "opportunity-123",
  "spacecraft_ref": "SC-001",
  "ground_station_ref": "station-svalbard",
  "antenna_or_service_pool_ref": "station-svalbard-antenna-1",
  "service_profile_ref": "service-realtime-ttc",
  "delivery_profile_ref": "delivery-cadence-primary",
  "starts_at": "2026-07-13T12:10:00Z",
  "ends_at": "2026-07-13T12:20:00Z",
  "status": "confirmed",
  "pass_phase": "scheduled",
  "delivery": {},
  "status_reason": null,
  "tags": {},
  "extensions": {}
}
```

The service and delivery profiles used for reservation are snapshotted. Later
profile changes do not silently alter an existing contact.

### Contact modification

When `contact_modification` is declared, Cadence may send
`PATCH /provider/v1/contacts/:id` before the Contact becomes active:

```json
{
  "client_reference": "cadence-change-123",
  "expected_revision": 2,
  "starts_at": "2026-07-13T12:11:00Z",
  "ends_at": "2026-07-13T12:21:00Z",
  "antenna_or_service_pool_ref": "station-svalbard-antenna-2",
  "reason": "operator_requested"
}
```

The simulator accepts only schedule and ground-resource fields. Service,
Delivery Profile, spacecraft, direction, protocol, endpoint, framing, and
credential changes are rejected as setup changes. `expected_revision` provides
optimistic concurrency. Every successful Contact change increments `revision`.

Modification uses the environment's declared mutation idempotency behavior.
Under native idempotency, `Idempotency-Key` is required and repeating the same
key and payload returns the current Contact without creating another revision.
A reused identity with a different payload or a stale expected revision returns
`409`.

Cadence normalizes every Contact response into an authoritative snapshot.
Requested, provider-confirmed, and Cadence-accepted snapshots remain distinct;
receiving a higher provider revision does not itself authorize an execution
change.

### Contact lifecycle

Normalized contact status is:

```text
pending -> confirmed -> active -> completed
   |          |            |
   +-> rejected            +-> failed
              +-> canceling -> canceled
```

Pass phase is separate:

```text
scheduled -> prepass -> pass -> postpass -> closed
```

Not every provider exposes every phase. Missing phases are allowed and declared
through capabilities or adapter normalization.

`status` drives reservation convergence. `pass_phase` explains operational
timing and contact diagnostics.

### Delivery descriptor

Once known, `delivery` contains an immutable contact-scoped descriptor:

```json
{
  "status": "ready",
  "direction": "downlink",
  "delivery_kind": "realtime_stream",
  "mode": "provider_connects",
  "protocol": "tcp",
  "endpoint_ref": "endpoint-456",
  "framing": {
    "family": "ccsds_tm",
    "mode": "fixed_size",
    "frame_bytes": 1115
  },
  "allowed_source_refs": ["SC-001"],
  "activation_window": {
    "starts_at": "2026-07-13T12:09:30Z",
    "ends_at": "2026-07-13T12:20:30Z"
  },
  "credential_ref": null,
  "diagnostics": {
    "endpoint_health": "healthy"
  }
}
```

Delivery status is independent of contact status:

```text
pending -> ready -> connected -> flowing -> ended
                          |          |
                          +-> degraded
                          +-> failed
```

`protocol`, endpoint details, and framing are adapter/runtime inputs and
administrator diagnostics. The primary operator label comes from the delivery
profile, such as `Streaming to Cadence` or `Recording to object storage`.

### Contact result

After or during a contact, `/contacts/:id/result` may return:

```text
planned and actual acquisition/loss times
delivered duration
bytes, frames, packets, and objects delivered
loss, duplication, corruption, and disconnect observations
provider and delivery failure reasons
delivery-profile and descriptor references
extensions
```

The provider result is evidence. Cadence combines it with its own runtime and
telemetry observations to produce the canonical Contact Result.

## Events

`GET /provider/v1/events?cursor=...&limit=...` returns ordered events for the
selected provider environment.

Minimum event shape:

```json
{
  "id": "event-123",
  "schema_version": "1.0",
  "sequence": 123,
  "occurred_at": "2026-07-13T12:10:00Z",
  "type": "contact.status_changed",
  "resource_type": "contact",
  "resource_id": "contact-123",
  "resource_revision": 2,
  "request_id": "request-123",
  "client_reference": "cadence-reservation-123",
  "data": {}
}
```

Supported event families include:

```text
contact.status_changed
contact.modified
contact.pass_phase_changed
delivery.status_changed
delivery.health_changed
contact.result_updated
inventory.changed
provider.health_changed
```

Events are at-least-once inputs and may be duplicated. Configured simulator
behavior may delay or omit advisory delivery to test polling repair. A Cadence
polling cursor advances only after every event in the page is durably inserted,
deduplicated, or quarantined in the same commit as the cursor. Domain processing
may happen later and remains idempotent; its state transition and audit evidence
commit together.

Provider adapters normalize each event into a `ProviderEvent` before returning
the page. Event types remain bounded strings rather than dynamically created
atoms so a future provider-native event can be durably quarantined without
expanding the VM atom table.

Event objects always contain string-keyed JSON data. Any LiveView or UI that
streams them must normalize them to a struct or configure the stream DOM ID;
wire maps are not UI models.

## Errors

Error responses use:

```json
{
  "error": {
    "code": "no_capacity",
    "detail": "The selected antenna is no longer available.",
    "retryable": false,
    "retry_after_seconds": null,
    "provider_request_ref": "provider-request-123"
  },
  "meta": {
    "contract_version": "1.0",
    "request_id": "request-123"
  }
}
```

Canonical error categories are:

```text
invalid_request
authentication_failed
authorization_failed
unsupported_capability
not_found
conflict
no_capacity
rate_limited
provider_unavailable
known_timeout
ambiguous_outcome
malformed_response
permanent_rejection
```

HTTP status alone is insufficient for retry decisions. `429` includes a retry
hint. A simulator fault can commit a mutation and then terminate the response
to produce a genuine ambiguous outcome.

## Configurable Provider Behavior

Scenario versions define a provider behavior profile in addition to stations,
fleet, opportunities, telemetry, and network faults.

Initial behavior controls include:

```text
native, client-reference, or no provider idempotency
immediate or asynchronous confirmation
confirmation delay
single or batched spacecraft/station search
page and horizon limits
rate limiting
request latency and provider outage
response loss before or after mutation commit
event duplication, delay, and omission
cancellation cutoff and ambiguity
contact phase support
delivery readiness, degradation, partial delivery, and failure
```

Named built-in profiles describe behaviors rather than vendors:

- `reference_native`
- `reference_async`
- `reference_best_effort_events`
- `reference_client_reference_recovery`
- `reference_non_idempotent`

They must not be labeled AWS-compatible or Leaf-compatible without a verified
vendor wire contract.

## Security and Evidence

- Admin and provider credentials are distinct outside an explicitly local
  profile.
- Provider environment selection is authorized by the provider credential.
- Returned evidence is bounded and sanitized before Cadence persists it.
- Raw delivery credentials never appear in provider evidence.
- Diagnostics may include endpoint addresses, ports, regions, profile IDs,
  protocol, framing, encryption mode, and health, but never secret material.
- Correlation IDs cross control-plane and data-plane logs.
- Delivery endpoint provisioning is auditable and idempotent.

## Stage 1 Migration

Stage 1 currently exposes scenarios and customer operations under one `/v1`
namespace and sends `host`, `port`, and `tm_frame_size` inside every contact
reservation.

Stage 2 replaces that contract atomically across the simulator and Cadence
adapter:

1. Move scenario/run operations to `/admin/v1`.
2. Move customer operations to `/provider/v1`.
3. Provision the TCP destination once as a Delivery Profile.
4. Reference Service and Delivery Profiles during search and reservation.
5. Return a delivery descriptor from contact describe.
6. Materialize the descriptor through the ordinary Transport and contact
   runtime.

The API has not been released as a public compatibility promise. Stage 2 does
not retain legacy `/v1` aliases or the per-reservation `data_plane` object. The
two applications and their tests change in one bounded implementation stage.

## Explicit Non-Goals

- General runtime plugin loading
- AWS or Leaf wire-protocol emulation
- A full organization-wide Provider Account product in this contract
- High-rate data delivery through JSON or the event feed
- Uplink and bidirectional execution in the first v1 implementation
- UDP, MQTT, and object-delivery runtime implementations before the
  provider-managed TCP proof is green
- A simulator console as part of the provider contract
- Hiding provider-specific evidence from administrators

## Contract Test Requirements

The simulator provider contract suite must cover:

- admin/provider namespace and credential separation;
- capability discovery for every built-in behavior profile;
- inventory and profile pagination;
- delivery-profile provisioning, sanitization, and health;
- opportunity pagination, expiry, and contention;
- all idempotency and ambiguous-outcome modes;
- contact and pass-phase transitions;
- independent delivery transitions;
- event duplication and polling repair;
- cancellation cutoff and uncertainty;
- result evidence;
- restart recovery from durable simulator state;
- absence of high-rate telemetry in HTTP provider resources.

The Cadence simulator adapter suite must cover the same semantics after
normalization. The end-to-end proof must still reserve over HTTP and receive
CCSDS telemetry through the ordinary contact-time transport.

## Definition of Done

- Cadence never calls `/admin/v1`.
- Simulator administration and provider credentials are independently
  configurable.
- Provider capability, service-profile, and delivery-profile resources exist.
- Contact requests contain profile references rather than raw TCP endpoint
  fields.
- Contact describe returns or references an immutable delivery descriptor.
- Contact status, pass phase, and delivery status are separately observable.
- Provider idempotency support is a declared capability rather than an assumed
  universal feature.
- Polling can repair missing or duplicated advisory events.
- Ordinary Cadence users see provider service and delivery summaries.
- Administrators can inspect protocol and endpoint diagnostics without seeing
  secrets.
- The separate-app TCP scheduling and telemetry proof remains green.
