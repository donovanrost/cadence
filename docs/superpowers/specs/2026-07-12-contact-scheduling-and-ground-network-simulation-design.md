# Design: Contact Scheduling and External Ground Network Simulation

- Status: draft for product and architecture review
- Created: 2026-07-12
- Scope: Define the idealized end state for provider-neutral contact scheduling
  in Cadence and for an independent ground-network simulator that exercises the
  same integration boundary as commercial providers.
- Related decisions:
  - [ADR-006: Contact, Link, and Transport Runtime Model](../../decisions/006-contact-link-and-transport-runtime-model.md)
  - [ADR-012: Provider Adapter and Ground Station Simulator Model](../../decisions/012-provider-adapter-and-ground-station-simulator-model.md)
  - [ADR-013: Shared CCSDS Library Boundary](../../decisions/013-shared-ccsds-library-boundary.md)
- Related designs:
  - [Comms Transport, Routing, and Spacecraft Profile UX](2026-06-01-comms-transport-routing-and-spacecraft-profile-design.md)
  - [Ground Network Simulator](../../ground-network-simulator.md)

## Summary

Cadence should schedule and execute contacts through a provider-neutral product
model. Whether a contact is supplied by the Cadence Ground Network Simulator,
AWS Ground Station, KSAT, a customer-owned antenna, or a future provider should
not change Cadence's mission workflow or canonical contact model.

The ground-network simulator is an independent provider peer. It owns simulated
spacecraft inventory, ground-station capacity, opportunity generation,
provider-side reservations, faults, simulation time, and contact-time telemetry
generation. Cadence owns mission spacecraft, contact requirements, planning,
provider selection, canonical scheduled and realized contacts, runtime paths,
telemetry interpretation, audit, and operator workflows.

The simulator is operationally realistic, deterministic, and scalable. It is
not required to be orbitally precise. Its purpose is to exercise the same
control-plane and data-plane boundaries that Cadence will use with real ground
networks.

## North Star

> A mission operator can replace the simulator provider with a commercial
> provider without changing the Cadence scheduling workflow, contact lifecycle,
> runtime path, or telemetry processing pipeline.

Provider-specific differences remain visible when they matter, but they are
expressed as capabilities and provider metadata rather than as separate Cadence
product flows.

## Product Principles

### The simulator is a provider, not a Cadence mode

Cadence does not start, stop, configure, or administer simulator scenarios.
There is no privileged simulator route, hidden telemetry injection path, or
simulator-only contact lifecycle inside Cadence.

### Planning and execution are separate

An opportunity is a provider proposal. A reservation is an external commitment.
A scheduled contact is Cadence's canonical execution intent. A realized contact
is the runtime instance that owns active paths and links.

These concepts must not be collapsed into one mutable record.

### Control plane and data plane are separate

The provider control plane searches opportunities, reserves capacity, reports
status, and negotiates delivery. The data plane moves contact-time bytes and
link observations. A provider may use REST for the control plane and TCP, UDP,
SLE, files, or a cloud delivery service for the data plane.

### Provider state is asynchronous

Provider requests can time out after succeeding, contacts can change after
acceptance, and terminal events can arrive late or more than once. Cadence must
use durable idempotency, durable provider-event cursors, and reconciliation.

### Realism means operational pressure

The simulator must model contention, capacity, lifecycle delay, outages,
acquisition failure, degraded links, and partial delivery. High-fidelity orbital
propagation is optional and replaceable.

### Do not invent a general plugin system yet

Provider clients implement a narrow behaviour and are selected through an
explicit registry. Adapters may later be packaged as OTP applications, but the
first provider integrations should teach us what an extension model actually
needs. Runtime code upload and an all-purpose plugin framework are out of scope.

## Goals

- Schedule contacts for fleets containing several hundred spacecraft.
- Use one Cadence workflow across simulated and commercial providers.
- Support manual booking, policy-assisted planning, and eventual automatic
  scheduling without changing the underlying contact model.
- Exercise the complete path from opportunity search through telemetry ingest.
- Make provider requests and resulting state fully auditable and recoverable.
- Produce deterministic simulator scenarios suitable for tests and demos.
- Allocate simulator telemetry workers only for active contacts.
- Support realistic provider and network failure modes.
- Keep CCSDS implementation shared without coupling the simulator to Cadence.
- Make adding a commercial provider an adapter project rather than a Cadence
  scheduling rewrite.

## Non-Goals

- Mission-grade orbit determination or access prediction in the initial
  simulator.
- Reproducing every vendor API field in Cadence's canonical model.
- Hiding useful provider-specific capabilities from operators.
- Treating TCP as the universal commercial-provider data plane.
- Building a generic optimization solver before the single-contact workflow is
  proven end to end.
- Letting the simulator create Cadence organizations, missions, spacecraft,
  routes, catalogs, or contacts.
- Storing high-rate telemetry in the simulator's control-plane database.
- Loading arbitrary third-party adapter code at runtime.

## Current Baseline

The repository now provides the first operator-visible vertical slice of this
design:

- `cadence_simulator` can run independently and expose a provider-style HTTP
  API for scenarios, runs, opportunities, reservations, and ordered events.
- Cadence has a provider-client behaviour, normalized simulator HTTP client,
  durable booking saga, and supervised status reconciler.
- Mission provider configuration can select the simulator scheduling client.
- Provider Reservation is first-class, mission-scoped integration state with
  durable idempotency, provider evidence, exact route versions, ambiguous-outcome
  recovery, and idempotent Scheduled Contact materialization.
- **Ops → Contacts** provides readiness, provider opportunity search,
  reservation, cancellation, and separate provider/Cadence lifecycle state
  inside the authenticated mission Ops surface.
- The existing contact scheduler realizes canonical scheduled contacts into
  path-local runtime.
- The end-to-end boundary proof reserves over simulator HTTP and receives
  decoded telemetry through Cadence's normal TCP/TM ingress pipeline.
- CCSDS framing, segmentation, reassembly, and COP-1 primitives live in the
  shared `cadence_ccsds` application.

This completes Stage 1, not the full contact-planning product. Contact
Requirements, versioned Contact Plans, provider accounts and secret references,
durable event cursors or webhooks, provider-fleet reconciliation, and automated
multi-spacecraft planning remain target state.

## Stage 1 Decisions

The first implementation milestone is settled:

- book directly from Opportunity to durable Provider Reservation to Scheduled
  Contact, without creating a Contact Plan;
- place Contact Scheduling at `/missions/:mission_id/ops/contacts` inside the
  authenticated mission Ops surface;
- prove downlink scheduling and telemetry first, deferring uplink and
  bidirectional execution.

The repo-grounded task sequence is defined in the
[Stage 1 Contact Scheduling Implementation Plan](../plans/2026-07-13-contact-scheduling-stage-1.md).

## System Ownership

| Concern | Cadence | Provider or simulator |
| --- | --- | --- |
| Mission spacecraft identity | Authoritative | External reference only |
| Spacecraft interpretation and catalogs | Authoritative | Generates bytes matching an agreed profile |
| Contact requirements and priorities | Authoritative | Not owned |
| Opportunity generation | Consumes and normalizes | Authoritative |
| Ground-station and antenna capacity | Observes available capabilities | Authoritative |
| Provider reservation state | Mirrors and reconciles | Authoritative |
| Canonical scheduled contact | Authoritative | External reference only |
| Contact realization and runtime paths | Authoritative | Supplies session and delivery state |
| Data-plane session | Owns Cadence endpoint and runtime half | Owns provider endpoint and runtime half |
| Telemetry generation | Not for provider simulation | Authoritative in simulator |
| Telemetry interpretation and persistence | Authoritative | Not owned |
| Scenario clock, seed, and faults | Not owned | Authoritative in simulator |
| Operator audit | Records Cadence decisions and provider evidence | Records provider-side activity |

## Product Vocabulary

| Term | Meaning | Current implementation relationship |
| --- | --- | --- |
| Provider Type | One integration implementation and capability family, such as simulator HTTP, AWS Ground Station, or KSAT. | `ProviderClient` implementation and registry entry. |
| Provider Account | Organization-owned credentials, endpoint, commercial account, and connection policy. | Not yet separated; some values currently live in `ProviderProfile.configuration`. |
| Mission Provider | A mission's enabled use of a Provider Account, including spacecraft mapping, allowed services, and scheduling policy. | Closest to the existing mission-scoped `ProviderProfile`. |
| Transport | Durable capability for moving bytes. It may be provider-backed but does not itself mean a contact is booked. | Product model defined by the comms design; currently materialized through provider/path configuration. |
| Contact Requirement | A statement of needed service, constraints, priority, and acceptable delivery outcomes. | New target-state concept. |
| Opportunity | A time-limited provider proposal for specific resources and service. | Returned by provider opportunity search; not canonical mission state. |
| Contact Plan | A versioned selection of opportunities intended to satisfy one or more requirements. | New target-state concept. |
| Provider Reservation | Cadence's durable mirror of a provider-side booking and its reconciliation state. | First-class mission-owned persistence with durable idempotency and status reconciliation. |
| Scheduled Contact | Cadence's canonical time-bounded execution intent after capacity is committed or explicitly planned for a non-reserving transport. | Existing `ScheduledContact`. |
| Realized Contact | Runtime realization containing active paths, links, bindings, and observations. | Existing `RealizedContact`. |
| Contact Result | Planned-versus-delivered summary including timing, volume, failures, and provider evidence. | New projection over contact and runtime records. |

User-facing product language should prefer Provider, Requirement, Opportunity,
Plan, Scheduled Contact, and Contact Result. Internal persistence names such as
`ProviderProfile`, `PathTemplate`, and `ProviderBinding` should not leak into the
primary scheduling workflow.

## Conceptual Model

### Provider Type and capabilities

A Provider Type identifies an adapter and publishes capabilities. Capabilities
must be explicit because providers differ without requiring separate Cadence
workflows.

Initial capability vocabulary should include:

- opportunity search
- immediate reservation
- asynchronous reservation confirmation
- reservation modification
- cancellation
- provider event polling
- provider webhooks
- spacecraft inventory discovery
- ground-station inventory discovery
- downlink, uplink, or bidirectional service
- supported data-plane kinds
- supported framing or service protocols
- maximum search horizon and request limits
- counteroffers or provider-selected resource substitution

Cadence must reject unsupported operations before sending a provider request.

### Provider Account

A Provider Account logically contains:

- provider type
- API endpoint and region, when applicable
- secret references
- account or network identifiers
- request timeout, retry, and rate-limit policy
- event ingestion mode
- health and credential-validation status
- provider-specific configuration that does not belong to one mission

The ideal ownership is organization scope with explicit mission grants. The
first implementation may remain mission-scoped, but APIs should not assume that
credentials can never be shared across missions.

Raw credentials must not be stored in ordinary provider configuration maps,
rendered in LiveView assigns, returned by read APIs, or written to logs. Provider
configuration should store secret references.

### Mission Provider

A Mission Provider binds a provider account to mission intent:

- enabled services and directions
- provider spacecraft mappings
- permitted stations, antennas, or service pools
- preferred delivery transports
- mission-specific dataflow profile references
- scheduling horizon and policy
- budget or quota constraints
- active configuration version

Mapping is explicit. Cadence spacecraft identity remains canonical, while the
provider spacecraft ID remains external evidence.

### Contact Requirement

A Contact Requirement describes the outcome the mission needs without selecting
a provider opportunity.

An initial requirement shape should support:

```text
spacecraft
service direction and intent
earliest start and latest end
minimum and preferred duration
minimum expected data volume, when known
acceptable providers and stations
priority
redundancy count
minimum separation between contacts
approval policy
metadata and operator rationale
```

A requirement may be created manually, generated from mission policy, or
imported. Requirements are versioned and auditable. Editing a requirement after
planning creates a new version and does not silently mutate an approved plan.

### Opportunity

An Opportunity is provider-owned and ephemeral. The canonical normalized shape
should include:

```text
provider opportunity reference
provider and account references
Cadence spacecraft reference plus provider spacecraft reference
ground station, antenna, or service-pool reference
start and end time
supported directions and services
estimated capacity or data volume
availability or confidence
price or cost evidence when supplied
reservation deadline or expiry
provider-specific extensions
raw evidence reference
```

Cadence may cache opportunity snapshots for planning and audit, but it must not
assume a cached opportunity remains reservable. Reservation is the authority.

Provider-native fields should be retained as bounded extension metadata or raw
evidence, not added to the canonical model without a cross-provider use case.

### Contact Plan

A Contact Plan is a versioned, reviewable selection of opportunities. It records:

- requirements it intends to satisfy
- opportunity snapshots considered
- selected and rejected opportunities
- scoring and constraint explanations
- estimated coverage, volume, cost, and risk
- conflicts and unsatisfied requirements
- approval status and approver evidence
- the exact version used to initiate reservations

The first product slice may book one opportunity without exposing a plan object
in the UI. The end-state model should still leave room for a plan so bulk and
automatic scheduling do not overload `ScheduledContact`.

### Provider Reservation

A Provider Reservation is first-class durable integration state. It must not
exist only as metadata on a scheduled contact.

It records:

- Cadence reservation ID
- provider account and mission provider
- provider reservation and opportunity references
- idempotency key
- request and normalized response evidence
- requested and provider-confirmed resources and times
- provider status and Cadence reconciliation status
- linked plan, requirement, and scheduled contact
- last provider event and durable cursor evidence
- ambiguous-outcome and compensation state
- retry and error history

Suggested normalized lifecycle:

```text
requesting -> pending -> confirmed -> active -> completed
     |           |          |
     +--------> rejected     +-> canceling -> canceled
     +--------> unknown      +-> failed
```

`unknown` means Cadence cannot determine whether a timed-out request succeeded.
It triggers describe/reconcile using the same idempotency key. It must not cause
an immediate duplicate reservation.

### Scheduled Contact

A Scheduled Contact is created when:

- a reserving provider confirms capacity; or
- a provider/transport explicitly supports authoritative local scheduling
  without a reservation.

It owns Cadence execution intent, selected routing references, source endpoints,
planned start/end, and the linked provider reservation. Provider changes do not
silently overwrite it; reconciliation records the change and applies an
auditable transition or creates an operator decision when required.

The existing lifecycle remains a useful execution-level model:

```text
scheduled -> realized -> completed
    |            |
    +-> expired  +-> completed with degraded result
    +-> canceled
```

Provider reservation status and scheduled-contact lifecycle are related but not
identical. A provider may confirm a reservation before Cadence marks the contact
ready, or report a failure after Cadence has realized the runtime.

### Realized Contact and Contact Result

The Realized Contact owns runtime paths, provider bindings, transport runtime,
clock mode, link observations, and lifecycle. It should not perform opportunity
search or provider booking.

The Contact Result compares intent with delivery:

- planned, provider-confirmed, acquisition, and loss-of-signal times
- delivered duration
- received and transmitted bytes, frames, packets, and application records
- expected versus delivered volume
- provider and Cadence failure reasons
- path and transport health
- command delivery and verification outcomes when uplink is present
- provenance links to provider events and canonical runtime records

## Provider Contract

Cadence defines a provider-neutral application contract. Provider adapters
translate vendor APIs into this contract; commercial providers are not expected
to implement Cadence's HTTP API.

The simulator is the reference provider implementation and should expose an
HTTP form of the same semantics for contract testing.

### Required operations

The target provider-client boundary includes:

```text
capabilities
validate_connection
list_spacecraft or resolve_spacecraft
list_ground_stations
search_opportunities
reserve_contact
describe_contact
modify_contact, when supported
cancel_contact
list_events from a durable cursor
acknowledge or verify webhook delivery, when supported
```

Each operation accepts the provider account, mission provider context, a
correlation ID, and operation-specific parameters. Mutating operations require
an idempotency key generated and durably recorded by Cadence before the request
is sent.

### Error contract

Adapters normalize provider errors into categories while preserving sanitized
provider evidence:

- invalid request
- authentication or authorization failure
- unsupported capability
- resource not found
- conflict or no capacity
- rate limited, including retry hints
- provider unavailable
- request timeout with known failure
- ambiguous outcome
- malformed provider response
- permanent provider rejection

Retry decisions belong to platform integration policy, not to individual
LiveViews or callers.

### Versioning

The canonical contract is versioned independently from vendor API versions.
Adapters declare the canonical versions and capabilities they implement.
Provider-native API version changes are contained inside the adapter unless
they change a canonical capability.

## Contact Scheduling Workflow

### Single-contact workflow

The first complete workflow is:

1. An operator selects a spacecraft, service, and time range.
2. Cadence validates mission provider and routing readiness.
3. Cadence searches one or more enabled providers concurrently with bounded
   concurrency and provider-specific rate limits.
4. Cadence normalizes and displays opportunities with provider provenance.
5. The operator selects an opportunity.
6. Cadence durably creates a reservation attempt and idempotency key.
7. Cadence sends the provider reservation request.
8. Cadence confirms or reconciles the provider result.
9. Cadence creates the canonical Scheduled Contact and links it to the provider
   reservation.
10. The contact scheduler realizes the contact at the appropriate time.
11. Provider data-plane delivery enters the normal path runtime.
12. Provider events and Cadence observations update the Contact Result.

No step invokes simulator administration APIs from Cadence.

### Bulk and automatic workflow

The later fleet workflow adds:

1. Collect active requirements over a planning horizon.
2. Search providers in bounded batches.
3. Normalize and deduplicate opportunity sets.
4. Score opportunities against hard constraints and soft preferences.
5. Produce a versioned plan with unsatisfied-requirement explanations.
6. Obtain approval when policy requires it.
7. Reserve selected contacts using bounded concurrency and durable sagas.
8. Replan only affected requirements when reservations fail or providers
   counteroffer.

The planning engine must distinguish hard constraints from scoring. It must not
quietly violate a hard constraint because a plan has a better aggregate score.

### Cancellation and modification

Cancellation is a provider operation followed by a canonical Cadence
transition. Cadence should expose `canceling` or `reconciling` while the outcome
is unknown; it must not immediately claim that externally held capacity has
been released.

Modification uses a provider-native modify operation when supported. Otherwise
Cadence treats it as a replacement reservation followed by cancellation of the
old reservation, with explicit risk and rollback semantics. It must not cancel
the old contact before replacement capacity is confirmed unless an operator or
policy explicitly accepts that risk.

## Durable Reconciliation

Each active provider account has a supervised reconciliation worker or worker
partition. Reconciliation state is durable and includes:

- provider event cursor or continuation token
- last successful poll and health state
- webhook delivery IDs and deduplication keys
- retry schedule and backoff
- reservations requiring describe calls
- ambiguous mutations awaiting resolution

Provider events are at-least-once inputs. Processing must be idempotent. Cursor
advancement occurs only after the event and resulting canonical changes commit.

Polling and webhooks are complementary. Webhooks reduce latency; polling repairs
missed delivery and provides restart recovery. A provider adapter may support
only one, but Cadence's canonical reconciliation semantics remain the same.

Reconciliation must never rely solely on process memory.

## Data-Plane Contract

A confirmed reservation produces or references a data-plane descriptor. The
descriptor should represent:

- direction
- delivery mode: provider-connects, Cadence-connects, pull, or provider-managed
- endpoint or endpoint negotiation reference
- protocol or service type
- framing contract
- allowed source identities
- session activation window
- authentication or ephemeral credential reference
- provider binding metadata

Cadence materializes the descriptor into path-local provider and transport
bindings. The data-plane runtime remains under the Realized Contact and its
paths, consistent with ADR-006.

The simulator's initial data plane is provider-connects TCP downlink with fixed
CCSDS TM frames. The target model also leaves room for UDP, bidirectional TCP,
SLE, object storage, cloud streams, and provider-managed delivery.

High-rate bytes do not travel through the provider scheduling API.

## Simulator Product

### Deployment boundary

The simulator is independently buildable and runnable:

- local developer process
- CI service container
- shared development environment
- demo environment
- performance or chaos-test deployment

It owns its configuration, persistence, supervision tree, provider API, and
optional console. A production simulator release must not include Cadence core,
Cadence database configuration, or Cadence web configuration.

### Scenario

A Scenario is a reusable, versioned definition containing:

- spacecraft fleet generator or explicit inventory
- provider spacecraft IDs and optional mission aliases
- ground stations, antennas, service pools, and capacity
- maintenance and outage windows
- pass or opportunity model
- telemetry generation profiles
- data-plane defaults
- fault profile
- default clock settings
- deterministic seed policy

Editing a scenario creates a new version. A running simulation uses an immutable
scenario snapshot.

### Run

A Run contains:

- immutable scenario snapshot and version
- seed
- lifecycle state
- wall-clock start
- model-time anchor
- speed
- pause and resume history
- generated opportunities and reservations
- ordered event sequence
- active telemetry workers
- run-level health and metrics

Given the same scenario version, seed, time anchor, and sequence of API
requests, the simulator should produce the same opportunities and deterministic
fault decisions.

### Time model

Provider API timestamps are executable UTC instants. Cadence should not need a
simulator-specific clock to schedule a contact.

For accelerated runs, the simulator maps model time onto a compressed wall-clock
schedule and returns wall-clock contact times. Model time and speed are included
as simulator metadata for explanation and replay. Pausing a run stops new
lifecycle advancement and records the mapping change; it does not silently
rewrite already confirmed Cadence contacts without emitting provider events.

This choice preserves the real provider contract. A future fully virtual Cadence
clock is a separate replay capability, not a requirement for simulator-backed
contact scheduling.

### Opportunity model

The default opportunity engine may be deterministic and synthetic. It must
produce plausible operational behavior:

- bounded pass duration
- repeatable spacecraft-specific cadence and jitter
- station and antenna selection
- overlapping windows
- limited antenna capacity
- maintenance and outage exclusion
- stable opportunity IDs within a run
- opportunity expiry

The engine is replaceable. A future TLE/SGP4 or external propagation engine can
implement the same internal opportunity interface without changing the provider
API or Cadence integration.

All synthetic opportunities and results are explicitly marked as simulated.

### Reservation behavior

The simulator enforces:

- opportunity and resource validity
- station and antenna contention
- idempotent reservation creation
- configurable confirmation delay
- deterministic rejection
- modification and cancellation rules
- provider event emission for every externally visible transition
- restart recovery from durable reservation state

It should support both immediate confirmation and asynchronous pending behavior
so Cadence cannot assume one provider response style.

### Telemetry behavior

Telemetry workers exist only for acquiring or active contacts. During an active
downlink, a worker:

1. loads the simulator-owned telemetry definition or generator profile;
2. generates deterministic values for the provider spacecraft;
3. packetizes and frames data with `cadence_ccsds`;
4. applies configured faults and timing behavior;
5. opens or accepts the negotiated data-plane session;
6. streams bytes until contact completion, failure, or termination;
7. emits provider lifecycle and delivery observations.

The simulator should eventually support uplink reception and CLCW generation,
but end-to-end downlink is the first required scheduling slice.

### Fault model

Faults should be deterministic for a run and configurable at scenario, station,
spacecraft, reservation, and time-window scope.

Initial categories:

- provider API outage and latency
- authentication failure
- rate limiting
- scheduling rejection
- delayed confirmation
- acquisition failure
- late acquisition
- early termination
- station outage or maintenance
- packet or frame loss
- duplication, reordering, and corruption where the transport permits them
- network latency and jitter
- data-plane connection refusal or disconnect
- telemetry generator failure

Faults must be observable through provider events and metrics. They should not
exist only as unexplained dropped data.

## Operator Experience

### Cadence setup surface

Provider setup belongs in authenticated mission management under Comms or
Transports. It includes account selection, spacecraft mapping, services,
delivery configuration, and readiness checks.

Credentials and organization-level provider-account administration may later
move to organization settings. Mission pages should show references and health,
not reveal secrets.

### Cadence operations surface

Contact scheduling belongs under mission operations, not the durable comms
setup pages. The end-state surface includes:

- Requirements
- Planning horizon and provider filters
- Opportunity comparison
- Contact Plan review and approval
- Scheduled contacts calendar and timeline
- Contact detail with provider and runtime lifecycle
- Active contact status
- Contact Results and delivery variance

The simulator is shown as an ordinary provider with a clear `Simulated` badge.
Cadence may link to the simulator's console but does not embed simulator
administration.

### Simulator surface

The simulator may provide its own small console for:

- scenario authoring and version history
- run start, pause, resume, stop, and replay
- simulation clock and seed
- fleet and station inventory
- opportunity and reservation inspection
- active telemetry workers
- fault activation
- API and data-plane health

This console is optional for the first API milestone but is the correct home for
simulator operations.

## Security and Tenancy

- Every Cadence provider operation is scoped through organization and mission
  authorization.
- Provider accounts use secret references backed by an approved secret store.
- Provider responses and raw evidence are sanitized before persistence.
- Webhooks are authenticated and replay-protected.
- Data-plane credentials should be short-lived when supported.
- Simulator authentication must be enabled outside an explicitly local profile.
- Simulator scenarios and runs have their own tenant or namespace boundary in
  shared environments.
- Correlation IDs cross Cadence, adapter, simulator/provider, and data-plane
  logs without exposing credentials.

## Audit and Observability

Cadence records:

- requirement and plan versions
- opportunity search parameters and provider evidence references
- selected and rejected choices with rationale
- every mutating provider request and idempotency key
- normalized provider responses and error category
- reservation transitions
- provider events and cursor advancement
- operator approvals, cancellations, and overrides
- scheduled and realized contact transitions
- final planned-versus-delivered result

Required metrics include:

- provider request latency, errors, rate limiting, and retries
- reconciliation lag and cursor age
- reservations by state, including unknown and reconciling
- opportunity search volume and truncation
- scheduled, active, completed, failed, and canceled contacts
- acquisition success and timing variance
- delivered duration and data volume variance
- simulator active workers, generated frames, sent bytes, loss, and disconnects

Logs alone are not an audit model.

## Scale and Performance Targets

Initial target envelope:

- 500 spacecraft in one simulator scenario
- at least 30 simulated antennas across multiple stations
- a 72-hour search horizon
- at least 10,000 returned or paged opportunity candidates per planning run
- 100 concurrent active simulated contacts on a suitably provisioned host
- no process per idle spacecraft
- bounded provider-search concurrency and memory
- deterministic teardown of all contact workers

Initial service objectives for local or CI reference hardware:

- provider health request p95 below 250 ms
- single-spacecraft opportunity search p95 below 1 second
- 500-spacecraft batched search completing within 10 seconds or returning
  paginated progress
- reservation mutation p95 below 500 ms excluding configured delay
- provider terminal-event reconciliation visible in Cadence within 10 seconds
- zero duplicate reservations under idempotent retries

These are design targets, not claims about the current implementation. They
should be refined with repeatable benchmark hardware and scenario fixtures.

## Testing Strategy

### Provider contract suite

Cadence should own a reusable conformance suite for every Provider Client:

- capability declaration
- normalization of search and reservation responses
- idempotent mutation behavior
- error classification
- timeout and ambiguous-outcome handling
- event ordering, duplication, and cursor recovery
- cancellation and modification semantics
- sanitization of provider evidence

The simulator client is the first implementation. Commercial adapters must pass
the same canonical suite plus provider-specific tests.

### Simulator tests

- deterministic opportunity generation from scenario and seed
- capacity contention and opportunity expiry
- reservation idempotency and restart recovery
- every lifecycle and fault transition
- contact-only telemetry worker allocation
- data-plane framing and teardown
- API authentication and tenant isolation
- scale tests for fleet search and concurrent contacts

### End-to-end tests

The critical acceptance test runs separate simulator and Cadence applications:

1. Create a simulator scenario and run.
2. Configure a Cadence mission provider through normal APIs or UI.
3. Search and reserve a contact through Cadence.
4. Confirm canonical Scheduled Contact creation.
5. Realize the contact at its scheduled time.
6. Receive framed telemetry through the normal provider runtime.
7. Decommutate and persist mission telemetry.
8. Complete or fault the provider contact.
9. Reconcile the canonical Contact Result.

No direct database sharing, in-process simulator calls, or simulator-specific
Cadence injection helpers are permitted in this proof.

## Delivery Stages

### Stage 0: Boundary foundation

Status: substantially present.

- independent simulator application and configuration
- shared CCSDS leaf application
- provider-style simulator API
- provider-client behaviour and simulator client
- initial booking and event reconciliation seams
- mission provider scheduling configuration

### Stage 1: One contact, end to end

Status: implemented.

- provider readiness check and spacecraft mapping
- operator opportunity search for one spacecraft
- opportunity selection and durable reservation attempt
- canonical Scheduled Contact creation
- normal contact realization
- contact-time simulator telemetry through the existing runtime
- contact detail showing provider and Cadence lifecycle
- terminal result reconciliation

The automated proof crosses the provider HTTP boundary and the ordinary Cadence
TCP telemetry boundary without direct simulator injection.

### Stage 2: Durable integration semantics

- durable event cursors or webhook ingestion where provider capabilities justify
  moving beyond Stage 1 status polling
- secret references
- reservation modification and provider-initiated change handling
- complete audit evidence

### Stage 3: Requirements and planning

- Contact Requirement model and workflow
- versioned Contact Plans
- multi-provider search
- opportunity comparison and explanation
- approval workflow
- unsatisfied-requirement reporting

### Stage 4: Fleet scheduling and automation

- batched several-hundred-spacecraft planning
- policy scoring and hard constraints
- bounded parallel reservation sagas
- partial replanning
- quotas, budgets, and redundancy policy
- scale and chaos qualification

### Stage 5: Commercial provider proof

- implement one real provider adapter
- run the same conformance and end-to-end workflow
- identify actual extension points from vendor differences
- decide whether adapter packaging needs to evolve into a formal plugin model

The commercial-provider proof is the architecture test. If it requires a
separate Cadence scheduling workflow, the provider boundary is incomplete.

## Acceptance Criteria

### First product milestone

- The simulator and Cadence run as separate applications.
- A mission operator configures the simulator through the ordinary provider
  setup surface.
- The operator searches opportunities for one mapped spacecraft.
- Cadence reserves one opportunity with durable idempotency.
- The reservation creates one canonical Scheduled Contact.
- Contact realization uses the existing runtime and path model.
- Telemetry enters through the normal provider data plane and is interpreted for
  the mission spacecraft.
- Provider cancellation, acquisition failure, and early termination are visible
  and reconciled.
- Restarting either application does not create a duplicate reservation or lose
  terminal state.
- No Cadence simulator administration route or bootstrap command is required.

### Idealized end state

- Several hundred spacecraft can be planned over a multi-day horizon.
- Multiple providers can participate in one Contact Plan.
- Provider differences are expressed through capabilities and extensions.
- Provider mutations are durable, idempotent, auditable, and recoverable.
- Contact Results explain planned-versus-delivered outcomes.
- The simulator can reproduce operational failures deterministically.
- One commercial provider completes the same workflow without changing Cadence
  scheduling semantics.

## Open Questions

The draft recommends defaults but leaves these decisions for review:

1. **Provider account scope:** Prefer organization-owned accounts with explicit
   mission grants, while allowing the first implementation to remain
   mission-scoped.
2. **Approval defaults:** Which missions require approval before reservation,
   and is approval policy organization-, mission-, or requirement-scoped?
3. **Provider counteroffers:** Should a changed time/resource always require
   approval, or can policy accept bounded substitutions automatically?
4. **Clock acceleration:** The draft chooses wall-clock executable timestamps
   with model-time metadata. Is there a near-term need for Cadence-wide virtual
   time beyond replay?
5. **Inventory authority:** Should provider spacecraft mappings be manually
   curated, imported, or reconciled continuously?
6. **Data-plane credentials:** Which secret store and ephemeral credential model
   should the first non-local provider use?
7. **First commercial adapter:** AWS Ground Station has accessible public APIs,
   but another provider may better exercise reservation and event semantics.
8. **Simulator console:** Is an API-only simulator sufficient through Stage 2,
    or is a minimal separate console important for demos earlier?

The remaining questions do not block Stage 1.
