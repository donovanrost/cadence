---
title: Contact Scheduling UI Design Document
aliases: [schedule mode, contact schedule, passes view]
tags: [design, ui, contacts, ops-console]
related:
  - "[[contact]]"
  - "[[ground-station]]"
  - "[[target]]"
  - "[[mission]]"
created: 2026-02-02
updated: 2026-02-02
status: draft
prerequisites:
  - Orbit propagation / ephemeris data (for automatic contact window generation)
---

# Contact Scheduling UI Design Document

## Overview

Schedule Mode is an ops-v2 mode that provides a constellation-level view of scheduled ground station contacts. Unlike Timeline Mode which shows past events, Schedule Mode is future-oriented, helping operators visualize and manage upcoming communication windows.

> **Note:** This design assumes contacts are **manually planned temporal ranges**. A future enhancement will integrate orbit propagation data to automatically generate contact windows based on ground station visibility.

### Design Goals

| Goal | Description |
|------|-------------|
| **Visibility Planning** | See all upcoming contacts across the constellation |
| **Conflict Detection** | Identify overlapping contacts and resource contention |
| **Ground Station Utilization** | Understand antenna/station usage patterns |
| **Pass Prioritization** | Quickly identify and manage high-priority passes |
| **Shift Handoff** | Enable quick situational awareness of upcoming operations |

### Target Users

- **Pass Planners** - Scheduling contacts across the constellation
- **Ground Station Operators** - Managing antenna time and conflicts
- **Constellation Operators** - Monitoring upcoming operations
- **Mission Managers** - Understanding operational tempo

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            OPS-V2 CONSOLE                                    │
├──────────────┬──────────────────────────────────────────────┬───────────────┤
│              │                                              │               │
│  NAVIGATION  │            SCHEDULE MODE                     │   CONTEXT     │
│    PANEL     │         (main content area)                  │    PANEL      │
│              │                                              │               │
│  - Mission   │  ┌────────────────────────────────────────┐ │  - Active     │
│  - Mode      │  │  [RIBBON] [PASSES]                     │ │    Alarms     │
│    Switcher  │  ├────────────────────────────────────────┤ │               │
│  - Dashboard │  │                                        │ │  - Conflicts  │
│    List      │  │         VIEW-SPECIFIC CONTENT          │ │    Summary    │
│              │  │         (see view sections)            │ │               │
│              │  │                                        │ │               │
│              │  ├────────────────────────────────────────┤ │               │
│              │  │  CONTROLS BAR                          │ │               │
│              │  │  Time Range, Filters, View Toggle      │ │               │
│              │  └────────────────────────────────────────┘ │               │
│              │                                              │               │
└──────────────┴──────────────────────────────────────────────┴───────────────┘
```

### Route Structure

```
/missions/:id/ops/schedule          # Ribbon view (default)
/missions/:id/ops/schedule/passes   # Next N passes cards
```

### Data Sources

Schedule Mode queries from the contacts system:

| Source | Table | Fields | Purpose |
|--------|-------|--------|---------|
| **Contacts** | `contacts` | start_time, end_time, state, priority | Scheduled contact windows |
| **Targets** | `targets` | name, status, type | Spacecraft identification |
| **Ground Stations** | `ground_station_profiles` | name, antenna, location | Station info for color coding |

### Real-time Updates

Subscribe to existing PubSub topics for live updates:

```elixir
# Topics to subscribe
"mission:#{mission_id}:contacts"     # Contact lifecycle events
"mission:#{mission_id}:alarms"       # Alarm events (for context panel)
```

## View Designs

Schedule Mode offers two complementary views optimized for different tasks.

---

### View 1: RIBBON

Spacecraft-centric horizontal timeline showing contacts as colored bars. The primary view for understanding contact coverage across the constellation.

#### Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  TIME →    -2h         NOW         +2h         +4h         +6h        +8h  │
│  ───────────────────────│────────────────────────────────────────────────── │
│                         │                                                   │
│  ┌─ SAT-001 ────────────│───────────────────────────────────────────────┐  │
│  │           ████████   │   ░░░░░░░░░░░░░░░░░           ████████        │  │
│  │           SVALBARD   │   SANTIAGO (pending)          MCMURDO         │  │
│  └──────────────────────│───────────────────────────────────────────────┘  │
│                         │                                                   │
│  ┌─ SAT-002 ────────────│───────────────────────────────────────────────┐  │
│  │                      │   ████████████████    ░░░░░░░░░░░░░           │  │
│  │                      │   FAIRBANKS           SVALBARD (conflict!)    │  │
│  └──────────────────────│───────────────────────────────────────────────┘  │
│                         │                                                   │
│  ┌─ SAT-003 ────────────│───────────────────────────────────────────────┐  │
│  │       ████████       │                   ████████████████████        │  │
│  │       MCMURDO        │                   SANTIAGO                    │  │
│  └──────────────────────│───────────────────────────────────────────────┘  │
│                         │                                                   │
│  ───────────────────────│────────────────────────────────────────────────── │
│                         │                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  SELECTED: SAT-002 → SVALBARD  14:30-14:45 UTC                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Duration: 15 min  │  Direction: ⇅ BIDIR  │  Priority: 3           │   │
│  │  ⚠ CONFLICT: Overlaps with SAT-004 → SVALBARD (antenna contention)  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ [RIBBON][PASSES] │ Range: [12h ▼] │ Filter: [All ▼] │ [◀][▶] [NOW] [+ NEW] │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Contact Bar Anatomy

```
┌─────────────────────────────────────────────────────────┐
│ ████████████████████████████████████████████████████████│  ← Solid fill
│ GROUND-STATION-NAME    ↑15m                             │  ← Label + duration
└─────────────────────────────────────────────────────────┘
  │                      │
  │                      └─ Direction icon (↑ uplink, ↓ downlink, ⇅ bidir)
  └─ Position based on start_time, width based on duration

Bar styles:
  ████████  Solid = active or confirmed contact
  ░░░░░░░░  Dashed/dim = pending or planned
  ▓▓▓▓▓▓▓▓  Hatched = conflict (overlapping with another)
```

#### Ground Station Color Coding

Each ground station gets a distinct color from the HUD palette:

| Station | Color | CSS Variable |
|---------|-------|--------------|
| Station 1 | Cyan | `--contact-station-1` |
| Station 2 | Violet | `--contact-station-2` |
| Station 3 | Teal | `--contact-station-3` |
| Station 4 | Amber | `--contact-station-4` |
| Station 5+ | Rotating | `--contact-station-n` |

#### Conflict Visualization

Conflicts are visually emphasized:
- **Dashed border** around conflicting contact bars
- **Glow effect** on hover
- **Warning icon** in lane header if any conflicts exist
- **Detail panel** explains the conflict type

Conflict types:
1. **Antenna contention** - Same ground station, overlapping time
2. **Spacecraft overlap** - Same spacecraft, overlapping contacts
3. **Priority conflict** - Lower priority contact blocking higher

#### Scrubber / NOW Marker

```
                              │
                              │  ← Vertical line
                              │
                         ┌────┴────┐
                         │   NOW   │  ← Label with current time
                         └─────────┘
```

- Draggable to pan the timeline
- Double-click to jump to current time
- Animates smoothly when time advances

---

### View 2: PASSES

Card-based list of upcoming contacts, sorted by start time. Optimized for quick scanning and pass management.

#### Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  UPCOMING PASSES                                          Showing 24 of 156 │
│                                                                             │
│  ┌─────────────────────────────────────┐  ┌─────────────────────────────────┐
│  │ SAT-001 → SVALBARD (ANT-1)          │  │ SAT-002 → FAIRBANKS             │
│  │ 14:30 - 14:45 UTC  (15 min)         │  │ 14:32 - 14:50 UTC  (18 min)     │
│  │ ⇅ BIDIRECTIONAL   Priority: 3       │  │ ↓ DOWNLINK ONLY   Priority: 2   │
│  │ ✓ No conflicts                      │  │ ✓ No conflicts                  │
│  └─────────────────────────────────────┘  └─────────────────────────────────┘
│                                                                             │
│  ┌─────────────────────────────────────┐  ┌─────────────────────────────────┐
│  │ SAT-003 → SANTIAGO                  │  │ SAT-001 → MCMURDO               │
│  │ 14:45 - 15:02 UTC  (17 min)         │  │ 15:00 - 15:20 UTC  (20 min)     │
│  │ ↑ UPLINK ONLY     Priority: 1       │  │ ⇅ BIDIRECTIONAL   Priority: 3   │
│  │ ⚠ Conflicts with CONTACT-42         │  │ ✓ No conflicts                  │
│  └─────────────────────────────────────┘  └─────────────────────────────────┘
│                                                                             │
│  ┌─────────────────────────────────────┐  ┌─────────────────────────────────┐
│  │ SAT-004 → SVALBARD (ANT-2)          │  │ SAT-002 → SVALBARD (ANT-1)      │
│  │ 15:10 - 15:25 UTC  (15 min)         │  │ 15:15 - 15:30 UTC  (15 min)     │
│  │ ⇅ BIDIRECTIONAL   Priority: 2       │  │ ⇅ BIDIRECTIONAL   Priority: 3   │
│  │ ✓ No conflicts                      │  │ ⚠ CONFLICT: Antenna contention  │
│  └─────────────────────────────────────┘  └─────────────────────────────────┘
│                                                                             │
│  [Load more...]                                                             │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ [RIBBON][PASSES] │ Filter: [All ▼] │ Sort: [Time ▼] │ [+ NEW CONTACT]       │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Pass Card Anatomy

```
┌─────────────────────────────────────────┐
│ SPACECRAFT → GROUND-STATION (ANTENNA)   │  ← Header
│ START - END UTC  (DURATION)             │  ← Time info
│ DIRECTION-ICON DIRECTION   Priority: N  │  ← Metadata
│ STATUS-ICON STATUS/CONFLICT INFO        │  ← Status line
└─────────────────────────────────────────┘
```

Direction icons:
- `↑` Uplink only
- `↓` Downlink only
- `⇅` Bidirectional

Status icons:
- `✓` No conflicts (green)
- `⚠` Has conflicts (amber)
- `●` Active/in-progress (cyan pulse)

#### Sorting Options

| Sort | Description |
|------|-------------|
| Time (default) | Chronological by start_time |
| Spacecraft | Grouped by spacecraft, then time |
| Ground Station | Grouped by station, then time |
| Priority | Highest priority first |
| Duration | Longest passes first |

#### Filtering Options

| Filter | Options |
|--------|---------|
| Spacecraft | All, specific spacecraft, or group |
| Ground Station | All or specific station |
| Direction | All, Uplink, Downlink, Bidirectional |
| State | Planned, Confirmed, Active, Completed |
| Conflicts | All, Conflicts only, No conflicts |

---

## Contact Detail Panel

When a contact is selected in either view:

```
┌─────────────────────────────────────────────────────────────────┐
│ CONTACT: SAT-002 → SVALBARD                                     │
│ ════════════════════════════════════════════════════════════════│
│                                                                 │
│ ┌─ TIMING ──────────────┐  ┌─ STATUS ────────────────────────┐ │
│ │ Start:    14:30:00 UTC│  │ State: PLANNED                  │ │
│ │ End:      14:45:00 UTC│  │ Direction: ⇅ Bidirectional      │ │
│ │ Duration: 15 minutes  │  │ Priority: 3                     │ │
│ └───────────────────────┘  └─────────────────────────────────┘ │
│                                                                 │
│ ┌─ SPACECRAFT ────────────┐  ┌─ GROUND STATION ──────────────┐ │
│ │ SAT-002                 │  │ SVALBARD                       │ │
│ │ Status: NOMINAL         │  │ Antenna: ANT-1                 │ │
│ │ [VIEW TARGET]           │  │ Location: 78.2°N, 15.6°E      │ │
│ └─────────────────────────┘  └───────────────────────────────┘ │
│                                                                 │
│ ┌─ CONFLICTS ─────────────────────────────────────────────────┐│
│ │ ⚠ ANTENNA CONTENTION                                        ││
│ │   Overlaps with: SAT-004 → SVALBARD (ANT-1)                ││
│ │   Overlap window: 14:30 - 14:35 (5 min)                    ││
│ │   Recommendation: Shift SAT-004 contact by +10 min         ││
│ │                                                             ││
│ │   [RESOLVE] [IGNORE] [VIEW OTHER CONTACT]                  ││
│ └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│ ┌─ ACTIONS ─────────────────────────────────────────────────┐  │
│ │ [EDIT] [DUPLICATE] [DELETE] [VIEW IN RIBBON]              │  │
│ └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Controls Bar

Persistent controls at the bottom of the mode content area:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌─ VIEW ─────┐  ┌─ TIME RANGE ──────────┐  ┌─ TIME NAV ──────────────────┐│
│  │[RBN][PASS] │  │ [12h ▼] [24h] [48h] [7d]│  │ [◀] [14:23 UTC] [▶] [NOW] ││
│  └────────────┘  └───────────────────────┘  └─────────────────────────────┘│
│                                                                             │
│  ┌─ FILTERS ──────────────────────────────┐  ┌─ ACTIONS ─────────────────┐ │
│  │ Spacecraft: [All ▼]  Station: [All ▼] │  │ [+ NEW CONTACT]           │ │
│  └────────────────────────────────────────┘  └───────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Time Range Options

| Range | Use Case |
|-------|----------|
| 12 hours | Immediate operations planning |
| 24 hours | Daily schedule overview |
| 48 hours | Short-term planning |
| 7 days | Weekly schedule view |

---

## HUD Visual Design

Consistent with ops-v2 mission control aesthetic.

### Color Palette

| Element | Color | Hex | Usage |
|---------|-------|-----|-------|
| Contact bar (active) | Station color | varies | Confirmed contacts |
| Contact bar (pending) | Station color @ 50% | varies | Planned contacts |
| Conflict indicator | Amber | `#fbbf24` | Overlapping contacts |
| NOW marker | White | `#ffffff` | Current time reference |
| Selected | Primary | `#22d3ee` | Selected contact |
| Lane background | Base 800 | `#1f2937` | Spacecraft row |
| Lane header | Base 700 | `#374151` | Spacecraft name area |

### Typography

| Element | Style |
|---------|-------|
| Timestamps | Monospace, `text-xs` |
| Contact labels | Sans-serif, `text-sm` |
| Duration | Monospace, `text-xs` |
| Spacecraft names | Monospace, `text-sm font-medium` |
| Panel headers | Sans-serif, uppercase, `text-xs tracking-wider` |

### Contact Bar Styling

```css
/* Base contact bar */
.contact-bar {
  @apply absolute h-6 rounded-sm;
  @apply flex items-center justify-center;
  @apply text-xs font-medium text-white;
  @apply transition-all duration-150;
  min-width: 20px; /* Minimum visible width for short contacts */
}

/* Pending/planned state */
.contact-bar.pending {
  @apply opacity-60 border border-dashed;
}

/* Conflict state */
.contact-bar.conflict {
  @apply border-2 border-warning-500;
  box-shadow: 0 0 8px rgba(251, 191, 36, 0.4);
}

/* Selected state */
.contact-bar.selected {
  @apply ring-2 ring-primary-500 ring-offset-1 ring-offset-base-900;
}

/* Hover state */
.contact-bar:hover {
  @apply brightness-110 cursor-pointer;
}
```

### NOW Marker Styling

```css
.schedule-now-marker {
  @apply absolute top-0 bottom-0 w-px bg-white z-10;
  @apply pointer-events-none;
}

.schedule-now-label {
  @apply absolute -top-6 left-1/2 -translate-x-1/2;
  @apply px-2 py-0.5 bg-white text-base-900;
  @apply text-xs font-mono rounded;
}
```

---

## Keyboard Shortcuts

| Key | Action | Context |
|-----|--------|---------|
| `j` / `→` | Next contact | Both views |
| `k` / `←` | Previous contact | Both views |
| `Enter` | Open contact detail | Both views |
| `Esc` | Close detail / deselect | Both views |
| `n` | Jump to NOW | Ribbon |
| `[` / `]` | Pan timeline left/right | Ribbon |
| `+` / `-` | Zoom in/out | Ribbon |
| `1` | Switch to Ribbon | Both views |
| `2` | Switch to Passes | Both views |
| `c` | Create new contact | Both views |
| `e` | Edit selected contact | Both views |
| `d` | Delete selected contact | Both views |
| `?` | Show keyboard help | Both views |

---

## Component Architecture

### Files to Create

| File | Purpose |
|------|---------|
| `lib/cadence_web/live/ops_console_live/schedule.ex` | Main LiveView |
| `lib/cadence_web/live/ops_console_live/schedule/components.ex` | Schedule-specific components |
| `assets/css/modes/schedule-mode.css` | Schedule mode styling |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/cadence_web/router.ex` | Add schedule routes under ops_console live_session |
| `assets/css/app.css` | Import schedule-mode.css |

### Component Breakdown

#### Main LiveView Assigns

```elixir
defmodule CadenceWeb.OpsConsoleLive.Schedule do
  # Socket assigns
  @type assigns :: %{
    contacts: [Contact.t()],
    spacecraft_targets: [Target.t()],
    ground_station_targets: [Target.t()],
    profiles_by_station: %{station_id => [GroundStationProfile.t()]},
    conflicts: [ContactValidator.conflict()],
    hard_errors: [ContactValidator.error()],
    time_range: String.t(),           # "12h", "24h", "48h", "7d"
    offset_minutes: integer(),         # Pan offset from now
    selected_contact: Contact.t() | nil,
    selected_spacecraft: Target.t() | nil,
    current_time: DateTime.t()
  }
end
```

#### Ribbon View Components

```
schedule_ribbon_view/1
├── schedule_controls/1          # Time range, filters, view toggle
├── schedule_time_axis/1         # Hour markers across top
├── spacecraft_lane/1            # Per-spacecraft row
│   ├── lane_header/1            # Spacecraft name/status
│   └── lane_track/1             # Contains contact bars
│       └── contact_bar/1        # Individual contact (positioned + sized)
├── schedule_scrubber/1          # NOW marker + drag interaction
└── contact_detail_panel/1       # Selected contact details
```

#### Passes View Components

```
schedule_passes_view/1
├── schedule_controls/1          # Shared controls
├── passes_filter/1              # Additional filtering
└── passes_grid/1                # Card grid
    └── pass_card/1              # Individual contact card
```

---

## Data Loading

```elixir
defp load_schedule_data(socket, mission_id) do
  org_id = socket.assigns.current_scope.current_organization.id
  window = calculate_time_window(socket.assigns)

  # Load contacts for time window
  contacts = Contacts.list_contacts(org_id,
    mission_id: mission_id,
    state: [:planned, :confirmed, :active],
    overlapping: {window.start_time, window.end_time}
  )

  # Load targets, split by type
  targets = Targets.list_targets_with_preloads(mission_id)
  {spacecraft, ground_stations} = Enum.split_with(targets, &(&1.type == :spacecraft))

  # Load ground station profiles
  profiles = GroundStations.list_enabled_profiles(mission_id)
  profiles_by_station = Enum.group_by(profiles, & &1.ground_station_id)

  # Validate contacts for conflicts
  validation = ContactValidator.validate(org_id, mission_id, contacts)

  socket
  |> assign(:contacts, contacts)
  |> assign(:spacecraft_targets, spacecraft)
  |> assign(:ground_station_targets, ground_stations)
  |> assign(:profiles_by_station, profiles_by_station)
  |> assign(:conflicts, validation.conflicts)
  |> assign(:hard_errors, validation.hard_errors)
end

defp calculate_time_window(assigns) do
  current_time = assigns.current_time || DateTime.utc_now()
  range_hours = parse_time_range(assigns.time_range)
  offset_minutes = assigns.offset_minutes || 0

  anchor_time = DateTime.add(current_time, offset_minutes, :minute)

  # Show 20% past, 80% future for schedule view
  past_hours = range_hours * 0.2
  future_hours = range_hours * 0.8

  %{
    start_time: DateTime.add(anchor_time, -trunc(past_hours * 60), :minute),
    end_time: DateTime.add(anchor_time, trunc(future_hours * 60), :minute)
  }
end
```

---

## JS Hooks

Adapt from existing Timeline Lanes hooks:

### ScheduleScrubber Hook

```javascript
// .ScheduleScrubber - Timeline panning and NOW marker
export default {
  mounted() {
    this.isDragging = false
    this.startX = 0
    this.startOffset = 0

    this.el.addEventListener('mousedown', this.startDrag.bind(this))
    document.addEventListener('mousemove', this.onDrag.bind(this))
    document.addEventListener('mouseup', this.endDrag.bind(this))

    // Double-click to jump to NOW
    this.el.addEventListener('dblclick', () => {
      this.pushEvent('jump_to_now', {})
    })
  },

  startDrag(event) {
    this.isDragging = true
    this.startX = event.clientX
    this.pushEvent('scrub_state', { dragging: true })
  },

  onDrag(event) {
    if (!this.isDragging) return
    const deltaX = event.clientX - this.startX
    const intensity = Math.abs(deltaX) / 50
    const direction = deltaX < 0 ? 'forward' : 'back'
    this.pushEvent('pan_schedule', { direction, intensity })
    this.startX = event.clientX
  },

  endDrag() {
    if (!this.isDragging) return
    this.isDragging = false
    this.pushEvent('scrub_state', { dragging: false })
  }
}
```

### ContactSelection Hook

```javascript
// .ContactSelection - Click to select, hover for conflict highlight
export default {
  mounted() {
    this.el.addEventListener('click', this.selectContact.bind(this))
    this.el.addEventListener('mouseenter', this.highlightConflicts.bind(this))
    this.el.addEventListener('mouseleave', this.clearHighlights.bind(this))
  },

  selectContact() {
    const contactId = this.el.dataset.contactId
    this.pushEvent('select_contact', { id: contactId })
  },

  highlightConflicts() {
    const conflictIds = JSON.parse(this.el.dataset.conflictIds || '[]')
    conflictIds.forEach(id => {
      const el = document.querySelector(`[data-contact-id="${id}"]`)
      if (el) el.classList.add('conflict-highlight')
    })
  },

  clearHighlights() {
    document.querySelectorAll('.conflict-highlight').forEach(el => {
      el.classList.remove('conflict-highlight')
    })
  }
}
```

---

## Implementation Phases

### Phase 1: MVP Ribbon View

**Goal**: Basic schedule visualization

- [ ] Create route and basic LiveView structure
- [ ] Implement spacecraft lane rendering
- [ ] Render contact bars with position and width calculation
- [ ] Add time axis with hour markers
- [ ] Basic styling with ground station colors
- [ ] NOW marker (static)

**Deliverable**: Viewable schedule ribbon

### Phase 2: Conflict Visualization

**Goal**: Identify and display scheduling conflicts

- [ ] Integrate ContactValidator for conflict detection
- [ ] Add conflict styling (dashed border, glow)
- [ ] Implement contact selection
- [ ] Build contact detail panel
- [ ] Hover highlight for related conflicts

**Deliverable**: Conflict-aware schedule view

### Phase 3: Interactivity

**Goal**: Full timeline navigation

- [ ] Implement ScheduleScrubber hook for panning
- [ ] Add time range controls (12h, 24h, 48h, 7d)
- [ ] Spacecraft/ground station filtering
- [ ] Jump to NOW functionality
- [ ] Keyboard shortcuts

**Deliverable**: Fully interactive ribbon view

### Phase 4: Passes View

**Goal**: Card-based contact list

- [ ] Build pass_card component
- [ ] Implement passes route and view
- [ ] Add sorting options
- [ ] Add filtering options
- [ ] Link card click to ribbon view

**Deliverable**: Complete passes view

### Phase 5: Polish

**Goal**: Production-ready experience

- [ ] PubSub integration for real-time updates
- [ ] NOW marker animation
- [ ] HUD aesthetic polish (corner brackets, glow effects)
- [ ] Accessibility review
- [ ] Performance optimization for large contact sets

**Deliverable**: Complete Schedule Mode

---

## Future Considerations

### Orbit Propagation Integration

When ephemeris data becomes available:

- **Automatic window generation** - Calculate visibility windows from TLEs
- **Elevation/azimuth display** - Show pass geometry
- **Max elevation indicator** - Mark peak of each pass
- **AOS/LOS times** - Precise acquisition/loss of signal times
- **Doppler predictions** - Frequency shift information

### Enhanced Features

- **Drag-to-create** - Create contacts by dragging on empty lane space
- **Drag-to-resize** - Adjust contact duration by dragging edges
- **Drag-to-move** - Reschedule by dragging contact to new time
- **Bulk operations** - Select and modify multiple contacts
- **Templates** - Save and apply contact patterns
- **Auto-scheduling** - AI-assisted optimal schedule generation

### Performance at Scale

- **Virtualization** - Only render visible lanes/contacts
- **Time-based pagination** - Load contacts in chunks
- **WebSocket streaming** - Efficient real-time updates
- **Caching** - Cache conflict calculations

---

## Reference Files

| File | Use For |
|------|---------|
| `lib/cadence_web/live/ops_console_live/timeline.ex` | Lanes view pattern, time window calc |
| `lib/cadence_web/live/ops_console_live/components.ex` | Lane components, positioning logic |
| `lib/cadence/application/contacts/contact_validator.ex` | Conflict detection |
| `assets/css/modes/timeline-mode.css` | CSS patterns |
| `lib/cadence_web/live/mission_live/contacts.ex` | Existing contact data loading |

---

## Verification Checklist

### Manual Testing

- [ ] Create contacts for multiple spacecraft/ground stations
- [ ] Verify bars render with correct position and width
- [ ] Verify conflicts highlight correctly
- [ ] Test time range controls and panning
- [ ] Test contact selection and detail panel
- [ ] Test passes view sorting and filtering

### Edge Cases

- [ ] Contacts spanning outside visible window (clip correctly)
- [ ] Many contacts on same spacecraft (no vertical overflow)
- [ ] Very short contacts (minimum bar width enforced)
- [ ] Contacts at exact same time (z-index/stacking)
- [ ] Empty state (no contacts in window)
- [ ] Single spacecraft filter active

---

## Appendix: Operator Workflows

### Workflow 1: Daily Schedule Review

1. Open Schedule Mode, Ribbon view
2. Set time range to 24 hours
3. Scan for conflict indicators (amber glow)
4. Click conflicts to see details
5. Resolve conflicts or note for planning team

### Workflow 2: Pass Monitoring

1. Open Schedule Mode, Passes view
2. Filter to specific spacecraft or station
3. Sort by time
4. Monitor upcoming passes
5. Click to see details before each pass

### Workflow 3: Conflict Resolution

1. Notice conflict indicator in ribbon
2. Click conflicting contact
3. Review conflict details in panel
4. Use suggested resolution or manually adjust
5. Verify conflict is resolved

### Workflow 4: Schedule Planning

1. Open Schedule Mode, 7-day range
2. Review overall schedule density
3. Identify gaps in coverage
4. Create new contacts to fill gaps
5. Verify no new conflicts introduced
