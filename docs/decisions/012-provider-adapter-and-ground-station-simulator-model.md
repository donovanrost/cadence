---
title: "ADR-012: Provider Adapter and Ground Station Simulator Model"
aliases:
  [provider adapter, ground station simulator, gs provider model, tcp provider]
tags: [adr, architecture, provider, transport, simulator, gsaas, tcp]
status: accepted
created: 2026-03-30
updated: 2026-03-30
---

# ADR-012: Provider Adapter and Ground Station Simulator Model

> CCSDS code sharing and the simulator's independent dependency/configuration
> boundary are defined by [ADR-013](013-shared-ccsds-library-boundary.md).

## Status

Accepted

## Context

ADR-006 established that contact, path, and transport runtime are first-class
operational scopes under `realized_contact`.

ADR-007 established that first-party capability logic must not perform direct
external side effects and must instead emit typed action requests.

Cadence now has:

- realized contact and path runtime
- transport-local extensions under path runtime
- typed `uplink_request` execution
- real `TC` framing and narrow `COP-1`
- dev ingress harnesses for `space_packet` and `TM` transfer frames

The next external-integration question is how Cadence should interact with real
or simulated ground systems.

There are two important product realities:

- long-term, Cadence should support multiple commercial ground-station-as-a-
  service providers
- near-term, the most useful development and lab path is a TCP-based simulator
  like legacy Cadence's `mix cadence.simulate`

Legacy Cadence's simulator approach worked well operationally, but it mixed
several concerns into one runtime shape:

- telemetry generation
- packet and frame encoding
- socket ownership
- partial uplink handling
- protocol/runtime assumptions tied to the old channel-service topology

The new architecture needs to preserve the good parts of that experience
without turning a simulator transport into the permanent architectural center of
the system.

## Decision

Cadence will use an explicit **provider adapter boundary** under the contact
and transport runtime.

Providers are the external integration layer that actually exchanges bytes or
provider-native status with a real or simulated ground system.

Cadence core owns mission logic, command release policy, framing, transport
protocol state, canonical records, and verification. Provider adapters own
external I/O only.

Cadence will also support an **external Ground Station Simulator** as a
first-class development and lab tool. The simulator is not the provider model
itself. It is one external peer that can talk to one provider adapter,
initially a TCP provider.

## Model

### 1. Provider Means External Link-System Integration

In this architecture, a provider is the concrete adapter that:

- sends bytes from Cadence to an external system
- receives bytes or status from an external system
- translates provider-native events into canonical transport or ingress inputs

Examples include:

- a TCP socket transport used in development or lab environments
- a custom ground station front-end integration
- a commercial GSaaS API such as AWS Ground Station

Provider does **not** mean:

- CCSDS framing logic
- `COP-1` state machine logic
- command approval or queueing
- mission semantic handling

Those remain Cadence concerns.

### 2. Provider Adapters Live Under Realized Contact and Path Runtime

Provider adapters are operational, path-local concerns.

They belong under the ADR-006 runtime shape:

- `realized_contact`
- directional `path`
- transport runtime under the path

Cadence should not revive a mission-global channel-service process that owns
provider integration, framing, and semantic dispatch together.

### 3. Cadence Owns Protocol and Mission Logic

Cadence remains responsible for:

- command staging, request, approval, queueing, and release
- command encoding and `TC` transfer-frame generation
- `COP-1` sender logic and timer behavior
- downlink frame decoding and packet extraction
- canonical persistence and replay
- command verification state
- telemetry semantic handling and projections

Provider adapters should not decide:

- whether a command is allowed to release
- how command priority works
- how `COP-1` sender state behaves
- how telemetry packets are interpreted semantically

### 4. Provider Adapters Own External I/O Only

Provider adapters own:

- connection or session establishment with the external system
- send and receive of raw octets or provider-native messages
- provider-specific authentication or API request mechanics
- translation between provider-native messages and Cadence transport events
- provider-specific health and error reporting

Provider adapters should emit canonical operational records and events rather
than hiding external outcomes inside opaque logs.

### 5. Typed Boundary

The provider boundary should remain typed and platform-owned.

At minimum, the boundary must support:

- outbound `uplink_request`
- inbound downlink byte delivery
- inbound provider status and acknowledgement events
- provider connection and fault records

The important boundary rule is:

- Cadence core emits typed action requests
- provider adapters perform external I/O
- provider adapters feed the resulting observations back into canonical
  transport or ingress paths

This keeps provider integrations compatible with replay, audit, and later
multi-provider support.

### 6. TCP Is The First Provider

Cadence will implement a narrow TCP provider first.

This is not because TCP is the desired long-term commercial abstraction.
It is because it is the fastest and most useful way to:

- exercise the new runtime end to end
- support local development
- support lab integration
- support a future external simulator
- avoid prematurely designing around one commercial GSaaS vendor

The first TCP provider should support:

- outbound uplink byte delivery from `uplink_request`
- inbound downlink frame or packet ingestion
- inbound `CLCW` or related transport reports
- durable provider-side status and failure recording

### 7. The Ground Station Simulator Is External

Cadence will treat the Ground Station Simulator as an external companion tool,
not as a special internal runtime mode.

The simulator may:

- generate telemetry values
- encode them into packets and transfer frames
- send them to Cadence over the TCP provider
- receive `TC` transfer frames from Cadence
- emit `CLCW` reports or simulated delivery behavior back to Cadence
- simulate loss, latency, and degraded link behavior

This preserves the usefulness of legacy `mix cadence.simulate` without forcing
Cadence core to own simulator sockets or simulator process topology.

### 8. Simulator Is A Peer, Not The Architecture

The simulator should exercise the same provider boundary that real integrations
use.

That means:

- no privileged simulator-only path inside the mission runtime
- no separate hidden command or telemetry injection path for the simulator
- no simulator-specific semantic shortcuts

The simulator may remain a dev-oriented product surface, but it should talk to
Cadence through the provider boundary.

### 9. GSaaS Providers Use The Same Boundary

Commercial GSaaS providers must fit the same model as the TCP provider.

Some providers may expose:

- streaming socket interfaces
- REST or job APIs
- scheduled contact APIs
- provider-native status and acknowledgement events

Cadence should adapt those differences inside provider adapters, not by
rewriting the command or telemetry core for each vendor.

This preserves a stable Cadence core while still allowing provider-specific
capabilities.

### 10. AWS Ground Station Is Not The Canonical Shape

AWS Ground Station may be the first commercial provider with public
documentation, but Cadence should not treat its API surface as the canonical
architecture for all providers.

Cadence should instead define its own provider boundary and adapt AWS Ground
Station onto it later.

This avoids baking one vendor's workflow into:

- contact modeling
- command release semantics
- downlink ingest semantics
- transport verification state

### 11. Dev Harnesses Remain Useful

Existing mission-scoped dev ingress endpoints remain valid as direct platform
exercise tools.

Examples:

- dev `space_packet` injection
- dev `TM` transfer-frame injection

These are still useful for deterministic testing and control-plane bootstrap.

But they are not the long-term provider path and should not replace provider
adapters for integrated uplink/downlink system testing.

### 12. Anti-Decisions

Cadence should not:

- treat the TCP provider as the universal long-term provider abstraction
- collapse provider logic into command release or transport state machines
- make the simulator a hidden internal transport mode of Cadence core
- design the provider boundary around one commercial vendor
- require commercial-provider work before recovering the useful local simulator
  workflow

## Consequences

### Positive

- preserves the successful legacy simulator workflow in a cleaner architecture
- gives Cadence a practical first provider for development and lab use
- keeps protocol and mission logic inside Cadence core
- makes future GSaaS support additive rather than architectural rework
- gives simulator and real providers the same external integration seam

### Negative

- introduces another explicit subsystem boundary to design and implement
- requires provider-specific adapters instead of one generic socket shortcut
- means the simulator must evolve alongside the provider boundary rather than
  living as an isolated internal tool

## Follow-On Work

- define the concrete provider adapter ABI and runtime ownership model
- implement the first TCP provider adapter under path or transport runtime
- add a dev or API surface for injecting provider-side transport reports such as
  `CLCW`
- revive the legacy simulator as an external tool that targets the TCP provider
- later add one commercial provider adapter, likely AWS Ground Station first
