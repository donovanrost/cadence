---
title: Add a Provider Adapter
tags: [how-to, developer, runtime, provider, ingress]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Add a Provider Adapter

This guide describes how to add a new path-local provider adapter to Cadence.

Use this guide when you need to integrate a new external transport boundary,
such as a WebSocket session, a vendor SDK, or another socket-based link.

The provider boundary is intentionally narrow:

- providers own transport I/O
- providers do not own mission semantics
- providers hand canonical ingress units to the ordered ingress executor

For the broader rationale, see the
[Developer Architecture Guide](../developer-architecture-guide.md).

## 1. Start from the adapter behavior

All provider adapters implement
[`Cadence.ProviderAdapters.Adapter`](../../apps/cadence/lib/cadence/provider_adapters/adapter.ex).

The behavior is intentionally small:

- `child_spec/1`
- `snapshot/1`
- `deliver_uplink/2`

That means your adapter runtime is a path-local worker with:

- a runtime child spec
- a runtime snapshot shape for diagnostics and API visibility
- an uplink delivery entrypoint when the path supports uplink

## 2. Put the module in the provider adapter namespace

Create the adapter under:

- `apps/cadence/lib/cadence/provider_adapters/`

The existing reference implementation is:

- [`Cadence.ProviderAdapters.TCPSocket`](../../apps/cadence/lib/cadence/provider_adapters/tcp_socket.ex)

Use that module as the model for:

- process ownership
- socket/session lifecycle
- runtime snapshot structure
- executor handoff

Do not copy its transport specifics blindly. Reuse its shape, not its TCP-only
details.

## 3. Keep the provider boundary narrow

A provider adapter should own:

- connect/listen/accept/session lifecycle
- provider-specific framing into canonical ingress message units
- provider-local metadata
- uplink byte delivery when applicable
- health and error reporting in `snapshot/1`

A provider adapter should not own:

- source-endpoint semantic interpretation
- telemetry decode or extraction
- dispatch evaluation
- archive or Postgres persistence
- UI-facing read models

The practical rule is:

> adapt external I/O into canonical Cadence ingress or transport events, then
> hand off

## 4. Hand off to the ordered ingress executor

Providers should enqueue into
[`Cadence.Runtime.ProviderIngressExecutor`](../../apps/cadence/lib/cadence/runtime/provider_ingress_executor.ex),
not call the whole ingress boundary directly.

The public handoff API is:

- `enqueue_telemetry/2`
- `enqueue_many_telemetry/2`
- `enqueue_transport_event/4`
- `enqueue_many_transport_events/4`

Prefer the batch forms when your transport naturally yields more than one
message at a time.

That preserves the intended split:

- provider: transport adaptation
- executor: ordered mission-facing runtime work
- projector: async persistence

## 5. Register the adapter

Add the new adapter key to:

- [`Cadence.ProviderAdapters.Registry`](../../apps/cadence/lib/cadence/provider_adapters/registry.ex)

That registry is what lets path runtime startup resolve `adapter_key` values
from provider bindings into actual modules.

If you skip this step, realized contact startup will fail with an unknown
provider adapter error.

## 6. Make sure path runtime startup can use it

Provider runtimes are started by
[`Cadence.Runtime.PathCoordinator`](../../apps/cadence/lib/cadence/runtime/path_coordinator.ex).

The startup flow is:

1. start a path-local persistence projector
2. start a path-local ingress executor
3. resolve the adapter module from the registry
4. start the provider runtime with path-local names and binding config

That means your adapter should accept path-local startup opts similar to the
existing TCP adapter:

- mission id
- realized contact id
- path id
- provider binding id
- source endpoint ref when applicable
- direction
- provider configuration
- ingress executor name

If your adapter has extra configuration, keep it inside the provider binding
configuration map instead of inventing a new side channel.

## 7. Wire mission-owned configuration, not ad hoc runtime config

Provider runtime startup comes from mission-owned provider profiles and
realized-contact path bindings.

The relevant domain types are under:

- `apps/cadence/lib/cadence/contacts/provider_profile.ex`
- `apps/cadence/lib/cadence/contacts/path.ex`

Use the provider profile configuration map as the source of transport-specific
options. Do not hard-code environment-specific behavior inside the adapter.

## 8. Design a useful runtime snapshot

`snapshot/1` is the operational debugging surface for a provider runtime.

At minimum, expose:

- connection state
- local host/port or peer/session identity
- ingress counts and byte counts
- recent error state
- whether reads are paused or backpressured
- ingress executor snapshot
- ingress persistence projector snapshot when relevant

The TCP adapter is the current model for a production-useful snapshot.

## 9. Add tests at the runtime seam

At minimum, add:

- unit tests for transport framing or session logic
- runtime tests that start the adapter in a path-local context
- snapshot assertions for the fields operators will inspect
- failure-path tests for disconnects, reconnects, and ingress handoff

The current reference file is:

- [`tcp_socket_provider_test.exs`](../../apps/cadence/test/cadence/runtime/tcp_socket_provider_test.exs)

## 10. Validate with the normal dev loop

After wiring the adapter:

1. add or update a dev profile that uses the new adapter
2. run the local development flow
3. verify the path runtime snapshot shows your provider runtime
4. confirm ingress reaches the executor and projector as expected

Start with:

```bash
iex --sname cadence -S mix phx.server
mix cadence.simulator demo_spacecraft
mix cadence.profile demo_spacecraft --snapshot
```

## Checklist

- module added under `provider_adapters/`
- behavior implemented
- registry updated
- configuration comes from provider bindings
- adapter hands off to `ProviderIngressExecutor`
- `snapshot/1` is operationally useful
- tests cover connect/listen/session and handoff paths
- profile-driven local workflow still works
