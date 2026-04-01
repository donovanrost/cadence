---
title: Glossary
tags: [glossary, index, terminology]
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Glossary

Canonical terminology for Cadence. Check here first when encountering unfamiliar domain terms.

## Core Domain

| Term | Brief Definition |
|------|------------------|
| [Mission](mission.md) | Operational context grouping targets, interfaces, and config |
| [Target](target.md) | Spacecraft, ground station, or simulator |
| [Interface](interface.md) | Connection endpoint (TCP, UDP, serial) to a target |
| [Command](command.md) | Operation sent to a target |
| [Telemetry Point](telemetry-point.md) | Monitored data item from a target |
| [CVT](cvt.md) | Current Value Table - live cache of latest telemetry |

## Architecture

| Term | Brief Definition |
|------|------------------|
| [Control Plane](control-plane.md) | Configuration management layer (DB, UI, CRUD) |
| [Data Plane](data-plane.md) | Runtime processing layer (no DB calls) |
| [Domain Entity](domain-entity.md) | Pure business object without persistence concerns |

## Protocols

| Term | Brief Definition |
|------|------------------|
| [COP-1](cop-1.md) | CCSDS link-layer protocol for reliable command delivery |

## Event Sourcing

| Term | Brief Definition |
|------|------------------|
| [Aggregate](aggregate.md) | Entity whose state is derived from its recordings |
| [Recordable](recordable.md) | Strongly-typed event stored in its own table |
| [Recording](recording.md) | Index entry linking events to aggregates |

## Procedures

| Term | Brief Definition |
|------|------------------|
| [Procedure](procedure.md) | Executable operational logic (umbrella term) |
| [Sequence](sequence.md) | Step-based procedure with approval workflow |
| [Automation](automation.md) | Simple trigger → action rule |

## See Also

- [Architecture Decisions](../decisions/_index.md) - Why things are this way
- [Patterns](../patterns/_index.md) - How to extend the codebase
