---
title: Aggregate
aliases: [aggregates, event-sourced entity]
tags: [glossary, event-sourcing, recordings]
related:
  - "[[recording]]"
  - "[[recordable]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Aggregate

An **Aggregate** is an entity whose state is derived by replaying its [recordings](recording.md).

## Purpose

Rather than storing current state directly, aggregates derive their state from the sequence of events that happened to them. This provides:

- **Complete audit trail** - Every state change is recorded
- **Time travel** - Can reconstruct state at any point
- **Causality** - Know what caused each change

## Current Aggregates

| Aggregate | States | Example Lifecycle |
|-----------|--------|-------------------|
| `Command` | dispatched → sent → verified/failed | User sends command, system transmits, verification completes |
| `Alarm` | triggered → acknowledged → cleared | Limit violated, operator acknowledges, condition resolves |
| `ProcedureExecution` | started → running → completed/failed | Procedure triggered, steps execute, finishes |
| `QueueEntry` | queued → dequeued | Command enters queue, gets transmitted |

## State Derivation

```
Aggregate: Command cmd-123
Recordings: [CommandDispatched, CommandSent, CommandVerified]
State: verified (derived by replaying events in order)
```

## Related Concepts

- [Recording](recording.md) - Index entries that track aggregate history
- [Recordable](recordable.md) - The events that change aggregate state

## See Also

- [Adding a Recordable](../patterns/adding-recordable.md) - Full pattern guide
