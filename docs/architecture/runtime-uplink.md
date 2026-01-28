---
title: Runtime Uplink Flow
aliases: [uplink flow, command uplink]
tags: [architecture, uplink, cop-1, runtime]
related:
  - "[[cop-1]]"
  - "[[interface]]"
  - "[[target]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Runtime Uplink Flow

This document captures the stable release contract for the runtime uplink path.

> **Glossary:** [COP-1](../glossary/cop-1.md) | [Interface](../glossary/interface.md) | [Target](../glossary/target.md)

## COP-1 Protected Uplink

Flow:

CommandApplication/TargetDispatcher
  -> RoutingService
  -> TCFraming.build_frames (SDLP profile)
  -> COP1Application (windowing, timers, retransmits)
  -> ReleasedUplinkFrame (release contract)
  -> UplinkPipeline.send_release (send bytes)
  -> LinkAdapter

Notes:

- TC frame building happens in `TCFraming.build_frames/4` before COP-1 windowing.
- The release contract is `Cadence.Runtime.Uplink.ReleasedUplinkFrame` and carries
  `mission_id`, `interface_id`, `stream_id`, `bytes`, `kind`, and optional `seq`.
- `correlation_id` is attached to releases to correlate COP-1
  accept/reject/timeout events.

## Non-COP-1 Uplink

Flow:

CommandApplication/TargetDispatcher
  -> RoutingService
  -> UplinkPipeline.encode/4
  -> ReleasedUplinkFrame
  -> LinkAdapter
