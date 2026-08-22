---
title: Procedure
aliases: [procedures]
tags: [glossary, procedures, automation]
related:
  - "[[sequence]]"
  - "[[automation]]"
  - "[[recording]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Procedure

A **Procedure** is an umbrella term for executable operational logic in Cadence. Procedures come in four types with different complexity levels.

## Procedure Types

| Type | Description | Complexity | Use Case |
|------|-------------|------------|----------|
| [Sequence](sequence.md) | Ordered steps with checks | Medium | Approval workflows, predictable operations |
| [Automation](automation.md) | Trigger → Action rules | Low | Simple reactive logic |
| Script | Raw Lua code | Medium-High | Complex custom operations |
| Campaign | Multi-target orchestration | High | Constellation-wide rollouts (deferred) |

## Common Runtime

All procedure types share a common execution runtime built on Luerl (Lua in Erlang).

See [ADR-002: Luerl for Procedure Execution](../decisions/002-luerl-for-procedures.md) for rationale.

## Execution Lifecycle

```
pending → running → completed
                 → failed
                 → cancelled
           ↓ ↑
         paused
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Procedures` | Context facade |
| `Cadence.Procedures.Engine.ExecutionProcess` | GenServer holding Luerl VM |
| `Cadence.Procedures.Engine.ExecutionCoordinator` | Per-mission supervisor |

## Event Sourcing

Procedure executions create [Recordings](recording.md):
- `ProcedureStarted`
- `ProcedureStepCompleted`
- `ProcedurePaused` / `ProcedureResumed`
- `ProcedureCompleted` / `ProcedureFailed` / `ProcedureCancelled`

## Related Concepts

- [Sequence](sequence.md) - Step-based procedures
- [Automation](automation.md) - Trigger-action rules
- [Recording](recording.md) - Event sourcing for procedure history

## See Also

- [Procedures Design](../design/procedures.md) - Full design document
