---
title: COP-1 Protocol Architecture
tags: [architecture, cop1, protocol, transport, runtime]
created: 2026-01-29
updated: 2026-01-29
status: active
---

# COP-1 Protocol Architecture

## Overview

COP-1 (Communications Operation Procedure 1) provides reliable command delivery through sequencing, acknowledgment, and retransmission. The implementation follows CCSDS standards adapted for Elixir.

**Location:** `lib/cadence/runtime/transport/cop1/`

## High-Level Flow

```
TargetDispatcher (command PDU)
       ↓
FrameBuilder.build_frames/3 (PDU → TC frames with seq)
       ↓
COP1.Application.propose_send_frames/4
       ↓
COP1.Stream (windowing, timing)
       ↓
ReleasedUplinkFrame → Transport.send_bytes()
       ↓
[Spacecraft]
       ↓
Telemetry with CLCW in OCF
       ↓
DownlinkHandler.ingest_tm_ocf/4
       ↓
CLCWReportDecoder → Report
       ↓
COP1.Stream.apply_clcw/2 (ACK frames, update flags)
       ↓
ProtocolEvent broadcast (:accepted/:rejected/:timeout)
```

## Core Components

### FOP (Frame Operation Procedure)

**File:** `cop1/FOP.ex`

Ground-side controller managing channel-level COP-1 state.

### Stream

**File:** `cop1/Stream.ex`

Per-stream state machine implementing:
- Sliding window with configurable size
- Timer-based retransmission
- Lockout/wait/hold state management
- CLCW report processing

**Key State Variables:**

| Variable | Purpose |
|----------|---------|
| `pending` | Queue of frames waiting to send |
| `in_flight` | Frames sent but not ACKed |
| `timers` | seq → timer_ref for timeouts |
| `window_size` | Max frames in flight (default: 4) |
| `timeout_ms` | Per-frame timeout (default: 5000) |
| `max_retransmit` | Max retries (default: 3) |

**State Flags:**

| Flag | Meaning |
|------|---------|
| `lockout` | Max retransmits exceeded; no sends until resync |
| `wait` | CLCW indicates spacecraft busy; defer new sends |
| `retransmit` | CLCW requests re-send of in-flight frames |
| `held` | Stream held pending first report or manual resync |

### StreamServer / StreamSupervisor

**Files:** `cop1/StreamServer.ex`, `cop1/StreamSupervisor.ex`

GenServer wrapper and DynamicSupervisor for per-stream processes.

### CLCW (Communications Link Control Word)

**File:** `lib/cadence/ccsds/transport/cop1/CLCW.ex`

32-bit status word from spacecraft:

| Field | Bits | Description |
|-------|------|-------------|
| `lockout` | 1 | Spacecraft lockout |
| `wait` | 1 | Spacecraft busy |
| `retransmit` | 1 | Retransmit request |
| `no_rf_available` | 1 | RF signal lost |
| `no_bit_lock` | 1 | Bit lock lost |
| `report_value` | 8 | Latest ACKed sequence (mod 256) |

## Operating Modes

### FOP Mode (Reliable Delivery)

Full protocol with windowing and retransmission:

1. Frame enqueued to `pending`
2. Send up to `window_size` frames
3. Start timer for each sent frame
4. Wait for CLCW acknowledgment
5. On timeout: retransmit (up to `max_retransmit`)
6. On max retries: enter lockout

### Bypass Mode

Direct send without windowing:

1. Frame sent immediately
2. `:accepted` event emitted immediately
3. No timers, no retransmission
4. Used for time-critical or fire-and-forget commands

### APID Filtering

Optional allowlist for FOP mode:

```elixir
cop1: %{
  mode: :fop,
  apids: [10, 20]  # Only these APIDs use FOP; others bypass
}
```

## CLCW Processing

When CLCW arrives from telemetry:

1. **VCID Match** - Skip if CLCW VCID doesn't match stream
2. **Flag Updates** - Update lockout/wait/retransmit flags
3. **Lockout Transition** - If entering lockout: clear queues, fail pending
4. **Retransmit** - If retransmit flag set: re-send all in-flight
5. **ACK Frames** - Compute distance from oldest seq to report_value
6. **Emit Events** - `:accepted` for ACKed frames via correlation_id

**Sequence Math (mod 256):**
```elixir
distance = rem(report_value - oldest_seq + 256, 256)
# ACK all frames up to distance from oldest
```

## Timeout Flow

```
Timer fires for seq N
       ↓
Check in_flight for frame
       ↓
retries < max_retransmit?
  ├─ Yes: Retransmit, increment retries, reschedule timer
  └─ No: Enter lockout
              ↓
         Clear timers & queues
              ↓
         Emit :timeout for all correlated commands
```

## Correlation Tracking

Commands map to `correlation_id`, attached to frames:

1. Single command may span multiple frames
2. Stream tracks `correlation_id → remaining_frame_count`
3. When last frame ACKed: emit `:accepted` event
4. Commanding layer subscribes and maps to domain outcomes

## Supervision Structure

```
MissionInstance
└── COP1.StreamSupervisor (DynamicSupervisor)
    └── StreamServer per {scid, vcid} (GenServer)
```

Streams created on-demand when first frame proposed for a channel.

## Configuration

```elixir
cop1: %{
  mode: :fop | :bypass,        # Operating mode
  window_size: 4,              # Sliding window size
  timeout_ms: 5000,            # Per-frame timeout
  max_retransmit: 3,           # Max retries
  initial_seq: 0,              # Starting sequence
  apids: [...]                 # Optional APID filter
}
```

## Protocol Events

Published to `mission:#{mission_id}:events`:

| Status | Meaning |
|--------|---------|
| `:accepted` | Frame(s) acknowledged by CLCW |
| `:rejected` | Frame rejected by FARM |
| `:timeout` | Max retransmits exceeded |
| `:cop1_retransmit` | Frame retransmitted |
| `:cop1_window_full` | Window exhausted, deferral |
| `:cop1_stream_lockout` | Entered lockout state |
| `:cop1_stream_hold` | Stream held on restart |
| `:cop1_stream_resynced` | Hold cleared |

## Key Design Points

1. **Per-Stream State** - Each TC stream has own window/timers
2. **FOP + Bypass Coexist** - Same Stream, different code path via context flag
3. **Hold-on-Restart** - Streams start held; first report or manual resync clears
4. **No Command Domain Leakage** - Generic protocol events only
5. **Modulo-256 Sequencing** - Standard CCSDS wrapping
