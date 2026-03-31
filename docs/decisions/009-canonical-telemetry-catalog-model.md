---
title: "ADR-009: Canonical Telemetry Catalog Model"
aliases: [telemetry catalog, canonical telemetry model, mdb telemetry model]
tags: [adr, architecture, telemetry, catalog, import]
status: accepted
created: 2026-03-29
updated: 2026-03-29
---

# ADR-009: Canonical Telemetry Catalog Model

## Status

Accepted

## Context

ADR-008 established the layered catalog import architecture:

1. source artifact
2. format-specific parsed model
3. canonical operational catalog
4. provenance and extensions

Cadence now has the shared artifact/import-run substrate, but it still needs a
stable canonical telemetry model before implementing the first real importer.
That importer substrate must support the common case where one uploaded mission
database yields both telemetry and command definitions under the same import
run.

Legacy Cadence's `c2_database_model_v2` contains useful concepts:

- immutable versioned definition snapshots
- reusable shared types
- explicit packet/container versus parameter separation
- reusable match criteria
- units and calibration algorithms

But the legacy document also aimed for a single universal internal schema that
could round-trip every source format completely. That is not the direction of
the new system.

The new runtime has different boundaries:

- live runtime consumes governed runtime-facing definitions
- derived telemetry and limits are already modeled as separate governed families
- contact/link/transport runtime is separate from catalog import

The canonical telemetry catalog must fit those boundaries.

## Decision

Cadence will use a **canonical telemetry catalog** that is richer than the
current `PacketDefinition` slice, but narrower than the legacy universal MDB.

The canonical telemetry catalog is mission-scoped, versioned, immutable per
snapshot, and built from catalog import runs. It contains the operational
telemetry concepts Cadence needs across supported source formats:

- telemetry catalog snapshot
- telemetry packet
- telemetry packet entry
- telemetry point
- telemetry type
- telemetry unit
- telemetry calibration algorithm
- telemetry match criteria
- provenance and extension documents

One source artifact or import run may therefore yield a telemetry catalog
snapshot alongside a command catalog snapshot. The telemetry canonical model is
separate, but it is not required to come from a telemetry-only upload.

Derived telemetry and limits are **not** stored as embedded parts of the
canonical telemetry catalog. They remain separate governed families that may be
imported from source material and reference canonical telemetry point IDs.

Live runtime does not consume imported source formats directly and does not need
the full canonical telemetry catalog on its hot path. Instead, Cadence compiles
the canonical telemetry catalog into narrower governed runtime artifacts such as
packet definitions, selectors, and capability configuration inputs.

## Model

### 1. TelemetryCatalogSnapshot

The root immutable version of one imported telemetry catalog.

It records:

- organization and mission scope
- source artifact reference
- source format and importer key
- content hash and import run reference
- published or superseded lifecycle fields
- snapshot-level provenance and extension data

This is the successor to the legacy `DefinitionSet` idea, but scoped to the
telemetry catalog family rather than a monolithic combined MDB.

Multiple catalog-family snapshots may share the same source artifact and import
run when the uploaded source format contains both telemetry and commanding.

### 2. TelemetryType

Reusable type definition referenced by telemetry points.

The canonical type model should include only the common operational subset
needed across supported formats:

- scalar categories such as integer, float, boolean, string, binary
- enumerated types
- aggregate or structured types
- array types
- time-related types
- raw encoding information needed to interpret packet data

Format-specific type features that do not fit the canonical subset remain in
provenance or extension documents.

### 3. TelemetryUnit

Explicit engineering-unit definitions are part of the canonical telemetry
catalog.

Units are worth modeling directly because they are operationally meaningful for
display, conversion, validation, and import fidelity.

### 4. TelemetryCalibrationAlgorithm

Cadence will keep a first-class model for imported calibration or conversion
algorithms, but only for algorithm families that are stable and operationally
meaningful in the platform, such as:

- polynomial
- spline or table interpolation
- discrete state mapping
- math-expression based conversion

The canonical model should not assume mission-supplied executable code in the
catalog. Source formats that support custom code keep those details in
extensions or provenance unless Cadence later defines a safe first-party model
for them.

### 5. TelemetryPoint

The canonical telemetry point definition is independent of packet layout.

It includes:

- stable point ID and name
- display metadata and significance
- type reference
- unit reference
- persistence and stale-data hints when present in source material
- provenance and extension data

This is the successor to the legacy `Parameter` idea.

### 6. TelemetryPacket

The canonical telemetry packet definition describes how a packet is identified
and how packet entries are assembled into telemetry points.

It includes:

- stable packet ID and name
- abstract versus concrete packet/container flag
- inheritance or base-packet reference
- packet identification hints such as APID and packet type
- packet-level match criteria for identification
- packet-level byte order and sizing metadata
- provenance and extension data

This is the successor to the legacy `Container` idea.

### 7. TelemetryPacketEntry

Packet entries describe how a telemetry packet references telemetry points or
other nested packet structures.

It includes:

- entry kind
- position and offset semantics
- referenced point or nested packet
- fixed values when relevant
- inclusion conditions
- display ordering metadata

This is the successor to the legacy `ContainerEntry` idea.

### 8. TelemetryMatchCriteria

Cadence will keep a reusable canonical condition model for telemetry import.

It is used for:

- packet identification
- conditional packet entries
- imported context-sensitive telemetry behavior that later compiles into other
  governed artifacts

The canonical representation should favor a typed condition AST, not only raw
boolean-expression strings.

### 9. Provenance and Extensions

Every canonical telemetry definition must retain:

- source artifact reference
- importer key and import run reference
- source object reference within the imported artifact
- importer warnings and lossy-conversion notes
- extension data for source-specific attributes

Cadence should preserve source richness without forcing every source attribute
into the canonical operational schema.

## Explicit Non-Goals

The canonical telemetry catalog will not:

- become a universal round-trip schema for every possible source format
- absorb command catalog semantics
- absorb derived telemetry or limit definitions as embedded catalog fields
- own live contact, link, or transport runtime configuration
- execute custom importer-defined code as part of the catalog model

## Relationship To Current Runtime

The current `Cadence.Telemetry.PacketDefinition` and
`Cadence.Telemetry.FieldDefinition` model is a valid early runtime slice, but it
is intentionally narrower than the canonical telemetry catalog.

The canonical telemetry catalog should become the richer imported source of
truth. Cadence will then compile from canonical telemetry catalog snapshots into
runtime-facing governed artifacts, including:

- definition-bound packet definitions
- selectors or identification rules
- capability configuration inputs

This keeps the live runtime and replay runtime narrow while still allowing rich
multi-format import support.

## Relationship To Derived Telemetry And Limits

Imported derived telemetry definitions and imported limit definitions should be
handled as separate governed families that reference canonical telemetry point
IDs.

The legacy model placed derivation and alarms close to the parameter or type
layer. Cadence will not embed them there in the new architecture. They are
closer to governed processing policy than to the stable base telemetry catalog.

## Relationship To Stream And Framing Definitions

Legacy `Stream` concepts are still useful as imported source vocabulary, but
they are not the owner of live runtime transport behavior in the new system.

Cadence may retain imported framing or protocol hints in:

- catalog provenance
- extension documents
- compiler hints used to produce runtime selectors or protocol bindings

But live contact, link, and transport runtime configuration remains governed by
the runtime models from ADR-006.

## Consequences

### Positive

- preserves the best structural ideas from the legacy MDB design
- keeps telemetry import rich enough for XTCE-like formats
- avoids flattening all source formats into one universal schema
- keeps live runtime artifacts narrower and easier to govern
- cleanly separates imported base telemetry catalog from derived and limit policy

### Negative

- requires a compiler step from canonical telemetry catalog to runtime artifacts
- introduces another model layer between source format and runtime
- makes import implementation more structured than direct packet-definition
  creation

## Initial Implementation Scope

The first implementation of the canonical telemetry catalog should cover:

- snapshot root
- telemetry packets and packet entries
- telemetry points
- telemetry types
- units
- calibration algorithms
- match criteria
- provenance and extension documents

Cadence does not need full parity with every feature in the legacy `MDB v2`
document before implementing the first real telemetry importer.

## Follow-On Work

- define the concrete Elixir domain structs for the canonical telemetry catalog
- decide which current `PacketDefinition` paths become compiler outputs
- implement the first real telemetry importer against this model
- define how imported derived telemetry and limits map into their existing
  governed families
