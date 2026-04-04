---
title: Understand the Runtime Substrate and Capabilities
tags: [how-to, developer, runtime, capabilities, architecture]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Understand the Runtime Substrate and Capabilities

This guide explains the Cadence runtime substrate, the services it provides,
and how capability families fit into that runtime.

Use this guide when you need to answer questions like:

- what long-lived runtime services exist under a mission?
- where does ordered processing happen?
- what does a capability family actually get from the substrate?
- what belongs in a managed application versus a transport extension?

For the broader system view, see the
[Developer Architecture Guide](../developer-architecture-guide.md).

## 1. Start with the runtime tree

Cadence runtime is mission-rooted.

The top-level supervisor is:

- [`Cadence.Runtime.MissionRuntime`](../../apps/cadence/lib/cadence/runtime/mission_runtime.ex)

For each mission, it provides stable runtime names and supervisors for:

- realized contact runtimes
- partition owners
- path runtimes
- provider runtimes
- transport runtimes
- provider ingress executors
- provider persistence projectors

This naming layer matters because the rest of the runtime looks workers up by
mission, contact, path, transport binding, and provider binding identifiers.

## 2. Understand the core runtime services

The substrate is not one process. It is a set of cooperating services with
different responsibilities.

### MissionCoordinator

- module:
  [`Cadence.Runtime.MissionCoordinator`](../../apps/cadence/lib/cadence/runtime/mission_coordinator.ex)
- scope: mission
- job:
  - load the active activation and binding set
  - resolve the correct partition for ingress
  - ensure the partition owner exists
  - hand telemetry ingress to the partition owner

This is the runtime service that turns "ingress for mission X" into "ordered
processing in partition Y".

### PartitionOwner

- module:
  [`Cadence.Runtime.PartitionOwner`](../../apps/cadence/lib/cadence/runtime/partition_owner.ex)
- scope: mission partition, usually by source endpoint
- job:
  - own ordered semantic processing for that partition
  - manage managed-application state
  - decode TM ingress and dispatch packets
  - own managed-application timers
  - emit managed runtime records and async outputs

This is the core semantic execution engine for mission telemetry handling.

### ContactCoordinator

- module:
  [`Cadence.Runtime.ContactCoordinator`](../../apps/cadence/lib/cadence/runtime/contact_coordinator.ex)
- scope: realized contact
- job:
  - start path runtimes for the realized contact
  - expose contact-level snapshots
  - route transport events and control inputs to the correct path
  - own the contact-level downlink combiner

### PathCoordinator

- module:
  [`Cadence.Runtime.PathCoordinator`](../../apps/cadence/lib/cadence/runtime/path_coordinator.ex)
- scope: realized contact path
- job:
  - start provider runtimes for the path
  - start transport runtimes for the path
  - start the path-local ingress executor and persistence projector
  - expose path-level snapshots

This is the bridge between link-local workers and the mission runtime.

### ProviderIngressExecutor

- module:
  [`Cadence.Runtime.ProviderIngressExecutor`](../../apps/cadence/lib/cadence/runtime/provider_ingress_executor.ex)
- scope: path-local provider lane
- job:
  - accept canonical ingress units from providers
  - preserve ordered provider-local processing
  - perform mission-facing live work
  - emit compact processed batches to the async projector

This is the ordered live ingress lane that sits between provider I/O and async
persistence.

### IngressPersistenceProjector

- module:
  [`Cadence.Runtime.IngressPersistenceProjector`](../../apps/cadence/lib/cadence/runtime/ingress_persistence_projector.ex)
- scope: path-local provider lane
- job:
  - perform slower durable writes asynchronously
  - archive raw ingress and protocol artifacts
  - persist anomalies and other low-rate projections
  - keep the ordered live lane from blocking on storage

### TransportRuntime

- module:
  [`Cadence.Runtime.TransportRuntime`](../../apps/cadence/lib/cadence/runtime/transport_runtime.ex)
- scope: one transport capability instance
- job:
  - own the state of a transport extension
  - handle transport events, control inputs, and timers
  - emit transport records and action requests

This is the execution substrate for capability families whose scope is the link
or transport layer rather than mission packet dispatch.

### DownlinkCombiner

- module:
  [`Cadence.Runtime.DownlinkCombiner`](../../apps/cadence/lib/cadence/runtime/downlink_combiner.ex)
- scope: realized contact
- job:
  - merge competing downlink observations from multiple active paths
  - choose winners
  - emit combined records and diagnostics

This is a good example of a focused runtime service that is not itself a
general capability family.

### TimerService

- module:
  [`Cadence.Runtime.TimerService`](../../apps/cadence/lib/cadence/runtime/timer_service.ex)
- scope: partition-owned managed applications and transport runtimes
- job:
  - schedule and cancel timers
  - support both live and replay clocks
  - surface timer snapshots

This is part of the substrate because capability families should not reinvent
their own timer wheel.

## 3. Understand what a capability family is

Capability families are the plugin-like execution units of the runtime.

They are registered in:

- [`Cadence.Capabilities.Registry`](../../apps/cadence/lib/cadence/capabilities/registry.ex)

Current first-party families include:

- `definition_bound_telemetry`
- `packet_counter`
- `heartbeat_monitor`
- `uplink_gateway`

The runtime-facing service boundary for those families is:

- [`Cadence.Runtime.CapabilityRegistry`](../../apps/cadence/lib/cadence/runtime/capability_registry.ex)

That service:

- loads the static family registry
- validates descriptors
- exposes descriptor lookup
- builds instances from activation context
- dispatches managed application callbacks
- dispatches transport extension callbacks

The point of `Cadence.Runtime.CapabilityRegistry` is that the rest of the
runtime talks to one supervised service boundary, not directly to arbitrary
modules.

## 4. Understand descriptors

Every capability family exposes a platform-visible descriptor:

- [`Cadence.Capabilities.Descriptor`](../../apps/cadence/lib/cadence/capabilities/descriptor.ex)

A descriptor tells the runtime:

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

These fields are not just metadata. They are how governance and runtime
validation understand whether a capability instance is legal in a given scope.

In practice, the descriptor answers:

- where may this family run?
- what kind of runtime is it?
- what input stage does it handle?
- does it keep state?
- what outputs should the platform expect?

## 5. Know the important capability kinds

The current descriptor kinds are:

- `:semantic_handler`
- `:managed_application`
- `:projection`
- `:transport_extension`

The most important operational distinction today is:

- managed applications run in partition owners
- transport extensions run in transport runtimes

If you are adding behavior that reacts to decoded mission data and may keep
partition-local application state, it probably belongs in a managed
application.

If you are adding behavior that extends a path or transport binding, it
probably belongs in a transport extension.

## 6. Understand execution contexts

The runtime gives capability families explicit context objects rather than
making them reach into global runtime state.

Two important context types are:

- [`Cadence.Runtime.ActivationContext`](../../apps/cadence/lib/cadence/runtime/activation_context.ex)
- `Cadence.Capabilities.ExecutionContext`

`ActivationContext` is used when building runtime-owned instances from the
active basis. It carries:

- mission id
- activation id
- binding set id and version
- partition key
- metadata

`ExecutionContext` is used during actual callback execution.

This explicit-context pattern is important:

- it makes capability execution deterministic
- it makes replay semantics more realistic
- it avoids hidden ambient dependencies

## 7. What services does the substrate provide to capabilities?

From a capability author’s perspective, the substrate provides several things.

### Ordered ownership

Managed applications get ordered record handling inside a partition owner.

Transport extensions get ordered event handling inside a transport runtime.

### Stable scoping

The substrate decides whether an instance is mission-scoped, source-endpoint
scoped, path-scoped, or transport-scoped.

### Timers

Capability families can request timers through action requests and rely on the
runtime timer service instead of implementing timer scheduling themselves.

### Clock mode

The substrate can run in live or replay-aware clock modes, which matters for:

- timers
- transport runtime advancement
- reproducible replay behavior

### Persistence hooks

The substrate persists runtime records and action requests emitted by managed
applications and transport extensions through the persistence boundary. The
capability family does not directly write rows.

### Snapshot surfaces

Managed applications and transport extensions participate in runtime snapshots
through the substrate, which is how operators and developers inspect live
state.

## 8. What does not belong in a capability family?

A capability family should not own:

- socket/session lifecycle
- provider transport adaptation
- archive backend implementation
- auth or tenant governance
- direct Postgres persistence strategy
- ad hoc global process lookup

Those belong to the substrate around the capability, not inside the family.

This is the same architectural idea used elsewhere:

- providers adapt transport
- executors preserve ordering
- projectors persist asynchronously
- capabilities express mission or transport behavior

## 9. A useful mental model

The runtime substrate is the operating system for Cadence mission behavior.

It provides:

- process placement
- scoped ownership
- clocks
- timers
- ordering
- lifecycle
- persistence handoff
- snapshotting

Capability families are the loaded programs that run on top of that operating
system.

That framing helps when deciding where new behavior belongs.

If the thing you are adding looks like:

- a reusable behavior family with governed configuration and scoped execution

then it may belong as a capability family.

If it looks like:

- a generic runtime service every family needs

then it probably belongs in the substrate.

## 10. When extending the runtime, ask these questions

Before adding new runtime behavior, ask:

- is this substrate or capability behavior?
- what scope owns it?
- does it need ordered execution?
- does it need timers or replay-aware time?
- should it emit runtime records, action requests, or both?
- should it run in a partition owner or a transport runtime?
- is a descriptor the right declaration surface?

If those answers are unclear, the runtime design is not ready yet.
