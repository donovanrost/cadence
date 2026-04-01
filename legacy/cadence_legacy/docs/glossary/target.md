---
title: Target
aliases: [targets, spacecraft, satellite, ground station]
tags: [glossary, core, targets]
related:
  - "[[interface]]"
  - "[[mission]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Target

A **Target** is a spacecraft, ground system, or simulator that Cadence communicates with. Targets are the logical endpoints for commands and the source of telemetry.

## Target Types

| Type | Description |
|------|-------------|
| Spacecraft | Satellite, probe, or other space vehicle |
| Ground Station | Earth-based communication equipment |
| Simulator | Software or hardware test system |

## Relationship to Other Concepts

```
Organization
  └── Mission
        └── Target (spacecraft)
              ├── Interface (how we connect)
              ├── Telemetry Points (what we monitor)
              └── Commands (what we send)
```

## Common Confusion

> **Target vs Interface**: A target is the *logical* endpoint (the spacecraft). An interface is the *physical* connection (TCP socket to the ground station that talks to the spacecraft).

One target may have multiple interfaces:
- Primary ground station link
- Backup ground station link
- Direct-to-spacecraft link (for testing)

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Targets` | Context facade |
| `Cadence.Domain.Targets.Entities.Target` | Domain entity |

## Related Concepts

- [Interface](interface.md) - How we connect to targets
- [Mission](mission.md) - Operational context containing targets

## See Also

- [Data Plane / Control Plane](../architecture/data-plane-control-plane.md)
