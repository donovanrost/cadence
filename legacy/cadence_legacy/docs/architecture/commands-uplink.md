---
title: Commands and Uplink Architecture
tags: [architecture, commands, uplink, runtime]
created: 2026-01-29
updated: 2026-01-29
status: active
---

# Commands and Uplink Architecture

## Overview

The command system handles the flow from user action to spacecraft transmission. Commands flow through queues, dispatchers, and the uplink routing system before reaching transport interfaces.

**Location:**
- `lib/cadence/runtime/commands/`
- `lib/cadence/runtime/uplink/`

## High-Level Flow

```
User Action (Web/API)
       ↓
Control Plane (persist QueuedCommand)
       ↓
TargetQueue (in-memory ordering)
       ↓
TargetDispatcher (validation, encoding)
       ↓
UplinkDispatcher (routing)
       ↓
ChannelService (framing)
       ↓
Transport Interface → Spacecraft
```

## Target Pipeline

Each target has its own queue and dispatcher for command serialization:

```
TargetPipelineSupervisor
└── TargetPipeline (per target, one_for_one)
    ├── TargetQueue
    └── TargetDispatcher
```

### TargetQueue

**File:** `commands/target_queue.ex`

In-memory command ordering with:
- Priority-based sorting (0=emergency, 5=background)
- Scheduled execution (commands with future `scheduled_at`)
- Automatic expiration (`expires_at` checking)
- Retry on transient failures (1-second delay)

States: `pending` → `executing` → `completed`/`failed`/`cancelled`

### TargetDispatcher

**File:** `commands/target_dispatcher.ex`

Handles command processing pipeline:

1. **Phase Check** - Verify command allowed in current mission phase
2. **Validation** - Validate parameters against argument specs
3. **Hazard Check** - Require confirmation for hazardous commands
4. **Encoding** - Compile command to binary using definition set
5. **PDU Build** - Wrap in CCSDS PDU
6. **Dispatch** - Send to uplink system
7. **Recording** - Audit via CommandDispatched event
8. **Verification** - Start verification if configured

## Uplink Routing

### UplinkDispatcher

**File:** `uplink/dispatcher.ex`

Routes PDUs to appropriate channels:

```
UplinkPDU{target_id, pdu, pdu_type, apid}
       ↓
Resolver: target_id → [ChannelId]
       ↓
Channel Selection (override or active)
       ↓
Transport Selection (LinkController)
       ↓
ChannelService.send_uplink()
```

### Resolver

**File:** `uplink/resolver.ex`

Maps targets to channels using ConfigBundle. Returns `RouteDecision` with:
- `scid`, `vcid`, `map_id` - channel identifiers
- `transport_id` - selected transport
- `cop1_mode` - `:fop` or `:bypass`

### FrameBuilder

**File:** `uplink/frame_builder.ex`

Builds TC frames from PDUs:

```
PDU → SDU Encoding → Segmentation → Frame Encoding
       ↓
[{seq: 1, bytes: <<...>>}, {seq: 2, bytes: <<...>>}, ...]
```

## Verification

**File:** `commands/verification_manager.ex`

Multi-stage command verification system:

1. Start verification after PDU dispatch
2. Subscribe to telemetry updates
3. Check each verification stage against requirements
4. Record `CommandVerified` or `CommandVerificationFailed`

Supports timeout actions: `:continue`, `:retry`, `:abort`

## Hazardous Commands

Commands marked hazardous require confirmation:

1. Dispatcher returns `{:error, :requires_confirmation, info}`
2. User receives confirmation token (60-second expiry)
3. User confirms with token
4. Dispatcher re-dispatches with `skip_hazardous_check`

## COP-1 Integration

For FOP mode (reliable delivery):

1. Command stored in `pending_cop1` map
2. Wait for `ProtocolEvent` from COP-1 stack
3. On `:accepted` → record `CommandSent`
4. On `:rejected`/`:timeout` → record `CommandErrored`

Bypass mode records `CommandSent` immediately.

## Recording Events

| Event | When |
|-------|------|
| `CommandDispatched` | Command sent to dispatcher |
| `CommandSent` | Transmitted via transport |
| `CommandErrored` | Dispatch/transmission failed |
| `CommandRejected` | Validation/phase check failed |
| `CommandVerified` | Verification stages complete |
| `CommandVerificationFailed` | Verification requirement not met |

## Key Design Points

1. **Per-Target Serialization** - Commands to same target execute sequentially (safety)
2. **Cross-Target Parallelism** - Different targets dispatch in parallel (performance)
3. **No DB in Hot Path** - MetaCommandCache (ETS) for O(1) command lookup
4. **Async Execution** - Task.async with 30-second timeout
5. **Isolated Failure** - Target crash doesn't affect other targets
