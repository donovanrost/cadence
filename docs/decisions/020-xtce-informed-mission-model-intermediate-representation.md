---
title: "ADR-020: XTCE-Informed Mission Model Intermediate Representation"
aliases:
  [xtce, mission model, mission database, semantic hir, catalog compiler]
tags:
  [adr, architecture, xtce, catalog, telemetry, commanding, algorithms, monitoring]
status: accepted
created: 2026-08-11
updated: 2026-08-12
---

# ADR-020: XTCE-Informed Mission Model Intermediate Representation

## Status

Accepted

If accepted, this ADR amends parts of
[ADR-008](008-multi-format-catalog-import-architecture.md),
[ADR-009](009-canonical-telemetry-catalog-model.md),
[ADR-010](010-canonical-command-catalog-model.md), and
[ADR-016](016-typed-extension-packages-and-product-applications.md).

It retains their decisions that:

- source artifacts and format-specific parsed models remain first-class;
- provenance, extensions, and import diagnostics are preserved;
- runtime code never interprets source formats directly;
- telemetry decoding, algorithm execution, monitoring, and commanding have
  separate runtime semantics; and
- product applications may retain separate operator-facing workflows.

It replaces the assumptions that:

- separate telemetry and command snapshots are the highest canonical semantic
  representation;
- derived telemetry and limits are semantically separate governed definition
  families outside the catalog model; and
- the current Derived Telemetry and Limits domain APIs or persistence shapes
  constrain the target architecture.

## Implementation Status

The initial implementation is complete as of 2026-08-12. Cadence now has:

- immutable declaration layers, resolved Mission Model revisions, typed
  references, provenance, defaults, inheritance checks, semantic validation,
  target capability diagnostics, and deterministic target plans;
- adapters from the existing telemetry and command snapshots plus governed
  migration helpers for the transitional Derived Telemetry and Limits models;
- an XTCE 1.3 frontend with a pinned, offline copy of the normative schema,
  source-location diagnostics, semantic preservation of unsupported executable
  constructs, and deterministic export of the representable core subset;
- runtime consumers for compiled telemetry, algorithm, monitoring, and command
  plans, including command constraints resolved against the shared parameter
  graph;
- mission- and spacecraft-scoped semantic execution, ordered alarm state,
  durable commits, restart recovery, periodic triggers, and runtime provenance
  pinned to the active revision and plan;
- activation-time qualification reports and governed replay corpora for
  higher-risk revisions; and
- explicit guards that prevent the legacy Derived Telemetry and Limits
  execution paths from competing with an active Mission Model runtime.

XTCE schema validation invokes `xmllint --nonet`; installations that import
XTCE must provide that executable. The checked-in schemas are content-addressed
and schema URLs supplied by imported documents are never fetched.

This implementation does not claim executable support for every XTCE feature.
Unsupported required constructs remain preserved with provenance and produce
target-specific blocking diagnostics. The current telemetry and command
snapshot adapters remain transitional compatibility boundaries until all
catalog producers emit Mission Model declarations directly.

## Context

Cadence imports command and telemetry databases through a layered architecture
and compiles canonical catalog snapshots into narrower runtime definitions.
That direction successfully separates source formats from live execution, but
the current canonical boundary divides one connected mission model into several
independent families:

- telemetry packets, points, types, units, and calibrations;
- command definitions, arguments, constraints, and verifiers;
- Derived Telemetry definitions;
- Limits definitions; and
- alarm projections and operational state.

The separation is convenient for bounded implementation slices, but it obscures
relationships that are part of the command and telemetry database itself:

- a container extracts a raw value for a parameter;
- a calibration converts that raw value into an engineering value;
- an algorithm consumes parameters and produces derived parameters;
- a monitoring policy evaluates parameter values in a context;
- a command constraint or verifier consumes parameters or container events; and
- all of those definitions belong to named systems and subsystems.

The current underdeveloped Limits and Derived Telemetry implementations make
this fragmentation visible. Limits primarily model four numeric thresholds.
Derived Telemetry primarily models one expression and one output point, rejects
stateful functions, and executes outside the catalog compiler. Imported
calibration algorithms and richer catalog constructs may be preserved without
having executable runtime semantics.

Extending each feature independently would create parallel expression
languages, reference mechanisms, lifecycle rules, and runtime evaluators. It
would also make an XTCE importer choose between losing source semantics and
reconstructing XTCE relationships in feature-specific storage after import.

The Object Management Group's
[XML Telemetric and Command Exchange Format (XTCE) 1.3](https://www.omg.org/spec/XTCE/1.3/About-XTCE)
provides a mature semantic vocabulary for many of these relationships. XTCE
models hierarchical `SpaceSystem` namespaces, telemetry and command metadata,
containers, parameter types, calibrations, algorithms, alarms, streams,
services, command constraints, and command verification.

XTCE is nevertheless an interchange schema, not an execution engine. Its XML
shape, implicit defaults, string path references, external algorithm escape
hatches, optional features, and extension points are not suitable as Cadence's
runtime representation.

Cadence therefore needs a compiler-style high-level intermediate
representation that adopts XTCE's useful semantics without making the XTCE XML
object model or any one source format authoritative inside the runtime.

## Decision

Cadence will introduce an immutable, XTCE-informed **Mission Model IR** as its
highest canonical semantic representation of command and telemetry meaning.

XTCE 1.3 is the initial semantic reference and a planned import and export
format. It is not the literal in-memory IR, persistence schema, or runtime
execution model.

The Mission Model IR will unify related declarations in one resolved semantic
graph while preserving separate compiler targets for:

- telemetry decoding;
- calibration and value transformation;
- derived-parameter algorithms;
- monitoring and alarm evaluation;
- command validation and encoding;
- command constraints and verification; and
- stream or framing behavior when Cadence supports it.

The defining distinction is:

```text
Mission Model IR = what telemetry and commands mean
Deployment bindings = where and how that model is active
Runtime records = what happened or is happening now
```

### 1. Compiler Layers

Catalog processing will use these conceptual layers:

```text
source artifacts
    -> format-specific parsed source models
    -> canonical declaration layers
    -> resolved Mission Model IR
    -> target legalization and lowering
    -> immutable runtime plans
```

#### Source Artifact

The uploaded file or bundle is retained verbatim with its content identity,
format, importer version, mission scope, actor, and timestamps.

#### Format-Specific Parsed Source Model

Each importer parses into a typed model that retains source-specific structure,
locations, extensions, explicit values, and diagnostics. An XTCE source model
may closely follow the XTCE schema. A Cadence YAML source model does not need to
pretend to be XML or synthesize an XTCE document.

#### Canonical Declaration Layer

An importer or Cadence authoring workflow emits canonical declarations using
Mission Model concepts. References may still carry source spelling, source
scope, and unresolved target information at this boundary.

Imported declarations and Cadence-authored semantic augmentations are separate,
immutable layers. They do not silently mutate one another.

#### Resolved Mission Model IR

The compiler composes an exact set of declaration layers, builds namespace
symbol tables, resolves references, applies defaults, validates types and
inheritance, and produces one immutable semantic graph.

The resolved graph uses stable internal identities. Source paths remain attached
for provenance and diagnostics, but runtime consumers do not use unvalidated
path strings as identity.

#### Runtime Plans

Target compilers lower the resolved graph into small, executable artifacts.
Runtime plans contain the exact definitions needed by one runtime concern and
pin:

- the effective Mission Model revision;
- all contributing declaration-layer revisions;
- compiler and target contract versions;
- a deterministic content hash; and
- provenance sufficient to explain every compiled definition and diagnostic.

The live and replay runtimes consume runtime plans, not source documents or the
full Mission Model IR.

### 2. `SpaceSystem` Is The Semantic Namespace And Composition Root

The Mission Model IR will contain one or more rooted `SpaceSystem` trees.

A `SpaceSystem`:

- owns a name and stable identity;
- has an optional parent and ordered or named children;
- establishes the lexical scope for declarations;
- may describe an asset group, asset, component, ground system, or another
  semantic grouping;
- owns telemetry, command, algorithm, monitoring, stream, message, and service
  declarations; and
- retains aliases, descriptions, ancillary metadata, provenance, and source
  extension data where available.

Local, relative, and absolute source references resolve through the
`SpaceSystem` tree. Every reference records an expected symbol kind so a
parameter reference cannot accidentally resolve to a container, type, command,
or algorithm with the same spelling.

Conceptually:

```elixir
%SymbolRef{
  source_system_id: binary(),
  expected_kind: :parameter | :type | :container | :algorithm | :command,
  original_spelling: binary(),
  resolved_id: binary() | nil,
  provenance: map()
}
```

The exact Elixir structs may differ, but these semantics are required.

`SpaceSystem` nesting is not inheritance. Type, container, and command
inheritance remain explicit semantic relationships with their own validation
and lowering rules.

A source file boundary is also not a `SpaceSystem` boundary. Several files may
compose one system tree, and one file may declare multiple child systems.

### 3. `SpaceSystem` Is Not Deployment Inventory

The Mission Model describes reusable meaning. It does not own the operational
spacecraft inventory, onboard-node inventory, source endpoints, routes,
transports, contacts, credentials, or active runtime state.

Cadence may later bind a deployed spacecraft or onboard processing node to a
specific `SpaceSystem` and effective Mission Model revision. That binding is a
management-plane deployment artifact outside this IR.

This separation permits:

- one generic bus or payload model to be reused by several spacecraft;
- one spacecraft to bind different catalog systems or revisions to different
  onboard computers;
- redundant computers to share semantic definitions;
- telemetry forwarded through another computer to retain its semantic origin;
  and
- transport routing to change without rewriting the command and telemetry
  model.

This ADR establishes the semantic binding boundary but does not decide or
authorize a spacecraft-composition UI.

### 4. Parameters Are The Common Semantic Currency

The Mission Model will treat a parameter as a typed declaration whose updates
may have different producers and common consumers.

```text
container entry -> decode -> calibrate ---------+
algorithm inputs -> algorithm output -----------+-> parameter update
constant, local, ground, or command effect ------+

parameter update -> algorithm input
                 -> monitoring policy
                 -> command constraint or verifier
                 -> archive or current-value projection
                 -> operator display
```

A parameter declaration will preserve at least:

- stable identity and owning `SpaceSystem`;
- type and unit relationships;
- source classification such as telemetered, derived, constant, local, or
  ground;
- producer relationships where known;
- validity, time association, persistence, or quality metadata when modeled;
- aliases, descriptions, provenance, and source extensions; and
- explicit consumers through resolved graph edges.

The IR distinguishes parameter definitions from parameter update records. A
definition belongs to a versioned model. A value, quality transition, or alarm
occurrence is runtime evidence.

### 5. Derived Telemetry Becomes Parameter Production By Algorithms

Derived telemetry will no longer be a semantically independent definition
family with a parallel point namespace.

A derived parameter is an ordinary parameter whose update producer is an
algorithm output. Algorithms will support a typed semantic contract containing:

- zero or more typed parameter or argument inputs;
- one or more parameter outputs;
- trigger definitions, including parameter updates, container updates,
  periodic triggers, or explicitly supported Cadence triggers;
- an implementation such as a typed math AST or a registered implementation
  reference;
- explicit state, timing, windowing, alignment, missing-input, and quality
  propagation semantics when required; and
- provenance and source extensions.

Stateful behavior must be represented explicitly. It must not be inferred only
from function names such as `rate`, `delta`, or `rolling_average`.

Imported external or custom algorithms are preserved, but import never grants
authority to execute arbitrary code. Such an algorithm is executable only when
a separately registered, versioned, and allowed Cadence implementation can
legalize it for the selected target.

The existing Derived Telemetry product application may remain an authoring,
activation, and observability workflow. Its saved definitions will become a
semantic augmentation layer that contributes parameter and algorithm
declarations to the effective Mission Model.

The current `Cadence.DerivedTelemetry.Definition` API, one-output expression
shape, evaluator, and persistence schema are transitional. They may be replaced
rather than preserved through compatibility adapters indefinitely.

### 6. Limits And Alarms Become Monitoring Semantics

Cadence will use **monitoring policy** as the semantic umbrella for limits,
alarm conditions, persistence, context, and severity.

The terms have distinct meanings:

- a **limit** is a numeric range, boundary, or change condition;
- a **monitoring rule** evaluates a parameter value or value transition;
- an **alarm policy** maps monitoring results and context to defined severity
  and persistence behavior; and
- an **alarm occurrence or state** is a runtime result and evidence record.

A monitoring policy may contain:

- a default rule set;
- ordered contextual rule sets with typed match criteria;
- numeric static ranges and change or rate rules;
- enumerated, string, boolean, binary, or time predicates where supported;
- open, closed, disjoint, or multi-range boundaries;
- severity levels and normal-state semantics;
- minimum-violation and minimum-conformance counts;
- disabled or suspended behavior;
- explicit missing, stale, invalid, and quality handling;
- references to registered custom evaluators where allowed; and
- provenance and source extensions.

Simple Cadence red/yellow low/high thresholds are syntax sugar for a basic
monitoring policy. They are not a separate architectural family.

Monitoring definitions may be imported from XTCE or contributed by a
Cadence-authored semantic augmentation layer. They compile into the same
monitoring runtime plan. The compiler must report conflicts rather than allow an
augmentation to silently replace an imported policy.

The existing Limits product application may remain an operator-facing authoring
and observability workflow. The current `Cadence.Limits.Definition`, four-
threshold evaluator, storage schema, and API are transitional and may be
replaced.

Alarm read models remain projections over runtime monitoring results. They are
not the authoritative definition store.

### 7. Calibration And Value Transformation Remain Explicit

Calibration is semantically adjacent to algorithms but remains an explicit
value-transformation concept because it participates in type and encoding
interpretation for each raw value.

The Mission Model will preserve:

- polynomial, spline or interpolation, enumeration, and math transforms;
- contextual calibrator selection;
- raw and calibrated validity ranges;
- units and output types; and
- registered custom transformations where allowed.

Target compilers must state whether a transform is executable, preserved but
unsupported, or lossy. Preserving a calibration definition in a catalog does
not count as runtime calibration support.

### 8. Telemetry And Commands Share A Graph But Lower Separately

Telemetry and command declarations remain distinct typed families within the
Mission Model. They are not collapsed into one universal definition type.

They share:

- `SpaceSystem` ownership and symbol resolution;
- stable identity, provenance, aliases, and extensions;
- typed match and boolean criteria where semantics align;
- parameter references;
- algorithms and event relationships where appropriate; and
- one effective model revision and diagnostic basis.

They retain separate runtime lowering because decoding telemetry and validating,
encoding, releasing, and verifying commands have different safety and execution
semantics.

Command constraints and verifiers that reference telemetry resolve directly to
the same parameter, container, or algorithm identities used by telemetry
lowering. They do not use a second telemetry-point namespace or unchecked string
references.

The Mission Model may preserve richer XTCE concepts such as command inheritance,
block commands, interlocks, contextual significance, parameter-setting effects,
alarm suspension, and multi-stage verification before every concept has a
Cadence runtime implementation.

### 9. Imported And Authored Definitions Compose As Immutable Layers

Unifying semantics does not require one mutable catalog document or one
authoring workflow.

An effective Mission Model revision is the deterministic composition of:

```text
one or more imported declaration layers
    + zero or more governed semantic augmentation layers
    = one resolved effective Mission Model revision
```

Each layer is immutable and attributable. Composition records exact layer
versions and content identities.

Augmentations may add definitions or explicitly extend supported definitions.
Replacement or override behavior must be typed, explicit, and diagnosed.
Ordering alone must not silently decide which duplicate definition wins.

Composition must detect at least:

- duplicate identities or qualified names;
- incompatible type changes;
- dangling or wrong-kind references;
- inheritance and algorithm cycles;
- ambiguous producers;
- incompatible monitoring policies;
- unsupported custom implementations; and
- source or augmentation revision drift.

This permits simple operator workflows for limits and derived telemetry while
retaining one semantic compiler and one effective graph.

### 10. Target Legalization Is Explicit

Representation in the Mission Model does not imply executable support in every
runtime target.

Each target compiler declares a versioned capability contract and emits
structured diagnostics for constructs that are:

- supported and lowered exactly;
- supported with an identified transformation;
- preserved but not executable;
- lossy; or
- invalid for that target.

Diagnostics include source provenance, semantic identity, compiler stage,
target, severity, and a stable diagnostic code.

Activation policy decides whether diagnostics block a runtime plan. Required
behavior must fail closed. Optional or unused declarations may remain preserved
without preventing unrelated supported definitions from compiling when the
activation contract permits partial lowering.

Compiler support must not be inferred from the presence of a field in a
canonical struct. A feature counts as supported only when its intended target
can validate, lower, execute, and test it.

### 11. Plane Ownership Remains Explicit

This decision follows
[ADR-015](015-management-control-data-plane-architecture.md):

- the management plane owns artifact import, semantic authoring, immutable
  layers, revision history, diagnostics, approval, and activation intent;
- the control plane selects an exact effective Mission Model revision, compiles
  or resolves its approved runtime plans, binds them to operational scope, and
  reconciles active generations; and
- the data plane executes exact telemetry, algorithm, monitoring, command, and
  stream plans and reports observations.

Runtime observations never silently rewrite the Mission Model or an authored
augmentation.

Product applications from ADR-016 may own bounded authoring and operational
workflows without owning a competing semantic namespace or bypassing these
plane boundaries.

### 12. Provenance And Export

Every declaration and resolved edge retains provenance sufficient to answer:

- which source artifact or authored layer introduced it;
- which source object and location produced it;
- which importer and compiler versions transformed it;
- which defaults or normalization rules were applied;
- which diagnostics or losses occurred; and
- which runtime plans include it.

The preserved source artifact is authoritative for byte-exact reproduction of
the input.

An XTCE exporter may produce a semantically equivalent XTCE document from the
effective Mission Model where the model is representable. Cadence does not
promise syntactic round-trip identity, preservation of XML formatting, or an
XTCE representation for Cadence-only operational concerns.

## Required Compiler Passes

The implementation may combine passes internally, but it must preserve the
following observable responsibilities:

1. parse and source-schema validation;
2. declaration normalization with provenance;
3. deterministic layer composition;
4. `SpaceSystem` and symbol-table construction;
5. typed reference resolution;
6. default application and inheritance validation;
7. type, unit, layout, criteria, algorithm, and monitoring validation;
8. cycle and producer-consumer graph analysis;
9. target capability legalization;
10. target-specific lowering and optimization; and
11. immutable runtime-plan emission with structured diagnostics.

Compiler output must be deterministic for the same source identities, layer
versions, compiler version, and target contract.

## Impact On Current Cadence Models

The current `Cadence.Catalog.Bundle`, telemetry snapshot, and command snapshot
may remain as transitional importer outputs or compatibility views while the
Mission Model is introduced. They will not remain the authoritative top-level
semantic boundary after migration.

Current runtime packet and command definitions remain valid examples of lowered
runtime artifacts. They should evolve through versioned compiler targets rather
than absorbing the entire Mission Model.

Current Derived Telemetry and Limits definitions, persistence, actions, and
evaluators are explicitly not compatibility constraints. Migration should favor
the clean target model over dual-writing or permanently translating between two
semantic systems.

Separate operator-facing applications may remain useful for focused workflows:

- Telemetry Decom for inspecting and operating telemetry decoding;
- Derived Telemetry for authoring and observing algorithm-derived parameters;
- Limits or Monitoring for authoring monitoring policy; and
- Alarms for observing and acknowledging runtime alarm state.

Those surfaces consume or contribute to the shared Mission Model and its
runtime plans. Their UI separation does not imply semantic separation.

## Explicit Non-Goals

This ADR does not require Cadence to:

- implement every XTCE 1.3 feature before introducing the Mission Model;
- use XTCE XML as the internal object graph or persistence schema;
- synthesize XTCE as an intermediate file when importing another format;
- execute arbitrary source-supplied code or external algorithms;
- make the full Mission Model available on the data-plane hot path;
- merge telemetry and command runtime engines;
- move deployment inventory, routing, transports, contacts, credentials, or
  authorization into the catalog model;
- build a spacecraft-composition or Mission Model editing UI in the first
  implementation slice;
- preserve the existing Derived Telemetry or Limits APIs and storage shapes;
- guarantee syntactic round trips for XTCE or any other format; or
- treat unsupported but preserved source constructs as implemented features.

## Consequences

### Positive

- Cadence gains one semantic reference graph for telemetry, commanding,
  algorithms, monitoring, and their cross-references.
- XTCE import can preserve substantially more meaning without coupling runtime
  code to XML.
- Derived telemetry becomes an ordinary parameter-production path rather than a
  parallel telemetry universe.
- Limits and alarms become progressively richer forms of one monitoring model.
- Command constraints and verifiers can resolve against the same telemetry
  identities used by decoding and monitoring.
- `SpaceSystem` namespaces permit local names, reusable subsystem models, and
  multi-computer spacecraft catalogs without mission-wide naming conventions.
- Imported and operator-authored definitions share validation and runtime
  compilation without sharing one mutable authoring document.
- Runtime support and import fidelity become separately measurable.
- Explicit legalization diagnostics make partial implementation safe and
  visible.

### Negative

- The canonical catalog becomes a graph with symbol resolution, not a pair of
  simple aggregate snapshots.
- Cadence needs compiler infrastructure, model versioning, deterministic layer
  composition, and target capability contracts.
- Existing Derived Telemetry and Limits code will likely be replaced rather
  than incrementally extended.
- Richer algorithms and monitoring require explicit time, state, quality, and
  missing-data semantics.
- Cross-family validation makes catalog activation more rigorous and potentially
  more expensive.
- Supporting both semantic preservation and exact runtime claims requires a
  larger diagnostic and test matrix.

## Alternatives Considered

### Use The Literal XTCE XML Object Model As The IR

Rejected. It would make XML structure, string paths, implicit defaults, and
extension mechanics leak throughout Cadence. It would also force non-XTCE
formats through an unnecessary XML-shaped representation.

### Keep Separate Telemetry, Command, Derived, Limits, And Alarm Models

Rejected as the target architecture. Separate runtime and product surfaces are
useful, but separate semantic models duplicate identity, references,
expressions, context, provenance, and compilation rules.

### Normalize Directly Into Current Runtime Definitions

Rejected. Current decoder, encoder, derived-expression, and limit structures are
intentionally narrow. Treating them as canonical would lose source semantics
and make future runtime improvements require re-importing or reinterpreting
source artifacts.

### Make XTCE The Only Supported Authoring Format

Rejected. Cadence must continue to accept simpler formats and focused product
workflows. XTCE supplies a semantic reference and exchange target, not a
mandatory authoring experience.

### Wait For Complete XTCE Runtime Support

Rejected. The Mission Model can preserve and diagnose a construct before every
runtime target can execute it. Versioned legalization provides an incremental
path without overstating support.

## Implementation Sequence

Implementation should proceed in bounded, testable slices:

1. define Mission Model identity, revision, `SpaceSystem`, declaration, symbol
   reference, provenance, and diagnostic contracts in `cadence_catalog`;
2. introduce adapters that project current telemetry and command snapshots into
   a minimal Mission Model without changing active runtime behavior;
3. implement deterministic namespace construction, reference resolution, and
   runtime target capability diagnostics;
4. define parameter producer-consumer edges and typed algorithm contracts using
   representative XTCE fixtures;
5. replace the current Derived Telemetry definition family with governed
   parameter-and-algorithm augmentation layers and compiled execution plans;
6. define monitoring policy and replace the current Limits definition family
   and evaluator with monitoring augmentations and compiled plans;
7. resolve command constraints and verifiers against the shared semantic graph;
8. add an XTCE frontend with conformance fixtures covering hierarchy,
   references, containers, algorithms, monitoring, and commands;
9. add semantic XTCE export for the representable subset; and
10. remove transitional canonical-family adapters after all active consumers use
    Mission Model revisions or compiled runtime plans.

Each slice must retain current runtime behavior until its replacement path is
activated and verified. No slice should require a flag day across every runtime
target.

## Validation Expectations

The architecture is demonstrated when tests prove that:

- the same effective inputs compile deterministically;
- local, relative, and absolute `SpaceSystem` references resolve correctly;
- wrong-kind and dangling references produce stable diagnostics;
- imported and authored layers compose without silent overwrite;
- inheritance and algorithm cycles fail validation;
- a telemetered and a derived parameter are interchangeable to downstream
  monitoring and verifier consumers after production;
- simple red/yellow limits lower as a valid subset of monitoring policy;
- unsupported XTCE constructs remain queryable with provenance and cannot be
  activated accidentally;
- telemetry, algorithm, monitoring, and command plans pin the same effective
  Mission Model revision; and
- live and replay execution produce equivalent semantic results for the same
  ordered inputs and runtime-plan basis.

## See Also

- [ADR-008: Multi-Format Catalog Import Architecture](008-multi-format-catalog-import-architecture.md)
- [ADR-009: Canonical Telemetry Catalog Model](009-canonical-telemetry-catalog-model.md)
- [ADR-010: Canonical Command Catalog Model](010-canonical-command-catalog-model.md)
- [ADR-015: Management Plane, Control Plane, and Data Plane Architecture](015-management-control-data-plane-architecture.md)
- [ADR-016: Typed Extension Packages and Product Applications](016-typed-extension-packages-and-product-applications.md)
- [ADR-019: Telemetry Data-Plane Persistence and Projection Topology](019-telemetry-data-plane-persistence-and-projection-topology.md)
- [OMG XTCE 1.3](https://www.omg.org/spec/XTCE/1.3/About-XTCE)
- [XTCE 1.3 normative schema](https://www.omg.org/spec/XTCE/20250214/SpaceSystem.xsd)
