---
title: "ADR-010: Canonical Command Catalog Model"
aliases: [command catalog, canonical command model, mdb command model]
tags: [adr, architecture, commanding, catalog, import]
status: superseded
created: 2026-03-30
updated: 2026-03-30
---

# ADR-010: Canonical Command Catalog Model

## Status

Superseded by
[ADR-020](020-xtce-informed-mission-model-intermediate-representation.md).
The separate canonical command snapshot described below has been removed;
commanding is now a declaration family in the resolved Mission Model IR.

## Context

ADR-008 established the layered catalog import architecture:

1. source artifact
2. format-specific parsed model
3. canonical operational catalog
4. provenance and extensions

ADR-009 then defined the canonical telemetry catalog model.

Cadence now needs the equivalent command-side model so command import can fit
the same substrate without collapsing commanding into:

- telemetry structures
- source-format-specific parsed models
- runtime request or queue state

The command-side model must also support the common case where one uploaded
mission database contains both commands and telemetry. A single source artifact
and import run may therefore produce both command and telemetry canonical
snapshots.

Legacy Cadence's `c2_database_model_v2` contains useful command concepts:

- immutable versioned definition snapshots
- `MetaCommand` inheritance and abstraction
- explicit `Argument` definitions
- `TransmissionConstraint`
- multi-stage `CommandVerifier`
- operational significance and safety metadata

But the legacy document also leaned toward a large universal MDB that mixed
catalog structure, runtime behavior, and source-specific richness into one
model. That is not the direction of the new system.

The new runtime has different boundaries:

- imported command catalogs are mission-scoped and versioned
- command request, approval, release, and uplink runtime are separate concerns
- contacts, paths, transports, and `COP-1` are separate runtime layers
- live runtime should compile from canonical command definitions into narrower
  governed runtime artifacts

The canonical command catalog must fit those boundaries.

## Decision

Cadence will use a **canonical command catalog** that is richer than a future
runtime encoder slice, but narrower than a universal round-trip MDB.

The canonical command catalog is mission-scoped, versioned, immutable per
snapshot, and built from catalog import runs. It contains the operational
command concepts Cadence needs across supported source formats:

- command catalog snapshot
- command definition
- command argument type
- command argument
- command encoding layout
- command transmission constraint
- command verifier
- command operational metadata
- provenance and extension documents

One source artifact or import run may therefore yield a command catalog snapshot
alongside a telemetry catalog snapshot. The command canonical model is separate,
but it is not required to come from a command-only upload.

Telemetry and command catalogs remain separate canonical families. They share
import infrastructure, but they do not collapse into one combined catalog
schema.

Live runtime does not consume imported source formats directly and does not need
the full canonical command catalog on its hot path. Instead, Cadence compiles
the canonical command catalog into narrower governed runtime artifacts such as:

- command encoding definitions
- validator and constraint inputs
- verifier plans
- uplink-facing operational bindings

## Model

### 1. CommandCatalogSnapshot

The root immutable version of one imported command catalog.

It records:

- organization and mission scope
- source artifact reference
- source format and importer key
- content hash and import run reference
- published or superseded lifecycle fields
- snapshot-level provenance and extension data

This is the command-side sibling of `TelemetryCatalogSnapshot`.

Multiple catalog-family snapshots may share the same source artifact and import
run when the uploaded source format contains both commanding and telemetry.

### 2. CommandDefinition

The canonical command definition is the successor to the legacy `MetaCommand`
idea.

It includes:

- stable command ID and name
- abstract versus concrete flag
- inheritance or base-command reference
- display name and operator-facing description
- significance and safety metadata
- packet or service identification hints when present
- encoding layout reference
- default argument assignments and fixed values when present
- provenance and extension data

The canonical model must support reusable abstract command templates and derived
concrete commands without forcing every source format into one inheritance
strategy.

### 3. CommandArgumentType

Cadence will model command argument types explicitly instead of reusing
`TelemetryType`.

This keeps command semantics separate even when the underlying scalar type
families overlap. The canonical command argument type model should include the
common operational subset needed across source formats:

- integer, float, boolean, string, binary
- enumerated types
- aggregate and array argument types where operationally meaningful
- encoding metadata needed for packing
- unit or display metadata when present

Format-specific type richness that does not fit the canonical subset remains in
provenance or extension documents.

### 4. CommandArgument

Arguments are independent definitions referenced by command layouts and command
definitions.

They include:

- stable argument ID and name
- argument type reference
- required versus optional semantics
- default value when present
- fixed assignment or inherited-assignment metadata
- display ordering metadata
- safety or hazardous-value metadata when present
- provenance and extension data

The canonical command catalog should preserve argument identity and meaning
independently from any one binary layout.

### 5. CommandEncodingLayout

Cadence will keep a first-class canonical model for how a command is encoded
for uplink.

This includes:

- layout ID and layout kind
- argument placement and ordering
- fixed header or trailer fields
- byte or bit ordering rules
- packet or service opcode fields when present
- checksum or trailer metadata when operationally meaningful
- nesting or inheritance overlays when present
- provenance and extension data

This is where source-format-specific command containers or command packet
structures normalize into a stable operational model.

`CommandEncodingLayout` describes the command binary itself. It does not own
contact, path, provider, or transport runtime configuration.

### 6. CommandTransmissionConstraint

Cadence will model imported command preconditions explicitly.

These include operational checks such as:

- spacecraft mode requirements
- telemetry-state requirements
- timing or environment constraints when present in source material
- command interlock or sequencing requirements when representable

The canonical representation should favor a typed condition AST or structured
constraint form, not only raw boolean-expression strings.

Where a constraint references telemetry, it should resolve to canonical
telemetry point IDs when possible. Unresolved source references must remain in
provenance or importer diagnostics.

### 7. CommandVerifier

Cadence will keep a first-class canonical model for command verification.

It includes:

- verifier ID and stage or phase
- success, failure, and timeout criteria
- timing windows or delay metadata
- telemetry or event references used for verification
- optional severity or operator significance metadata
- provenance and extension data

The canonical model should support multi-stage verification instead of reducing
all verification to one flat post-send check.

Verifier definitions remain catalog data. Runtime verifier execution, retries,
and operator workflow remain separate command-plane concerns.

### 8. CommandOperationalMetadata

Cadence will preserve operationally meaningful command metadata that affects how
operators reason about release and execution, such as:

- significance
- critical or hazardous flags
- subsystem or display grouping
- preferred uplink service hints
- release or verification policy hints from source material

This metadata is part of the canonical command catalog when it is stable and
operator-facing.

Policy enforcement itself is not stored in the catalog. Approval rules and
authorization remain governed runtime concerns.

### 9. Provenance And Extensions

Every canonical command definition must retain:

- source artifact reference
- importer key and import run reference
- source object reference within the imported artifact
- importer warnings and lossy-conversion notes
- extension data for source-specific attributes

Cadence should preserve source richness without forcing every source attribute
into the canonical operational schema.

## Explicit Non-Goals

The canonical command catalog will not:

- become a universal round-trip schema for every possible source format
- absorb telemetry catalog semantics into command definitions
- own command request, approval, release, or queue state
- own live contact, link, transport, or `COP-1` runtime configuration
- encode automation or procedure logic as part of command definitions
- execute custom importer-defined code as part of the catalog model

## Relationship To Telemetry Catalog

Telemetry and command catalogs are separate canonical families because they have
different runtime semantics.

They may still relate to each other:

- command constraints may reference canonical telemetry points
- command verifiers may reference canonical telemetry points or events
- shared source formats may produce both telemetry and command snapshots from
  the same source artifact family

These relationships should be explicit references, not a merged universal
catalog schema.

## Relationship To Command Execution

The canonical command catalog is the imported source of truth for command
definitions, but it is not the runtime command execution model.

Cadence should compile from canonical command catalog snapshots into narrower
runtime-facing governed artifacts, including:

- command encoders
- argument validators
- transmission-constraint evaluators
- verifier plans
- uplink-facing operational bindings

This keeps the live runtime and replay runtime narrow while still allowing rich
multi-format command import support.

## Relationship To Approval And Uplink Runtime

Approval policy, request lifecycle, release authority, uplink path selection,
transport behavior, and `COP-1` remain outside the canonical command catalog.

Those concerns consume compiled command artifacts, but they are not part of the
catalog model itself.

## Consequences

This decision gives Cadence a stable command-side import target that:

- fits the shared catalog import substrate from ADR-008
- stays parallel to ADR-009 without over-unifying telemetry and commanding
- preserves important source richness through provenance and extensions
- supports future multi-format import work such as XTCE or dev formats
- provides the right foundation for the later command request and uplink API

The next step is to define the Elixir domain structs for this canonical command
catalog and only then pick the first dev or real command format to import.
