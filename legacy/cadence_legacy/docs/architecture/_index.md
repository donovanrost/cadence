---
title: Architecture
tags: [architecture, index]
created: 2025-01-27
updated: 2026-01-29
status: active
---

# Architecture

System-level documentation for how Cadence components fit together.

## Start Here

1. [Data Plane / Control Plane](data-plane-control-plane.md) - Core architectural separation
   - Related: [ADR-001: No DB in Data Plane](../decisions/001-no-db-in-data-plane.md)
2. [Mission Runtime](mission-runtime.md) - Per-mission supervision trees

## Documents

### Runtime Architecture

| Document | Description |
|----------|-------------|
| [Data Plane / Control Plane](data-plane-control-plane.md) | Separation of config management and runtime data flow |
| [Mission Runtime](mission-runtime.md) | Per-mission isolation and supervision structure |
| [Telemetry Pipeline](telemetry-pipeline.md) | Lanes and shards architecture for packet processing |
| [Commands and Uplink](commands-uplink.md) | Command flow from user action to spacecraft |
| [Interfaces and Transports](interfaces-transports.md) | Socket lifecycle and byte I/O |
| [COP-1 Protocol](cop1-protocol.md) | Reliable delivery via windowing and retransmission |
| [Runtime Uplink](runtime-uplink.md) | Uplink flow through COP-1 and non-COP-1 paths |

### Event Sourcing

| Document | Description |
|----------|-------------|
| [Recordings](recordings.md) | Immutable audit trail and event sourcing |

### Reference

| Document | Description |
|----------|-------------|
| [C2 from Codex](c2_from_codex.md) | Command and control reference |

## See Also

- [Patterns](../patterns/_index.md) - How to extend these systems
- [Glossary](../glossary/_index.md) - Terminology
- [Decisions](../decisions/_index.md) - Why things are this way
- [Archive](../archive/) - Historical planning documents
