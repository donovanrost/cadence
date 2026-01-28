---
title: COP-1
aliases: [COP1, Communications Operation Procedure 1, FOP]
tags: [glossary, protocols, ccsds, cop-1]
related:
  - "[[interface]]"
  - "[[target]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# COP-1

**COP-1** (Communications Operation Procedure 1) is a CCSDS link-layer protocol that provides reliable command delivery through sequencing, acknowledgment, and retransmission.

## Purpose

COP-1 ensures commands reach the spacecraft reliably over an unreliable link by:

- **Sequencing** - Each frame gets a sequence number
- **Windowing** - Multiple frames in flight (sliding window)
- **Acknowledgment** - CLCW in telemetry confirms receipt
- **Retransmission** - Resend on timeout or rejection

## Key Concepts

| Term | Description |
|------|-------------|
| FOP | Frame Operation Procedure - the sending side |
| FARM | Frame Acceptance and Reporting Mechanism - the receiving side |
| CLCW | Command Link Control Word - acknowledgment in telemetry |
| TC Frame | Telecommand Transfer Frame - the unit of transmission |

## Cadence Architecture

COP-1 is a transport-layer concern, separate from commanding:

```
Commanding (application)
    ↓ PDU
TC Framing (transport/SDLP)
    ↓ TC Frames
COP-1 FOP (transport)
    ↓ Bytes + windowing/retransmit
Link Adapter (interface)
    ↓
[Spacecraft]
    ↓ Telemetry with CLCW
COP-1 FOP ← acknowledgment
```

## Protocol Events

COP-1 emits generic protocol events (not command-domain events):

```elixir
%ProtocolEvent{
  protocol: :cop1,
  status: :accepted | :rejected | :timeout,
  stream_id: term(),
  correlation_id: term()
}
```

Commanding subscribes and maps to domain outcomes.

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Runtime.Uplink.COP1Application` | FOP state machine |
| `Cadence.CCSDS.Transport.COP1.CLCW` | CLCW parsing |
| `Cadence.CCSDS.TC.TransferFrame` | TC frame encoding |

## Related Concepts

- [Interface](interface.md) - COP-1 runs over interfaces
- [Target](target.md) - COP-1 ensures reliable delivery to targets

## See Also

- [COP-1 Boundary Refactor](../architecture/cop1-boundary-refactor.md)
- [Runtime Uplink](../architecture/runtime-uplink.md)
