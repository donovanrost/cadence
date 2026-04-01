---
title: Command
aliases: [commands, telecommand, TC]
tags: [glossary, commanding, core]
related:
  - "[[target]]"
  - "[[interface]]"
  - "[[cop-1]]"
  - "[[recording]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Command

A **Command** is an operation sent to a [Target](target.md). Commands flow through routing, framing, and optional [COP-1](cop-1.md) reliable delivery before reaching the target via an [Interface](interface.md).

## Command Lifecycle

```
User/Procedure/Automation
    ↓ dispatch
Validation & Hazard Check
    ↓ encode
Routing (target → interface)
    ↓ frame
TC Framing (CCSDS)
    ↓ optional
COP-1 (reliable delivery)
    ↓ transmit
Interface → Target
```

## Command States

| State | Description |
|-------|-------------|
| `pending` | Dispatched, awaiting transmission |
| `sent` | Transmitted to interface |
| `verified` | Verification passed (if configured) |
| `failed` | Verification failed or transmission error |
| `rejected` | Validation or authorization failed |

## Event Sourcing

Commands are [Aggregates](aggregate.md) tracked via [Recordings](recording.md):

- `CommandDispatched` - Initial dispatch
- `CommandSent` - Transmitted to interface
- `CommandVerified` / `CommandVerificationFailed`
- `CommandRejected` / `CommandErrored`

## Hazardous Commands

Some commands require additional authorization:

| Level | Description |
|-------|-------------|
| Normal | Standard authorization |
| Hazardous | Requires confirmation |
| Critical | Requires multi-person authorization |

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Commands` | Context facade |
| `Cadence.Commands.TargetDispatcher` | Routes commands to targets |
| `Cadence.Commands.Staging` | Queues commands for later |
| `Cadence.Runtime.Uplink.TCFraming` | TC frame encoding |

## Related Concepts

- [Target](target.md) - Where commands are sent
- [Interface](interface.md) - How commands are transmitted
- [COP-1](cop-1.md) - Reliable delivery protocol
- [Procedure](procedure.md) - Automated command sequences

## See Also

- [Runtime Uplink](../architecture/runtime-uplink.md)
- [Adding a Recordable](../patterns/adding-recordable.md) - Command event sourcing
