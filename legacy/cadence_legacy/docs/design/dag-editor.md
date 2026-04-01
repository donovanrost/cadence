---
title: DAG Procedure Editor Design
tags: [design, procedures, dag, ui]
related:
  - "[[procedure]]"
  - "[[sequence]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# DAG Procedure Editor Design

## Overview

A visual editor for building DAG-based procedures with real-time text synchronization.

## Goals

1. **Visual-first editing** - Drag, connect, and configure steps on a canvas
2. **Text parity** - YAML editor with equal functionality, live sync
3. **Progressive disclosure** - Add steps quickly, configure details later
4. **Validation feedback** - Visual indicators for incomplete/invalid steps

## Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Procedure: [name]                                       [Cancel] [Save]    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                         ││
│  │     ┌──────────────────┐              ┌────────────────────────────────┐││
│  │     │ ⚡ enable_bus    │              │  TEXT EDITOR (30% width)      │││
│  │     │──────────────────│              │  z-index above canvas         │││
│  │     │ ENABLE_BUS       │              │                               │││
│  │     │ bus: PRIMARY     │              │  steps:                       │││
│  │     └────────┬─────────┘              │    enable_bus:                │││
│  │              │                        │      type: command            │││
│  │              ▼                        │      ...                      │││
│  │     ┌──────────────────┐              │                               │││
│  │     │ ⏱ wait_stable   │              └────────────────────────────────┘││
│  │     │──────────────────│                                               ││
│  │     │ 500ms            │                                               ││
│  │     └──────────────────┘                                               ││
│  │                                                                         ││
│  │     ┌───────────────────────────────────┐                               ││
│  │     │ [+ Add] │ [−][100%][+] │ [⊞][◎] │ [T] │  ← Floating toolbar     ││
│  │     └───────────────────────────────────┘                               ││
│  │                                                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

When a node is selected, side panel slides in:

┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌────────────────────────────────────────────────┬────────────────────────┐│
│  │                                                │ ✕ enable_bus          ││
│  │     [Canvas with nodes]                        │─────────────────────────│
│  │                                                │ Name: [enable_bus   ]  ││
│  │                                                │ Type: [command    ▼]  ││
│  │                                                │                        ││
│  │                                                │ ── Configuration ──    ││
│  │                                                │ Command: [ENABLE_BUS]  ││
│  │                                                │ Arguments:             ││
│  │                                                │   bus: [PRIMARY   ▼]  ││
│  │                                                │                        ││
│  │                                                │ ── Dependencies ──     ││
│  │                                                │ ☐ wait_stable          ││
│  │                                                │                        ││
│  │                                                │ [Delete Step]          ││
│  └────────────────────────────────────────────────┴────────────────────────┘│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Floating Toolbar

Segmented toolbar anchored to bottom of canvas:

| Segment | Controls | Purpose |
|---------|----------|---------|
| Add | `[+ Add]` | Opens add step modal |
| Zoom | `[−] [100%] [+]` | Zoom controls |
| View | `[⊞] [◎]` | Minimap toggle, fit to view |
| Text | `[T]` | Toggle text editor overlay |

### 2. Canvas (JS Hook)

SVG-based canvas with:
- **dagre** for automatic layout
- Pan (drag background) and zoom (scroll wheel)
- Node selection (click)
- Edge creation (drag from node handle)
- Real-time sync with LiveView state

### 3. Node Rendering

Each node displays:
- Type icon
- Step name
- Key configuration summary (type-specific)

**Node states:**
- Default: gray border
- Selected: blue border + glow
- Incomplete: red border + shimmer animation
- Hover: lighter background

**Type-specific summaries:**

| Type | Display |
|------|---------|
| `command` | Command name + key args |
| `wait` | Duration (human readable) |
| `wait_for` | `item operator value`, timeout |
| `check` | Condition, on_fail action |
| `assert` | Condition |
| `log` | Level + truncated message |
| `set` | `name = value` |
| `branch` | Condition + goto |
| `label` | Label name |

### 4. Add Step Modal

Minimal modal for quick step creation:
1. Step name (auto-generated default)
2. Type selector (icon grid)
3. Optional quick config fields (type-specific)
4. All fields optional except name - incomplete steps show shimmer

### 5. Side Panel

Slides in from right when node selected:
- Full configuration form for step type
- Dependency checkboxes
- Delete button
- Close button

### 6. Text Editor Overlay

- 30% width, positioned on right
- Above canvas (higher z-index)
- YAML format with syntax highlighting
- Bidirectional sync with canvas
- CodeMirror or Monaco editor

## Step Types

### command
```yaml
type: command
name: ENABLE_BUS        # required
args:                   # optional
  bus: PRIMARY
```

### wait
```yaml
type: wait
duration: 500           # required, milliseconds
```

### wait_for
```yaml
type: wait_for
item: THERMAL.temp      # required
operator: ">="          # default: "=="
value: 25               # required
timeout: 30000          # default: 30000ms
```

### check
```yaml
type: check
condition: voltage >= 24  # required
on_fail: abort            # default: "abort"
message: "Voltage low"    # optional
```

### assert
```yaml
type: assert
condition: mode != FAULT  # required
message: "In fault mode"  # optional
```

### log
```yaml
type: log
level: info               # default: "info"
message: "Starting..."    # optional
```

### set
```yaml
type: set
name: start_temp          # required
value: telemetry.temp     # required
```

### branch
```yaml
type: branch
condition: status == SAFE # required
goto: safe_handler        # required
else_goto: null           # optional
```

### label
```yaml
type: label
name: safe_handler        # required
```

## Validation

Steps are validated in real-time. Invalid/incomplete steps show:
- Red border with shimmer animation
- Warning icon in node
- Tooltip with validation message

Validation rules per type defined in `Cadence.Procedures.Sequences.Step`.

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         LiveView                                │
│                                                                 │
│  assigns:                                                       │
│    - steps: %{name => %{type, ...}}                            │
│    - selected_step: nil | step_name                            │
│    - validation_errors: %{step_name => [errors]}               │
│    - text_source: YAML string                                  │
│    - show_text_editor: boolean                                 │
│    - zoom_level: float                                         │
│                                                                 │
│  events:                                                        │
│    - add_step(type, name, config)                              │
│    - update_step(name, config)                                 │
│    - delete_step(name)                                         │
│    - rename_step(old_name, new_name)                           │
│    - connect_steps(from, to)                                   │
│    - disconnect_steps(from, to)                                │
│    - select_step(name)                                         │
│    - deselect_step()                                           │
│    - update_from_text(yaml_source)                             │
│    - toggle_text_editor()                                      │
│    - set_zoom(level)                                           │
│    - fit_to_view()                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────────┐        ┌─────────────────────┐
│  DagCanvas Hook     │        │  TextEditor Hook    │
│                     │        │                     │
│  pushEvent() ──────────────► │  handleEvent()      │
│  handleEvent() ◄──────────── │  pushEvent()        │
│                     │        │                     │
│  - Renders SVG      │        │  - CodeMirror       │
│  - dagre layout     │        │  - YAML parse       │
│  - User interactions│        │  - Sync on change   │
└─────────────────────┘        └─────────────────────┘
```

## File Structure

```
lib/cadence_web/live/procedure_live/
├── edit.ex                      # Main LiveView (full page)
├── edit.html.heex               # Template
├── components/
│   ├── toolbar.ex               # Floating toolbar
│   ├── add_step_modal.ex        # Add step modal
│   ├── side_panel.ex            # Step configuration panel
│   └── step_fields.ex           # Type-specific form fields

assets/js/hooks/
├── dag_canvas.js                # Canvas hook (SVG + dagre)
└── text_editor.js               # CodeMirror hook
```

## Dependencies

**JavaScript (npm):**
- `dagre` - Graph layout algorithm (~8kb)
- `codemirror` - Text editor (or Monaco)
- `@codemirror/lang-yaml` - YAML syntax highlighting

## Migration Path

1. Build new `/procedures/:id/edit` route
2. Keep existing modal editor functional
3. Link to new editor from procedure show/index pages
4. Once stable, remove old modal-based editor

## Future Enhancements

- Undo/redo support
- Copy/paste steps
- Step templates/snippets
- Keyboard shortcuts
- Collaborative editing
- Version diffing
