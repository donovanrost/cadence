---
title: Configuration UI Design
tags: [design, ui, configuration]
related:
  - "[[mission]]"
  - "[[target]]"
  - "[[interface]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Cadence Configuration UI Design

## Executive Summary

This document proposes a complete redesign of Cadence's configuration pages to support multi-interface spacecraft operations. The design separates transport concerns (Interfaces) from protocol concerns (Links/Channels) and introduces Bindings as the central concept for connecting them.

---

## 1. Information Architecture

### Proposed Navigation Structure

```
Config
├── Interfaces                    # Transport resources (sockets, serial)
│   ├── [list view]
│   └── {interface}              # Show/edit transport config
│       └── Bindings (read-only) # Which channels use this interface
│
├── Links                         # Spacecraft by SCID
│   ├── [list view]
│   └── {link}                   # Protocol config lives here
│       ├── Overview             # Summary + observed state
│       ├── Protocol             # TM/TC/COP-1 configuration
│       └── Channels             # VCID list
│           └── {channel}        # Channel detail + binding editor
│               └── Bindings     # Primary place to edit bindings
│
└── Onboarding Wizard            # Guided flow for new missions
```

### Terminology Mapping

| UI Term | Backend Concept | User Mental Model |
|---------|-----------------|-------------------|
| **Interface** | `Interface` schema | "A network socket or serial port" |
| **Link** | `LinkController` / SCID | "A spacecraft I communicate with" |
| **Channel** | `ChannelId` (SCID+VCID) | "A data path (telemetry/commanding)" |
| **Binding** | `Binding` struct | "Which interface carries which channel" |

---

## 2. Routing Structure

```elixir
# lib/cadence_web/router.ex - proposed additions

scope "/missions/:id", CadenceWeb.MissionLive, as: :mission do
  pipe_through [:browser, :require_authenticated_user, :require_mission_access]

  # Interfaces (transport only)
  live "/interfaces", Interfaces, :index
  live "/interfaces/new", Interfaces, :new
  live "/interfaces/:transport_id", InterfaceShow, :show
  live "/interfaces/:transport_id/edit", InterfaceShow, :edit

  # Links (spacecraft)
  live "/links", Links, :index
  live "/links/new", Links, :new
  live "/links/:scid", LinkShow, :show
  live "/links/:scid/edit", LinkShow, :edit
  live "/links/:scid/protocol", LinkShow, :protocol

  # Channels (nested under Link)
  live "/links/:scid/channels", LinkShow, :channels
  live "/links/:scid/channels/new", LinkShow, :new_channel
  live "/links/:scid/channels/:vcid", ChannelShow, :show
  live "/links/:scid/channels/:vcid/edit", ChannelShow, :edit
  live "/links/:scid/channels/:vcid/bindings", ChannelShow, :bindings

  # Onboarding wizard
  live "/onboarding", Onboarding, :start
  live "/onboarding/interfaces", Onboarding, :interfaces
  live "/onboarding/link", Onboarding, :link
  live "/onboarding/channels", Onboarding, :channels
  live "/onboarding/review", Onboarding, :review
end
```

---

## 3. Page Designs

### 3.1 Interfaces Index (`/missions/:id/interfaces`)

**Purpose:** List all transport interfaces, show connection status, provide quick access to create/edit.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Interfaces                                          [+ New Interface]│
│ Transport connections for telemetry and commanding                   │
├─────────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────┐ │
│ │ 🟢 Primary TM       │ │ 🟢 Primary TC       │ │ ⚪ Backup TM    │ │
│ │ TCP Client          │ │ TCP Client          │ │ TCP Client      │ │
│ │ 192.168.1.10:8080   │ │ 192.168.1.10:8081   │ │ 192.168.1.11:80 │ │
│ │ ─────────────────── │ │ ─────────────────── │ │ ───────────────│ │
│ │ 3 bindings          │ │ 2 bindings          │ │ 1 binding       │ │
│ │ [View] [Edit]       │ │ [View] [Edit]       │ │ [View] [Edit]   │ │
│ └─────────────────────┘ └─────────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Sections:**
- **Interface cards** with:
  - Status indicator (connected/disconnected/error)
  - Connection type badge
  - Endpoint address
  - Binding count
  - Quick actions

**Assigns:**
```elixir
%{
  interfaces: [Interface.t()],
  interface_statuses: %{transport_id => :connected | :disconnected | :error},
  binding_counts: %{transport_id => non_neg_integer()}
}
```

**PubSub Subscriptions:**
- `"mission:#{mission_id}:interface_config"` - Interface CRUD
- `"mission:#{mission_id}:interface_status"` - Connection state changes

---

### 3.2 Interface Show (`/missions/:id/interfaces/:transport_id`)

**Purpose:** View/edit transport configuration. Show bindings read-only with navigation to edit them at Channel level.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ ← Back to Interfaces                                                │
│ Primary Telemetry                              [Edit] [Delete]      │
│ Transport interface for spacecraft communication                    │
├─────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────────┐ │
│ │ Status           │ │ Connection       │ │ Uptime               │ │
│ │ 🟢 Connected     │ │ TCP Client       │ │ 2h 34m               │ │
│ │                  │ │ 192.168.1.10:8080│ │                      │ │
│ └──────────────────┘ └──────────────────┘ └──────────────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│ Transport Configuration                                             │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Host:           192.168.1.10                                    │ │
│ │ Port:           8080                                            │ │
│ │ Auto-reconnect: ✓ Enabled (5000ms delay)                        │ │
│ └─────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│ Bindings Using This Interface                    [Edit at Channel →]│
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Link      │ Channel │ Direction │ Role    │ Desired │ Observed │ │
│ ├───────────┼─────────┼───────────┼─────────┼─────────┼──────────┤ │
│ │ SAT-001   │ VC0     │ ↓ Downlink│ Primary │ Active  │ 🟢 Active│ │
│ │ SAT-001   │ VC1     │ ↓ Downlink│ Primary │ Active  │ 🟢 Active│ │
│ │ SAT-001   │ VC0     │ ↑ Uplink  │ Primary │ Active  │ 🟢 Active│ │
│ └─────────────────────────────────────────────────────────────────┘ │
│ Note: Edit bindings on the Channel configuration page               │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Sections:**
1. **Status Panel** - Real-time connection state (observed)
2. **Transport Configuration** - Host/port/serial settings (edit in modal)
3. **Bindings Table** - Read-only view with links to edit at Channel level

**Form Fields (Edit Modal):**
- Name
- Connection Type (immutable after creation)
- Host/Port OR Bind Address/Port OR Device Path
- Auto-reconnect settings

**What's NOT here:**
- No protocol configuration (that's on Link/Channel)
- No VCID configuration (that's on Channel)
- Bindings are read-only (edit at Channel)

---

### 3.3 Links Index (`/missions/:id/links`)

**Purpose:** List all spacecraft (by SCID) with protocol status summary.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Links (Spacecraft)                                      [+ New Link]│
│ Spacecraft connections with protocol configuration                  │
├─────────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Name        │ SCID │ Channels │ Protocol │ COP-1 State │ Status │ │
│ ├─────────────┼──────┼──────────┼──────────┼─────────────┼────────┤ │
│ │ SAT-001     │ 42   │ 3        │ AOS/USLP │ S1 (Active) │ 🟢 OK  │ │
│ │ SAT-002     │ 43   │ 2        │ AOS      │ S1 (Active) │ 🟢 OK  │ │
│ │ GROUND-SIM  │ 99   │ 1        │ TM/TC    │ S6 (Init)   │ ⚪ Idle│ │
│ └─────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│ 💡 Links define spacecraft identity (SCID) and protocol settings.  │
│    Channels (VCIDs) are configured within each link.               │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Columns:**
- Name (user-friendly identifier)
- SCID (spacecraft ID)
- Channel count
- Protocol type
- COP-1 state (runtime observed state)
- Overall status

---

### 3.4 Link Show (`/missions/:id/links/:scid`)

**Purpose:** Central hub for spacecraft configuration. Protocol config lives here.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ ← Back to Links                                                     │
│ SAT-001 (SCID: 42)                                    [Edit] [Delete]│
│ Primary mission spacecraft                                          │
├─────────────────────────────────────────────────────────────────────┤
│ [Overview] [Protocol] [Channels]                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─ Runtime Status ─────────────────────────────────────────────────┐│
│ │ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐               ││
│ │ │ COP-1 State  │ │ Active Links │ │ Last Frame   │               ││
│ │ │ S1 (Active)  │ │ 2 up / 3 cfg │ │ 0.3s ago     │               ││
│ │ └──────────────┘ └──────────────┘ └──────────────┘               ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Channels ───────────────────────────────────────────────────────┐│
│ │ VCID │ Name           │ Direction │ Interfaces │ Status          ││
│ ├──────┼────────────────┼───────────┼────────────┼─────────────────┤│
│ │ 0    │ Realtime TM    │ ↓ Down    │ 2 bound    │ 🟢 Active       ││
│ │ 1    │ Stored TM      │ ↓ Down    │ 1 bound    │ 🟢 Active       ││
│ │ 0    │ TC Uplink      │ ↑ Up      │ 1 bound    │ 🟢 Active       ││
│ │                                        [+ Add Channel]           ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Quick Binding Summary ──────────────────────────────────────────┐│
│ │ Primary TM (TCP) ──── VC0, VC1 (Downlink)                        ││
│ │ Primary TC (TCP) ──── VC0 (Uplink)                               ││
│ │ Backup TM (TCP)  ──── VC0 (Downlink, Backup)                     ││
│ └──────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

**Tabs:**

1. **Overview** - Status summary, channel list, binding summary
2. **Protocol** - Full protocol configuration form
3. **Channels** - Detailed channel management

---

### 3.5 Link Protocol Tab (`/missions/:id/links/:scid/protocol`)

**Purpose:** Configure TM/TC protocol settings for this spacecraft.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Protocol Configuration                                    [Save]    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─ Telemetry (TM) ─────────────────────────────────────────────────┐│
│ │ Frame Type:    [AOS ▼]                                           ││
│ │ Frame Length:  [1115] bytes                                      ││
│ │ ☐ Insert Zone present                                            ││
│ │                                                                  ││
│ │ ▶ Advanced TM Settings                                           ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Telecommand (TC) ───────────────────────────────────────────────┐│
│ │ Frame Type:    [TC ▼]                                            ││
│ │ ☑ Use SDLP framing                                               ││
│ │                                                                  ││
│ │ ▶ Advanced TC Settings                                           ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ COP-1 Configuration ────────────────────────────────────────────┐│
│ │ ☑ Enable COP-1 flow control                                      ││
│ │                                                                  ││
│ │ Window Width (K):  [5]                                           ││
│ │ T1 Timeout:        [5000] ms                                     ││
│ │ Report APID:       [2047]                                        ││
│ │                                                                  ││
│ │ ▶ Advanced COP-1 Settings                                        ││
│ │   ┌────────────────────────────────────────────────────────────┐ ││
│ │   │ Transmission Limit: [10]                                   │ ││
│ │   │ Timeout Type:       [T1_EXPIRY ▼]                          │ ││
│ │   │ ☐ Positive Window                                          │ ││
│ │   └────────────────────────────────────────────────────────────┘ ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ 💡 Protocol settings apply to all channels on this link.           │
│    Channel-specific overrides can be set on individual channels.   │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Principle:** Collapsible "Advanced" sections to avoid overwhelming users. Default settings work for 90% of cases.

---

### 3.6 Channel Show (`/missions/:id/links/:scid/channels/:vcid`)

**Purpose:** Configure a single channel (VCID) and its bindings. This is the PRIMARY place to edit bindings.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ ← Back to SAT-001                                                   │
│ Channel: VC0 (Realtime Telemetry)                    [Edit] [Delete]│
│ Virtual Channel 0 on SAT-001 (SCID: 42)                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─ Channel Configuration ──────────────────────────────────────────┐│
│ │ Name:      Realtime Telemetry                                    ││
│ │ VCID:      0                                                     ││
│ │ Direction: Downlink                                              ││
│ │                                                                  ││
│ │ ▶ Channel-Specific Protocol Overrides                            ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Interface Bindings ─────────────────────────────── [+ Add Binding]│
│ │                                                                  ││
│ │ ┌────────────────────────────────────────────────────────────┐   ││
│ │ │ Interface     │ Role    │ Priority │ Desired  │ Observed   │   ││
│ │ ├───────────────┼─────────┼──────────┼──────────┼────────────┤   ││
│ │ │ 🟢 Primary TM │ Primary │ 1        │ [Active▼]│ 🟢 Active  │ ✏️││
│ │ │ ⚪ Backup TM  │ Backup  │ 2        │ [Active▼]│ ⚪ Inactive│ ✏️││
│ │ └────────────────────────────────────────────────────────────┘   ││
│ │                                                                  ││
│ │ Active Interface: Primary TM (priority 1)                        ││
│ │ Failover: Backup TM will activate if Primary TM disconnects      ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Uplink Bindings ────────────────────────────────── [+ Add Binding]│
│ │ (This channel is downlink-only. No uplink bindings configured.)  ││
│ └──────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

**Binding Editor Inline:**
- Interface selector (dropdown of available interfaces)
- Role selector (Primary / Backup / Replay)
- Priority (numeric, lower = higher priority)
- Desired State (Active / Inactive / Draining)
- Observed State (read-only, live-updated)
- Edit/Delete actions

**Add Binding Modal:**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Add Interface Binding                                        [×]    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Interface:     [Select interface... ▼]                              │
│                ├─ 🟢 Primary TM (192.168.1.10:8080)                 │
│                ├─ 🟢 Primary TC (192.168.1.10:8081)                 │
│                └─ ⚪ Backup TM (192.168.1.11:8080)                  │
│                                                                     │
│ Direction:     [Downlink ▼]                                         │
│                                                                     │
│ Role:          [Primary ▼]                                          │
│                ├─ Primary - Active data path                        │
│                ├─ Backup - Failover when primary unavailable        │
│                └─ Replay - Historical data playback                 │
│                                                                     │
│ Priority:      [1] (lower = higher priority)                        │
│                                                                     │
│ Initial State: [Active ▼]                                           │
│                                                                     │
│                                              [Cancel] [Add Binding] │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 3.7 Onboarding Wizard (`/missions/:id/onboarding`)

**Purpose:** Guide new users through the complete setup flow: Interface → Link → Channel → Bind.

**Flow:**
```
[Start] → [Create Interfaces] → [Create Link] → [Add Channels] → [Review & Activate]
```

**Step 1: Welcome**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Welcome to Mission Configuration                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Let's set up communication with your spacecraft. This wizard will   │
│ guide you through:                                                  │
│                                                                     │
│   1. Creating transport interfaces (network connections)            │
│   2. Defining your spacecraft link (SCID and protocol)             │
│   3. Configuring channels (virtual channels for data)              │
│   4. Binding channels to interfaces                                 │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Quick Setup Profiles:                                           │ │
│ │                                                                 │ │
│ │ ○ Standard (Recommended)                                        │ │
│ │   Single spacecraft, one TM interface, one TC interface         │ │
│ │                                                                 │ │
│ │ ○ Redundant                                                     │ │
│ │   Single spacecraft with backup interfaces                      │ │
│ │                                                                 │ │
│ │ ○ Multi-spacecraft                                              │ │
│ │   Multiple spacecraft on shared interfaces                      │ │
│ │                                                                 │ │
│ │ ○ Custom                                                        │ │
│ │   Manual configuration step-by-step                             │ │
│ └─────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│                                                  [Next: Interfaces →]│
└─────────────────────────────────────────────────────────────────────┘
```

**Step 2: Interfaces**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Step 1 of 4: Create Interfaces                     [← Back] [Next →]│
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Create the network connections for your mission.                    │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Interfaces                                        [+ Add More]  │ │
│ │                                                                 │ │
│ │ ┌──────────────────────────────────────────────────────────┐    │ │
│ │ │ Name: [Telemetry Interface        ]                      │    │ │
│ │ │ Type: [TCP Client ▼] Host: [192.168.1.10] Port: [8080]   │    │ │
│ │ └──────────────────────────────────────────────────────────┘    │ │
│ │                                                                 │ │
│ │ ┌──────────────────────────────────────────────────────────┐    │ │
│ │ │ Name: [Command Interface          ]                      │    │ │
│ │ │ Type: [TCP Client ▼] Host: [192.168.1.10] Port: [8081]   │    │ │
│ │ └──────────────────────────────────────────────────────────┘    │ │
│ └─────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│ 💡 You can add more interfaces later from the Interfaces page.     │
└─────────────────────────────────────────────────────────────────────┘
```

**Step 3: Link**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Step 2 of 4: Define Spacecraft Link                [← Back] [Next →]│
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Configure your spacecraft's identity and protocol settings.         │
│                                                                     │
│ ┌─ Spacecraft Identity ────────────────────────────────────────────┐│
│ │ Name:           [SAT-001                    ]                    ││
│ │ Spacecraft ID:  [42  ] (SCID: 0-1023)                            ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Protocol Profile ───────────────────────────────────────────────┐│
│ │ ○ CCSDS AOS (Recommended for modern spacecraft)                  ││
│ │ ○ CCSDS TC/TM (Legacy CCSDS)                                     ││
│ │ ○ Custom (Manual protocol configuration)                         ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ COP-1 Flow Control ─────────────────────────────────────────────┐│
│ │ ☑ Enable COP-1 (recommended for reliable commanding)             ││
│ │   Window Width: [5]  Timeout: [5000]ms                           ││
│ └──────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

**Step 4: Channels & Bindings**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Step 3 of 4: Configure Channels                    [← Back] [Next →]│
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Define virtual channels and connect them to interfaces.             │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ VCID │ Name              │ Dir  │ Interface Binding             │ │
│ ├──────┼───────────────────┼──────┼───────────────────────────────┤ │
│ │ 0    │ [Realtime TM    ] │ ↓    │ [Telemetry Interface ▼]       │ │
│ │ 0    │ [TC Uplink      ] │ ↑    │ [Command Interface ▼]         │ │
│ │                                              [+ Add Channel]    │ │
│ └─────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│ 💡 VC0 is typically used for realtime telemetry and commanding.    │
│    Add more VCIDs for stored data, file transfer, etc.             │
└─────────────────────────────────────────────────────────────────────┘
```

**Step 5: Review**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Step 4 of 4: Review Configuration                  [← Back] [Finish]│
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─ Summary ────────────────────────────────────────────────────────┐│
│ │ Interfaces: 2                                                    ││
│ │   • Telemetry Interface (TCP → 192.168.1.10:8080)               ││
│ │   • Command Interface (TCP → 192.168.1.10:8081)                 ││
│ │                                                                  ││
│ │ Link: SAT-001 (SCID: 42)                                         ││
│ │   Protocol: CCSDS AOS with COP-1                                 ││
│ │                                                                  ││
│ │ Channels: 2                                                      ││
│ │   • VC0 Downlink → Telemetry Interface                          ││
│ │   • VC0 Uplink → Command Interface                              ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ ┌─ Activation ─────────────────────────────────────────────────────┐│
│ │ ☑ Activate bindings after creation (start data flow)             ││
│ │ ☐ Leave bindings inactive (manual activation later)              ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                     │
│                                           [Save as Draft] [Finish →]│
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Component Library

### 4.1 Core Components

```elixir
# lib/cadence_web/components/config_components.ex

defmodule CadenceWeb.ConfigComponents do
  use Phoenix.Component

  # ... component implementations below
end
```

#### InterfaceCard

**Purpose:** Display interface summary in grid/list views.

```elixir
attr :interface, :map, required: true
attr :status, :atom, default: :disconnected  # :connected | :disconnected | :error
attr :binding_count, :integer, default: 0

def interface_card(assigns) do
  ~H"""
  <div class="rounded-lg border border-base-300 bg-base-200/40 p-4 hover:border-primary/50 transition-colors">
    <div class="flex items-center justify-between mb-3">
      <div class="flex items-center gap-2">
        <.interface_status_badge status={@status} />
        <h3 class="font-semibold text-base-content">{@interface.name}</h3>
      </div>
      <span class="text-xs text-base-content/60">{connection_type_label(@interface.connection_type)}</span>
    </div>

    <p class="text-sm text-base-content/70 mb-3">{interface_endpoint(@interface)}</p>

    <div class="flex items-center justify-between">
      <span class="text-xs text-base-content/50">{@binding_count} binding(s)</span>
      <div class="flex gap-2">
        <.link navigate={~p"/missions/#{@interface.mission_id}/interfaces/#{@interface}"} class="btn btn-xs btn-ghost">
          View
        </.link>
        <.link patch={~p"/missions/#{@interface.mission_id}/interfaces/#{@interface}/edit"} class="btn btn-xs">
          Edit
        </.link>
      </div>
    </div>
  </div>
  """
end
```

#### InterfaceStatusBadge

**Purpose:** Visual indicator for interface connection state.

```elixir
attr :status, :atom, required: true  # :connected | :disconnected | :connecting | :error
attr :size, :atom, default: :md      # :sm | :md | :lg

def interface_status_badge(assigns) do
  ~H"""
  <span class={[
    "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium",
    status_classes(@status)
  ]}>
    <span class={["w-2 h-2 rounded-full", status_dot_classes(@status)]}></span>
    {status_label(@status)}
  </span>
  """
end

defp status_classes(:connected), do: "bg-success/20 text-success"
defp status_classes(:connecting), do: "bg-warning/20 text-warning"
defp status_classes(:disconnected), do: "bg-base-300 text-base-content/60"
defp status_classes(:error), do: "bg-error/20 text-error"
```

#### BindingTable

**Purpose:** Display and optionally edit bindings for a channel.

```elixir
attr :bindings, :list, required: true
attr :editable, :boolean, default: false
attr :on_change, :any, default: nil  # Event handler for editable mode
attr :interfaces, :list, default: []  # Available interfaces for dropdown

def binding_table(assigns) do
  ~H"""
  <div class="overflow-x-auto">
    <table class="table table-sm">
      <thead>
        <tr class="text-xs uppercase text-base-content/60">
          <th>Interface</th>
          <th>Direction</th>
          <th>Role</th>
          <th>Priority</th>
          <th>Desired</th>
          <th>Observed</th>
          <th :if={@editable}></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={binding <- @bindings} class="hover:bg-base-200/50">
          <td>
            <div class="flex items-center gap-2">
              <.interface_status_badge status={binding.observed_state} size={:sm} />
              <span>{binding.interface_name}</span>
            </div>
          </td>
          <td><.direction_badge direction={binding.direction} /></td>
          <td><.role_badge role={binding.role} /></td>
          <td class="text-center">{binding.priority}</td>
          <td>
            <%= if @editable do %>
              <select
                name={"binding[#{binding.id}][desired_state]"}
                class="select select-xs"
                phx-change={@on_change}
              >
                <option value="active" selected={binding.desired_state == :active}>Active</option>
                <option value="inactive" selected={binding.desired_state == :inactive}>Inactive</option>
                <option value="draining" selected={binding.desired_state == :draining}>Draining</option>
              </select>
            <% else %>
              <.state_badge state={binding.desired_state} />
            <% end %>
          </td>
          <td><.observed_state_indicator state={binding.observed_state} /></td>
          <td :if={@editable}>
            <button type="button" class="btn btn-xs btn-ghost text-error" phx-click="remove_binding" phx-value-id={binding.id}>
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
  """
end
```

#### ProtocolConfigForm

**Purpose:** Reusable form for TM/TC/COP-1 protocol settings.

```elixir
attr :form, Phoenix.HTML.Form, required: true
attr :on_change, :any, required: true
attr :on_submit, :any, required: true

def protocol_config_form(assigns) do
  ~H"""
  <.simple_form for={@form} phx-change={@on_change} phx-submit={@on_submit}>
    <%-- Telemetry Section --%>
    <.collapsible_section title="Telemetry (TM)" default_open={true}>
      <.input field={@form[:tm_frame_type]} type="select" label="Frame Type"
        options={[{"AOS", "aos"}, {"TM", "tm"}]} />
      <.input field={@form[:tm_frame_length]} type="number" label="Frame Length (bytes)" />
      <.input field={@form[:tm_insert_zone]} type="checkbox" label="Insert Zone present" />

      <.collapsible_section title="Advanced TM Settings" default_open={false}>
        <.input field={@form[:tm_asm]} type="text" label="ASM Pattern (hex)" />
        <.input field={@form[:tm_randomize]} type="checkbox" label="Randomize data" />
      </.collapsible_section>
    </.collapsible_section>

    <%-- Telecommand Section --%>
    <.collapsible_section title="Telecommand (TC)" default_open={true}>
      <.input field={@form[:tc_frame_type]} type="select" label="Frame Type"
        options={[{"TC", "tc"}, {"USLP", "uslp"}]} />
      <.input field={@form[:tc_use_sdlp]} type="checkbox" label="Use SDLP framing" />

      <.collapsible_section title="Advanced TC Settings" default_open={false}>
        <.input field={@form[:tc_segment_header]} type="checkbox" label="Segment header present" />
      </.collapsible_section>
    </.collapsible_section>

    <%-- COP-1 Section --%>
    <.collapsible_section title="COP-1 Flow Control" default_open={true}>
      <.input field={@form[:cop1_enabled]} type="checkbox" label="Enable COP-1" />

      <div :if={@form[:cop1_enabled].value} class="grid grid-cols-2 gap-4 mt-4">
        <.input field={@form[:cop1_window_width]} type="number" label="Window Width (K)" />
        <.input field={@form[:cop1_t1_timeout]} type="number" label="T1 Timeout (ms)" />
        <.input field={@form[:cop1_report_apid]} type="number" label="Report APID" />
      </div>

      <.collapsible_section :if={@form[:cop1_enabled].value} title="Advanced COP-1" default_open={false}>
        <.input field={@form[:cop1_transmission_limit]} type="number" label="Transmission Limit" />
        <.input field={@form[:cop1_timeout_type]} type="select" label="Timeout Type"
          options={[{"T1 Expiry", "t1_expiry"}, {"Transmission Limit", "transmission_limit"}]} />
        <.input field={@form[:cop1_positive_window]} type="checkbox" label="Positive Window" />
      </.collapsible_section>
    </.collapsible_section>

    <:actions>
      <.button type="submit">Save Protocol Configuration</.button>
    </:actions>
  </.simple_form>
  """
end
```

#### ChannelSelector

**Purpose:** Dropdown/chips for selecting channels (VCIDs).

```elixir
attr :channels, :list, required: true
attr :selected, :list, default: []
attr :on_select, :any, required: true
attr :multi, :boolean, default: false

def channel_selector(assigns) do
  ~H"""
  <div class="flex flex-wrap gap-2">
    <button
      :for={channel <- @channels}
      type="button"
      phx-click={@on_select}
      phx-value-vcid={channel.vcid}
      class={[
        "px-3 py-1.5 rounded-full text-sm font-medium transition-colors",
        if(channel.vcid in @selected,
          do: "bg-primary text-primary-content",
          else: "bg-base-300 text-base-content hover:bg-base-200"
        )
      ]}
    >
      VC{channel.vcid}
      <span :if={channel.name} class="text-xs opacity-75 ml-1">({channel.name})</span>
    </button>
  </div>
  """
end
```

#### CollapsibleSection

**Purpose:** Hide advanced settings by default.

```elixir
attr :title, :string, required: true
attr :default_open, :boolean, default: false
slot :inner_block, required: true

def collapsible_section(assigns) do
  ~H"""
  <div x-data={"{ open: #{@default_open} }"} class="border border-base-300 rounded-lg">
    <button
      type="button"
      @click="open = !open"
      class="flex items-center justify-between w-full px-4 py-3 text-left hover:bg-base-200/50"
    >
      <span class="font-medium text-base-content">{@title}</span>
      <.icon name="hero-chevron-down" class="w-5 h-5 transition-transform" x-bind:class="{ 'rotate-180': open }" />
    </button>
    <div x-show="open" x-collapse class="px-4 pb-4 space-y-4">
      {render_slot(@inner_block)}
    </div>
  </div>
  """
end
```

#### DirectionBadge, RoleBadge, StateBadge

**Purpose:** Consistent visual indicators.

```elixir
attr :direction, :atom, required: true  # :uplink | :downlink | :both

def direction_badge(assigns) do
  ~H"""
  <span class={["inline-flex items-center gap-1 text-xs", direction_color(@direction)]}>
    <.icon name={direction_icon(@direction)} class="w-3 h-3" />
    {direction_label(@direction)}
  </span>
  """
end

defp direction_icon(:uplink), do: "hero-arrow-up"
defp direction_icon(:downlink), do: "hero-arrow-down"
defp direction_icon(:both), do: "hero-arrows-up-down"

attr :role, :atom, required: true  # :primary | :backup | :replay

def role_badge(assigns) do
  ~H"""
  <span class={["badge badge-sm", role_classes(@role)]}>
    {role_label(@role)}
  </span>
  """
end

defp role_classes(:primary), do: "badge-primary"
defp role_classes(:backup), do: "badge-secondary"
defp role_classes(:replay), do: "badge-accent"

attr :state, :atom, required: true  # :active | :inactive | :draining

def observed_state_indicator(assigns) do
  ~H"""
  <div class="flex items-center gap-1.5">
    <span class={["w-2 h-2 rounded-full", state_dot(@state)]}></span>
    <span class="text-xs">{state_label(@state)}</span>
  </div>
  """
end

defp state_dot(:active), do: "bg-success animate-pulse"
defp state_dot(:inactive), do: "bg-base-content/30"
defp state_dot(:draining), do: "bg-warning animate-pulse"
```

---

## 5. State Management

### 5.1 Assigns Structure

```elixir
# Interface pages
%{
  interfaces: [Interface.t()],
  interface_statuses: %{transport_id => status},
  binding_counts: %{transport_id => count}
}

# Link pages
%{
  link: %{
    scid: integer,
    name: string,
    protocol_config: map
  },
  channels: [%{vcid: integer, name: string, bindings: [Binding.t()]}],
  interfaces: [Interface.t()],  # For binding dropdowns
  runtime_state: %{
    cop1_state: atom,
    active_bindings: integer,
    last_frame_at: DateTime.t()
  }
}

# Channel pages
%{
  link: map,
  channel: %{
    vcid: integer,
    name: string,
    direction: atom
  },
  bindings: [Binding.t()],
  interfaces: [Interface.t()]
}
```

### 5.2 PubSub Topics

```elixir
# Configuration changes (user-initiated)
"mission:#{mission_id}:interface_config"     # Interface CRUD
"mission:#{mission_id}:link_config"          # Link CRUD, protocol changes
"mission:#{mission_id}:channel_config"       # Channel CRUD
"mission:#{mission_id}:binding_config"       # Binding changes

# Runtime state (system-observed)
"mission:#{mission_id}:interface_status"     # Connection up/down
"mission:#{mission_id}:link_status"          # COP-1 state, frame stats
"mission:#{mission_id}:binding_status"       # Observed state changes
```

### 5.3 LiveView Subscriptions

```elixir
defmodule CadenceWeb.MissionLive.LinkShow do
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"id" => mission_id, "scid" => scid}, _session, socket) do
    if connected?(socket) do
      # Config changes
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:link_config")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:channel_config")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:binding_config")

      # Runtime state
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:link_status")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:binding_status")
    end

    {:ok, load_link_data(socket, mission_id, scid)}
  end

  @impl true
  def handle_info({:link_status_changed, %{scid: scid} = status}, socket) do
    if socket.assigns.link.scid == scid do
      {:noreply, assign(socket, :runtime_state, status)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:binding_observed_state_changed, binding}, socket) do
    # Update the specific binding's observed state optimistically
    {:noreply, update_binding_observed_state(socket, binding)}
  end
end
```

### 5.4 Optimistic Updates

```elixir
def handle_event("set_binding_state", %{"binding_id" => id, "state" => state}, socket) do
  binding = find_binding(socket.assigns.bindings, id)

  # Optimistic update
  socket = update_binding_in_assigns(socket, id, %{desired_state: String.to_atom(state)})

  # Async server update
  Task.start(fn ->
    case Cadence.Bindings.set_desired_state(binding, String.to_atom(state)) do
      :ok -> :ok
      {:error, reason} ->
        # Revert will happen via PubSub broadcast of actual state
        Logger.warning("Failed to set binding state: #{reason}")
    end
  end)

  {:noreply, socket}
end
```

---

## 6. Validation & Error Handling

### 6.1 Form Validation

```elixir
# Inline validation feedback
def handle_event("validate", %{"link" => params}, socket) do
  changeset =
    socket.assigns.link
    |> Link.changeset(params)
    |> Map.put(:action, :validate)

  {:noreply, assign_form(socket, changeset)}
end

# Display errors inline
<.input field={@form[:scid]} type="number" label="Spacecraft ID" />
# Automatically shows: "must be between 0 and 1023" etc.
```

### 6.2 Conflict Detection

```elixir
# In binding creation
defp validate_binding_conflicts(socket, new_binding) do
  existing = socket.assigns.bindings

  conflicts = Enum.filter(existing, fn b ->
    b.transport_id == new_binding.transport_id and
    b.direction == new_binding.direction and
    b.role == :primary and new_binding.role == :primary
  end)

  case conflicts do
    [] -> {:ok, new_binding}
    [conflict] -> {:warning, "This will replace #{conflict.interface_name} as primary"}
    _ -> {:error, "Multiple primary bindings not allowed"}
  end
end
```

### 6.3 Error Display

```elixir
# Flash messages for async errors
def handle_info({:binding_error, %{message: msg}}, socket) do
  {:noreply, put_flash(socket, :error, msg)}
end

# Inline errors for form fields
<.input field={@form[:scid]} type="number" label="Spacecraft ID" />
<%# Shows validation error automatically via Phoenix.HTML.Form %>
```

---

## 7. Example Wireframe Descriptions

### Interface Index - Empty State
```
┌─────────────────────────────────────────────────────────────────────┐
│ Interfaces                                          [+ New Interface]│
│ Transport connections for telemetry and commanding                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│              ┌─────────────────────────────────────┐                │
│              │     📡 No interfaces configured     │                │
│              │                                     │                │
│              │  Create your first interface to     │                │
│              │  establish communication with       │                │
│              │  your spacecraft.                   │                │
│              │                                     │                │
│              │  [+ Create Interface]               │                │
│              │                                     │                │
│              │  or [Start Onboarding Wizard →]     │                │
│              └─────────────────────────────────────┘                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Link Show - Multi-Interface Binding Visualization
```
┌─────────────────────────────────────────────────────────────────────┐
│ SAT-001 (SCID: 42)                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Data Flow Diagram                                                  │
│  ─────────────────                                                  │
│                                                                     │
│    ┌──────────────┐                                                 │
│    │  SAT-001     │                                                 │
│    │  SCID: 42    │                                                 │
│    └──────┬───────┘                                                 │
│           │                                                         │
│     ┌─────┴─────┐                                                   │
│     │           │                                                   │
│   VC0         VC1                                                   │
│  (RT TM)    (Stored)                                                │
│     │           │                                                   │
│     │     ┌─────┘                                                   │
│     │     │                                                         │
│  ┌──┴─────┴──┐  ┌────────────┐                                      │
│  │ Primary   │  │ Backup     │                                      │
│  │ TM 🟢     │  │ TM ⚪      │                                      │
│  └───────────┘  └────────────┘                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 8. Migration Path

### Phase 1: Schema Changes
1. Add `Link` schema (or repurpose existing Target + SCID relationship)
2. Add `Channel` schema (distinct from `InterfaceVcid`)
3. Add `Binding` schema (persistent, not just runtime)
4. Migrate protocol config from Interface.config to Link

### Phase 2: UI Implementation
1. Create new component library (`ConfigComponents`)
2. Implement Links Index/Show pages
3. Implement Channel pages with binding editor
4. Refactor Interface pages to be transport-only
5. Build onboarding wizard

### Phase 3: Runtime Integration
1. Connect UI bindings to `LinkController.set_binding/1`
2. Subscribe UI to runtime status broadcasts
3. Implement desired/observed state separation in UI

---

## 9. Future Extensibility

### MAP Support
- Channel schema includes optional `map_id` field
- Channel selector shows MAP hierarchy under VCID
- Binding editor supports MAP-level bindings
- UI surfaces MAP only when `map_id` is configured

### Additional Channels
- Channel list dynamically grows
- No hardcoded VC0/VC1 assumptions
- Channel templates for common patterns (realtime, stored, file transfer)

### Multi-Spacecraft
- Links Index scales to many spacecraft
- Filtering/search for large link counts
- Batch binding operations

---

## 10. File Structure

```
lib/cadence_web/
├── components/
│   ├── core_components.ex          # Existing
│   └── config_components.ex        # NEW: Config-specific components
│
├── live/
│   ├── mission_live/
│   │   ├── interfaces.ex           # Refactored: transport-only
│   │   ├── interface_show.ex       # Refactored: transport-only
│   │   ├── links.ex                # NEW: Links index
│   │   ├── link_show.ex            # NEW: Link detail with tabs
│   │   ├── channel_show.ex         # NEW: Channel + binding editor
│   │   └── onboarding.ex           # NEW: Setup wizard
│   │
│   └── components/
│       ├── interface_form.ex       # Existing, simplified
│       ├── link_form.ex            # NEW
│       ├── protocol_config.ex      # Moved from interface
│       ├── channel_form.ex         # NEW
│       └── binding_editor.ex       # NEW: Inline binding editor
```

---

This design cleanly separates transport (Interfaces) from protocol (Links/Channels), makes Bindings the central concept for multi-interface operations, and provides a scalable foundation for future MAP support and multi-spacecraft operations.
