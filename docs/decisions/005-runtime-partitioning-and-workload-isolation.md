---
title: "ADR-005: Runtime Partitioning and Workload Isolation"
aliases: [mission partitioning model, otp runtime partitioning, workload isolation]
tags: [adr, architecture, runtime, partitioning, otp, distribution]
status: accepted
created: 2026-03-28
updated: 2026-03-28
---

# ADR-005: Runtime Partitioning and Workload Isolation

## Status

Accepted

## Context

Cadence is being built in Elixir and should use OTP-native supervision and
distribution features as a core architectural advantage.

At the same time, Cadence is intended to support constellation-scale missions.
A mission with roughly 150 spacecraft should not be forced into a single-node
runtime assumption.

Prior ADRs established:

- [ADR-001](001-mission-scoped-runtime-and-selector-model.md): `mission` is the
  semantic and runtime root
- [ADR-002](002-organization-mission-scope-and-identity-model.md):
  organizations own missions and mission-owned operational data
- [ADR-004](004-activation-authorization-and-approval-policy.md): activations
  change the active basis, then runtime reconcilers converge workers

Those decisions leave one major runtime question:

- how to scale one mission across nodes while preserving one mission-wide config
  basis and one mission-wide semantic namespace

Cadence also needs clear workload isolation so live operational traffic is not
degraded by replay, rebuild, or other batch workloads.

## Decision

Cadence will use a distributed mission runtime with one mission coordinator per
mission, many execution partitions per mission, and separate workload capacity
pools for live operational traffic versus replay or batch work.

### 1. Mission Is The Semantic Root, Not The Execution Singleton

`mission` remains the semantic and governance root.

Cadence will not require one entire mission runtime to fit on one node.

Instead:

- one mission has one active mission coordinator
- one mission may have many active execution partitions
- execution partitions may be placed across multiple cluster nodes

This preserves one mission-wide namespace for selectors, configuration basis,
and managed capability meaning while allowing runtime scale-out.

### 2. One Active Mission Coordinator Per Mission

Each active mission has one active mission coordinator process.

The mission coordinator is responsible for:

- observing the active mission configuration basis
- deriving the desired partition map
- deciding partition placement
- reconciling partition lifecycle
- monitoring partition health and ownership

The mission coordinator is not intended to sit in the hot path for every
ingress record.

### 3. One Active Owner Per Execution Partition

Each execution partition has exactly one active owner at a time.

Partition ownership is the core runtime exclusivity rule.

This means:

- one partition key maps to one active partition runtime
- no two nodes should process the same partition as active live owners
- failover transfers ownership by reassigning the partition, not by permitting
  concurrent live ownership

### 4. Default Partition Key

Release one partitions mission runtime primarily by `source_endpoint_ref`.

This is the default execution key because it aligns with:

- selector routing identity
- per-spacecraft or per-endpoint protocol state
- per-endpoint application instances such as `CFDP`
- per-endpoint derived telemetry and limit state
- constellation growth patterns

When missions use a one-to-one mapping between source endpoints and spacecraft,
this effectively becomes per-spacecraft partitioning.

### 5. Future Partition Refinement

Release one assumes `source_endpoint_ref` as the primary partition key.

Cadence may later support finer subdivision inside a source endpoint partition,
such as protocol-channel or transport-local subpartitioning, but that is
explicitly deferred.

The architecture should not prevent future refinement, but it should not depend
on that refinement for release-one viability.

### 6. What Belongs In A Partition

Partition-owned runtime responsibilities include:

- source-endpoint routing tables
- ingress protocol workers for that partition
- per-endpoint managed application instances
- per-endpoint derived telemetry state
- per-endpoint limit evaluation state
- contact, link, or transport workers tightly coupled to that endpoint

Mission-wide responsibilities that should not be modeled as per-partition
workers include:

- activation governance
- mission coordinator logic
- mission-level placement and reconciliation
- cross-partition fleet summaries
- org and mission governance records

### 7. OTP-Native Runtime Primitives

Cadence should lean on OTP-native distribution features including:

- distributed Erlang node connectivity and monitoring
- `DynamicSupervisor` for partition lifecycle
- `PartitionSupervisor` for local concurrency and sharded work execution
- local `Registry` for node-local process discovery
- `:pg` for mission or role group membership and broadcast fanout
- `:erpc` for targeted remote execution and reconciliation calls

Cadence should avoid using cluster-wide mutable registries as the primary source
of runtime truth for hot-path ownership.

### 8. Cluster Trust Boundary

OTP distribution is an internal trusted platform boundary, not a tenant
boundary.

Organization isolation is enforced through:

- data scoping
- authorization
- activation scope
- runtime ownership rules

not through distrust between Erlang nodes in the same cluster.

### 9. Durable Truth Versus Runtime Truth

OTP runtime state is not the sole source of truth for placement or
configuration.

Cadence must retain durable truth for:

- active configuration basis
- activation history
- partition ownership or placement basis
- canonical mission records
- audit and approval records

If a node fails, replacement workers reconstruct from durable truth plus active
configuration, not from best-effort in-memory cluster state alone.

### 10. Failure And Recovery Model

If a node owning one or more partitions fails:

1. the cluster detects node or process loss
2. the mission coordinator marks affected partitions unowned
3. the mission coordinator reassigns those partitions
4. replacement partition workers start on healthy nodes
5. workers rebuild runtime state from durable records and active config

Failure of one partition must not require restarting the entire mission runtime
unless the mission coordinator itself fails.

### 11. Workload Capacity Pools

Cadence separates runtime work into at least these workload classes:

- live operational mission runtime
- replay and reprocessing
- projection rebuild and other batch or maintenance tasks
- web or API handling

These workload classes must not compete on equal footing for the same runtime
capacity in release one.

At minimum:

- live mission partitions run in a dedicated operational capacity pool
- replay and rebuild workloads run in separate batch capacity pools

### 12. Live Traffic Has Priority Over Replay

When capacity is constrained:

- live ingest and live mission runtime work take precedence
- replay, rebuild, and bulk reprocessing degrade first

This follows the operational requirement that replay must not endanger live
mission handling.

### 13. Partition Placement Is A Reconciled Function

Partition placement should be treated like runtime desired state:

- the mission coordinator computes desired placement
- actual live partitions are observed
- discrepancies are reconciled

Placement decisions may consider:

- node health
- node role or pool membership
- partition count
- estimated load

Release one does not require a highly sophisticated scheduler, but it does
require explicit placement and rebalancing logic rather than ad hoc worker
startup.

### 14. Release-One Cluster Shape

Release one may use coarse cluster roles such as:

- web or API nodes
- operational runtime nodes
- replay or batch nodes

These roles are deployment concerns rather than mission-domain concepts, but the
runtime architecture should assume that not all nodes are interchangeable for
all workload classes.

### 15. Anti-Decisions

Cadence should not adopt these as release-one assumptions:

- one active node must own an entire mission
- replay jobs may run inside the same unconstrained pool as live mission work
- cluster-global process registration is the primary placement truth
- tenant isolation is achieved by separate Erlang trust zones inside one
  cluster

## Consequences

### Positive

- Cadence can scale one mission across multiple nodes without abandoning the
  mission-scoped semantic model.
- Per-endpoint or per-spacecraft state has a natural execution home.
- OTP-native supervision and distribution provide clean failover and placement
  primitives.
- Live mission work is protected from replay or rebuild saturation.
- The architecture remains viable for large constellation missions.

### Negative

- Runtime placement and failover logic become first-class platform concerns.
- Mission-wide read models and summaries must aggregate across partitions.
- Partition reassignment and recovery need careful deterministic rebuild logic.
- Some cross-partition workflows will require explicit coordination rather than
  assuming all relevant state is co-located.

### Constraints Introduced

- Partition ownership must remain exclusive.
- Mission coordinator logic must stay off the hot path.
- Release one assumes `source_endpoint_ref` is a sufficient first partition key.
- Batch and replay work must not share the same unconstrained runtime pool as
  live mission work.

## Open Questions

1. What exact durable representation should Cadence use for partition ownership
   and placement state?
2. Should release one support automatic partition rebalancing, or only failover
   reassignment?
3. Which partition-local state should be rebuilt only from canonical records
   versus snapshotted periodically for faster recovery?
4. Do contacts that span relay or multi-endpoint scenarios require a special
   coordination layer above endpoint partitions?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-002: Organization, Mission, and Identity Scope Model](002-organization-mission-scope-and-identity-model.md)
- [ADR-004: Activation Authorization and Approval Policy](004-activation-authorization-and-approval-policy.md)
