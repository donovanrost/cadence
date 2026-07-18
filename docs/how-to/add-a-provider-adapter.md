---
title: Add a Ground Network Provider Integration
tags: [how-to, developer, provider, transport, ingress]
status: active
created: 2026-04-03
updated: 2026-07-15
---

# Add a Ground Network Provider Integration

Cadence deliberately has no general plugin loader. Provider integrations are
first-party modules selected through explicit, allow-listed registries. This
keeps provider evidence, credential handling, and runtime configuration inside
reviewed application code while commercial integrations teach us what a future
packaging model actually needs.

A provider integration can touch three independent layers:

| Layer | Responsibility | Main behavior |
| --- | --- | --- |
| Provider Client | Vendor control plane: capabilities, inventory, profiles, opportunities, Contacts, and recovery | `Cadence.Contacts.ProviderClient` |
| Transport Kind | Durable mission setup and derivation of approved byte-moving configuration | `Cadence.Comms.TransportKind` |
| Runtime adapter | Path-local data-plane I/O after a Contact is realized | `Cadence.ProviderAdapters.Adapter` |

Do not collapse these layers. A REST reservation API does not imply that
telemetry travels over HTTP, and a TCP runtime does not make an internal runtime
Provider Profile the provider control-plane identity.

## 1. Decide which layers are new

Most commercial integrations need a new Provider Client. They may reuse the
existing provider-connects TCP Transport Kind and TCP runtime adapter if the
provider supplies a compatible Delivery Profile.

Add a new Transport Kind and runtime adapter only when the provider introduces a
new data-plane contract such as UDP datagrams, object delivery, SLE, or a cloud
stream. Provider-specific names should not create duplicate runtime adapters for
the same wire behavior.

## 2. Implement the Provider Client

Implement
[`Cadence.Contacts.ProviderClient`](../../apps/cadence/lib/cadence/contacts/provider_client.ex)
under `apps/cadence/lib/cadence/contacts/provider_clients/`.

The current canonical operations are:

- connection validation and capability discovery;
- spacecraft and ground-station inventory;
- Service and Delivery Profile discovery;
- optional Delivery Profile provisioning;
- opportunity search;
- Contact reservation, description, capability-declared modification, and
  cancellation;
- optional recovery by client reference;
- optional provider event polling.

The simulator reference implementation is
[`Cadence.Contacts.ProviderClients.SimulatorHTTP`](../../apps/cadence/lib/cadence/contacts/provider_clients/simulator_http.ex).
It uses `Req`; new HTTP clients must also use the existing `Req` dependency.

Provider Clients receive a `Cadence.GroundNetworks.ProviderContext`. They do not
read LiveView assigns, simulator run state, or Transport runtime processes.

Opportunity pages must retain bounded provider-level evidence independently of
the opportunity list. Put facts such as ephemeris reference/version, orbit-data
validity, and provider validation status in `provider_evidence`. This is
required even when `data` is empty. A provider that cannot evaluate the horizon
because orbit data is missing, expired, or still processing must normalize to a
provider-not-ready error, not successful empty availability.

## 3. Normalize and sanitize at the boundary

Translate vendor payloads into the canonical types under
`Cadence.GroundNetworks`:

- `ProviderCapabilities`
- `ServiceProfile`
- `DeliveryProfile`
- `Opportunity`
- `ProviderContact`
- `DeliveryDescriptor`
- `ProviderError`

Keep provider-native fields in bounded, sanitized evidence. Do not add a vendor
field to the canonical model without a cross-provider use case. Never persist or
return raw access tokens, passwords, private keys, or ephemeral delivery
credentials.

Capabilities are executable behavior, not display metadata. Reject unsupported
operations before sending a provider request. Normalize retry hints, provider
revisions, change evidence, event identities, and ambiguous outcomes so booking,
delivery-policy evaluation, and reconciliation remain outside the LiveView and
outside vendor-specific code. Provider event pages must contain normalized
`ProviderEvent` structs, not raw string-keyed wire maps.

## 4. Preserve mutation and recovery semantics

Cadence persists its Provider Reservation, exact Provider Account/grant,
Mission Provider/Transport/profile/policy versions, request evidence, and
internal idempotency key before calling the Provider Client.

The client must follow the provider's declared behavior:

- use a native idempotency header only when the provider guarantees it;
- use a unique client reference or tag when that is the recovery mechanism;
- preserve an ambiguous outcome when the request may have committed and no safe
  retry exists.

Contact requests contain only provider resource and correlation references.
Endpoint addresses, framing, generator configuration, and raw credentials are
setup data and must not be copied into every reservation request.

For modifications, send the exact expected provider revision and a stable
change identity according to the provider's declared idempotency mechanism.
Normalize every response as an authoritative snapshot. Do not update the
Scheduled Contact in the adapter: the shared delivery-policy evaluator decides
whether a proposal is observed, accepted by bounded policy, approval-pending,
acknowledgment-required, or a non-approvable configuration failure.

## 5. Register the provider type explicitly

Add the client to
[`Cadence.Contacts.ProviderClients.Registry`](../../apps/cadence/lib/cadence/contacts/provider_clients/registry.ex).
Then extend the allow-listed provider types and `client_for/1` mapping used by
the Provider Account and Mission Provider boundaries.

Do not convert user-supplied provider or client names to atoms. Form values must
resolve through the explicit allow lists.

A versioned Provider Account is organization-owned and stores:

- provider type and client selection;
- API base URL, region, and provider environment/account reference;
- a stable credential-registry reference whose backend locator is owned by the
  credential registry;
- event ingestion mode/configuration, request policy, and organization
  guardrails;
- account validation, capability, and health evidence.

The secret itself belongs to the configured backend, not the database or
LiveView form. Production integrations use `Cadence.Secrets.ExternalBackend`
or another reviewed `Cadence.Secrets.Backend`; HTTP integrations use `Req` and
HTTPS by default. The environment backend is local-only and must be explicitly
enabled. Never pass raw material into provider evidence, audit, errors, or
diagnostics. Rotation keeps the stable credential reference; revocation fails
new operations closed while preserving history.

Organization administrators grant an exact Provider Account version to a
mission. Grant restrictions can only narrow account guardrails. A Mission
Provider then binds that exact account/grant pair and owns mission spacecraft
mappings, permitted resources, enabled service/delivery profiles, preferred
Transports, bounded inventory sync, validated capabilities, and the versioned
mission delivery policy. It does not own or copy the endpoint, environment, or
credential reference.

## 6. Map provider delivery into a Transport

Provider-managed Transports select exact Mission Provider, Service Profile, and
Delivery Profile versions. Their protocol configuration is derived and
read-only in the product UI. Reservations also snapshot the upstream Provider
Account, mission grant, and delivery-policy version.

If the provider's Delivery Profile maps to an existing Transport Kind, extend
that kind's derivation only when the canonical provider evidence is sufficient
to validate the mapping. A Contact response may report an immutable delivery
descriptor, but it must never rewrite a versioned Transport. Cadence validates
the descriptor against approved setup and records a durable configuration
failure when it conflicts.

Direct Transports remain user-configured local setup. Materializing runtime
compatibility evidence for a direct Transport must not grant external
opportunity search.

## 7. Add a Transport Kind when the wire contract is new

Transport Kind modules implement
[`Cadence.Comms.TransportKind`](../../apps/cadence/lib/cadence/comms/transport_kind.ex)
and live under `apps/cadence/lib/cadence/comms/transport_kinds/`.

They own:

- configuration normalization and validation;
- progressive-form metadata;
- operator-safe display summaries;
- temporary runtime Provider Profile materialization for the current execution
  engine.

Provider-managed derivation also needs an explicit, validated conversion from a
synchronized Delivery Profile and dispatch from `Cadence.Comms.TransportStore`.
The TCP reference is `Cadence.Comms.TransportKinds.TCPSocket.from_delivery_profile/1`.

Update the explicit registry and type allow lists in `Cadence.Comms.Transport`
and `Cadence.Comms.TransportKind`. Provider-managed fields must render read-only;
direct-origin fields may render as inputs when operators genuinely own them.

The internal `Cadence.Contacts.ProviderProfile` is execution evidence only. Do
not add it to the Provider product form or use it as scheduling control-plane
identity.

## 8. Add a runtime adapter when byte I/O is new

Runtime adapters implement
[`Cadence.ProviderAdapters.Adapter`](../../apps/cadence/lib/cadence/provider_adapters/adapter.ex)
under `apps/cadence/lib/cadence/provider_adapters/` and are registered in
[`Cadence.ProviderAdapters.Registry`](../../apps/cadence/lib/cadence/provider_adapters/registry.ex).

The reference implementation is
[`Cadence.ProviderAdapters.TCPSocket`](../../apps/cadence/lib/cadence/provider_adapters/tcp_socket.ex).

A runtime adapter owns:

- connect, listen, accept, and session lifecycle;
- transport framing into canonical ingress units;
- provider-local connection metadata;
- uplink byte delivery when applicable;
- operational state returned by `snapshot/1`.

It does not own spacecraft interpretation, telemetry extraction, dispatch,
archive persistence, opportunity search, or Contact booking.

Runtime adapters hand received units to
[`Cadence.Runtime.ProviderIngressExecutor`](../../apps/cadence/lib/cadence/runtime/provider_ingress_executor.ex)
using its ordered enqueue APIs. Runtime startup remains path-local under
`Cadence.Runtime.PathCoordinator`.

## 9. Keep the product journeys shared

The integration must use the existing authenticated journeys:

- organization **Provider Accounts** for shared control-plane endpoint,
  environment, credential lifecycle, ingestion health, and mission grants;
- **Comms → Providers** for a granted mission binding, mappings, delivery
  policy, validation, and sync;
- **Comms → Transports** for direct or provider-managed delivery setup;
- **Comms → Routing** for exact Transport selection;
- **Ops → Requirements** for versioned operational intent, multi-provider
  search evidence, opportunity comparison, exact Plan review, approval, and
  restart-safe execution;
- **Ops → Contacts** for direct ad hoc reservation and all realized/reserved
  Contact reconciliation, changes, approval/acknowledgment, and cancellation.

Do not create a provider-specific scheduling page. Provider differences appear
as capabilities, profile summaries, validation findings, and administrator
diagnostics.

## 10. Test each seam

At minimum, add:

- Provider Client normalization, authentication, capability, pagination, error,
  and evidence-sanitization tests;
- provider-level readiness evidence on both non-empty and empty search pages,
  plus an explicit not-ready proof for missing/expired orbital data;
- native-idempotency or client-reference recovery tests matching the provider's
  real guarantees;
- event normalization, duplicate, out-of-order, cursor-restart, identity
  collision, poison-event quarantine/reprocess, and missing-event safety-poll
  tests when polling is supported;
- modification revision conflict, post-commit ambiguity, provider-initiated
  change, bounded policy, approval, acknowledgment, configuration mismatch, and
  exactly-once Scheduled Contact revision tests when changes are supported;
- Transport Kind normalization, derivation, and progressive-form tests when the
  data plane changes;
- runtime framing, reconnect, handoff, and snapshot tests for a new adapter;
- a separate-application boundary proof that reserves over the provider control
  plane and moves high-rate data over the ordinary runtime path.

Commercial clients should pass the same canonical behavior suite as the
simulator plus provider-specific contract tests based on verified vendor
documentation.

## 11. Validate with the normal workflow

Exercise the integration as an operator would:

1. start the external provider or simulator independently;
2. create an organization Provider Account with a stable secret reference and
   validate it;
3. grant the exact account version to the mission;
4. create a Mission Provider from that grant, configure delivery policy, and
   synchronize capabilities, inventory, and profiles;
5. create a provider-managed Transport from exact compatible profile versions;
6. map spacecraft and create an enabled Routing Rule;
7. create a Requirement in **Ops → Requirements**, search every eligible route,
   select an opportunity, and create a Plan;
8. submit, approve, and execute the exact Plan version, or separately prove the
   direct ad hoc path in **Ops → Contacts**;
9. confirm Contact, pass, delivery, and Cadence observations independently;
10. ingest advisory events, describe authoritative state, and exercise one
   approval or acknowledgment path;
11. verify bytes enter the normal runtime and telemetry pipeline;
12. restart planning execution/ingestion/reconciliation and prove no duplicate
    provider mutation, domain decision, Scheduled Contact, or Scheduled Contact
    revision.

Run focused tests from the owning application, then run `mix precommit` from the
umbrella root.

## Checklist

- Provider Client behavior implemented and explicitly registered
- provider type and client mapping allow-listed
- external evidence normalized and sanitized
- provider-owned orbit/readiness evidence survives empty searches and
  not-ready errors without making Cadence an orbital propagator
- Provider Account owns endpoint, environment, stable credential reference,
  request policy, event ingestion, and organization guardrails
- mission access uses an exact, narrowing Provider Account grant
- Mission Provider owns mission mappings and delivery policy, not shared
  endpoint/environment/credential setup
- production credentials resolve through a reviewed backend; raw material is
  never persisted, rendered, logged, audited, or returned as evidence
- declared idempotency and recovery semantics covered
- durable event cursor/inbox behavior and quarantine recovery covered when
  events are supported
- provider changes use revision/idempotency semantics and the shared
  approval-versus-acknowledgment policy boundary
- Contact requests contain references, not endpoint setup
- provider-managed Transport derives exact, read-only protocol configuration
- new Transport Kind added only for a genuinely new wire contract
- runtime adapter remains path-local and hands off to the ordered executor
- shared Comms and Ops journeys remain intact
- separate control-plane and data-plane proof passes
- `mix precommit` passes
