---
title: Concepts
tags: [concepts, index]
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Concepts

Core concepts and mental models for understanding Cadence.

## Architecture Concepts

These foundational concepts are documented in the [Glossary](../glossary/_index.md):

| Concept | Description |
|---------|-------------|
| [Data Plane](../glossary/data-plane.md) | Runtime telemetry processing (no DB calls) |
| [Control Plane](../glossary/control-plane.md) | Configuration management and persistence |
| [Domain Entity](../glossary/domain-entity.md) | Pure business objects without persistence concerns |

## Event Sourcing Concepts

| Concept | Description |
|---------|-------------|
| [Recording](../glossary/recording.md) | Index entry linking events to aggregates |
| [Recordable](../glossary/recordable.md) | Strongly-typed event in its own table |
| [Aggregate](../glossary/aggregate.md) | Entity whose state is derived from recordings |

## Procedures Concepts

| Concept | Description |
|---------|-------------|
| [Procedure](../glossary/procedure.md) | Executable operational logic (umbrella term) |
| [Sequence](../glossary/sequence.md) | Step-based procedure with approval workflow |
| [Automation](../glossary/automation.md) | Simple trigger → action rule |

## Core Domain Concepts

| Concept | Description |
|---------|-------------|
| [Mission](../glossary/mission.md) | Operational context grouping targets and config |
| [Target](../glossary/target.md) | Spacecraft or ground system |
| [Interface](../glossary/interface.md) | Connection endpoint to targets |

## Protocol Concepts

| Concept | Description |
|---------|-------------|
| [COP-1](../glossary/cop-1.md) | CCSDS link-layer protocol for reliable delivery |

## Telemetry Concepts

| Concept | Description |
|---------|-------------|
| [Telemetry Point](../glossary/telemetry-point.md) | Monitored data item from a target |
| [CVT](../glossary/cvt.md) | Current Value Table - live telemetry cache |
| [Command](../glossary/command.md) | Operation sent to a target |

## Planned Concepts

Concepts that need dedicated notes:

- Protocol Chain - Layered protocol processing pipeline

## See Also

- [Glossary](../glossary/_index.md) - Term definitions
- [Architecture](../architecture/_index.md) - How concepts combine into systems
- [Decisions](../decisions/_index.md) - Why concepts work this way
