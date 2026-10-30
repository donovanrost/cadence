# OTP-native multi-node runtime and supervision plan

Status: OTP cluster spike, local mission supervision, and opt-in cross-node
partition placement/routing and uncertain-attempt resolution Control APIs implemented.
The local session-readiness gate and durable frame/counter preparation boundary
are implemented. Provider-specific external fencing, send reconciliation,
protocol restoration, safe reclamation, and deployment qualification remain open.
Version 1 COP-1 checkpoint export and blocked restoration are implemented.
Audited prepared-send reconciliation and provider-specific recovery orchestration
remain next. Automatic uplink takeover remains blocked until
external fencing and recovery are qualified for a concrete provider/protocol/version
combination; implementing these slices alone does not enable it.
Updated: 2026-10-28.

## Initial implementation and rollout contract

`mix test.cluster` boots three real BEAM nodes using libcluster and OTP peer
control over standard I/O. It includes six synthetic lifecycle cases and seven
cases using actual Cadence Runtime/PartitionOwner modules. Production-runtime
cases cover remote placement and direct routing, generation convergence,
coordinator and membership restart isolation, owner-node loss, routing admission,
unknown call outcomes, eligibility withdrawal, admission loss during recovery, and remote mission shutdown.
The runner is included in `mix precommit`. libcluster is now a runtime dependency;
clustering remains disabled unless explicitly configured. See
[the cluster README](../dev/otp_cluster/README.md).

Cluster mode captures configuration in RootComposition and publishes it as
root-local Registry metadata. Logical mission, admission, coordinator, and
execution component names use a scoped OTP global registry adapter, retaining
local Registry entries for lifecycle inspection. One named mission controller
admits generations; requesting replicas use that controller rather than create
independent mission admission state. Names are scoped by deployment ID, process
namespace, and mission ID (the globally unique governed mission identifier).

A node-local execution pool is independent of mission controllers. A scoped pg
group advertises eligible agents. Rendezvous hashing chooses an agent for a
missing partition; existing owners never move just because membership changes.
The agent starts children locally with its node's captured runtime dependencies.
Registration precedes deferred domain recovery. Owners monitor the admission PID;
admission loss or disconnection retires remote execution without a restart loop.
Coordinator restart preserves that admission PID and healthy remote owners.

Cluster partition calls first reserve a per-partition request slot through the
mission controller, then send payloads directly to the resolved owner PID. Slots
are released on completion or caller loss. They bound admitted live callers;
they are not durable byte credits and a controller restart resets them. Calls
wait for recovery rather than treating registration as readiness. Owner-call
failure returns `partition_outcome_unknown` and is never retried by the router.
Missing names permit reconstruction through the controller and an eligible agent.

Cluster semantic execution disables Store's legacy automatic epoch reclaim.
A fenced owner records its rejection in supervised admission and retires with a
controlled shutdown instead of stealing authority back from its replacement.
Lazy replacement for that exact generation is refused, including after controller
restart. A newer generation or explicit mission stop/re-admission can authorize
recovery. Required partition identities also survive controller restart even
when their owner has already disappeared. Semantic epochs/predecessor checks remain PostgreSQL
responsibilities; placement has no database rows or leases. Global naming still
allows separate owners in disconnected components. Mission roots are temporary
children in cluster mode, so a losing global registration cannot trigger a
supervisor restart contest; governed reconciliation must re-admit a lost root.

Local MissionRuntime now orders MissionAdmission, MissionExecution, and
MissionCoordinator under `:rest_for_one`. MissionExecution contains independent
contact and partition pools under `:one_for_one`. Coordinator replacement retains
healthy execution and reconstructs its rollout from supervised admission state.
Partition recovery reads that state instead of the coordinator's live process.
Loss of admission state still invalidates dependent execution; it is not a durable
substitute for active configuration and recovery records.

The selected rollout policy is independent partition convergence. A failed
partition reports unavailable while confirmed peers continue on their admitted
generation. No mission-wide restart or aggregate application receipt is produced
for an incomplete rollout. Retries and interrupted coordinator recovery reapply
the desired basis idempotently, preserving already-admitted partition state and
timers. The rollout API exposes applying/incomplete status, pending count, ready
partitions, and failures. Existing applied-spec/summary inspection identifies the
last fully applied generation; exact confirmation remains the convergence gate.
Processing observation contexts and partition snapshots identify their own
generation and runtime basis. Operations needing a common generation must use
the explicit confirmation boundary rather than infer it from historical summary.

Local process-kill tests exercise coordinator, admission, contact-pool, and
partition failures, incomplete rollout/retry, and interruption during generation
application. The broader node resource tree, per-binding pipeline extraction,
pipeline/resource isolation, deployment qualification, and bounded journal
backpressure/drain validation remain later work. Journal replication and
cross-node journal handoff are outside this plan. The table below records the
original boundaries that motivated the plan.

## Direction

Use BEAM membership, naming, monitoring, and supervision for runtime placement
and lifecycle. Keep PostgreSQL for governed intent, committed state, checkpoints,
and stale-writer fencing. Database placement tables, renewable execution leases,
and a database placement coordinator are removed from the baseline proposal.

The reference design uses libcluster for connectivity, a fixed `:pg` scope for
eligible execution agents, `:global` for logical mission/partition names, and
local Registry/DynamicSupervisor trees for execution. Placement decisions are
reconstructible runtime state. A small mission placement coordinator chooses
eligible nodes and reconciles through their local agents. The implemented baseline uses stable deterministic placement without automatically
moving healthy partitions on membership changes. Explicit pinning is still optional future work.

This revises the earlier Syn-plus-database-placement proposal. Syn remains a
possible discovery alternative; Horde becomes a serious placement/supervision
alternative if it eliminates substantial custom lifecycle code. Neither is a
baseline dependency before a spike. Libraries are welcome where they remove
machinery without weakening recovery and effect guarantees.

Preserve [ADR-005](decisions/005-runtime-partitioning-and-workload-isolation.md),
[ADR-006](decisions/006-contact-link-and-transport-runtime-model.md), and the plane
boundaries in [ADR-015](decisions/015-management-control-data-plane-architecture.md).
Runtime registration must not become the sole authority for durable effects.

## Journal buffer contract

The journal is a bounded, node-local buffer for bursts and temporary downstream
slowdowns. Archival and decommutation should keep up with steady-state ingress;
healthy operation has little or no retained backlog. It is not the cluster's
system of record or a prerequisite for relocating a partition.

- Keep independent archive and processing cursors. Reclaim sealed segments only
  after both required consumers have completed their work under their existing
  acknowledgement contracts. Archiving alone does not authorize dropping an
  unprocessed range, and processing alone does not authorize dropping an
  unarchived range.
- Bound disk use and downstream in-flight work. Define high-water marks,
  transport backpressure, and explicit capacity-exhaustion behavior for sources
  that cannot pause. Do not silently overwrite required buffered input.
- Local persistence supports process restart and replay while the buffer remains
  available. Its configured sync policy describes local durability; it does not
  promise survival of physical node or disk loss.
- Planned node drain stops admission and lets archival and processing catch up
  within a deadline, then checkpoints/seals the local buffer. Report unfinished
  backlog and drain timeout explicitly; do not transfer journal custody or bytes
  to a replacement node.
- Moving a processing partition does not move the journal: a surviving capture
  pipeline can continue routing buffered input to that partition's replacement.
  When a capture node is replaced, start fresh node-local capture without
  requiring its old journal. Preserve committed semantic state through its
  existing recovery boundary, and establish a new stream/session boundary rather
  than carrying partial framing state across a missing byte range.
- Node or disk loss can lose bytes not yet archived unless an upstream source
  can resend them. Bytes already archived can support a separate, explicitly
  initiated replay workflow; automatic archive replay is not a live-failover
  prerequisite. Surface observed gaps and uncertain ranges rather than claiming
  lossless continuity.

Journal replication, shared/reattachable journal storage as a failover
requirement, cross-node journal handoff, and journal-aware placement are out of
scope. This resolves the earlier replication and cross-node custody questions
for this rollout; adding those guarantees would require a separate decision.
Provider-effect authority and unknown command outcomes remain a separate
qualification concern.

## What the current tree makes difficult

| Current boundary | Consequence | Proposed change |
| --- | --- | --- |
| `Runtime.Supervisor` groups archives, telemetry stores, capability registry, local Registry, and mission supervisor under `:one_for_all`. | A failed child resource can restart all mission runtimes on that node. | Separate resources, essential execution infrastructure, and independently restartable execution units. Document which resource losses require quiescence or rebuilding. |
| `Runtime.MissionRuntime` groups contact supervisor, partition supervisor, and MissionCoordinator under `:one_for_all`. | Coordinator loss restarts local contacts and partitions; the mission tree assumes colocation. | Separate mission coordination from node-local partition/contact supervision. Coordination reconstructs its view by monitoring and querying execution units. |
| `Control.MissionRecovery` starts active missions on every replica. | Local uniqueness does not produce one cluster control owner. | All replicas may discover desired missions, but starts converge through a cluster-named control owner before side-effectful children run. |
| MissionCoordinator starts partition owners and forwards ingress to them. | Placement and the hot path share a mission process. | Route ingress directly to the partition PID; keep placement and generation orchestration outside the record path. |
| PartitionOwner initializes through a locally named `spec_source`. | Restart depends on a particular local coordinator being alive. | Recover from a verified admitted specification identity and local/durable source; use explicit generation-application messages for changes. |
| PathCoordinator starts each provider pipeline worker separately under a DynamicSupervisor. | Startup order exists in coordinator code, but the dynamic supervisor does not encode ordered dependency restarts. | Add a per-binding provider pipeline supervisor with explicit dependencies and completion protocols. |
| Drain enumerates local mission roots and stops mission control first. | A node drain could remove coordination without handing it off, and stopping a mission is confused with stopping this node's work. | Separate node drain, execution-unit drain, control handoff, and cluster-wide mission stop. |

Classify shared Control children before enabling replicas: provider reservation
reconciliation, provider-event ingestion, command dispatch, verifier scheduling,
and optional global contact scheduling each need an explicit node, mission, or
cluster scope. Workers with durable claim/idempotency contracts can run on every
node; effectful singleton duties need logical ownership. Do not globally name
every background worker or accidentally multiply provider actions at boot.

These original boundaries protected exact generation application partly by
restarting whole mission execution. The initial implementation replaces that
failure response with truthful partial-rollout status and per-partition admission;
it preserves exact aggregate acknowledgement without requiring atomic cutover.

## Proposed supervision shape

The following names are proposed roles, not implemented modules. Every child
has a local supervisor on its execution node. Remote coordination uses messages
and monitors, not a remote parent-child supervision relationship.

```text
Cadence.Supervisor                         existing plane boundaries retained
  Platform.Supervisor
    Repo and shared platform services
    ClusterSupport.Supervisor             libcluster, fixed pg scope, membership
    EventBus / cluster wakeup bridge
  Management.Supervisor
  Control.Supervisor
    MissionControlSupervisor              local DynamicSupervisor
      Control.MissionRuntime(mission)     one named control unit per mission
        MissionRuntimeReconciler          governed generation -> runtime requests
        MissionPlacementCoordinator       reconstructible placement and monitors
        ContactScheduler                  mission control decisions
  Runtime.Supervisor
    Resources.Supervisor                  archives, stores; dependency-specific policy
    Execution.Supervisor                  ordered essential infrastructure
      Registry                            local component addresses
      CapabilityRegistry / spec support   verified, versioned local dependencies
      ExecutionPools.Supervisor           one_for_one between independent pools
        PartitionSupervisor               local DynamicSupervisor
          PartitionOwner(partition)       current GenServer is initially the unit
        ContactSupervisor                 local DynamicSupervisor
          RealizedContactRuntime(contact) paths, transports, provider pipelines
      NodeAgent                           advertise eligibility after dependencies
  Projections.Supervisor                  local query/cache consumers
```

Globally name the mission control unit and partition endpoint using fully scoped
logical keys. Keep component addresses local. Control's placement coordinator
must use the public Runtime boundary; moving placement out of
Runtime.MissionCoordinator does not permit Control to call private data-plane
modules. Retain a generation-application/observation boundary in Runtime even
when the present MissionCoordinator is split or retired.

Extend ProcessNamespace and RootComposition explicitly for the new pools and
addresses. Preserve isolated local test roots; do not replace every local
Registry address with a global name or dynamically construct module-name atoms.

A future `PartitionRuntime` supervisor is justified if a partition acquires
several processes with a shared recovery boundary. Do not add an empty wrapper
around PartitionOwner solely to make the diagram uniform. Likewise, do not
reparent all contacts under endpoint partitions: one contact can span endpoints
and several paths can feed one endpoint. Placement may express affinity without
changing semantic ownership.

### Restart and shutdown contracts

- Keep the application root `:one_for_one`. Preserve Management, Control, Runtime,
  and Projections boundaries and existing composition/dependency injection.
- Under Execution, evaluate `:rest_for_one` with Registry and other essential
  dependencies first. Losing local registrations must restart or deliberately
  re-register dependent children; simply switching the old root to
  `:one_for_one` would leave invisible live processes. Later-child failures must
  not restart earlier dependencies. Nest independent partition/contact pools
  under their own `:one_for_one` parent, so loss of one pool does not restart the
  other merely because of sibling ordering.
- Local dynamic execution pools use `:one_for_one`. A normal partition failure
  restarts that partition; restart-intensity escalation remains explicit. A
  fenced partition exits with a controlled shutdown and must not immediately
  reacquire a newer writer token through supervisor/reconciler loops.
- Mission control restarts without killing healthy execution elsewhere. A
  restarted coordinator reconstructs state from active intent and ready owners;
  running partitions must not depend on its birth PID. Guard control decisions
  against stale generation and incarnation even when naming has converged.
- Define global-name conflict handling together with child restart policy.
  Expected loss of a control or partition name must deliberately stop that local
  unit and reconcile with the survivor. An abnormal loser exit plus a permanent
  restart policy must not exhaust an execution pool's restart budget. Register
  before enabling side effects, and test simultaneous start and split/heal.
- Preserve contact/path `:one_for_all` until their state and protocol contracts
  justify narrower restart strategies. Their existing coupled recovery is a
  smaller and potentially valid fault boundary.
- Isolate optional profiling and independent backend failures. An essential
  current-value store, archive, or capability-registry failure may require
  admission pause, replay, or a targeted restart; failure isolation must not
  silently lose state or acknowledgements.
- Per-binding pipelines should start the bounded local journal buffer before
  dependent execution and ingress admission. Choose `:rest_for_one` or smaller nested
  supervisors from actual dependency edges. Keep archive and processing cursors
  independent. A socket reconnect need not discard committed processing state;
  local journal failure pauses dependent admission until a valid buffer is
  available. Do not interpret that dependency as a requirement to preserve the
  buffer across node replacement. Test the chosen child order.
- Supervisor shutdown is a fallback. Explicit drain stops admission, settles
  local buffered work within a deadline, and checkpoints/seals the buffer before
  teardown. DB/archive services remain available during settlement. Report any
  remaining backlog at the deadline. Control handoff is independent of the
  journal; journal transfer is not part of drain.

Static supervisors start children in order and terminate in reverse; dynamic
supervisors do not encode dependency ordering between their children. See
[Supervisor](https://hexdocs.pm/elixir/Supervisor.html) and
[DynamicSupervisor](https://hexdocs.pm/elixir/DynamicSupervisor.html).

## Naming, placement, and routing

Start cluster support before reconciliation but never block local boot waiting
for a particular peer count. Eligibility requires local dependencies, compatible
runtime support, storage access, and a non-draining state. Rejoin the fixed pg
scope after its restart. Tenant/mission/partition IDs belong in tuple names, not
dynamically created atoms. Resolve organization scope at a trusted boundary.

Use libcluster's deployment-specific strategy. The Kubernetes candidate is a
headless discovery service with long node names, independent of HTTP readiness.
Configure distribution reachability, cookies, and the deployment trust/TLS
boundary. Connectivity alone does not establish capacity or recovery readiness.

Register a partition name before writer acquisition to arbitrate ordinary
connected-cluster starts. Registration identifies an initializing endpoint;
readiness is a separate state returned by its admission protocol. Do not delay
name arbitration until after all contenders have claimed semantic epochs.
Remote requests include expected generation and owner incarnation; replies can
report recovering, draining, stale, busy, or unavailable.

Use a bounded local NodeAgent API to start a child under that node's supervisor.
Remote callers must not invoke an unsupervised remote `start_link` and become its
accidental parent. Startup request retries use idempotent logical identities and
reconcile unknown outcomes. The coordinator monitors execution PIDs; it does not
link its lifetime to them. Routing resolves the partition name to a PID and sends
work directly with bounded request/byte credits. A router need not be a GenServer.

The implemented ingress boundary resolves the globally named mission before
attempting supervised creation. Further hardening should remove mission creation
from ingress altogether. A missing
name wakes reconciliation or returns unavailable; it does not authorize every
requesting replica to start a local partition. A timeout does not cancel work:
stable evidence/stream identities and durable completion reconciliation are
required before replaying an uncertain request into a stateful framer.

Generation changes must preserve exact admitted basis and application receipts
across assigned units. Replacements rebuild a verified partition-specific spec;
passing a stale birth spec or silently selecting an unrelated latest generation
is unsafe. Queries and operational summaries distinguish local execution from
cluster-wide mission state.

## Fencing and network-partition contract

PostgreSQL keeps the existing semantic head, monotonic writer epoch, predecessor,
generation/basis checks, and checkpoints. A runtime-selected starter claims once,
recovers, and admits work only while its token remains current at commit. Keep
independent database enforcement. Do not add database placement assignments or
renewable runtime leases as part of this baseline.

The current Store recovery path can acquire a newer epoch after being fenced.
Replace that behavior at the execution boundary: a superseded owner quiesces and
reports lost authority. Reconciliation must not repeatedly restart it and steal
another epoch. Test startup, replacement, and recovery while membership changes.

Global names are not consensus-backed authority over external effects. Disjoint
clusters may run contenders; pg membership views can diverge. The initial safety
claim is fenced, ordered semantic commits, not exactly one live process under
all failures. Current epochs serialize accepted writes, but do not by themselves
stop duplicate computation, repeated ownership steals, or provider commands.

Qualify semantic replacement under stable membership, asymmetric disconnects,
old-owner return, and minorities. Automatic uplink takeover has a separate gate:
externally effective session fencing and verified protocol recovery, as defined
below. Do not infer a majority or exclusive send authority from a shrinking
visible Node.list alone. Under unresolved authority, preserve capture where safe
and report degraded/unavailable rather than perform new exclusive external
uplink actions. Global registration and semantic commit fencing do not satisfy
the external-effect gate.

PostgreSQL is still needed for durable semantic commits during a DB outage;
removing placement leases does not remove that persistence dependency.

## Provider-effect failover contract

Build on the existing `CommandReleaseAttempt`, command queue/request, and
`ProviderReservation` records. They remain the durable identities and evidence
for external operations. Do not introduce a parallel generic effect ledger or
outbox merely to support node failover. Extend these records and their existing
transaction boundaries only where the recovery contract requires it. BEAM
placement remains reconstructible; effect tracking does not restore database
placement tables or renewable execution leases.

### Existing guarantees and their limits

- [ReleaseStore](../apps/cadence/lib/cadence/commanding/release_store.ex) claims a
  command lane and persists its exact release attempt and encoded command before
  transmission. Completion is checked against the original claim and immutable
  attempt basis, and terminal completion is idempotent. These are durable
  admission/completion guarantees, not exactly-once physical execution.
- [Command release](../apps/cadence/lib/cadence/commanding.ex) retains ambiguous
  transport or completion failures as uncertain. Dispatcher startup does not
  automatically requeue incomplete claims; the affected lane remains held. A
  successful claim is required for a new release, but losing database access
  does not revoke a transmission already admitted to a live socket.
- [ProviderBooking](../apps/cadence/lib/cadence/contacts/provider_booking.ex)
  persists a reservation before the external mutation. An existing idempotency
  key with the same immutable payload returns its existing attempt without
  resubmission; a conflicting payload is rejected. Keep that key stable across
  recovery. Different keys represent different attempts.
- [ProviderReservationReconciler](../apps/cadence/lib/cadence/contacts/provider_reservation_reconciler.ex)
  rereads durable work after restart and queries by provider contact reference or
  client reference where supported. Provider capabilities already distinguish
  native idempotency, client-reference support, and no idempotency. Those
  capabilities constrain recovery; provider-side deduplication is not universal.
- A cancellation's durable `canceling` transition is not by itself an exclusive
  claim for the external call. Qualify cancellation and other mutations under
  the same explicit operation-identity and uncertain-outcome rules as booking.
- The TCP adapter quiesces and rejects new sends. It now validates a one-use,
  session-bound delivery permit before delivery and checks admission before each
  payload. These local permits are not external fencing or durable request
  deduplication. Socket-send
  success is local delivery evidence, not proof of provider or spacecraft
  acceptance. Transport runtimes initialize extension state from configuration;
  audit records alone do not establish verified restoration of protocol state.

- [PathCoordinator](../apps/cadence/lib/cadence/runtime/path_coordinator.ex)
  retains an active capture/runtime lifecycle, separate from uplink readiness.
  Command release now acquires session admission before claiming a durable
  attempt. The provider delivery boundary also enforces admission. The default
  qualification policy supports no provider, so connected TCP sessions start
  blocked for real uplink. Provider-less protocol simulation produces no network
  delivery and does not grant a provider session any authority.
- [TransportRuntime](../apps/cadence/lib/cadence/runtime/transport_runtime.ex)
  commits exact frame bytes, stable frame identities, original attempt links,
  session basis, and before/after protocol states in existing transport action
  records before executing provider sends. TCP verifies and consumes that
  preparation before writing. Local write observations and final transport
  persistence are separate; missing either leaves durable uncertainty and blocks
  the stream. Prepared records never generate command-verifier acceptance.
  A stored snapshot alone still does not establish remote acceptance.
- [UplinkGateway](../apps/cadence/lib/cadence/capabilities/transport_extensions/uplink_gateway.ex)
  implements live packet/frame counters, COP-1 windows, CLCW processing,
  retransmissions, and T1 timers. Startup resets packet counters, uses configured
  initial frame counters, and initiates AD without a CLCW check. Transport state
  snapshots exist, but the extension behaviour has no restore callback and
  transport startup does not load and validate those snapshots against the peer.

Existing release-recovery and booking tests exercise these durable contracts,
including independent-connection completion serialization. The current
multi-BEAM partition tests do not qualify provider sockets, uplink continuity,
or external-effect fencing.

### Explicit uncertain-attempt resolution (implemented Control APIs)

Control-plane review and resolution APIs now operate on the existing attempts
and reservations, with an additive `resolution_evidence` JSON column on each
record. An authenticated mission administrator identifies the original scoped
attempt, immutable command/request basis, provider identity, and applicable
session incarnation. It records the evidence source, actor, time, correlation
references, and resolution decision. Provider receipts, protocol acknowledgements,
and operator evidence must refer to that exact operation; a later unrelated
provider state or a newly generated request ID cannot settle the old attempt.

The APIs preserve existing lifecycle states and apply these outcomes:

| Evidence-backed outcome | Recovery behavior |
| --- | --- |
| Confirmed accepted at a specified provider/protocol stage | Apply the corresponding completion to the original claim idempotently. Keep later execution/spacecraft verification separate; acceptance does not prove execution. |
| Confirmed not sent or definitively rejected | Record the evidence, fail the attempt, and cancel its command request/queue entry without resend. An unconfirmed booking can be closed; a reservation with an existing provider contact remains held for correlated provider status. |
| Still unknown | Retain the original claim and lane hold. Continue supported status reconciliation or require operator review. Elapsed time, process death, a missing global name, or a new TCP connection is not evidence of non-delivery. |

Serialize resolution with the current claim using the existing request/lane
locks and immutable-basis checks. Concurrent resolvers and late acknowledgements
must converge without duplicating completion or overwriting established success.
Retain contradictory evidence for review. An operator's authorization to accept
risk must be audited as such; it must not manufacture a confirmed-not-sent fact.
Provider-supported retries must reuse the same operation key and payload under
that provider's qualified contract, rather than create a fresh operation to
bypass an unresolved one.

The implementation locks the command request, lane, queue entry, and attempt in
that order; reservation resolution and ordinary reservation transitions serialize
on the existing reservation row. Stale provider observations cannot overwrite a
resolved record. Resolution IDs are idempotent per original record; reuse with
different evidence is rejected. Actor identity and recording time come from the
server. Review hashes bind evidence to the original immutable operation basis.
Evidence is appended atomically with the decision, including contradictory and
still-unknown observations; ordinary persistence cannot replace the audit field.

Accepted command evidence reconstructs verification from the attempt's stored
mission-model revision and uses the existing completion transaction. A missing
original verification basis keeps the lane held and records the evidence.
Acceptance is distinct from later verifier success. Provider acceptance requires
a correlated provider response and uses existing status/materialization logic.
These APIs do not query providers, verify receipt authenticity, transmit, or
resubmit. Operator UI and provider-specific evidence acquisition remain future
work. See [Resolve uncertain provider effects](how-to/resolve-uncertain-provider-effects.md)
for the current API contract.

### Enforced session-readiness gate (implemented local admission)

A supervised root-local `SessionReadiness` process supplies an admission boundary
separate from mission/partition readiness and ordinary socket connectivity. Scope it to the actual exclusive provider and
protocol resource: a shared uplink session and its affected spacecraft/virtual
channels may span multiple Cadence paths, bindings, and command lanes. Do not
create independent authorities just because two paths have different IDs.

The implemented lifecycle is `blocked -> recovering -> ready`. Transition into
recovery requires provider-policy verification of external fencing evidence;
transition to ready requires separate protocol-recovery verification. Quiescing,
authority loss, evidence expiry, or member/configuration replacement blocks the
session and changes its evidence/admission generation.
Initial startup, socket reconnect, provider/transport restart, replacement, and
missing recovery evidence must start blocked for ordinary uplink. A verified
fresh session needs its own provider/protocol initialization contract; absence
of local records is not proof that the peer has no prior state.

A readiness receipt binds the exact resource identity, session incarnation,
provider/binding and protocol configuration versions, fencing evidence, recovery
basis, and qualified retry policy. Changes or loss of any prerequisite invalidate
it. A new global owner, successful TCP connection, semantic commit epoch, or
mission generation confirmation cannot manufacture that receipt.

Enforce the gate both when admitting new commands and at the provider delivery
boundary. Bind queued work to its admitted session incarnation and reject stale
requests after replacement. Cover every emission path: initial frames,
retransmissions, timer callbacks, direct/bypass traffic, protocol control frames,
and adapter entry points. Cancellation of a timer is not sufficient if its
callback or delivery call is already in flight. Readiness checks must not
introduce a bypass through a lower-level provider call.

Recovery may need peer queries or protocol control frames before general
readiness. Give those narrowly defined actions a separate recovery permit after
external fencing is established, bound to the same resource/incarnation and
recovery operation. It must not admit ordinary commands or unrestricted retries.
Read-only reconciliation and independently safe capture may continue under their
own contracts. Quiescing prevents new admissions and settles in-flight work;
unknown settlement is not proof that the old sender stopped.

The local gate rejects work when authority is lost or unverifiable. It does not
replace enforcement at the external resource: an isolated old sender may retain
its socket and local state. The replacement stays blocked until that sender is
externally fenced. Expose distinct reasons such as `fencing_unproven`,
`protocol_recovery_required`, `send_outcome_unknown`, and `unsupported_takeover`.

The implementation requires an explicit canonical `uplink_resource_id` on TCP
provider configuration. It is preserved through transport/provider-profile
materialization; missing identity blocks delivery. Within a Runtime root, a
second live provider connection for the same resource is refused and invalidates
the existing connection's readiness. Transparent sharing/fanout is not yet
implemented. Cross-node or cross-root exclusivity still requires the external
fencing policy; local registration is not a distributed authority guarantee.

Provider connections and registered transport PIDs are monitored. Reconnects
create new connection incarnations. Transport replacement, even with identical
configuration, invalidates prior evidence. A queued release is bound to an exact
runtime PID and opaque admission generation. Short-lived, bounded delivery
permits bind exact request bytes and are consumed once at the TCP boundary.
Recovery permits additionally bind operation ID and purpose; reissuing a consumed
operation does not create a new permission. Ordinary sends, timer and CLCW-driven
retransmissions, direct/bypass frames, and direct adapter calls use the same
provider check. In-flight delivery counts remain visible after revocation;
revocation cannot prove an already-admitted socket write did not happen.

`RootComposition` captures a trusted `uplink_session_policy` dependency. The
production default, `SessionQualification`, returns `unsupported_takeover` for
all verification callbacks. No configuration or request metadata flag marks a
session ready. Fencing and recovery receipts bind the current basis and a
provider-verified UTC expiry, capped locally at five minutes and converted to a
monotonic deadline. A fresh review is required after fencing or invalidation.
No production provider has been qualified by adding this interface; the passing
socket/COP-1 tests use an explicitly installed test-only policy. See
[Inspect uplink session readiness](how-to/inspect-uplink-session-readiness.md).

### Provider-specific fencing and protocol recovery (planned)

Declare capabilities per provider/protocol combination and configuration, with
unsupported/blocked as the default. Separate booking idempotency capabilities
from live uplink authority and protocol recovery. A capability declaration or
operator configuration alone is not evidence of successful fencing or recovery.

| Contract | Required evidence before ordinary uplink becomes ready |
| --- | --- |
| Exclusive authority | Provider/gateway enforcement of the current authority epoch/session, verified revocation of the old session, or verified fencing of the old host. Define whether buffered/in-flight old-session data can still reach the peer and how it is reconciled. Raw TCP reconnect alone provides no such guarantee. |
| Attempt reconciliation | Account for original durable attempts and reservations. Unknown commands keep their lane holds. Widen the hold to the shared protocol stream when unresolved frames or counters affect other lanes. Do not use a fresh operation ID to bypass an unresolved effect. |
| Protocol continuity | Restore a versioned durable checkpoint and reconcile it with fresh peer evidence, or perform a specifically authorized resynchronization/reset. Validate resource, session, model/protocol configuration, and checkpoint compatibility before use. |
| Qualified retries | Define operation/frame identities, exact bytes, peer deduplication or protocol retransmission rules, and acceptance stages. Distinguish legitimate COP-1 retransmission from submitting a new command; no generic exactly-once guarantee over TCP. |

Protocol recovery must cover packet sequence counts per applicable stream,
frame counters per spacecraft/VC, COP-1 V(S)/acknowledgement state, exact
outstanding frames and original attempt correlations, pending control exchanges,
retry counts/limits, and timers/deadlines. Reject stale or incompatible snapshots.
Late acknowledgements must retain their original session/frame correlation and
may advance replacement state only through explicit recovery reconciliation;
unrelated or stale acknowledgements must not advance it. Retain relevant late
evidence on the original operation. Explicitly reconcile which frames are
acknowledged, outstanding, or still ambiguous before authorizing further work.

The existing COP-1 state machine provides control/initialization primitives;
Cadence must supply the recovery orchestration and permitted policy. Configured
initial counters and `initiate_ad_without_clcw_check` are not a default recovery
path. A negotiated reset must define what happens to outstanding frames and
unknown commands and retain their audited evidence; it must not imply they were
never delivered. Direct and bypass modes need their own recovery qualification.

The versioned restoration boundary below is implemented for the initial COP-1
state subset. Provider-specific recovery still needs to recreate/arm timers from durable deadlines
under the recovery policy, including already-expired deadlines; do not restore
BEAM references or automatically release retransmissions during startup. Keep
session admission and transport/provider lifecycle coupled so restart of either
invalidates readiness. Independently healthy sessions need not restart together.

#### Versioned COP-1 checkpoints and blocked restoration (implemented foundation)

The transport-extension boundary now has optional `export_checkpoint/2` and
`restore_checkpoint/3` callbacks. The uplink gateway implements the
`cadence-cop1/v1` payload for TC/COP-1 AD state. It preserves packet counters keyed
by integer APID, frame sequence wrap, COP-1 state and retry budgets, original
attempt/request correlations, and outstanding exact wire bytes. Validation checks
configuration compatibility, FOP invariants, contiguous outstanding sequence
numbers, wire SCID/VCID/sequence fields, and complete frame/release correspondence.
Direct/bypass modes, pending BC/BD directives and wait-queue requests are rejected
in this version; negotiated initialization/reset and further state compatibility
remain provider-specific follow-up work.

`TransportRuntime.export_protocol_checkpoint/1` persists an explicit checkpoint.
Supported attached COP-1 runtimes with normal durable history also append one
atomically with each successful transport-record/send-confirmation transaction.
Optional-history mode cannot export a recovery checkpoint: its physical sends
still require preparation, but it does not retain a complete observation basis.
Existing external-term snapshots remain evidence only and are never decoded by
the restoration path. The new bounded data-only JSON encoding supports known
COP-1 state and existing atoms without loading arbitrary modules or restoring
process, monitor, timer, function, or permit capabilities. Envelope and protocol
versions must match exactly; no migration or configured-counter fallback exists.

`TransportRuntime.latest_protocol_checkpoint/1` reviews the latest complete
persisted checkpoint without installing it or granting authority.
`TransportRuntime.restore_protocol_checkpoint/2` loads an exact persisted ID.
It revokes session admission and cancels live timers before validating the full
checkpoint chain, integrity hashes, exact configuration/scope and clock basis,
and the complete send/observation/timer watermark. The recovery query has no
operational-review truncation. Normal commits append hashes of only their new
evidence and the previous checkpoint basis, using an indexed predecessor lookup;
explicit export and recovery validate every covered evidence interval against
the full scoped record set. Missing, altered, duplicated, or unaccounted evidence
is rejected rather than silently folded into an existing basis.
Evidence changes between decode and durable installation reject the proposal. Durable installation is idempotent per target
runtime/checkpoint/session basis. Its marker records source revision and current
target session basis as `committed_pending_installation`. Only the live runtime
reports `installed_pending_reconciliation`, after changing in-memory state;
the durable marker alone cannot prove that a process installed the state.

Installation restores protocol data while retaining timer deadlines and metadata
as unarmed intents, with expiry evaluated at installation. It does not schedule
callbacks, emit frames, clear existing send/attempt holds, grant readiness, or
allow ordinary interactions to mutate the staged state. Restoration receipts and
checkpoints never generate command-verifier signals. The default production
policy still qualifies no provider; even the test-only readiness policy cannot
complete recovery through the runtime after blocked installation.

A failed or stale restore retains a blocked runtime without installing the
requested state. Checkpoint persistence failure rolls back resulting transport
records and confirmations, preserving the durable potentially-sent hold. Missing
or incompatible histories require explicit reconciliation; there is no automatic
latest-snapshot replay. Checkpoints and predecessors are currently retained;
safe compaction/migration and the qualified reconciliation/readiness transition
below remain unimplemented.

Use a validated, versioned protocol checkpoint in the existing transport
capability records, with references to existing prepared-send action records.
The envelope must identify:

- Checkpoint schema version, extension/protocol implementation version, supported
  compatibility or migration rules, and an immutable checkpoint ID/hash.
- Canonical uplink resource and protocol stream identity, including spacecraft,
  virtual channel, and applicable packet/APID streams; original and replacement
  session provenance, mission/model/binding/configuration basis, and runtime
  recovery generation.
- Durable checkpoint revision/predecessor and ordered observation/preparation
  watermark. Select a complete recovery basis through the scoped persistence
  boundary; the latest snapshot or the 100-record operational review is not a
  complete recovery query.
- Packet sequence counts, next frame counters, COP-1 V(S)/acknowledgement state,
  outstanding/waiting frames with exact bytes and original attempt/frame links,
  retry counts/limits, and pending directives/control exchanges.
- Logical timer intent and durable deadlines, including the time basis needed
  to handle downtime and already-expired deadlines. Exclude live PIDs, monitor
  references, timer references, and old admission/delivery permits.

Validate the envelope and protocol invariants before installation. Reject
unsupported versions, changed stream/configuration scope, missing predecessor
records, incomplete frame sets, and stale recovery evidence. Restore through
explicitly supported compatibility rules; a version mismatch cannot fall back to
configured initial counters. Recreate timers under the qualified recovery policy
and keep ordinary retransmissions suppressed until readiness. Expired deadlines
must produce a deliberate recovery decision, not an uncontrolled startup burst.

COP-1 is the first restoration target because its pure state machine already
contains the protocol primitives. Cadence still needs to expose and orchestrate
permitted initialization/unlock/set-VR exchanges, encode their wire outputs, and
collect correlated results. The current arbitrary exact-byte recovery exchange
is an emission boundary, not that orchestrator. Define both checkpoint continuity
and an explicitly authorized resynchronization/reset path. Neither reset nor
protocol acknowledgement proves an unknown command was never executed. Direct
and bypass modes require separate qualification and remain blocked by default.

#### Audited prepared-send reconciliation (implemented audit boundary; qualified application pending)

Scoped review and reconciliation APIs are implemented through
`Control.Commanding` and `Runtime.TransportRecords`, using an audit column on the
existing prepared-send action rows. Mission administrators and scoped services
can submit bounded, idempotent exact-frame interpretations with evidence hashes,
references, session provenance and observation times. Existing provider evidence
IDs are verified for organization scope and content hash. The server records the
authenticated actor, time, complete versioned review hash manifest and disposition.

The review covers every prepared send for the resource and all corresponding
transport actions, observations, timers, checkpoints, restoration markers and
original attempts. Resource audit serialization and prepared-row locks protect
comparison with the reviewed basis. Changed evidence requires fresh review; exact
duplicates return their original entry. Unknown, partial, uncorrelated and
contradictory claims are audited without overwriting previous interpretations.
Preparation ID plus ordinal and frame hash identify a physical occurrence; no
content/sequence-only inference merges retransmissions or sequence wrap.

This boundary preserves local send metadata/bytes/counter history and checkpoint
hashes. It deliberately leaves all lane/stream holds and readiness gates intact,
and emits no verifier acceptance. Audited preparations conservatively hold their
stream even when local transport commit succeeded. Complete correlated claims remain
`recorded_pending_qualified_recovery`; protocol acknowledgements do not yet advance
restored state, and outstanding observations do not authorize retransmission.
Attempt resolution remains its existing separately reviewed operation. There is
no new effect ledger, journal handoff or database placement machinery. See
[the reconciliation runbook](how-to/reconcile-prepared-sends.md).

The following qualified-application contract remains to be implemented:

A review basis must bind the exact resource/stream, original attempts and
prepared-send IDs, frame identities/bytes, checkpoint revision, provider/session
provenance, and all relevant observations. A reconciliation command supplies that
immutable basis, an idempotent resolution ID, authenticated actor or trusted
service identity, evidence references/hashes, observation times, and a qualified
provider/protocol interpretation. Validate scope and compare the current durable
basis under transaction/locking before applying it. A changed basis requires a
fresh review; duplicate submissions are idempotent, and conflicting/late evidence
is retained without overwriting established outcomes.

Record these dimensions separately rather than overloading send status:

| Evidence/disposition | Meaning and required behavior |
| --- | --- |
| Local preparation/write/transport commit | Preserve the original send history. `transport_committed` is not remote acceptance or a reconciliation result. |
| Proven not sent or definitively rejected | Record the proof and its exact acceptance stage. Resolve the original attempt only when its existing resolution contract permits it; never automatically create a replacement command. |
| Protocol acknowledged | Attribute the acknowledgement to the original frames and protocol stream. Advance the restored protocol state idempotently; do not infer command execution from frame acknowledgement. |
| Outstanding and safely retransmittable | Retain original exact bytes, logical frame/attempt identity, counters, retry budget, and qualified retransmission rules. A replacement session must not turn the work into a fresh command submission. |
| Unknown, contradictory, or uncorrelated | Retain evidence and the affected lane/stream holds. No fresh operation ID, counter reset, or successful socket reconnect resolves the uncertainty. |

A single command can span multiple prepared sends. Reconcile partial batches
without closing the original attempt from one frame's outcome. Preserve original
frame occurrence/order and logical identity across session replacement and
sequence wrap; content equality or a matching sequence number alone is not enough
for acknowledgement correlation. Provider acceptance, protocol acknowledgement,
and command execution remain distinct stages with their existing verifier rules.
Reservation booking/client-reference recovery may supply related evidence, but
does not establish live send authority or protocol continuity.

Carry provider/session provenance through acknowledgement ingress. Classify
fresh recovery observations separately from old-session, delayed, duplicate, or
unrelated observations; only explicitly reconciled evidence may advance a
replacement's state. Keep late evidence attached to its original operation even
when it cannot be applied. Repeated recovery exchanges follow provider-specific
safety rules and durable operation deduplication; changing an ID cannot bypass an
unresolved exchange.

Unknown command outcomes keep their lane holds. Unknown frame/counter continuity
also keeps the shared protocol stream blocked; unrelated healthy streams may
continue. A command-attempt resolution does not itself clear a stream hold.
Conversely, verified protocol continuity does not automatically resolve an
unknown command's execution outcome. Replace the current blanket
`unresolved_transport_send` / `protocol_state_restore_required` guards only with
an explicit validated reconciliation/restoration revision. Preserve historical
rows and their send statuses; deleting them or relabeling a send as
`transport_committed` is not a recovery mechanism.

#### Recovery commit and readiness contract (planned)

Keep recovery orchestration separate from the trusted evidence-verification
callbacks. The default qualification policy continues to reject every production
provider. For each supported combination, define actual external fencing,
buffered/in-flight old-session behavior, authoritative peer observations, allowed
recovery actions, retry semantics, and evidence expiry before qualification.
Reuse provider evidence/audit storage for sanitized receipts; a declared
capability, booking, or operator flag is not proof of successful fencing.

Use the following sequence while ordinary uplink stays blocked:

1. Establish and verify provider-specific fencing of the old sender. Recovery-only
   emissions require their separately scoped exact-operation permits.
2. Load a complete versioned checkpoint and prepared-send basis; gather fresh
   correlated peer evidence and compute a side-effect-free recovery proposal.
3. Commit the audited frame/attempt reconciliation, recovered checkpoint, durable
   deadlines, and restoration revision together where they share the database
   boundary. Compare the expected predecessor, observation watermark, and current
   resource/configuration/recovery basis; reject stale proposals.
4. Install that exact committed revision into the blocked runtime. Database commit
   and in-memory installation are separate steps: a crash between them must remain
   blocked and resume from durable evidence, never publish readiness early.
5. Verify a readiness receipt bound to the installed checkpoint/restoration
   revision, reconciliation watermark, current resource/session/configuration,
   qualified retry policy, and unexpired fencing/recovery evidence. Recheck that
   no prerequisite changed before admitting ordinary work and arming its timers.

The current gate basis covers session membership/configuration, but does not
include the durable recovered revision or reconciled frame set. Extend that basis
and its invalidation rules as part of this work. A later conflicting observation,
configuration change, evidence expiry, membership loss, or mismatch between the
installed and committed revision revokes readiness and requires a fresh review.
Reconcile retries idempotently after a crash at every step. Do not claim atomicity
between the database, BEAM state, and external provider writes.

### Send/persistence ambiguity (implemented boundary; provider reconciliation planned)

The write-ahead boundary is implemented for ordinary sends, retransmissions,
bypass frames, and separately authorized recovery exchanges. Physical sends
always require durable preparation, even when optional runtime history is disabled.
The existing transport action table carries `provider_send_prepared` records;
there is no new effect ledger or journal replication. Session review exposes
up to 100 recent preparations. Indexed resource/status queries inspect all
outstanding preparations when deciding whether a stream may resume.

Each preparation progresses through `prepared`, `sending`,
`local_write_completed`, and `transport_committed`, or remains `unknown` after
an observed send failure. A process crash or missing observation can leave any
intermediate state. Only `transport_committed` establishes that local writing and
resulting transport-record persistence completed; it says nothing about peer
acceptance. Every other state prevents ordinary sends and completion of session
recovery. A replacement transport with previous ordinary sends also reports
`protocol_state_restore_required`, rather than using freshly initialized counters.
No automatic recovery selection/replay or operator override is implemented.
Explicit versioned COP-1 installation is available but remains blocked. The
planned audited reconciliation and qualified recovery/readiness contracts above
must settle these records using external evidence and an installed recovery
revision; changing a command attempt's resolution does not clear a shared
protocol-stream hold.

Qualified recovery-only exchanges may run while older preparations remain
unresolved. Their operation identities are deduplicated durably across gate and
process lifetimes; a previously prepared operation cannot be blindly repeated.
All records are retained. Provider-specific safe retention/reclamation and
restoration remain required before automatic takeover is qualified.

Keep the existing durable command attempt before transmission. Extend existing
attempt and transport records with the minimum protocol recovery evidence:
exact prepared frame bytes, stable frame/operation identities, reserved counter
transitions, original attempt links, session incarnation, and subsequent
observations. This is bounded protocol recovery state, not a replicated ingress
journal or a parallel generic effect ledger/outbox. Define safe retention and
reclamation based on reconciled outcomes, not merely socket-send completion.

Commit the prepared protocol basis before the external send under serialized
session/stream ownership. Persisting preparation does not prove delivery, and
failure to record completion does not prove non-delivery. Database transactions
cannot atomically commit a TCP write. The provider-specific contract must
reconcile the remaining gap:

| Failure window | Required behavior |
| --- | --- |
| Preparation cannot commit before send admission | Do not send. Return a definite no-send result only when the execution path can establish that no external delivery began. |
| Prepared basis committed; crash or timeout before a recorded send outcome | Recover as potentially sent unless external evidence proves otherwise. Reuse the original basis; never allocate fresh counters/identities to retry blindly. |
| Partial multi-payload delivery, send timeout/error after delivery may have begun, or send success followed by persistence failure | Mark/infer uncertainty from the durable prepared record, retain attempt lane holds, invalidate session readiness, and block the affected protocol stream. An uncertain-outcome marker may itself fail to persist; recovery must still recognize the unresolved preparation. |
| Provider/protocol acknowledgement precedes durable completion | Correlate and apply it idempotently to the original frame/attempt and protocol state. Preserve contradictory evidence; a local socket write is not remote acceptance. |

After a possible send, never resume with pre-send counters/state merely because
persistence failed or the call timed out. Stop or quarantine the affected
transport/session, invalidate stale queued work/timers, and require reconciliation
before it becomes ready again. Completed due-timer interactions retain their state
even when a later input in the same call fails. An unavailable database must prevent new sends
that require durable preparation, while externally enforced fencing handles an
old sender's already-admitted work. Checkpoint persistence alone does not settle
what the provider or spacecraft accepted.

### Automatic uplink takeover qualification (planned)

Automatic uplink takeover remains blocked throughout the restoration and
reconciliation implementation slices, including when simulator tests pass. Enable
it only for an explicitly qualified provider/protocol/version/configuration
combination after the following contract is demonstrated.

Enable automatic takeover only when the enforced gate, provider-specific external
fencing, attempt reconciliation, protocol recovery, and send/persistence ambiguity
handling have all been demonstrated across real BEAM nodes and an instrumented
provider/peer. Qualify each supported provider/protocol/version combination;
unsupported combinations remain blocked with an explicit reason. No deployment
switch may bypass missing evidence by treating socket or semantic readiness as
uplink readiness.

Journal replication and cross-node journal handoff remain outside this plan.
Effect recovery uses the existing durable operation records, minimal protocol
checkpoints, and provider/protocol evidence, independent of the bounded local
capture buffer. This does not add database placement tables or renewable Cadence
execution leases; BEAM placement and local supervision remain OTP-native.

## Library choices

| Candidate | Role and disposition |
| --- | --- |
| libcluster | Preferred connectivity library; qualify Kubernetes DNS and local development strategies. |
| OTP pg/global/local Registry | Reference membership and naming stack. Test global conflicts, registration latency, scope restart, and topology requirements on the supported OTP version. |
| Horde.Registry + Horde.DynamicSupervisor | Compare as one coherent alternative if automatic placement/recovery substantially reduces code. Qualify quorum membership, duplicate startup, drain and restart behavior, and recovery admission before adoption. |
| Syn | Discovery alternative if metadata/scopes justify it; it does not replace a placement mechanism. No longer the default recommendation. |
| PartitionSupervisor | Optional local sharding of busy supervisors/tasks after measurement; it is not cross-node partition placement. |
| OTP distributed applications | Whole-application failover is too coarse for arbitrary endpoint partitions; not the execution model here. |

Sources: [libcluster](https://hexdocs.pm/libcluster/readme.html),
[global](https://www.erlang.org/doc/apps/kernel/global.html),
[pg](https://www.erlang.org/doc/apps/kernel/pg.html),
[Horde](https://hexdocs.pm/horde/readme.html),
[Horde quorum strategy](https://hexdocs.pm/horde/Horde.UniformQuorumDistribution.html),
[Syn](https://hexdocs.pm/syn/readme.html),
[PartitionSupervisor](https://hexdocs.pm/elixir/PartitionSupervisor.html), and
[distributed applications](https://www.erlang.org/doc/system/distributed_applications.html).

This is an architectural selection, not a performance comparison. Pin compatible
versions after checking the project's supported OTP/Elixir runtime. Libraries do
not replace local buffer/backpressure or provider effect contracts.

## Delivery sequence

1. **Define the failure contracts and run a three-node spike.** Exercise libcluster,
   pg/global, local execution agents, one mission controller, and direct routing.
   Compare Horde against the custom lifecycle code. Prove naming before claim,
   separate readiness, monitor behavior, scope restarts, split/heal, old-owner
   return, and no automatic epoch-stealing loops. Decide membership/failover policy.
2. **Refactor local supervision without enabling distribution.** Separate control
   lifetime from execution pools and resource dependencies. Introduce provider
   pipeline units. Replace local coordinator spec dependencies, and preserve
   generation acknowledgement and drain behavior. Add targeted process-kill tests
   before changing restart strategies.
3. **Enable scoped naming and two-node placement.** Route public Runtime calls
   through cluster names and local NodeAgents. Make mission recovery converge on
   the named control unit. Preserve authorization and exact generation semantics;
   remove lazy local partition creation from ingress.
4. **Integrate fenced replacement and distributed reconciliation.** Stop/reconcile
   fenced owners without reclaim loops. Reconstruct placement after coordinator
   loss, admit recovered owners explicitly, and add capacity/drain policies. Prove
   that coordinator failure leaves ready partitions serving their admitted basis.
5. **Qualify the bounded node-local buffer.** Measure archival and decommutation
   lag under steady load and bursts. Verify independent consumer cursors, safe
   reclamation, capacity limits, upstream backpressure, and explicit overflow
   behavior. Exercise local restart replay and deadline-bounded drain. On node
   replacement, recover committed state, start a new capture stream, and report
   gaps without requiring journal replication, transfer, or journal-aware
   placement. Treat archive replay as a separate workflow.
6. **Explicit uncertain-attempt resolution: Control APIs implemented.** Review
   and resolve existing release attempts and reservations with audited evidence
   and preserved lane holds. Provider-status reconciliation already exists;
   provider-specific evidence acquisition and operator UI remain to be added.
   Qualify cancellation and other mutations without adding a parallel generic
   ledger.
7. **Local session admission implemented.** Explicit resource identity, connection
   incarnations, verified readiness receipts, and separately scoped recovery
   permits gate every real send path. Startup/restart is blocked and changes to
   authority, evidence, configuration, or transport/provider membership invalidate
   readiness. Production qualification remains unsupported by default.
8. **Send/persistence boundary implemented.** Exact frames and counter transitions
   commit before delivery in existing transport records. Unresolved preparations
   and replacement runtimes block ordinary sends, including when an uncertainty
   marker could not persist. Qualify provider-specific reconciliation/restoration
   before clearing those holds or enabling automatic takeover.
9. **Define one provider-specific fencing/recovery contract.** Specify external
   revocation, buffered old-session writes, fresh evidence, supported modes,
   allowed recovery operations, and retry/acceptance semantics. Keep production
   qualification unsupported while implementing the next slices.
10. **Versioned COP-1 blocked restoration foundation implemented.** Checkpoint
    export, atomic checkpoint/transport persistence, strict compatibility and
    full-basis validation, idempotent durable installation, and unarmed timer
    intents are available. No readiness/hold-clearing transition is enabled.
    Extend compatibility and pending-control support only under explicit version
    contracts; qualify resynchronization separately from checkpoint continuation.
11. **Implement audited prepared-send reconciliation.** Use existing operation
    and transport records plus provider evidence. Preserve original bytes,
    identities, lane/stream holds, and contradictory observations. Commit the
    reconciled checkpoint/restoration revision before installation; bind readiness
    to that exact installed revision and its evidence watermark.
12. **Qualify provider-specific automatic takeover.** Prove external fencing,
    frame/attempt reconciliation, protocol restoration or authorized reset, and
    timer/retry behavior across real BEAM nodes and an instrumented provider/peer.
    Enable only the qualified combination; all others remain explicitly blocked.
13. **Qualify operations.** Test multi-machine failure, DB-only/BEAM-only isolation,
    rolling restart, mixed versions/generations, projection consistency, provider
    side effects, and command continuity. Prove correctness and freshness separately.

The local refactor should be reviewable independently; it must not claim
cross-node failover before the later gates pass. Use the same unit boundaries
for the OTP reference and any Horde variant so a library choice does not force
another domain restructuring.

## Acceptance and observability

- Kill the mission controller: healthy partition and contact PIDs survive.
- Kill one partition: unrelated partitions and contacts survive, except explicit
  restart-intensity escalation. Recovery restores committed state and, when the
  local buffer is available, a verified input position. Node replacement follows
  the fresh-stream and loss-reporting contract above.
- Kill an execution pool supervisor: reconcile its lost children from admitted
  intent and reconstructible placement while the other pool continues. A restarted
  empty DynamicSupervisor must not be mistaken for recovered execution.
- Kill Registry: dependent execution is rebuilt or re-registered predictably;
  there are no orphaned live owners invisible to naming.
- Kill a provider socket, executor, journal consumer, projector, or journal:
  restart only the documented dependency scope, preserving receipt/cursor rules.
  A restarted socket/transport is not eligible to resume uplink until the
  provider-effect takeover gate is satisfied.
- Drain one node: other nodes' missions stay active; no cluster-wide mission stop
  is inferred. Hand off a locally hosted controller before terminating its tree.
- Partition the network with DB still reachable: stale epochs cannot commit;
  naming conflict resolution and supervisor restart cannot cause ownership churn.
- Crash between name registration, writer claim, recovery, ready publication,
  commit, and response. Resolve retries without overlapping byte-range decoding.
- Restart local journal consumers and verify cursor recovery and replay while
  local files remain available. Preserve independent processing/archive
  acknowledgements from
  [ADR-018](decisions/018-capture-first-telemetry-ingress-journal.md) and persistence
  boundaries from [ADR-019](decisions/019-telemetry-data-plane-persistence-and-projection-topology.md).
- Lose a capture node or its disk: replacement capture does not wait for journal
  access, replication, or transfer. Recover committed semantic state, start a new
  stream boundary, and expose observed gaps/uncertain ranges. Test upstream
  redelivery only where the source provides it; do not assume it.
- Sustain nominal ingress with archival and decommutation keeping pace and little
  retained backlog. Slow either consumer to verify bounded growth, backpressure,
  reclamation only after both required cursors, and explicit overflow behavior.
  Drain with both a cleared backlog and an expired deadline; report the remaining
  backlog without handing the journal to another node.
- Race command release callers across nodes: one exact durable claim wins and
  the stored command basis cannot change. Crash before send, after partial
  multi-payload send, after socket-send success, before provider acknowledgement,
  and after acknowledgement but before database completion. Preserve uncertain
  claims and lane holds; never infer remote acceptance from local send success.
- Resolve an uncertain attempt concurrently with another resolver and a late
  acknowledgement. Verify exact attempt/basis matching, idempotent completion,
  preserved success, evidence auditability, and continued holds for unknown
  outcomes. Definitive failure and operator risk acceptance must remain distinct.
- Race booking/cancellation callers across nodes. Reuse stable operation keys
  and enforce immutable payloads. Where the provider lacks deduplication or
  recovery evidence, retain uncertainty rather than automatically resubmit.
- Isolate an old uplink owner while its socket remains usable, including loss of
  only database access or only BEAM connectivity. Prove that session fencing
  prevents stale external sends before the replacement becomes ready. A local
  refusal to finalize a database record does not prove that the send was stopped.
- Restart or move the uplink runtime with outstanding protocol frames and timers.
  Verify sequence continuity, acknowledged/outstanding frame reconciliation,
  protocol-authorized retransmission, and no duplicate command submission after
  verified restore or resynchronization. Unsupported recovery stays blocked.
- Start or reconnect a session without fencing/recovery evidence: ordinary
  uplink stays blocked even with a ready semantic partition and connected socket.
  Exercise initial sends, retransmissions, timer races, direct/bypass sends,
  control frames, and direct adapter calls; none bypass admission. Permit only
  explicitly authorized recovery exchanges while ordinary uplink is blocked.
- Change binding/configuration or replace the provider/transport process: reject
  old-incarnation requests and receipts. Shared paths/lanes for the same exclusive
  resource cannot acquire independent send authority. Unrelated qualified
  sessions may continue.
- Inject failure before prepared-basis commit, immediately after it, after each
  payload send, before state persistence, and after peer acknowledgement. Verify
  no sends without committed preparation, inferred uncertainty without a durable
  failure marker, no counter reuse, exact frame/attempt identity retention, and
  a stream-wide hold whenever continuity is ambiguous.
- Restore old/incompatible checkpoints, deliver stale-session acknowledgements,
  and recover with expired timers. Validate peer reconciliation and negotiated
  reset policy; do not fire ordinary retransmissions merely by restoring timers.
  Prove old-session buffered/in-flight frames cannot violate the qualified
  takeover contract after external fencing.
- Exercise audited prepared-send reconciliation with duplicate resolution IDs,
  stale review bases, concurrent resolvers, partial frame batches, contradictory
  evidence, sequence wrap, and late acknowledgements. Preserve the original send
  history and distinguish frame acknowledgement from command execution. Unknown
  outcomes keep their proper lane/stream holds; resolving an attempt alone cannot
  release a protocol-stream hold.
- Crash before/after recovery revision commit, during installation, and before
  readiness publication. Restart recovery idempotently from the exact committed
  basis. Change the observation watermark or configuration between proposal and
  admission and verify readiness cannot use stale evidence. Test supported
  checkpoint migrations and reject missing/incompatible histories without
  falling back to fresh counters or auto-deserializing evidence snapshots.
- Version readiness, routing, and recovery protocols. Define an initial cutover
  when old binaries cannot participate safely; disabling fencing is not rollback.
- Export control handoff, registry conflicts, fenced exits, ownership churn,
  readiness/recovery duration, request/byte pressure, journal occupancy,
  per-consumer lag, oldest buffered input age, backpressure transitions, drain
  backlog/timeouts, observed input gaps, uncertain-attempt count/age, held-lane
  duration, resolution outcomes, session-fencing status, protocol recovery state,
  installed/committed checkpoint revisions and recovery watermark mismatches,
  reconciliation conflicts, oldest unresolved preparation, readiness transitions,
  prepared-but-unsettled frame counts, persistence-after-send
  failures, affected-stream hold duration, takeover blocking reasons, and freshness.
  Keep unbounded mission/partition identifiers in logs rather than metric labels.
- Bridge cross-node wakeups with reconciliation as backstop; audit queries so
  one web replica's local ETS view is not mistaken for complete mission state.

Use focused local failure tests, independent-connection fencing tests, a real
multi-BEAM suite, and a multi-machine deployment harness. Process namespaces on
one BEAM do not test network partitions. Run `mix precommit` for delivered changes.
The prior ten-second freshness target is an initial measured workload gate, not
an assumed guarantee of failover duration.
