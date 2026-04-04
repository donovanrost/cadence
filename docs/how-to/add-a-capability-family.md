---
title: Add a Capability Family
tags: [how-to, developer, runtime, capabilities, managed-application, transport-extension]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Add a Capability Family

This guide describes how to add a new first-party capability family to the
Cadence runtime.

Use this when you are adding governed runtime behavior that should execute
inside the Cadence substrate rather than inside a provider adapter or ad hoc
service process.

For the runtime substrate itself, see
[Understand the Runtime Substrate and Capabilities](understand-the-runtime-substrate-and-capabilities.md).

## 1. Decide what kind of capability you are adding

The first decision is not code. It is runtime placement.

In practice, most new families should be one of:

- `:managed_application`
- `:transport_extension`

Choose a managed application when the behavior:

- reacts to decoded mission data
- belongs in a mission partition
- may keep partition-owned state
- may use managed timers

Choose a transport extension when the behavior:

- belongs to a path or transport binding
- reacts to transport events or control inputs
- should run in a transport runtime instead of a partition owner

Use the current examples as references:

- managed application:
  [`PacketCounter`](../../apps/cadence/lib/cadence/capabilities/managed_applications/packet_counter.ex)
- transport extension:
  [`UplinkGateway`](../../apps/cadence/lib/cadence/capabilities/transport_extensions/uplink_gateway.ex)

## 2. Implement the shared family behavior

Every capability family implements:

- [`Cadence.Capabilities.Family`](../../apps/cadence/lib/cadence/capabilities/family.ex)

That means providing:

- `descriptor/0`
- `validate_config/2`
- `build_instance/2`

These are the platform-facing hooks used by governance and the runtime
registry.

### `descriptor/0`

Return a [`Cadence.Capabilities.Descriptor`](../../apps/cadence/lib/cadence/capabilities/descriptor.ex)
that correctly declares:

- `family_key`
- `kind`
- `supported_scopes`
- `input_stages`
- `partition_affinity`
- `config_schema`
- `emitted_record_kinds`
- `emitted_action_kinds`
- `replay_mode`
- `state_mode`

Treat the descriptor as part of the platform contract, not incidental
metadata.

### `validate_config/2`

This is called with a
[`Cadence.Capabilities.ValidationContext`](../../apps/cadence/lib/cadence/capabilities/validation_context.ex).

Use it to reject invalid or scope-incompatible configuration before runtime
activation.

### `build_instance/2`

This is called with a
[`Cadence.Runtime.ActivationContext`](../../apps/cadence/lib/cadence/runtime/activation_context.ex).

Use it to normalize the configuration that the runtime will actually own for
that instance.

## 3. Implement the right execution behavior

After the shared family behavior, implement the runtime-specific behavior for
your capability kind.

### Managed application

Implement:

- [`Cadence.Capabilities.ManagedApplication`](../../apps/cadence/lib/cadence/capabilities/managed_application.ex)

Callbacks:

- `init_instance/2`
- `handle_record/3`
- `handle_timer/3`
- `snapshot_state/2`

These callbacks run inside partition-owned ordered execution.

### Transport extension

Implement:

- [`Cadence.Capabilities.TransportExtension`](../../apps/cadence/lib/cadence/capabilities/transport_extension.ex)

Callbacks:

- `init_transport/2`
- `handle_transport_event/3`
- `handle_control_input/3`
- `handle_timer/3`
- `snapshot_state/2`

These callbacks run inside a transport runtime.

## 4. Use the execution context instead of ambient state

Runtime callbacks receive:

- [`Cadence.Capabilities.ExecutionContext`](../../apps/cadence/lib/cadence/capabilities/execution_context.ex)

That context carries:

- mission id
- activation id
- binding set id and version
- current time
- partition key
- capability instance id
- scope ref
- metadata

Use this context instead of reaching into global runtime state or process
dictionaries.

That is important for:

- deterministic behavior
- replay realism
- testability

## 5. Return `ExecutionResult`, not side effects

Capability callbacks should return:

- [`Cadence.Capabilities.ExecutionResult`](../../apps/cadence/lib/cadence/capabilities/execution_result.ex)

That result contains:

- `state`
- `records`
- `action_requests`
- `metadata`

This is how a capability family asks the substrate to do work.

Do not directly:

- write Postgres rows
- write archive objects
- schedule your own timers with `Process.send_after/3`
- deliver uplinks from the family module

Instead:

- emit action requests
- emit records
- let the substrate execute and persist them

## 6. Register the family

Add the new family to:

- [`Cadence.Capabilities.Registry`](../../apps/cadence/lib/cadence/capabilities/registry.ex)

If you skip this step, governance validation and runtime lookup will both fail
with an unknown capability family error.

## 7. Make the descriptor honest

There are three common mistakes here:

- declaring the wrong `kind`
- declaring the wrong `supported_scopes`
- declaring the wrong `input_stages`

Those fields drive governance and runtime placement.

If the family handles decoded packets, do not pretend it is transport-local.
If it is path-local transport behavior, do not pretend it is a managed
application just because that feels simpler.

## 8. Keep capability code focused

Capability families should express mission or transport behavior.

They should not own:

- socket or session I/O
- provider lifecycle
- archive backend code
- auth or tenancy policy
- global orchestration

If the code starts looking like a runtime service every family would want, it
probably belongs in the substrate, not in the family.

## 9. Test at the right level

At minimum, add:

- unit tests for configuration normalization and validation
- callback tests for `handle_record/3`, `handle_transport_event/3`, or timers
- snapshot tests for state shape
- runtime integration tests if the family affects path or mission behavior

Use the current first-party families as examples for both style and scope.

## 10. Validate through the actual runtime path

After wiring the family:

1. make sure governance can validate it
2. make sure runtime descriptor lookup works
3. activate it through a real binding set or transport binding path
4. verify it appears in the relevant runtime snapshot

If it is a managed application, inspect partition snapshots.

If it is a transport extension, inspect path and transport runtime snapshots.

## Checklist

- correct kind chosen
- `Cadence.Capabilities.Family` implemented
- managed application or transport extension callbacks implemented
- descriptor fields are honest
- configuration validation is explicit
- callback results use `ExecutionResult`
- family added to `Cadence.Capabilities.Registry`
- tests cover config, callbacks, and snapshots
