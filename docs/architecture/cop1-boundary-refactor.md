---
title: COP-1 Boundary Refactor Spec
aliases: [cop1 refactor, protocol boundaries]
tags: [architecture, cop-1, ccsds, protocols, refactor]
related:
  - "[[cop-1]]"
  - "[[interface]]"
  - "[[target]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# COP-1 Boundary Refactor Spec (Greenfield-First)

> **Glossary:** [COP-1](../glossary/cop-1.md) | [Interface](../glossary/interface.md) | [Target](../glossary/target.md)

This project is greenfield and under active development. The priority is
end-state architectural correctness over minimizing intermediate breakage.
If a missing layer/component is needed, we design and implement it rather than
shim into the existing architecture.

## Problem Statement

Current code blurs CCSDS TC framing, COP-1 application (FOP), and commanding.
Examples include TC transfer frame modules under COP-1 namespaces, COP-1 stream
code emitting command-domain events, and a single context struct mixing routing,
framing, COP-1 controls, and command correlation.

We want clean, explicit boundaries:

- TC framing/segmentation is transport (SDLP/TC), not COP-1.
- COP-1 FOP is link-layer protocol state (windowing, timers, CLCW handling),
  independent of commanding.
- Commanding consumes protocol-level outcomes and maps them to domain events.

## Goals

- Align modules with CCSDS layering and names.
- Make boundaries visible in code, data flow, and types.
- Remove COP-1 logic from commanding and TC framing from COP-1 namespaces.
- Define explicit contracts between layers (structs/events).
- Prefer correctness and clean architecture over compatibility shims.

## Non-Goals

- Preserve current module names or APIs.
- Minimize intermediate build breakage.
- Implement COP-1 FARM beyond simulator needs (still allowed later).

## End-State Layering

1) **Commanding (application/domain)**
   - Builds command PDUs.
   - Handles mission policy, hazard checks, recording, queueing.
   - Receives protocol outcomes via a protocol-agnostic event interface.

2) **Uplink Routing (application/runtime)**
   - Resolves interface, VCID, SCID, and protocol mode for a PDU.
   - Produces a `RouteDecision` and a routing-only context.

3) **TC Framing (transport/SDLP)**
   - Encodes PDUs into TC transfer frames.
   - Handles segmentation state keyed by a TC stream identity.
   - No COP-1 timers/windowing or command correlation.

4) **COP-1 FOP (transport/COP-1)**
   - Manages per-stream window, timers, retransmits, lockout/wait.
   - Accepts framed TC data (bytes + seq).
   - Emits protocol outcomes (accepted/rejected/timeout) without domain knowledge.

5) **Link Adapter (interface/runtime)**
   - Sends bytes over TCP/UDP/serial.
   - Receives TM and provides OCF/CLCW to COP-1 FOP.

## Proposed Module Boundaries (End-State)

### Transport: TC

- `Cadence.CCSDS.TC.FrameCodec` stays as the TC codec.
- Move `Cadence.CCSDS.Transport.COP1.TCFrame` to:
  `Cadence.CCSDS.TC.TransferFrame` (or `Cadence.CCSDS.TC.Frame`).
- All TC framing/segmentation logic lives under `lib/cadence/ccsds/tc/`.

### Transport: COP-1

- `Cadence.CCSDS.Transport.COP1.CLCW` remains.
- `Cadence.Runtime.Uplink.COP1FOP` and stream code move to
  `Cadence.Runtime.Transport.COP1` or `Cadence.CCSDS.Transport.COP1.FOP`.
  (Pick one namespace and keep all COP-1 state there.)
- COP-1 emits protocol outcomes via a generic event interface:
  `Cadence.Runtime.Transport.ProtocolEvent` (or similar).

### Runtime: Uplink Pipeline

Split current `UplinkPipeline` responsibilities:

- `Cadence.Runtime.Uplink.TCFraming`:
  - `build_frames/4` (PDU -> framed bytes)
  - maintains segmentation state keyed by `tc_stream_id`
  - no COP-1 logic
- `Cadence.Runtime.Uplink.Dispatcher`:
  - chooses between COP-1 and direct send
  - passes frames to COP-1 FOP or bytes to Link Adapter

### Commanding Integration

- Commanding subscribes to generic protocol events and maps them to
  command-domain outcomes (recorded accept/reject/timeout).
- COP-1 no longer emits `COP1CommandEvent` (or similar domain events).

## New Core Types/Contracts

### Route Decision

Keep `RouteDecision` but limit to routing fields:

- `target_id`, `interface_id`, `scid`, `vcid`, `tc_stream_id`,
  `protocol_mode` (e.g., `:cop1` or `:direct`), `pdu_type`, `apid`.

### Uplink Context Split

Replace the current multi-purpose `UplinkContext` with explicit contexts:

- `RoutingContext` (routing override knobs only)
- `TCFramingContext` (frame_size, scid, vcid, map_id, flags)
- `COP1Context` (stream id, initial seq, control flags)
- `ProtocolCorrelation` (opaque correlation id, optional)

The dispatcher assembles these and passes only what the target layer needs.

### Framed TC Envelope

Define a transport-level frame envelope (COP-1 agnostic):

```
%TCFrameEnvelope{
  stream_id: term(),
  seq: non_neg_integer(),
  bytes: binary(),
  retries: non_neg_integer()
}
```

### Protocol Event (generic)

```
%ProtocolEvent{
  protocol: :cop1,
  status: :accepted | :rejected | :timeout,
  stream_id: term(),
  interface_id: String.t(),
  correlation_id: term() | nil,
  reason: term() | nil,
  seq: non_neg_integer() | nil,
  timestamp: DateTime.t()
}
```

Commanding translates this into domain events.

## End-State Data Flow

COP-1:

Commanding
  -> RoutingService
  -> TCFraming.build_frames (PDU -> [TCFrameEnvelope])
  -> COP1.FOP.send_frames (envelope + COP1Context + correlation_id)
  -> Release (bytes) -> Link Adapter
  <- TM OCF (CLCW) -> COP1.FOP.ingest_clcw
  -> ProtocolEvent(:accepted/:rejected/:timeout)
  -> Commanding maps to domain outcomes

Non-COP-1:

Commanding
  -> RoutingService
  -> Uplink.encode (PDU -> bytes)
  -> Release (bytes) -> Link Adapter

## Specific Changes (No Shims)

1) **Move TC frame module**
   - Rename `Cadence.CCSDS.Transport.COP1.TCFrame` to
     `Cadence.CCSDS.TC.TransferFrame`.
   - Update call sites (TC FrameCodec, simulator, etc).

2) **Split uplink pipeline**
   - Introduce `Cadence.Runtime.Uplink.TCFraming` responsible for
     segmentation state and TC frame building.
   - Remove COP-1 references from `UplinkPipeline`.

3) **Decouple COP-1 from commanding**
   - Replace `COP1CommandEvent` with generic `ProtocolEvent`.
   - Commanding subscribes to `ProtocolEvent` and maps to domain outcomes.

4) **Context cleanup**
   - Replace `UplinkContext` with smaller structs or maps.
   - Avoid putting command-domain data into transport contexts.

5) **COP-1 location and naming**
   - Move `COP1FOP`, `COP1Stream`, `COP1StreamServer`, and supervisor into
     a consistent COP-1 transport namespace.

6) **CLCW handling**
   - CLCW ingestion stays in COP-1 transport.
   - Downlink pipeline passes OCF to COP-1 FOP without any command coupling.

## Migration Plan (Correctness-First)

Phase 1: Namespace + type corrections
- Move `TCFrame` module to TC namespace and update all call sites.
- Introduce `ProtocolEvent` type and publish it from COP-1 FOP.

Phase 2: Layer split
- Implement `Runtime.Uplink.TCFraming` with segmentation state.
- Replace `UplinkPipeline.build_frames` usage with `TCFraming.build_frames`.
- Delete COP-1 segmentation state from the telemetry pipeline.

Phase 3: Commanding decoupling
- Commanding subscribes to `ProtocolEvent` and maps to domain events.
- Remove `COP1CommandEvent` and COP-1 awareness from command dispatch.

Phase 4: Context cleanup
- Replace `UplinkContext` with small layer-specific contexts.
- Update callers to pass only required contexts.

Phase 5: Cleanup
- Remove unused modules and update docs.

## Testing Plan

- Unit tests for `TC.TransferFrame` encode/decode.
- Unit tests for `TCFraming` segmentation and sequence behavior.
- COP-1 FOP tests for windowing, retransmit, lockout, and CLCW handling.
- Integration test: dispatch PDU -> COP-1 -> CLCW loopback -> protocol event.
- Commanding test: protocol event -> domain outcome.

## Open Questions

- Should `tc_stream_id` be derived strictly from target/interface/vcid or
  be a first-class configured value (current `tc_stream_id`)?
- Where should protocol events be published (PubSub vs explicit callbacks)?
- Do we want a generic `ProtocolCorrelation` that can be reused by future
  CFDP or other link protocols?
- How should COP-1 control commands (unlock) be represented in the new contexts?

## Notes

This spec intentionally favors clean boundaries and correct layering over
short-term compatibility. It is expected to be disruptive, and that is acceptable.
