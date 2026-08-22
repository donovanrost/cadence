---
title: Telemetry Pipeline Architecture
tags: [architecture, telemetry, runtime]
created: 2026-01-29
updated: 2026-01-29
status: active
---

# Telemetry Pipeline Architecture

## Overview

The telemetry pipeline processes spacecraft telemetry through a **lanes and shards** architecture. Packets flow through independent processing lanes with configurable parallelism via shards.

**Location:** `lib/cadence/runtime/telemetry/`

## High-Level Flow

```
Raw Telemetry (PubSub)
       ↓
    Router
       ↓ (lane selection + consistent hashing)
  ┌────┴────┐
  ↓         ↓
Shard 0   Shard N   (batch processing)
  ↓         ↓
    Log Sink        (durable storage)
       ↓
  ┌────┴────┐
  ↓         ↓
CVT      Limits     (async consumers)
Consumer Consumer
```

## Core Components

### Current Value Table (CVT)

**File:** `current_value_table.ex`

In-memory storage for latest telemetry values using mission-scoped ETS tables.

- **Table name:** `cvt_mission_<mission_id>`
- **Key:** `{target_id, packet_name, item_name}`
- **Value:** `%{value, received_time, packet_time, limits_state, metadata}`

Operations are optimized for high throughput:
- Batch inserts to reduce syscall overhead
- PubSub broadcasts grouped by packet
- 1% sampled timing to minimize measurement impact

### Router

**File:** `lanes/router.ex`

Routes incoming packets to appropriate processing lanes and shards.

**Responsibilities:**
- Subscribe to `mission:<mission_id>:telemetry:raw`
- Select lane based on packet metadata (APID, target, etc.)
- Assign shard via consistent hashing: `phash2({packet_id, apid}, virtual_shards)`
- Manage per-shard queues with credit-based flow control
- Apply backpressure at 80% queue depth, release at 50%

### Lane Configuration

**File:** `lanes/lane_config.ex`

Lanes are configured with:
- `shard_count` - number of parallel workers (default: 8)
- `virtual_shards` - partition count for consistent hashing (default: 256)
- `selectors` - routing rules (APIDs, targets, packet names)
- `priority` - selection order when multiple lanes match

### Shard Workers

**File:** `lanes/shard_worker.ex`

Each shard runs a fused processing pipeline:

```
Buffer events (batch_size: 200, timeout: 50ms)
       ↓
Parse & validate
       ↓
Resolve target/packet identity
       ↓
Decommutate (extract item values)
       ↓
Convert (engineering units)
       ↓
Append to log sink
       ↓
Return credits to router
```

## Limits System

### Limits Cache

**File:** `limits/cache.ex`

Global ETS cache (`limits_cache`) storing limit definitions per target. Supports named limit sets (NOMINAL, ECLIPSE) with 5-minute TTL.

### State Tracker

**File:** `limits/state_tracker.ex`

Per-mission ETS table tracking limit states with persistence logic:
- N consecutive violations before state transition
- Immediate transition on return to green
- States: `:green`, `:yellow`, `:red`, `:blue` (stale)

### Limits Consumer

**File:** `lanes/limits_consumer.ex`

Consumes from log sink asynchronously to evaluate limits without blocking the ingest path. Updates CVT with limit states and broadcasts events.

## Derived Items

**File:** `derived_items/cache.ex`

Cached computed telemetry definitions with:
- Pre-parsed expression AST
- Topological sort order for safe evaluation
- Packet index mapping packets to derivable items

Supports both stateless (computed per-packet) and stateful (windowed/accumulated) derivations.

## Supervision Tree

```
Lanes.Supervisor (rest_for_one)
├── Router
├── Autoscaler
├── Lane Supervisors
│   └── Shard Workers (0..N)
├── CVT Consumer
├── Limits Consumer
└── Stateful Supervisor (optional)
    ├── Stateful Router
    └── Stateful Shard Workers
```

## Configuration

Runtime configuration is managed via `ConfigBundle` stored in `:persistent_term` for low-latency access. Includes packet definitions, targets, derived items, and limits.

Config versioning ensures shard workers can swap configurations at batch boundaries without mid-batch changes.

## Key PubSub Topics

- `mission:<id>:telemetry:raw` - Raw packet ingest
- `mission:<id>:telemetry` - CVT update broadcasts
- `mission:<id>:events` - Limit transition events
