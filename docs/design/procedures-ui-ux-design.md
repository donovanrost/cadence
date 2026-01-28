---
title: Procedures UI/UX Design
tags: [design, procedures, ui, ux]
related:
  - "[[procedure]]"
  - "[[sequence]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Procedures UI/UX Design

> Designing an Epsilon3-caliber experience with Cadence's HUD aesthetic

## Design Philosophy

**Mission Control meets Modern SaaS**

Cadence's existing aesthetic is a strength: the vaporwave/Tokyo Night palette with HUD elements feels purpose-built for spacecraft operations. The procedures UI should feel like a natural extension - not a bolt-on.

### Core Principles

1. **Operator-First** - Every decision optimizes for the person executing the procedure
2. **Glanceable Status** - State is visible without clicking or hovering
3. **Progressive Disclosure** - Simple by default, detailed on demand
4. **Real-Time Confidence** - Live data feels alive, stale data looks stale
5. **Audit-Ready** - Every action is traceable and timestamped

---

## Two Contexts: Admin vs Ops

Cadence has two distinct UI paradigms:

| Aspect | Admin (Sidebar) | Ops-V2 (Full-Screen) |
|--------|-----------------|----------------------|
| **Purpose** | Configuration & management | Real-time operations |
| **Layout** | Sidebar + content area | 3-panel + modes |
| **Navigation** | Page-based routing | Mode switching |
| **Focus** | CRUD, approval workflows | Monitoring, execution |
| **Interaction** | Forms, tables, modals | Quick actions, live data |

### Procedures Span Both Contexts

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              ADMIN CONTEXT                               │
│                                                                          │
│   Procedure Authoring          Version Management         Snippets       │
│   ─────────────────           ──────────────────         ────────       │
│   • Create procedures         • Draft/Review/Approve     • Create       │
│   • Edit sections/steps       • Version history          • Organize     │
│   • Configure blocks          • Diff between versions    • Insert       │
│   • Set dependencies          • Reject with comments                    │
│   • Test validation           • Deprecate old versions                  │
│                                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│                               OPS CONTEXT                                │
│                                                                          │
│   Procedure Execution          Real-Time Monitoring       Collaboration │
│   ───────────────────         ────────────────────       ─────────────  │
│   • Start procedures          • Live telemetry blocks    • Comments     │
│   • Step-by-step progress     • Pass/fail evaluation     • Redlines     │
│   • Fill inputs               • Status in global bar     • @mentions    │
│   • Sign off steps            • Activity feed            • Handover     │
│   • Skip/pause/abort          • Alarm integration                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Context-Specific Requirements

**Admin Procedures UI needs:**
- Block-based visual editor (drag & drop)
- Side-by-side preview
- Version diff viewer
- Approval workflow UI
- Tag/organization management
- Import/export

**Ops Procedures UI needs:**
- Minimal chrome (maximum content)
- Keyboard navigation
- Quick signoff (single click/key)
- Alarm awareness (don't hide alerts)
- Integration with command queue
- Multiple procedures visible at once

---

## Visual Language Extension

### Procedure-Specific Colors

Extend the existing palette for procedure states:

```css
/* Step States */
--step-pending: var(--base-300);           /* Gray - not started */
--step-active: var(--primary);             /* Cyan - in progress */
--step-awaiting: var(--secondary);         /* Purple - needs signoff */
--step-completed: var(--success);          /* Green - done */
--step-skipped: var(--base-content-muted); /* Muted - skipped */
--step-failed: var(--error);               /* Red - failed */
--step-blocked: var(--warning);            /* Orange - blocked by dependency */

/* Block Type Accents */
--block-content: var(--base-content);      /* Text, notes */
--block-caution: #f5a623;                  /* Yellow-orange */
--block-warning: #ff007c;                  /* Hot pink (danger) */
--block-input: var(--primary);             /* Cyan */
--block-telemetry: var(--secondary);       /* Purple */
--block-command: var(--accent);            /* Pink */
```

### Step Card States

```
┌─────────────────────────────────────────┐
│ PENDING    │ Gray border, muted text    │
├─────────────────────────────────────────┤
│ ACTIVE     │ Cyan glow, bright text     │
│            │ Pulsing left border        │
├─────────────────────────────────────────┤
│ AWAITING   │ Purple glow, "Sign Off"    │
│ SIGNOFF    │ button prominent           │
├─────────────────────────────────────────┤
│ COMPLETED  │ Green left border,         │
│            │ checkmark, collapsed       │
├─────────────────────────────────────────┤
│ SKIPPED    │ Strikethrough title,       │
│            │ muted, collapsed           │
├─────────────────────────────────────────┤
│ FAILED     │ Red glow, error message    │
│            │ visible, expanded          │
├─────────────────────────────────────────┤
│ BLOCKED    │ Orange border, shows       │
│            │ which deps are pending     │
└─────────────────────────────────────────┘
```

---

## Editor UI

### Layout: Three-Column Editor

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ← Back to Procedures    Battery Health Check v3 (Draft)    [Save Draft] │
├────────────────┬─────────────────────────────────────────┬───────────────┤
│                │                                         │               │
│   SECTIONS     │            STEP EDITOR                  │   PROPERTIES  │
│                │                                         │               │
│  ┌──────────┐  │  ┌─────────────────────────────────┐   │  Step Config  │
│  │ 1. Setup │  │  │  Step: Verify Power             │   │  ───────────  │
│  │   ├ 1.1  │  │  │                                 │   │  Name: [    ] │
│  │   ├ 1.2  │  │  │  ┌─ Text Block ──────────────┐  │   │  Signoff: ☑  │
│  │   └ 1.3  │  │  │  │ Verify spacecraft is in   │  │   │  Roles: [...] │
│  ├──────────┤  │  │  │ safe mode before proceed. │  │   │               │
│  │ 2. Check │◀─│  │  └───────────────────────────┘  │   │  Dependencies │
│  │   ├ 2.1  │  │  │                                 │   │  ───────────  │
│  │   └ 2.2  │  │  │  ┌─ Telemetry Check ─────────┐  │   │  Depends on:  │
│  ├──────────┤  │  │  │ ⚡ target.EPS.voltage      │  │   │  [Step 1.1 ▼] │
│  │ 3. Exec  │  │  │  │    Pass: >= 24.0 V        │  │   │               │
│  │   └ 3.1  │  │  │  └───────────────────────────┘  │   │  On Failure   │
│  └──────────┘  │  │                                 │   │  ───────────  │
│                │  │  ┌─ + Add Block ─────────────┐  │   │  ( ) Abort    │
│  [+ Section]   │  │  │  Text | Input | Telemetry │  │   │  (•) Pause    │
│                │  │  │  Command | Note | Warning │  │   │  ( ) Continue │
│                │  │  └───────────────────────────┘  │   │               │
│                │  │                                 │   │               │
│                │  └─────────────────────────────────┘   │               │
│                │                                         │               │
│                │  [Previous Step]      [Next Step →]     │               │
│                │                                         │               │
└────────────────┴─────────────────────────────────────────┴───────────────┘
```

### Section Outline (Left Panel)

```elixir
# Component: ProcedureSectionOutline
def section_outline(assigns) do
  ~H"""
  <div class="hud-panel p-2 space-y-1">
    <div class="hud-label mb-2">SECTIONS</div>

    <%= for section <- @sections do %>
      <div class={[
        "group cursor-pointer rounded",
        @selected_section_id == section.id && "bg-primary/10"
      ]}>
        <!-- Section header -->
        <div class="flex items-center gap-2 px-2 py-1.5 hover:bg-base-300/50"
             phx-click="select_section" phx-value-id={section.id}>
          <.icon name="hero-chevron-right" class={[
            "size-3 transition-transform",
            section.expanded && "rotate-90"
          ]} />
          <span class="text-sm font-medium"><%= section.position %>. <%= section.name %></span>
          <span class="ml-auto text-xs text-base-content/50">
            <%= length(section.steps) %>
          </span>
        </div>

        <!-- Steps within section -->
        <%= if section.expanded do %>
          <div class="ml-4 border-l border-base-300 pl-2 space-y-0.5">
            <%= for step <- section.steps do %>
              <div class={[
                "flex items-center gap-2 px-2 py-1 rounded text-sm cursor-pointer",
                "hover:bg-base-300/50",
                @selected_step_id == step.id && "bg-primary/20 text-primary"
              ]}
              phx-click="select_step" phx-value-id={step.id}>
                <.step_status_dot status={step.validation_status} />
                <span class="truncate"><%= step.title || step.name %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>

    <button class="btn btn-ghost btn-sm w-full mt-2" phx-click="add_section">
      <.icon name="hero-plus" class="size-4" />
      Add Section
    </button>
  </div>
  """
end
```

### Block Editor

Blocks are the heart of the editor. Each type has a distinct visual treatment:

```elixir
# Component: BlockEditor
def block_editor(assigns) do
  ~H"""
  <div class={[
    "hud-panel relative group",
    block_border_class(@block.block_type)
  ]}>
    <!-- Block type indicator -->
    <div class={[
      "absolute -left-px top-0 bottom-0 w-1 rounded-l",
      block_accent_class(@block.block_type)
    ]} />

    <!-- Block header (on hover) -->
    <div class="absolute -top-3 left-2 opacity-0 group-hover:opacity-100 transition-opacity">
      <span class={[
        "text-xs px-1.5 py-0.5 rounded",
        block_label_class(@block.block_type)
      ]}>
        <%= block_type_label(@block.block_type) %>
      </span>
    </div>

    <!-- Block content -->
    <div class="p-3">
      <%= case @block.block_type do %>
        <% :text -> %>
          <.markdown_editor content={@block.content.markdown} />

        <% :note -> %>
          <div class="flex gap-2 items-start">
            <.icon name="hero-information-circle" class="size-5 text-info shrink-0 mt-0.5" />
            <.text_input value={@block.content.text} placeholder="Note text..." />
          </div>

        <% :caution -> %>
          <div class="flex gap-2 items-start bg-warning/10 -m-3 p-3 rounded">
            <.icon name="hero-exclamation-triangle" class="size-5 text-warning shrink-0 mt-0.5" />
            <.text_input value={@block.content.text} placeholder="Caution text..." />
          </div>

        <% :warning -> %>
          <div class="flex gap-2 items-start bg-error/10 -m-3 p-3 rounded">
            <.icon name="hero-x-circle" class="size-5 text-error shrink-0 mt-0.5" />
            <.text_input value={@block.content.text} placeholder="Warning text..." />
          </div>

        <% :number_input -> %>
          <.input_block_editor block={@block} />

        <% :telemetry_value -> %>
          <.telemetry_block_editor block={@block} />

        <% :telemetry_check -> %>
          <.telemetry_check_editor block={@block} />

        <% :command -> %>
          <.command_block_editor block={@block} />

        <% _ -> %>
          <div class="text-sm text-base-content/50">
            Unknown block type: <%= @block.block_type %>
          </div>
      <% end %>
    </div>

    <!-- Block actions (on hover) -->
    <div class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
      <.dropdown>
        <:trigger>
          <button class="btn btn-ghost btn-xs">
            <.icon name="hero-ellipsis-vertical" class="size-4" />
          </button>
        </:trigger>
        <:menu>
          <.dropdown_item phx-click="move_block_up">Move Up</.dropdown_item>
          <.dropdown_item phx-click="move_block_down">Move Down</.dropdown_item>
          <.dropdown_item phx-click="duplicate_block">Duplicate</.dropdown_item>
          <.dropdown_item phx-click="delete_block" class="text-error">Delete</.dropdown_item>
        </:menu>
      </.dropdown>
    </div>
  </div>
  """
end
```

### Block Type Palette

```
┌─────────────────────────────────────────────────────────────────┐
│  + Add Block                                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CONTENT                    DATA COLLECTION                      │
│  ┌─────────┐ ┌─────────┐   ┌─────────┐ ┌─────────┐              │
│  │  ≡ Text │ │ ℹ Note  │   │ # Number│ │ Aa Text │              │
│  └─────────┘ └─────────┘   └─────────┘ └─────────┘              │
│  ┌─────────┐ ┌─────────┐   ┌─────────┐ ┌─────────┐              │
│  │ ⚠ Warn  │ │ ⛔ Crit │   │ ▼ Select│ │ ☑ Check │              │
│  └─────────┘ └─────────┘   └─────────┘ └─────────┘              │
│                                                                  │
│  TELEMETRY                  COMMANDS                             │
│  ┌─────────┐ ┌─────────┐   ┌─────────┐ ┌─────────┐              │
│  │ ⚡ Value │ │ ✓ Check │   │ ▶ Cmd   │ │ ▶▶ Seq  │              │
│  └─────────┘ └─────────┘   └─────────┘ └─────────┘              │
│  ┌─────────┐                                                     │
│  │ ⏳ Wait │                                                     │
│  └─────────┘                                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Telemetry Block Editor

```elixir
def telemetry_block_editor(assigns) do
  ~H"""
  <div class="space-y-3">
    <!-- Item selector with autocomplete -->
    <div class="flex gap-2 items-center">
      <.icon name="hero-bolt" class="size-5 text-secondary" />
      <div class="flex-1 relative">
        <input
          type="text"
          value={@block.content.item}
          phx-change="update_telemetry_item"
          phx-debounce="300"
          placeholder="target.PACKET.item"
          class="input input-sm w-full font-mono"
          autocomplete="off"
          phx-hook="TelemetryAutocomplete"
        />
        <!-- Live preview of current value -->
        <%= if @live_value do %>
          <div class="absolute right-2 top-1/2 -translate-y-1/2">
            <span class={[
              "font-mono text-sm",
              quality_class(@live_value.quality)
            ]}>
              <%= format_value(@live_value.value, @block.content.format) %>
            </span>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Format and unit -->
    <div class="flex gap-2">
      <.input
        type="text"
        value={@block.content.format}
        placeholder="%.2f"
        label="Format"
        class="w-24"
      />
      <.input
        type="text"
        value={@block.content.unit}
        placeholder="V"
        label="Unit"
        class="w-16"
      />
    </div>
  </div>
  """
end
```

---

## Execution UI

### Layout: Focused Execution View

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ◀ Procedures   Battery Health Check                     SC-001 │ ALPHA  │
│                 v3 • Started 14:23:05 • Operator: jsmith                 │
├──────────────────────────────────────────────────────────────────────────┤
│ ┌────────────────────────────────────────────────────────────────────┐   │
│ │ ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Step 4 of 12  │   │
│ └────────────────────────────────────────────────────────────────────┘   │
├────────────────┬─────────────────────────────────────┬───────────────────┤
│                │                                     │                   │
│   PROGRESS     │         ACTIVE STEP                 │    ACTIVITY       │
│                │                                     │                   │
│  ✓ 1. Setup    │  ┌─────────────────────────────┐   │  ┌─────────────┐  │
│    ✓ 1.1       │  │  2.1 Verify Battery Voltage │   │  │ 14:25:32    │  │
│    ✓ 1.2       │  │  ════════════════════════   │   │  │ Step 1.2    │  │
│                │  │                             │   │  │ completed   │  │
│  ► 2. Check    │  │  Verify the main battery    │   │  ├─────────────┤  │
│    ► 2.1 ◀──────│  │  voltage is within nominal  │   │  │ 14:25:28    │  │
│    ○ 2.2       │  │  operating range.           │   │  │ jsmith      │  │
│                │  │                             │   │  │ signed off  │  │
│  ○ 3. Execute  │  │  ┌─ ⚠ CAUTION ───────────┐  │   │  │ Step 1.1    │  │
│    ○ 3.1       │  │  │ High voltage - verify  │  │   │  ├─────────────┤  │
│    ○ 3.2       │  │  │ safety equipment       │  │   │  │ 14:24:15    │  │
│                │  │  └───────────────────────┘  │   │  │ Execution   │  │
│                │  │                             │   │  │ started     │  │
│  ───────────   │  │  ┌─ Telemetry ───────────┐  │   │  └─────────────┘  │
│  Elapsed:      │  │  │ ⚡ EPS.battery_voltage │  │   │                   │
│  00:02:17      │  │  │                        │  │   │  [Comments 3]     │
│                │  │  │      25.4 V  ✓         │  │   │  [Redlines 0]     │
│  Est. Remain:  │  │  │                        │  │   │                   │
│  00:08:30      │  │  │  Pass: >= 24.0 V       │  │   │                   │
│                │  │  └───────────────────────┘  │   │                   │
│                │  │                             │   │                   │
│                │  │  ┌─ Number Input ────────┐  │   │                   │
│                │  │  │ Observed voltage:     │  │   │                   │
│                │  │  │ ┌─────────────────┐   │  │   │                   │
│                │  │  │ │ 25.3         V  │   │  │   │                   │
│                │  │  │ └─────────────────┘   │  │   │                   │
│                │  │  └───────────────────────┘  │   │                   │
│                │  │                             │   │                   │
│                │  │  ┌───────────────────────┐  │   │                   │
│                │  │  │      SIGN OFF         │  │   │                   │
│                │  │  │  Role: Operator       │  │   │                   │
│                │  │  └───────────────────────┘  │   │                   │
│                │  │                             │   │                   │
│                │  └─────────────────────────────┘   │                   │
│                │                                     │                   │
│                │  [Skip Step]  [Add Comment]         │                   │
│                │                                     │                   │
└────────────────┴─────────────────────────────────────┴───────────────────┘
│                            [Pause]  [Abort]                              │
└──────────────────────────────────────────────────────────────────────────┘
```

### Progress Sidebar

```elixir
def execution_progress(assigns) do
  ~H"""
  <div class="hud-panel p-3 space-y-2">
    <div class="hud-label">PROGRESS</div>

    <%= for section <- @sections do %>
      <div class="space-y-1">
        <!-- Section header -->
        <div class="flex items-center gap-2 text-sm">
          <.section_status_icon status={section.status} />
          <span class={section_text_class(section.status)}>
            <%= section.position %>. <%= section.name %>
          </span>
        </div>

        <!-- Steps -->
        <div class="ml-4 space-y-0.5">
          <%= for step <- section.steps do %>
            <div
              class={[
                "flex items-center gap-2 text-sm py-1 px-2 rounded cursor-pointer",
                step_row_class(step, @active_step_id)
              ]}
              phx-click="jump_to_step"
              phx-value-id={step.id}
            >
              <.step_status_icon status={step.status} />
              <span class={step_text_class(step.status)}>
                <%= step.title || step.name %>
              </span>

              <!-- Active indicator -->
              <%= if step.id == @active_step_id do %>
                <span class="ml-auto">
                  <.icon name="hero-chevron-left" class="size-4 text-primary animate-pulse" />
                </span>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <!-- Timing -->
    <div class="hud-divider my-3" />

    <div class="space-y-2">
      <.hud_data label="Elapsed" value={format_duration(@elapsed)} />
      <.hud_data label="Est. Remain" value={format_duration(@estimated_remaining)} />
    </div>
  </div>
  """
end

defp step_status_icon(%{status: :completed} = assigns) do
  ~H"""
  <.icon name="hero-check-circle" class="size-4 text-success" />
  """
end

defp step_status_icon(%{status: :active} = assigns) do
  ~H"""
  <span class="relative flex size-4">
    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75"></span>
    <span class="relative inline-flex rounded-full size-4 bg-primary"></span>
  </span>
  """
end

defp step_status_icon(%{status: :awaiting_signoff} = assigns) do
  ~H"""
  <span class="relative flex size-4">
    <span class="animate-pulse absolute inline-flex h-full w-full rounded-full bg-secondary opacity-75"></span>
    <.icon name="hero-pencil-square" class="relative size-4 text-secondary" />
  </span>
  """
end

defp step_status_icon(%{status: :pending} = assigns) do
  ~H"""
  <span class="size-4 rounded-full border-2 border-base-300"></span>
  """
end

defp step_status_icon(%{status: :skipped} = assigns) do
  ~H"""
  <.icon name="hero-minus-circle" class="size-4 text-base-content/30" />
  """
end

defp step_status_icon(%{status: :failed} = assigns) do
  ~H"""
  <.icon name="hero-x-circle" class="size-4 text-error" />
  """
end

defp step_status_icon(%{status: :blocked} = assigns) do
  ~H"""
  <.icon name="hero-lock-closed" class="size-4 text-warning" />
  """
end
```

### Active Step Card

```elixir
def active_step_card(assigns) do
  ~H"""
  <div class={[
    "hud-panel hud-border-glow relative overflow-hidden",
    step_glow_class(@step.status)
  ]}>
    <!-- Status bar at top -->
    <div class={[
      "h-1 w-full",
      step_bar_class(@step.status)
    ]} />

    <!-- Step header -->
    <div class="p-4 border-b border-base-300">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-xs text-base-content/50 mb-1">
            Step <%= @step.position %>
          </div>
          <h2 class="text-lg font-semibold">
            <%= @step.title || @step.name %>
          </h2>
        </div>

        <.step_status_badge status={@step.status} />
      </div>

      <!-- Dependencies warning if blocked -->
      <%= if @step.status == :blocked do %>
        <div class="mt-2 flex items-center gap-2 text-warning text-sm">
          <.icon name="hero-lock-closed" class="size-4" />
          <span>Waiting for: <%= Enum.join(@blocking_steps, ", ") %></span>
        </div>
      <% end %>
    </div>

    <!-- Blocks -->
    <div class="p-4 space-y-4">
      <%= for block <- @step.blocks do %>
        <.execution_block
          block={block}
          block_execution={get_block_execution(@step_execution, block.id)}
          context={@context}
        />
      <% end %>
    </div>

    <!-- Signoff section -->
    <%= if @step.requires_signoff do %>
      <div class="p-4 border-t border-base-300 bg-base-200/50">
        <.signoff_panel
          step={@step}
          step_execution={@step_execution}
          current_user={@current_user}
          can_sign_off={@can_sign_off}
        />
      </div>
    <% end %>

    <!-- Step actions -->
    <div class="p-4 border-t border-base-300 flex justify-between">
      <div class="flex gap-2">
        <button class="btn btn-ghost btn-sm" phx-click="skip_step">
          <.icon name="hero-forward" class="size-4" />
          Skip
        </button>
        <button class="btn btn-ghost btn-sm" phx-click="add_comment">
          <.icon name="hero-chat-bubble-left" class="size-4" />
          Comment
        </button>
        <button class="btn btn-ghost btn-sm" phx-click="suggest_edit">
          <.icon name="hero-pencil" class="size-4" />
          Suggest Edit
        </button>
      </div>
    </div>
  </div>
  """
end
```

### Block Execution States

```elixir
def execution_block(assigns) do
  ~H"""
  <div class={[
    "rounded-lg p-3",
    block_execution_class(@block, @block_execution)
  ]}>
    <%= case @block.block_type do %>
      <% :text -> %>
        <div class="prose prose-sm prose-invert max-w-none">
          <%= raw(Earmark.as_html!(@block.content.markdown)) %>
        </div>

      <% :note -> %>
        <div class="flex gap-3 items-start">
          <.icon name="hero-information-circle" class="size-5 text-info shrink-0" />
          <p class="text-sm"><%= @block.content.text %></p>
        </div>

      <% :caution -> %>
        <div class="flex gap-3 items-start bg-warning/10 -m-3 p-3 rounded-lg border-l-2 border-warning">
          <.icon name="hero-exclamation-triangle" class="size-5 text-warning shrink-0" />
          <p class="text-sm font-medium"><%= @block.content.text %></p>
        </div>

      <% :warning -> %>
        <div class="flex gap-3 items-start bg-error/10 -m-3 p-3 rounded-lg border-l-2 border-error">
          <.icon name="hero-x-circle" class="size-5 text-error shrink-0" />
          <p class="text-sm font-medium"><%= @block.content.text %></p>
        </div>

      <% :number_input -> %>
        <.number_input_execution
          block={@block}
          block_execution={@block_execution}
        />

      <% :telemetry_value -> %>
        <.telemetry_value_execution
          block={@block}
          block_execution={@block_execution}
          context={@context}
        />

      <% :telemetry_check -> %>
        <.telemetry_check_execution
          block={@block}
          block_execution={@block_execution}
          context={@context}
        />

      <% :command -> %>
        <.command_execution
          block={@block}
          block_execution={@block_execution}
          context={@context}
        />

      <% _ -> %>
        <div class="text-sm text-base-content/50">
          Block: <%= @block.block_type %>
        </div>
    <% end %>
  </div>
  """
end
```

### Live Telemetry Display

```elixir
def telemetry_value_execution(assigns) do
  ~H"""
  <div class="flex items-center gap-3">
    <.icon name="hero-bolt" class="size-5 text-secondary" />

    <div class="flex-1">
      <div class="text-xs text-base-content/50 mb-1 font-mono">
        <%= @block.content.item %>
      </div>

      <div class="flex items-baseline gap-2">
        <!-- Live value with glow effect -->
        <span
          class={[
            "font-mono text-2xl tabular-nums",
            value_quality_class(@block_execution.telemetry_reading.quality)
          ]}
          phx-hook="LiveTelemetry"
          id={"telemetry-#{@block.id}"}
          data-item={@block.content.item}
        >
          <%= format_value(
            @block_execution.telemetry_reading.value,
            @block.content.format
          ) %>
        </span>

        <span class="text-sm text-base-content/50">
          <%= @block.content.unit %>
        </span>

        <!-- Quality indicator -->
        <.quality_badge quality={@block_execution.telemetry_reading.quality} />
      </div>

      <!-- Timestamp -->
      <div class="text-xs text-base-content/30 mt-1 font-mono">
        <%= format_timestamp(@block_execution.telemetry_reading.timestamp) %>
      </div>
    </div>
  </div>
  """
end

defp value_quality_class(:good), do: "text-primary glow-cyan"
defp value_quality_class(:stale), do: "text-warning"
defp value_quality_class(:bad), do: "text-error"
defp value_quality_class(:manual), do: "text-secondary"
defp value_quality_class(_), do: "text-base-content/50"
```

### Telemetry Check with Pass/Fail

```elixir
def telemetry_check_execution(assigns) do
  ~H"""
  <div class={[
    "rounded-lg p-4",
    check_result_class(@block_execution.passed)
  ]}>
    <div class="flex items-start gap-3">
      <!-- Status icon -->
      <div class="mt-1">
        <%= if @block_execution.passed do %>
          <.icon name="hero-check-circle" class="size-6 text-success" />
        <% else %>
          <.icon name="hero-x-circle" class="size-6 text-error animate-pulse" />
        <% end %>
      </div>

      <div class="flex-1">
        <!-- Item path -->
        <div class="text-xs text-base-content/50 font-mono mb-1">
          <%= @block.content.item %>
        </div>

        <!-- Value display -->
        <div class="flex items-baseline gap-3 mb-2">
          <span class="font-mono text-xl tabular-nums">
            <%= format_value(@block_execution.telemetry_reading.value, @block.content.format) %>
          </span>
          <span class="text-sm text-base-content/50">
            <%= @block.content.unit %>
          </span>
        </div>

        <!-- Criteria -->
        <div class="flex items-center gap-2 text-sm">
          <span class="text-base-content/50">Pass criteria:</span>
          <code class="px-1.5 py-0.5 rounded bg-base-300 font-mono text-xs">
            <%= @block.content.pass_criteria %>
          </code>
        </div>

        <!-- Failure message if failed -->
        <%= if !@block_execution.passed && @block_execution.validation_message do %>
          <div class="mt-2 text-sm text-error">
            <%= @block_execution.validation_message %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
  """
end

defp check_result_class(true), do: "bg-success/10 border border-success/30"
defp check_result_class(false), do: "bg-error/10 border border-error/30"
defp check_result_class(nil), do: "bg-base-300/50 border border-base-300"
```

### Signoff Panel

```elixir
def signoff_panel(assigns) do
  ~H"""
  <div class="space-y-3">
    <div class="flex items-center justify-between">
      <div class="hud-label">SIGNOFF REQUIRED</div>

      <%= if length(@step.required_roles) > 0 do %>
        <div class="flex gap-1">
          <%= for role <- @step.required_roles do %>
            <span class="badge badge-sm badge-outline"><%= role %></span>
          <% end %>
        </div>
      <% end %>
    </div>

    <!-- Existing signoffs -->
    <%= if length(@step_execution.signoffs) > 0 do %>
      <div class="space-y-2">
        <%= for signoff <- @step_execution.signoffs do %>
          <div class="flex items-center gap-2 text-sm">
            <.icon name="hero-check" class="size-4 text-success" />
            <.avatar user={signoff.user} size={:xs} />
            <span><%= signoff.user.name %></span>
            <span class="text-base-content/50">as <%= signoff.role %></span>
            <span class="text-base-content/30 ml-auto">
              <%= format_time(signoff.inserted_at) %>
            </span>
          </div>
        <% end %>
      </div>
    <% end %>

    <!-- Signoff button -->
    <%= if @can_sign_off do %>
      <div class="flex gap-2">
        <select class="select select-sm flex-1" id="signoff-role">
          <%= for role <- available_roles(@current_user, @step) do %>
            <option value={role}><%= role %></option>
          <% end %>
        </select>

        <button
          class="btn btn-primary"
          phx-click="sign_off"
          phx-value-step-id={@step.id}
        >
          <.icon name="hero-check" class="size-5" />
          Sign Off
        </button>
      </div>
    <% else %>
      <div class="text-sm text-base-content/50 flex items-center gap-2">
        <.icon name="hero-lock-closed" class="size-4" />
        <%= signoff_blocked_reason(@step_execution, @current_user) %>
      </div>
    <% end %>
  </div>
  """
end
```

### Activity Feed

```elixir
def activity_feed(assigns) do
  ~H"""
  <div class="hud-panel p-3">
    <div class="hud-label mb-3">ACTIVITY</div>

    <div class="space-y-3 max-h-96 overflow-y-auto">
      <%= for event <- @events do %>
        <div class="flex gap-2 text-sm">
          <div class="text-base-content/30 font-mono text-xs w-16 shrink-0">
            <%= format_time(event.timestamp) %>
          </div>

          <div class="flex-1">
            <.activity_event event={event} />
          </div>
        </div>
      <% end %>
    </div>

    <!-- Quick actions -->
    <div class="mt-4 pt-3 border-t border-base-300 flex gap-2">
      <button class="btn btn-ghost btn-sm flex-1" phx-click="show_comments">
        <.icon name="hero-chat-bubble-left" class="size-4" />
        Comments (<%= @comment_count %>)
      </button>
      <button class="btn btn-ghost btn-sm flex-1" phx-click="show_redlines">
        <.icon name="hero-pencil" class="size-4" />
        Redlines (<%= @redline_count %>)
      </button>
    </div>
  </div>
  """
end

def activity_event(%{event: %{type: :step_completed}} = assigns) do
  ~H"""
  <div class="flex items-center gap-2">
    <.icon name="hero-check-circle" class="size-4 text-success" />
    <span>Step <strong><%= @event.step_title %></strong> completed</span>
  </div>
  """
end

def activity_event(%{event: %{type: :step_signed_off}} = assigns) do
  ~H"""
  <div class="flex items-center gap-2">
    <.avatar user={@event.user} size={:xs} />
    <span>
      <strong><%= @event.user.name %></strong> signed off
      <strong><%= @event.step_title %></strong>
    </span>
  </div>
  """
end

def activity_event(%{event: %{type: :comment_added}} = assigns) do
  ~H"""
  <div class="flex items-start gap-2">
    <.avatar user={@event.user} size={:xs} />
    <div>
      <strong><%= @event.user.name %></strong>
      <p class="text-base-content/70 mt-0.5"><%= truncate(@event.content, 80) %></p>
    </div>
  </div>
  """
end

def activity_event(%{event: %{type: :telemetry_check_passed}} = assigns) do
  ~H"""
  <div class="flex items-center gap-2">
    <.icon name="hero-bolt" class="size-4 text-secondary" />
    <span>
      <code class="text-xs"><%= @event.item %></code>
      = <%= @event.value %> ✓
    </span>
  </div>
  """
end
```

---

## Real-Time Updates

### LiveView Subscriptions

```elixir
defmodule CadenceWeb.ProcedureExecutionLive do
  use CadenceWeb, :live_view

  def mount(%{"id" => execution_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to execution events
      Phoenix.PubSub.subscribe(
        Cadence.PubSub,
        "procedure_execution:#{execution_id}"
      )

      # Subscribe to telemetry for active blocks
      subscribe_to_telemetry(socket.assigns.execution)
    end

    {:ok, socket}
  end

  # Handle execution events
  def handle_info({:execution_event, event}, socket) do
    socket = case event.type do
      :step_activated ->
        socket
        |> update_step(event.step_id, &Map.put(&1, :status, :active))
        |> scroll_to_step(event.step_id)
        |> subscribe_to_step_telemetry(event.step_id)

      :step_completed ->
        socket
        |> update_step(event.step_id, &Map.put(&1, :status, :completed))
        |> unsubscribe_from_step_telemetry(event.step_id)

      :block_value_entered ->
        update_block_execution(socket, event.block_id, event.value)

      :signoff_added ->
        add_signoff(socket, event.step_id, event.signoff)

      _ ->
        socket
    end

    {:noreply, add_activity_event(socket, event)}
  end

  # Handle live telemetry updates
  def handle_info({:telemetry_update, item_path, reading}, socket) do
    {:noreply, update_telemetry_reading(socket, item_path, reading)}
  end
end
```

### Telemetry Hook (JavaScript)

```javascript
// assets/js/hooks/live_telemetry.js
export const LiveTelemetry = {
  mounted() {
    this.item = this.el.dataset.item
    this.previousValue = null

    // Flash on value change
    this.handleEvent("telemetry_update", ({item, value, quality}) => {
      if (item !== this.item) return

      if (this.previousValue !== null && value !== this.previousValue) {
        this.flash()
      }
      this.previousValue = value
    })
  },

  flash() {
    this.el.classList.add('telemetry-flash')
    setTimeout(() => {
      this.el.classList.remove('telemetry-flash')
    }, 300)
  }
}
```

```css
/* Telemetry value flash animation */
.telemetry-flash {
  animation: telemetry-flash 0.3s ease-out;
}

@keyframes telemetry-flash {
  0% {
    background-color: rgba(125, 207, 255, 0.3);
    transform: scale(1.02);
  }
  100% {
    background-color: transparent;
    transform: scale(1);
  }
}
```

---

## Mobile Considerations

### Responsive Layout

```
Desktop (> 1024px)          Tablet (768-1024px)       Mobile (< 768px)
┌─────┬────────┬─────┐      ┌─────┬────────────┐     ┌────────────────┐
│     │        │     │      │     │            │     │   Step 2.1     │
│ Nav │  Step  │ Act │      │ Nav │    Step    │     │   ══════════   │
│     │        │     │      │     │            │     │                │
│     │        │     │      │     │            │     │   [Content]    │
│     │        │     │      │     │            │     │                │
│     │        │     │      │     │            │     │                │
│     │        │     │      │     │            │     ├────────────────┤
│     │        │     │      │     │            │     │ ◀ 2/12 ▶      │
└─────┴────────┴─────┘      └─────┴────────────┘     └────────────────┘
3 columns                   2 columns                 Single column
                           (Activity in drawer)       (Nav in header)
```

### Touch-Friendly Components

```elixir
def mobile_step_navigation(assigns) do
  ~H"""
  <div class="fixed bottom-0 left-0 right-0 bg-base-200 border-t border-base-300 p-2 flex items-center justify-between md:hidden">
    <button
      class="btn btn-ghost"
      phx-click="previous_step"
      disabled={@is_first_step}
    >
      <.icon name="hero-chevron-left" class="size-6" />
    </button>

    <div class="text-center">
      <div class="text-sm font-medium"><%= @current_step.title %></div>
      <div class="text-xs text-base-content/50">
        Step <%= @current_index + 1 %> of <%= @total_steps %>
      </div>
    </div>

    <button
      class="btn btn-ghost"
      phx-click="next_step"
      disabled={@is_last_step}
    >
      <.icon name="hero-chevron-right" class="size-6" />
    </button>
  </div>
  """
end
```

---

## Summary

The procedures UI builds on Cadence's HUD aesthetic while providing Epsilon3-level functionality:

| Aspect | Design Choice |
|--------|--------------|
| **Color** | Step states use existing palette (cyan=active, purple=awaiting, green=complete) |
| **Layout** | 3-column editor, 3-column execution (responsive) |
| **Blocks** | Color-coded left border, type label on hover |
| **Telemetry** | Glow effect on live values, flash on change |
| **Signoffs** | Prominent button, existing signoff list |
| **Progress** | Visual sidebar with pulsing active indicator |
| **Activity** | Timestamped feed, comment/redline counts |
| **Mobile** | Swipeable steps, fixed bottom nav |

The result should feel like a natural extension of Cadence's mission control aesthetic while matching Epsilon3's operator experience.
