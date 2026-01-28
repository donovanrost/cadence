---
title: Architecture
tags: [architecture, index]
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Architecture

System-level documentation for how Cadence components fit together.

## Start Here

1. [Data Plane / Control Plane](data-plane-control-plane.md) - Core architectural separation
   - Related: [ADR-001: No DB in Data Plane](../decisions/001-no-db-in-data-plane.md)

## Documents

### Core Architecture

| Document | Description |
|----------|-------------|
| [Data Plane / Control Plane](data-plane-control-plane.md) | Separation of config management and runtime data flow |
| [Runtime Uplink](runtime-uplink.md) | Uplink flow through COP-1 and non-COP-1 paths |
| [COP-1 Boundary Refactor](cop1-boundary-refactor.md) | Protocol boundary design |

### Implementation Plans

| Document | Description |
|----------|-------------|
| [Data Plane / Control Plane Migration](data-plane-control-plane-migration-plan.md) | Migration to DP/CP separation |
| [Recordables Implementation](recordables-implementation-plan.md) | Event sourcing implementation |
| [Telemetry Pipeline Redesign](telemetry_pipeline_redesign_plan.md) | Pipeline architecture changes |
| [Packet Format Normalization](packet-format-normalization-plan.md) | Standardizing packet formats |
| [Bucket Tree Implementation](bucket-tree-implementation-plan.md) | Hierarchical data storage |
| [Mission Reconciler](mission-reconciler-plan.md) | Mission state reconciliation |
| [Spacecraft Simulator](spacecraft-simulator-plan.md) | Simulation infrastructure |

### Reference

| Document | Description |
|----------|-------------|
| [C2 from Codex](c2_from_codex.md) | Command and control reference |

## See Also

- [Patterns](../patterns/_index.md) - How to extend these systems
- [Glossary](../glossary/_index.md) - Terminology
- [Decisions](../decisions/_index.md) - Why things are this way
