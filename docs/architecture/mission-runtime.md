---
title: Mission Runtime Architecture
tags: [architecture, missions, runtime]
created: 2026-01-29
updated: 2026-01-29
status: active
---

# Mission Runtime Architecture

## Overview

Each active mission runs as an isolated supervision tree in the data plane. Complete runtime isolation ensures one mission's failure doesn't affect others.

**Location:** `lib/cadence/runtime/missions/`

## Supervision Structure

```
MissionSupervisor (DynamicSupervisor)
└── MissionInstance (per mission, one_for_one)
    ├── ConfigManager
    ├── CurrentValueTable (CVT)
    ├── MetaCommandCache
    ├── StateTracker
    ├── StalenessMonitor
    ├── AlarmManager
    ├── Lanes.Supervisor (telemetry pipeline)
    ├── InterfaceSupervisor (transports)
    ├── COP1StreamSupervisor
    ├── ProtocolSupervisor
    ├── LinksSupervisor
    ├── ConfigReconciler
    ├── UplinkDispatcher
    ├── TargetPipelineSupervisor (commands)
    ├── VerificationManager
    ├── AutomationManager
    └── CacheWarmer (optional)
```

## Mission Lifecycle

### Starting a Mission

```
OrgReconciler (Control Plane)
       ↓
MissionConfig.load(mission_id)  ← Full config snapshot from DB
       ↓
MissionSupervisor.start_mission(config)
       ↓
MissionInstance starts all children
       ↓
Registers in MissionRegistry + Phoenix.Tracker
```

### Stopping a Mission

```
OrgReconciler detects mission should stop
       ↓
MissionSupervisor.stop_mission(mission_id)
       ↓
DynamicSupervisor.terminate_child()
       ↓
Entire supervision tree terminates
```

### Hot Reload

```
OrgReconciler detects config_generation drift
       ↓
MissionConfig.load(mission_id)  ← Reload from DB
       ↓
ConfigManager.apply_config(mission_id, config)
       ↓
Broadcasts via PubSub + warms caches
       ↓
Children handle updates independently
```

## Key Components

### ConfigManager

Stores mission configuration in GenServer state. On config updates:
- Stores new config
- Broadcasts `ConfigBundle` via PubSub
- Warms Limits and DerivedItems caches
- Sends `:config_version` to telemetry shards

### MissionTracker

Phoenix.Tracker-based state advertisement. Control plane observes actual state; data plane publishes status updates.

Status convergence:
- `:starting` - children initializing
- `:ready` - all conditions satisfied
- `:degraded` - any component failed

### AlarmManager

Subscribes to `mission:<id>:events` for limit transitions. Maintains ETS cache of active alarms. Publishes alarm changes to `mission:<id>:alarms`.

### AutomationManager

Subscribes to multiple event sources:
- `mission:<id>:alarms` - alarm state changes
- `mission:<id>:events` - telemetry events
- `mission:<id>:procedures` - procedure completion

Matches triggers against automation rules and executes actions.

## Registry Naming

All processes registered in `Cadence.MissionRegistry`:

```
mission_id                              → MissionInstance
{:mission_config, mission_id}           → ConfigManager
{:interface_supervisor, mission_id}     → InterfaceSupervisor
{:transport, mission_id, transport_id}  → Interface worker
{:lanes, mission_id, :router}           → Lane Router
{:uplink_dispatcher, mission_id}        → UplinkDispatcher
{:target_pipeline, mission_id, target_id} → TargetPipeline
```

## Control Plane Integration

The `OrgReconciler` runs a reconciliation loop (10-second interval):

1. Fetch desired state from database
2. Fetch actual state from MissionTracker
3. Decisions:
   - Should start but not running → start mission
   - Running but should stop → stop mission
   - Config changed → apply config
   - Converged → no action

Also subscribes to tracker diffs for faster reaction to state changes.

## Design Principles

1. **Isolation** - Each mission in its own supervision tree
2. **Config as State** - Children hold config in GenServer state, not shared ETS
3. **Registry Discovery** - All processes in MissionRegistry for dynamic lookup
4. **PubSub Events** - Event distribution via Phoenix.PubSub
5. **Snapshot Loading** - Full MissionConfig loaded once, distributed to children
6. **One-for-One** - Child crashes don't cascade
