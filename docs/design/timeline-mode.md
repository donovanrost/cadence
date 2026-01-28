---
title: Timeline Mode Design Document
aliases: [timeline mode, timeline view, activity timeline]
tags: [design, ui, timeline, ops-console]
related:
  - "[[command]]"
  - "[[procedure]]"
  - "[[automation]]"
  - "[[recording]]"
  - "[[target]]"
  - "[[mission]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Timeline Mode Design Document

## Overview

Timeline Mode is a new ops-v2 mode that provides a unified chronological view of all [Mission](../glossary/mission.md) activity—past, present, and future. Unlike other modes that are action-oriented ([Commands](../glossary/command.md), [Procedures](../glossary/procedure.md)), Timeline Mode is observation-oriented, designed for situational awareness, pattern recognition, and forensic investigation.

> **Data Source:** Timeline events are persisted as [Recordings](../glossary/recording.md), enabling historical queries and audit trails.

### Design Goals

| Goal | Description |
|------|-------------|
| **Constellation Scale** | Handle thousands of targets with high event velocity |
| **Temporal Completeness** | Show both historical events and scheduled future events |
| **Pattern Recognition** | Surface anomalies and correlations across the fleet |
| **Shift Handoff** | Enable quick situational awareness transfer |
| **Forensic Investigation** | Support deep-dive into specific targets or time ranges |

### Target Users

- **Constellation Operators** - Monitoring large fleets (100s-1000s of targets)
- **Anomaly Investigators** - Deep-diving into specific issues
- **Shift Supervisors** - Maintaining fleet-wide awareness
- **Mission Managers** - Understanding operational tempo and patterns

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            OPS-V2 CONSOLE                                    │
├──────────────┬──────────────────────────────────────────────┬───────────────┤
│              │                                              │               │
│  NAVIGATION  │            TIMELINE MODE                     │   CONTEXT     │
│    PANEL     │         (main content area)                  │    PANEL      │
│              │                                              │               │
│  - Mission   │  ┌────────────────────────────────────────┐ │  - Active     │
│  - Mode      │  │  [STREAM] [MATRIX] [LANES]             │ │    Alarms     │
│    Switcher  │  ├────────────────────────────────────────┤ │               │
│  - Dashboard │  │                                        │ │  - Command    │
│    List      │  │         VIEW-SPECIFIC CONTENT          │ │    Queue      │
│              │  │         (see view sections)            │ │               │
│              │  │                                        │ │               │
│              │  ├────────────────────────────────────────┤ │               │
│              │  │  CONTROLS BAR                          │ │               │
│              │  │  Filters, Search, Time Navigation      │ │               │
│              │  └────────────────────────────────────────┘ │               │
│              │                                              │               │
└──────────────┴──────────────────────────────────────────────┴───────────────┘
```

### Event Data Sources

Timeline Mode aggregates events from multiple persistent sources:

| Source | Table | Event Types | Timestamps |
|--------|-------|-------------|------------|
| **Commands** | `command_logs` | sent, verified, failed, rejected | `sent_at`, `verified_at` |
| **Alarms** | `alarm_events` | triggered, acknowledged, cleared, shelved, escalated | `inserted_at` |
| **Procedures** | `procedure_executions` | started, paused, completed, failed, cancelled | `started_at`, `completed_at` |
| **Automations** | `automation_executions` | triggered, completed, failed | `started_at`, `completed_at` |
| **Queue** | `command_queue_entries` | enqueued, executing, completed, cancelled | `scheduled_at`, `inserted_at` |
| **Schedules** | `schedules` | (future events) | `next_run_at` |

### Real-time Updates

Subscribe to existing PubSub topics for live streaming:

```elixir
# Topics to subscribe
"mission:#{mission_id}:alarms"       # Alarm lifecycle events
"mission:#{mission_id}:procedures"   # Procedure execution events
"mission:#{mission_id}:automations"  # Automation triggers
"mission:#{mission_id}:events"       # General events (limits, connections)
```

## View Designs

Timeline Mode offers three complementary views, each optimized for different cognitive tasks.

---

### View 1: STREAM

The primary real-time operational view. Events flow chronologically with smart aggregation for high-volume scenarios.

#### Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ▲ FUTURE                                                                   │
│  │                                                                          │
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ◇ 14:45:00 UTC  SCHEDULED                                           ││
│  │  │   CMD   SET_SAFE_MODE → 12 targets (Plane 7)              [EXPAND ▼]││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ◇ 14:30:00 UTC  SCHEDULED                                           ││
│  │  │   PROC  Daily Health Check → 847 targets                  [EXPAND ▼]││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │                                                                          │
│ ════════════════════════════ NOW 14:23:47 UTC ═════════════════════════════│
│  │                                                                          │
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ● 14:23:41 UTC  6s ago                                              ││
│  │  │   CMD   BEACON_RATE_HIGH → SAT-1847                     ✓ VERIFIED  ││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ● 14:23:38 UTC  9s ago                                    ▼ EXPAND  ││
│  │  │   CMD   BEACON_RATE_HIGH → 23 targets                   ✓ 23/23    ││
│  │  │   ├─ SAT-1842, SAT-1843, SAT-1844, ... (Plane 12)                   ││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ● 14:23:12 UTC  35s ago                                             ││
│  │  │   ALM   THERMAL_HIGH → SAT-0892                         ⚠ ACTIVE   ││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ● 14:22:58 UTC  49s ago                                             ││
│  │  │   PROC  Momentum Dump Complete → SAT-2201              ✓ COMPLETED  ││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  │ ● 14:22:44 UTC  1m ago                                    ✖ FAILED  ││
│  │  │   CMD   ANTENNA_SLEW → SAT-0341                        [DETAILS →] ││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │                                                                          │
│  ▼ PAST                                                                     │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ [🔍 Search...]  │ ☑CMD ☑ALM ☑PROC ☑AUTO │ Target:[All ▼] │ [⏸PAUSE] [↑NOW] │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Event Card Anatomy

```
┌─────────────────────────────────────────────────────────────────┐
│ [STATUS]  [TIMESTAMP] UTC  [RELATIVE]                 [ACTIONS]│
│   TYPE    [EVENT DESCRIPTION] → [TARGET]                [BADGE]│
│   [EXPANSION CONTENT - targets, parameters, etc.]              │
└─────────────────────────────────────────────────────────────────┘

STATUS:     ● (past event)  ◇ (future/scheduled)
TYPE:       CMD  ALM  PROC  AUTO  SYS
BADGE:      ✓ VERIFIED  ⚠ ACTIVE  ✖ FAILED  ◷ PENDING
```

#### Smart Aggregation Rules

When multiple similar events occur within a configurable time window:

1. **Batch Commands** - Same command sent to multiple targets within 5s
   - Collapse to single row showing count: "SET_MODE → 47 targets"
   - Expandable to show individual targets and their statuses

2. **Alarm Storms** - Multiple alarms from same condition
   - Group by alarm definition showing affected target count

3. **Scheduled Batches** - Commands scheduled for same time
   - Show as single future event with target count

#### Aggregation Display

```
┌─────────────────────────────────────────────────────────────────┐
│ ● 14:23:38 UTC  9s ago                              [▼ EXPAND] │
│   CMD   BEACON_RATE_HIGH → 23 targets              ✓ 23/23    │
├─────────────────────────────────────────────────────────────────┤
│ EXPANDED:                                                       │
│   ├─ SAT-1842  ✓ verified  Δt: 2.1s                            │
│   ├─ SAT-1843  ✓ verified  Δt: 2.3s                            │
│   ├─ SAT-1844  ✓ verified  Δt: 1.9s                            │
│   ├─ SAT-1845  ✓ verified  Δt: 2.4s                            │
│   │  ... 17 more ...                               [SHOW ALL]  │
│   └─ SAT-1864  ✓ verified  Δt: 3.1s                            │
└─────────────────────────────────────────────────────────────────┘
```

#### Live Streaming Behavior

- **Auto-scroll**: When at NOW marker, new events push timeline down
- **Pause Mode**: Freeze display for investigation; badge shows queued event count
- **Resume**: Catch up with queued events, optionally animate or instant

#### Stream Controls

| Control | Function |
|---------|----------|
| Event Type Toggles | Filter by CMD, ALM, PROC, AUTO, SYS |
| Target Filter | Dropdown/search for specific targets or groups |
| Search | Full-text search across event descriptions |
| Pause/Resume | Freeze timeline for investigation |
| Jump to NOW | Scroll to present moment |
| Density Slider | Adjust aggregation aggressiveness |

---

### View 2: MATRIX

Fleet-wide pattern recognition view. Time flows horizontally, targets/groups vertically.

#### Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  TIME →     13:00  13:15  13:30  13:45  14:00  14:15  NOW   14:30   14:45  │
│  ─────────────────────────────────────────────────────│─────────────────── │
│                                                       │                     │
│  PLANE 1    ·· ·   ·      ··     ·      ···    ··    │  ◇      ◇◇         │
│  PLANE 2    ·      ··     ·      ··     ·      ···   │  ◇◇     ◇          │
│  PLANE 3    ···    ·      ···    ●!     ··     ·     │  ◇      ◇          │
│  PLANE 4    ·      ·      ·      ·      ·      ··    │  ◇◇◇    ◇◇         │
│  PLANE 5    ··     ···    ·      ·      ··     ·     │  ◇                  │
│  PLANE 6    ·      ·      ··     ··     ·      ···   │                     │
│  PLANE 7    ·      ·      ·      ·      ·      ·     │  ◇◇◇◇◇◇◇◇◇◇◇◇      │
│  PLANE 8    ·      ··     ·      ·      ···    ··    │  ◇      ◇          │
│  ...                                                  │                     │
│                                                       │                     │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  LEGEND:  · cmd  ● alarm  ▲ proc  ◇ scheduled  ! error   [hover for detail]│
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  SELECTION: PLANE 3 @ 13:45                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ● ALM   THERMAL_HIGH → SAT-0892       Triggered, Value: 87.3°C    │   │
│  │  · CMD   HEATER_OFF → SAT-0892         ✓ Verified                  │   │
│  │  · CMD   SAFE_MODE → SAT-0892          ✓ Verified                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ Group by: [Plane ▼]  │  Bucket: [15m ▼]  │  Show: [All Types ▼]  │ [EXPORT]│
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Visual Encoding

| Symbol | Meaning | Color |
|--------|---------|-------|
| `·` | Command (normal) | Cyan |
| `●` | Alarm event | Amber |
| `▲` | Procedure event | Violet |
| `◆` | Automation event | Teal |
| `◇` | Scheduled/future | Dim (any type) |
| `!` | Error/failure modifier | Red |

#### Density Encoding

Cell density indicates activity level:
- Empty: No events
- Sparse (1-3 symbols): Low activity
- Dense (4+ symbols): High activity, symbols may overlap
- Hover reveals exact count and breakdown

#### Grouping Options

| Group By | Use Case |
|----------|----------|
| Orbital Plane | Standard constellation view |
| Region | Geographic operations focus |
| Subsystem | Cross-target subsystem health |
| Target (individual) | Detailed per-target rows |
| Custom Groups | User-defined target sets |

#### Time Bucket Options

| Bucket | Use Case |
|--------|----------|
| 5 minutes | High-resolution recent activity |
| 15 minutes | Standard operational view |
| 1 hour | Shift-level overview |
| 4 hours | Daily pattern analysis |

#### Interaction

- **Hover cell**: Tooltip with event count breakdown
- **Click cell**: Populate selection panel with cell's events
- **Click row header**: Filter Stream view to that group
- **Drag to select**: Multi-cell selection for bulk investigation

---

### View 3: LANES

Horizontal swimlane view for target-specific forensic investigation and correlation.

#### Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  TIME →    -2h         -1h         -30m        NOW         +30m        +1h │
│  ─────────────────────────────────────────────────│───────────────────────  │
│                                                   │                         │
│  ┌─ SAT-0892 ─────────────────────────────────────│───────────────────────┐│
│  │  (WATCH)   ───●───────CMD────CMD───ALM!────────│────◇PROC────────────  ││
│  │                    HEATER   SAFE   THERM       │    Health              ││
│  └────────────────────────────────────────────────│───────────────────────┘│
│                                                   │                         │
│  ┌─ SAT-0893 ─────────────────────────────────────│───────────────────────┐│
│  │             ───────────────CMD─────────────────│────◇PROC────────────  ││
│  │                           BEACON               │    Health              ││
│  └────────────────────────────────────────────────│───────────────────────┘│
│                                                   │                         │
│  ┌─ SAT-0894 ─────────────────────────────────────│───────────────────────┐│
│  │             ─────CMD───────────────────────────│────◇PROC────────────  ││
│  │                  SLEW                          │    Health              ││
│  └────────────────────────────────────────────────│───────────────────────┘│
│                                                   │                         │
│  ─────────────────────────────────────────────────│───────────────────────  │
│                                                   │                         │
│  ┌─ FLEET SUMMARY ────────────────────────────────│───────────────────────┐│
│  │  ▁▂▃▄▅▆▇ activity     ▁▁▁▂▁▁▁ alarms     ▁▁▁▁▁▂▃ scheduled            ││
│  └────────────────────────────────────────────────│───────────────────────┘│
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  EVENT DETAIL: CMD HEATER_OFF @ 13:42:17                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Target: SAT-0892  │  Status: ✓ Verified  │  Operator: jsmith       │   │
│  │  Parameters: { zone: "BATTERY", power: 0 }                          │   │
│  │  Verification: mode_flag == 0x04 (actual: 0x04) in 2.3s            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ Pinned: SAT-0892 ✕  SAT-0893 ✕  SAT-0894 ✕  │ [+ Add Lane] │ Zoom: [══●══] │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Lane Features

- **Persistent pins**: Pinned targets persist across view switches and sessions
- **Watch badges**: Mark targets as "watching" for visual priority
- **Vertical alignment**: Events at same time align across lanes for correlation
- **Fleet summary**: Sparkline showing overall activity for context

#### Adding Lanes

Multiple methods to add targets:
1. **Search**: Type target name in "Add Lane" input
2. **From Stream**: Right-click event → "Pin target to Lanes"
3. **From Matrix**: Click row → "Pin to Lanes"
4. **From Alarms panel**: Pin alarming targets

#### Event Markers on Lane

```
Lane timeline:
───●───────CMD────CMD───ALM!────────│────◇PROC────────────
   │         │     │     │          │      │
   │         │     │     │          │      └─ Scheduled procedure
   │         │     │     │          └─ NOW marker
   │         │     │     └─ Alarm with error indicator
   │         │     └─ Command (labeled)
   │         └─ Command (labeled)
   └─ Historical marker (older event)
```

#### Zoom Levels

| Zoom | Time Span | Resolution | Use Case |
|------|-----------|------------|----------|
| Maximum | ±15 min | Seconds | Real-time monitoring |
| High | ±1 hour | Minutes | Recent activity |
| Medium | ±4 hours | 5 minutes | Shift view |
| Low | ±12 hours | 15 minutes | Daily patterns |
| Minimum | ±24 hours | 1 hour | Full day review |

---

## Event Detail Panel

When an event is selected in any view, show detailed information:

```
┌─────────────────────────────────────────────────────────────────┐
│ COMMAND: SET_BEACON_RATE                                        │
│ ════════════════════════════════════════════════════════════════│
│                                                                 │
│ ┌─ TIMING ──────────────┐  ┌─ STATUS ────────────────────────┐ │
│ │ Sent:     14:23:41.234│  │ ✓ VERIFIED                      │ │
│ │ Verified: 14:23:44.456│  │   Verification time: 3.2s       │ │
│ │ Δt:       3.222s      │  │                                 │ │
│ └───────────────────────┘  └─────────────────────────────────┘ │
│                                                                 │
│ ┌─ TARGET ──────────────┐  ┌─ OPERATOR ──────────────────────┐ │
│ │ SAT-1847              │  │ jsmith@spaceco.com              │ │
│ │ Plane 12, Slot 23     │  │                                 │ │
│ │ [VIEW TARGET]         │  │                                 │ │
│ └───────────────────────┘  └─────────────────────────────────┘ │
│                                                                 │
│ ┌─ PARAMETERS ──────────────────────────────────────────────┐  │
│ │ rate_hz:     10                                           │  │
│ │ duration_s:  3600                                         │  │
│ └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ┌─ VERIFICATION ────────────────────────────────────────────┐  │
│ │ Stage 1: beacon_mode                                      │  │
│ │   Expected: 0x0A    Actual: 0x0A    ✓ PASS               │  │
│ │                                                           │  │
│ │ Stage 2: beacon_rate                                      │  │
│ │   Expected: 10      Actual: 10      ✓ PASS               │  │
│ └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ┌─ ACTIONS ─────────────────────────────────────────────────┐  │
│ │ [VIEW RAW BINARY]  [CORRELATE]  [PIN TARGET]  [COPY ID]  │  │
│ └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Controls Bar

Persistent controls at the bottom of the mode content area:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌─ VIEW ─────┐  ┌─ FILTERS ────────────────────┐  ┌─ TIME NAV ──────────┐ │
│  │[STR][MTX][LN]│  │☑CMD ☑ALM ☑PROC ☑AUTO ☐SYS │  │[◀][14:23 UTC][▶][NOW]│ │
│  └─────────────┘  │Target: [All ▼] [🔍 Search] │  │[PAUSE ⏸] [⏱ 15m ▼] │ │
│                   └─────────────────────────────┘  └─────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Control Descriptions

| Control | Description |
|---------|-------------|
| View Tabs | Switch between STREAM, MATRIX, LANES |
| Event Type Toggles | Filter by event category |
| Target Filter | Dropdown with search, supports multi-select |
| Search | Full-text search across events |
| Time Navigation | Manual time scrubbing |
| NOW Button | Jump to present |
| Pause | Freeze live updates |
| Time Range | Quick presets (15m, 1h, 4h, 8h, 24h, custom) |

---

## HUD Visual Design

Consistent with ops-v2 mission control aesthetic.

### Color Palette

| Element | Color | Hex | Usage |
|---------|-------|-----|-------|
| Commands | Cyan | `#22d3ee` | CMD badges, markers |
| Alarms | Amber | `#fbbf24` | ALM badges, markers |
| Procedures | Violet | `#a78bfa` | PROC badges, markers |
| Automations | Teal | `#2dd4bf` | AUTO badges, markers |
| System | Gray | `#9ca3af` | SYS badges, markers |
| Success | Green | `#4ade80` | Verified, completed |
| Error | Red | `#f87171` | Failed, rejected |
| Warning | Yellow | `#facc15` | Pending, active alarm |
| Future | Dim | 50% opacity | Scheduled events |
| NOW marker | White | `#ffffff` | Time reference |

### Typography

| Element | Style |
|---------|-------|
| Timestamps | Monospace, `text-xs` |
| Event descriptions | Sans-serif, `text-sm` |
| Badges | Monospace, uppercase, `text-xs` |
| Target names | Monospace, `text-sm font-medium` |
| Panel headers | Sans-serif, uppercase, `text-xs tracking-wider` |

### Event Card Styling

```css
/* Base card */
.timeline-event-card {
  @apply bg-base-800/50 border border-base-700 rounded;
  @apply hover:border-base-600 hover:bg-base-800/70;
  @apply transition-colors duration-150;
}

/* Selected state */
.timeline-event-card.selected {
  @apply border-primary-500 bg-base-800/80;
}

/* Future event */
.timeline-event-card.future {
  @apply opacity-60 border-dashed;
}

/* Error state */
.timeline-event-card.error {
  @apply border-l-4 border-l-error-500;
}
```

### NOW Marker Styling

```css
.now-marker {
  @apply relative w-full h-8 flex items-center justify-center;
  @apply text-xs font-mono text-white/80;

  &::before, &::after {
    content: '';
    @apply flex-1 h-px bg-gradient-to-r from-transparent via-white/40 to-transparent;
  }
}
```

---

## Keyboard Shortcuts

| Key | Action | Context |
|-----|--------|---------|
| `j` / `↓` | Select next event | Stream |
| `k` / `↑` | Select previous event | Stream |
| `Enter` | Expand selected event | Stream |
| `Esc` | Collapse / deselect | All |
| `Space` | Toggle pause | All |
| `n` | Jump to NOW | All |
| `g` | Open go-to-time dialog | All |
| `/` | Focus search | All |
| `1` | Switch to Stream | All |
| `2` | Switch to Matrix | All |
| `3` | Switch to Lanes | All |
| `p` | Pin selected target | Stream, Matrix |
| `?` | Show keyboard help | All |

---

## Data Layer

### Unified Event Query

Create a context module for querying across event sources:

```elixir
defmodule Cadence.Timeline do
  @moduledoc """
  Unified timeline queries across all event sources.
  """

  @type event_type :: :command | :alarm | :procedure | :automation | :system

  @type timeline_event :: %{
    id: binary(),
    type: event_type(),
    timestamp: DateTime.t(),
    target_id: binary() | nil,
    target_name: String.t() | nil,
    title: String.t(),
    description: String.t(),
    status: atom(),
    user_id: binary() | nil,
    metadata: map(),
    source_id: binary(),
    source_table: atom()
  }

  @doc """
  Fetch timeline events for a mission within a time range.

  Options:
    - :types - list of event types to include (default: all)
    - :target_ids - filter to specific targets
    - :statuses - filter by status
    - :limit - max events to return
    - :include_future - include scheduled events (default: true)
  """
  @spec list_events(binary(), DateTime.t(), DateTime.t(), keyword()) :: [timeline_event()]
  def list_events(mission_id, start_time, end_time, opts \\ [])

  @doc """
  Subscribe to real-time timeline events for a mission.
  """
  @spec subscribe(binary()) :: :ok
  def subscribe(mission_id)

  @doc """
  Aggregate events into time buckets for matrix view.
  """
  @spec aggregate_events(binary(), DateTime.t(), DateTime.t(), keyword()) :: map()
  def aggregate_events(mission_id, start_time, end_time, opts \\ [])
end
```

### Query Strategy

For efficient querying across multiple tables:

1. **Union Query** - Single query with UNION ALL across normalized subqueries
2. **Indexed by time** - All source tables have timestamp indexes
3. **Pagination** - Cursor-based for infinite scroll
4. **Caching** - Cache aggregations for Matrix view

```sql
-- Example unified query structure
WITH timeline_events AS (
  -- Commands
  SELECT
    id, 'command' as type, sent_at as timestamp,
    target_id, command_name as title, status, user_id
  FROM command_logs
  WHERE mission_id = $1 AND sent_at BETWEEN $2 AND $3

  UNION ALL

  -- Alarms
  SELECT
    ae.id, 'alarm' as type, ae.inserted_at as timestamp,
    a.target_id, a.name as title, ae.event_type as status, ae.user_id
  FROM alarm_events ae
  JOIN alarms a ON ae.alarm_id = a.id
  WHERE a.mission_id = $1 AND ae.inserted_at BETWEEN $2 AND $3

  UNION ALL

  -- Procedures
  SELECT
    id, 'procedure' as type, started_at as timestamp,
    target_id, (SELECT name FROM procedures WHERE id = procedure_id) as title,
    status, triggered_by_user_id as user_id
  FROM procedure_executions
  WHERE mission_id = $1 AND started_at BETWEEN $2 AND $3

  -- ... automations, etc.
)
SELECT * FROM timeline_events
ORDER BY timestamp DESC
LIMIT $4;
```

### Real-time Event Struct

```elixir
defmodule Cadence.Timeline.Event do
  @moduledoc """
  Normalized timeline event for UI consumption.
  """

  defstruct [
    :id,
    :type,           # :command | :alarm | :procedure | :automation | :system
    :timestamp,
    :target_id,
    :target_name,
    :target_group,   # e.g., "Plane 12"
    :title,          # e.g., "SET_BEACON_RATE"
    :description,    # e.g., "Verified in 3.2s"
    :status,         # :pending | :success | :error | :active | etc.
    :severity,       # :info | :warning | :critical
    :user_id,
    :user_name,
    :is_future,      # true for scheduled events
    :metadata,       # type-specific details
    :source_id,      # original record ID
    :source_table    # for drill-down queries
  ]
end
```

---

## Implementation Phases

### Phase 1: Foundation + Stream View (Core)

**Goal**: Basic timeline with real-time updates

- [ ] Create `Cadence.Timeline` context module
- [ ] Implement unified event query (commands, alarms, procedures)
- [ ] Add Timeline Mode to ops-v2 mode switcher
- [ ] Build Stream view with basic event cards
- [ ] Implement NOW marker with scroll behavior
- [ ] Add event type filtering
- [ ] Subscribe to PubSub for live updates
- [ ] Basic event detail panel

**Deliverable**: Functional timeline showing live mission activity

### Phase 2: Stream View (Constellation Scale)

**Goal**: Handle high-volume scenarios gracefully

- [ ] Implement smart aggregation logic
- [ ] Build aggregated event cards with expand/collapse
- [ ] Add target filtering (dropdown with search)
- [ ] Implement pause/resume with event queuing
- [ ] Add density slider control
- [ ] Full-text search
- [ ] Performance optimization for 1000+ events

**Deliverable**: Stream view usable for large constellations

### Phase 3: Matrix View

**Goal**: Fleet-wide pattern recognition

- [ ] Build matrix grid component
- [ ] Implement time bucketing logic
- [ ] Add target grouping (by plane, region, custom)
- [ ] Visual density encoding
- [ ] Cell hover tooltips
- [ ] Cell click → event list
- [ ] Row header interactions
- [ ] NOW line rendering

**Deliverable**: Visual fleet overview with drill-down

### Phase 4: Lanes View

**Goal**: Target-specific forensic investigation

- [ ] Build horizontal swimlane component
- [ ] Implement target pinning system (persisted to user prefs)
- [ ] Event markers on lanes
- [ ] Vertical alignment across lanes
- [ ] Fleet summary sparkline
- [ ] Zoom controls
- [ ] Lane add/remove UI
- [ ] Click-to-detail on lane markers

**Deliverable**: Multi-target correlation view

### Phase 5: Polish + Power Features

**Goal**: Production-ready experience

- [ ] Keyboard shortcuts (full set)
- [ ] Time range presets
- [ ] Go-to-time dialog
- [ ] Deep linking (URL reflects view state)
- [ ] Export functionality (CSV, JSON)
- [ ] Bookmarks/markers system
- [ ] Performance profiling and optimization
- [ ] Accessibility review
- [ ] Documentation

**Deliverable**: Complete Timeline Mode ready for operators

---

## Future Considerations

### Additional Event Sources

- **Contact windows** - Ground station passes, visibility windows
- **Orbital events** - Eclipse entry/exit, conjunction warnings
- **Telemetry anomalies** - Out-of-limit events (currently trigger alarms)
- **User sessions** - Login/logout, active operators
- **System events** - Interface connections, deployments

### Enhanced Features

- **Annotations** - User-added notes on timeline ("investigation started here")
- **Shift markers** - Automatic shift change boundaries
- **Comparison mode** - Side-by-side comparison of two time ranges
- **Playback mode** - Replay historical events in real-time
- **AI insights** - Anomaly detection, pattern suggestions

### Performance at Scale

- **Event archival** - Move old events to cold storage
- **Materialized views** - Pre-computed aggregations for Matrix
- **Time-series database** - Consider TimescaleDB for event storage
- **CDN caching** - Cache static historical data

---

## Appendix: Operator Workflows

### Workflow 1: Shift Handoff

1. Open Timeline Mode
2. Matrix view, last 8 hours
3. Identify any red/error cells
4. Click to investigate anomalies
5. Pin any problem targets to Lanes
6. Review Lanes for recent activity
7. Export summary for handoff notes

### Workflow 2: Anomaly Investigation

1. Get alert about SAT-0892 thermal alarm
2. Open Timeline Mode, Stream view
3. Search for "SAT-0892"
4. See alarm and related commands
5. Pin SAT-0892 to Lanes
6. Zoom out to see historical context
7. Correlate with nearby satellites (add lanes)
8. Identify pattern, take action

### Workflow 3: Post-Event Analysis

1. "What happened during yesterday's firmware update?"
2. Matrix view, filter to time window
3. Group by plane, see rollout pattern
4. Click cells to see individual updates
5. Identify any failures, investigate in Lanes
6. Export data for report

### Workflow 4: Real-time Monitoring

1. Stream view, live mode
2. Filter to specific plane or target group
3. Watch commands flow through
4. Alarm appears, click to see details
5. Quick action via context panel
6. Return to monitoring

---

## References

- Cadence Ops Console V2: `lib/cadence_web/live/ops_console_v2_live/`
- Command Log Schema: `lib/cadence/commands/command_log.ex`
- Alarm Events Schema: `lib/cadence/alarms/schemas/alarm_event.ex`
- Procedure Execution Schema: `lib/cadence/procedures/schemas/procedure_execution.ex`
- Existing mode implementations: `assets/js/hooks/ops_console_v2_hook.js`
