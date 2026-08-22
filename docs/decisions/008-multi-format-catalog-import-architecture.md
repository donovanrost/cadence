---
title: "ADR-008: Multi-Format Catalog Import Architecture"
aliases: [catalog import, c&t import, telemetry import, command import]
tags: [adr, architecture, telemetry, commands, catalog, import]
status: accepted
created: 2026-03-29
updated: 2026-03-29
---

# ADR-008: Multi-Format Catalog Import Architecture

## Status

Accepted

## Context

Cadence must support a variety of command and telemetry database formats.

Legacy Cadence attempted to normalize all source formats into one internal
model. That direction was useful in intent, but it creates two recurring risks:

- lowest-common-denominator normalization that loses important source detail
- runtime code becoming implicitly coupled to importer-specific assumptions

Cadence now has a governed runtime, governed activation, and a clearer mission
control plane. Catalog import should fit that model instead of becoming a
separate ad hoc subsystem.

The system also needs to preserve:

- original uploaded source artifacts
- importer diagnostics and lossiness
- provenance from canonical runtime definitions back to source material
- the ability to support telemetry and command catalogs without forcing them
  into one universal operational schema

## Decision

Cadence will use a layered catalog import model:

1. source artifact
2. format-specific parsed model
3. canonical operational catalog
4. provenance and extensions

Telemetry and command catalogs will share import infrastructure, but they will
remain separate canonical operational models.

Cadence must also support the common case where a single uploaded command and
telemetry database contains both families. One source artifact and one import
run may therefore produce:

- telemetry catalog outputs
- command catalog outputs
- or both

The separation is between **canonical catalog families**, not between uploaded
files or importer executions.

## Details

### 1. Source Artifacts Are Preserved Verbatim

Cadence will preserve the uploaded source artifact or artifact bundle as the
authoritative imported input.

Source artifacts must record at least:

- organization and mission scope
- importer format
- importer version
- artifact version and timestamps
- upload actor or service identity
- immutable content reference

Cadence should not discard the original format after import.

### 2. Importers Produce Format-Specific Parsed Models

Each supported source format gets a first-party importer family that parses the
source artifact into a typed format-specific model.

Cadence should not require one universal raw parse structure that fully
represents every source format.

The parsed model layer exists so Cadence can:

- keep importer logic format-aware
- retain format-specific structure during validation
- expose meaningful diagnostics
- support richer provenance than a flattened canonical schema alone

### 3. Canonical Operational Catalogs Are Runtime-Facing

Cadence will derive canonical operational definitions from the parsed model.

There are at least two canonical catalog families:

- canonical telemetry catalog
- canonical command catalog

These are separate models because telemetry and commanding have different
runtime semantics.

The canonical telemetry catalog should include the runtime-facing subset needed
for:

- packet definitions
- point definitions
- data types
- engineering unit and display metadata
- derived telemetry and limit binding references

The canonical command catalog should include the runtime-facing subset needed
for:

- command definitions
- argument schemas
- constraints and validation metadata
- command verification hooks or references
- uplink-facing operational metadata

One parsed source model may emit both canonical telemetry and canonical command
catalog outputs when the underlying source format is a combined command and
telemetry database.

### 4. Provenance And Extensions Are First-Class

Every canonical definition derived from an imported source should retain:

- source artifact reference
- source object identifier within that artifact
- importer warnings and lossy-conversion notes
- unmapped or format-specific extension data where needed

Cadence should not force every source attribute into the canonical operational
schema.

Instead:

- operationally meaningful common fields go into the canonical model
- source-specific extras remain in provenance or extension documents

### 5. Shared Import Infrastructure

Telemetry and command catalogs share these platform concerns:

- artifact storage and versioning
- importer registry
- parser and normalization lifecycle
- importer diagnostics
- governance and activation integration
- audit and attribution

Cadence should implement those concerns once and reuse them across telemetry and
command import.

This shared infrastructure must support importers that emit multiple catalog
families from one source artifact. For example, one XTCE or mission database
upload may produce a telemetry snapshot and a command snapshot under the same
import run and provenance basis.

### 6. Import Diagnostics Are Product Surface, Not Debug Leftovers

Every import run should surface structured diagnostics, including:

- fatal errors
- warnings
- lossy mappings
- unsupported source features
- summary counts

Operators need to know whether an imported catalog is safe to activate, not
just whether parsing succeeded.

### 7. Runtime Never Reads Source Formats Directly

The live runtime and replay runtime consume canonical operational catalogs, not
raw importer-specific parsed formats.

This keeps runtime behavior stable even as new source formats are added.

### 8. Initial Scope

Release-one implementation should:

- build the shared artifact/import infrastructure
- support one or more telemetry catalog importers first
- add command catalog import after the command-plane design pass is complete

Release one may still use narrow dev formats for telemetry or commands
independently, but the import architecture must not assume that source artifacts
are single-family forever.

Cadence should not attempt to design a single universal command-and-telemetry
schema before implementing the import substrate.

## Consequences

### Positive

- supports multiple source formats without flattening everything too early
- preserves provenance and importer diagnostics
- keeps the runtime tied to stable canonical models
- allows telemetry and command import to share infrastructure without forcing
  them into one schema
- supports the common case where one uploaded mission database defines both
  telemetry and commands

### Negative

- import architecture is more layered than a single flat normalization step
- importer implementation requires both parsed-model and canonical-model code
- product surface must expose diagnostics and provenance explicitly

## Follow-On Work

- add catalog artifact and import-run persistence
- define the canonical telemetry catalog model
- define the canonical command catalog model after the command-plane design pass
- implement first supported telemetry catalog importer(s)
