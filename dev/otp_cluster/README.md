# OTP cluster spike

Run `mix test.cluster` from the repository root. It is also part of `mix precommit`.
It requires OTP 25 or newer, EPMD, and local Erlang distribution connectivity.
The spike uses libcluster 3.5, OTP `:peer`, `:pg`, `:global`, and local dynamic
supervisors. Six cases use synthetic actors; seven use the actual Cadence Runtime
and PartitionOwner with persistence disabled. PostgreSQL and HTTP servers are not
started by the runner.

Each test boots three named BEAM nodes. Peer control uses standard I/O, so a
distribution netsplit leaves an independent inspection/cleanup channel. Peers
are stopped on completion. libcluster's static EPMD strategy establishes the
mesh; the origin is not a distributed node bridging the split.

The executable cases cover:

- three-node membership, direct remote routing, and separate readiness;
- simultaneous names on a synchronized connected cluster;
- controller replacement without restarting partition execution;
- two live contenders during a split and conflict notification on healing;
- re-advertisement after the process-group scope restarts without losing workers; and
- owner-node loss followed by explicitly admitted replacement elsewhere.

The initial experiment found that observing a full connection mesh alone was
not a sufficient synchronization barrier for simultaneous global registration.
The connected-start test now waits for `:global.sync/0` on each node. Production
startup still needs an explicit admission/convergence policy; do not translate
this into blocking every application's boot on every peer.

The split test deliberately proves that global names cannot guarantee one live
owner across disconnected components. The fixture uses the built-in notifying
conflict resolver and transient children, so the loser shuts down without being
restarted on healing. This is runtime discovery evidence, not a durable-effect
or provider-command guarantee. PostgreSQL fencing and journal/recovery contracts
must be tested independently before enabling production failover.

The production-runtime cases additionally prove remote placement, cross-node
inspection and generation application, coordinator and pg recovery without owner
replacement, node-loss reconstruction, routing limits and unknown outcomes,
eligibility withdrawal, admission loss and stale recovery sources, remembered
fencing rejection across controller restart, concurrent ready mission startup,
and remote shutdown. They use an empty compiled mission
model with persistence disabled. PostgreSQL fencing is covered separately by the
semantic store suite; these cases do not qualify persistent distributed recovery.
Kubernetes discovery, asymmetric failures, sustained churn, bounded local
buffer/backpressure behavior, and provider effects remain deployment validation
gates. The journal is a bounded node-local buffer: replication, cross-node
journal handoff, and shared-storage journal recovery are outside this rollout.
Node/disk loss can lose unarchived input unless the upstream source can resend
it. Archive replay is a separate workflow. See the
[journal buffer contract](../../docs/multi-node-runtime-plan.md#journal-buffer-contract).

Provider-effect failover builds on existing command release attempts and provider
reservation records. Explicit uncertain-attempt resolution Control APIs are
implemented; unknown command outcomes retain their lane holds and do not
authorize automatic resend. Automatic uplink takeover is not qualified for this
rollout. A root-local session-readiness gate now starts real uplink blocked and
checks ordinary delivery, retransmissions, and separately permitted recovery
exchanges. The default policy qualifies no provider. Provider-specific external
fencing of the old sender, verified protocol recovery, and reconciliation of
prepared sends remain required.
Exact frame preparation and counter transitions now commit before physical sends;
unresolved records and unrestored replacement runtimes block further ordinary
work. A new global owner, semantic readiness, or a
successful socket reconnect does not establish uplink authority. Existing
transport snapshots are not a verified recovery checkpoint, particularly when a
send succeeds before state persistence fails. See the
[provider-effect contract](../../docs/multi-node-runtime-plan.md#provider-effect-failover-contract).

Version 1 COP-1 checkpoints and explicit blocked installation are implemented in
the existing transport records. Normal durable COP-1 transport commits append a
checkpoint atomically; restoration validates the full history basis and installs
protocol state with timer deadlines retained but unarmed. It neither clears
prepared-send holds nor grants readiness. Audited reconciliation and qualified
provider recovery remain to be implemented. See the
[restoration foundation](../../docs/multi-node-runtime-plan.md#versioned-cop-1-checkpoints-and-blocked-restoration-implemented-foundation).
Automatic takeover remains blocked until provider-specific external fencing and
recovery are qualified across real nodes.

## Opt-in runtime configuration

Run named BEAM nodes with a shared cookie and reachable distribution ports. Use
the same deployment ID, pg scope atom, and ProcessNamespace on each participating
node. For example, in deployment runtime configuration:

```elixir
config :cadence, :runtime_cluster,
  id: :cadence_production,
  scope: Cadence.Runtime.ClusterGroups,
  execution?: true,
  topologies: [
    runtime: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"cadence@worker-a", :"cadence@worker-b"]]
    ]
  ]
```

The topology must match the deployment's node naming and reachable hosts.
Deployment-specific discovery such as Kubernetes remains to be qualified. An
empty `topologies` list uses already-connected nodes (for example, manual
`Node.connect/1`). Set `execution?: false` for routing/controller nodes that must not receive partition placement.
Only nodes with compatible runtime code and access to required durable storage
should join an execution group. Local node drain withdraws its execution agent;
it does not stop mission roots hosted on other nodes. A missing owner is rebuilt
on demand. Mission-root loss requires governed generation reconciliation before
processing resumes; runtime placement is not durable configuration.

Global names do not fence provider commands or guarantee a singleton across a
netsplit. Enable this mode only with the intended storage and effect contracts.
Single-node mode remains the default when `:runtime_cluster` is unset.
