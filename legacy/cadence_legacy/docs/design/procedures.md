---
title: Procedures Design Document
aliases: [procedures design, procedure system]
tags: [design, procedures, sequences, automations]
related:
  - "[[procedure]]"
  - "[[sequence]]"
  - "[[automation]]"
  - "[[002-luerl-for-procedures]]"
  - "[[recording]]"
created: 2024-12-01
updated: 2026-01-29
status: active
---

# Procedures Design Document

## Overview

Cadence Procedures is a comprehensive system for defining, reviewing, and executing operational workflows. The system supports:

| Feature | Description | Complexity |
|---------|-------------|------------|
| **DAG Procedures** | Step-based workflows with parallel execution via dependencies | Medium |
| **Scripts** | Sandboxed Lua for complex/custom operations | Medium-High |
| **[Automations](../glossary/automation.md)** | Trigger → Action rules | Low |
| **Campaigns** | Orchestration across targets/time | High (deferred) |

All features share a common execution runtime built on Luerl (Lua in Erlang). See [ADR-002: Luerl for Procedure Execution](../decisions/002-luerl-for-procedures.md) for rationale.

## Key Concepts

### Procedure Hierarchy

Procedures follow a hierarchical structure:

```
Procedure
└── ProcedureVersion (versioned snapshots with approval workflow)
    └── ProcedureSection (grouping for UI organization)
        └── ProcedureStep (unit of work with signoff requirements)
            └── ProcedureBlock (atomic content: text, inputs, commands, telemetry)
```

### Execution Modes

Procedure versions can specify an execution mode:

- **`:manual`** - Operator must manually trigger each step
- **`:assisted`** - System suggests next step, operator confirms
- **`:automatic`** - Steps execute automatically when dependencies are met

### Review Workflow

Procedure versions go through an approval workflow:

1. **`:draft`** - Being edited, not ready for use
2. **`:in_review`** - Submitted for approval
3. **`:changes_requested`** - Reviewer requested changes
4. **`:approved`** - Approved for execution
5. **`:closed`** - Abandoned (like closing a PR without merging)
6. **`:deprecated`** - No longer recommended for use

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Triggers                                 │
│  (Oban Cron, Event subscriptions, Manual via LiveView)          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Execution Process (V2 Architecture)                 │
│  lib/cadence/procedures/v2/execution_process.ex                 │
│                                                                  │
│  - GenServer per execution holding state                        │
│  - Delegates to ExecutionStrategy based on execution_mode       │
│  - Tracks step/block completion via StepExecution records       │
│  - Persists state changes via ExecutionPersistence              │
│  - Emits events via ProcedureExecutionEvent                     │
└─────────────────────────────────────────────────────────────────┘
                                │
           ┌────────────────────┼────────────────────┐
           ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Manual Strategy │  │Assisted Strategy│  │Automatic Strategy│
│  (Operator      │  │  (System        │  │  (Auto-advance  │
│   drives each   │  │   suggests,     │  │   when deps     │
│   step)         │  │   operator      │  │   are met)      │
│                 │  │   confirms)     │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Cadence Runtime API (Lua)

Exposed to script-type procedures via `lib/cadence/procedures/runtime/cadence_api.ex`:

```lua
-- Telemetry access (read-only)
cadence.telemetry.get("HEALTH.cpu_temp")
cadence.telemetry.wait_for("HEALTH.cpu_temp", "<", 80, timeout_ms)

-- Command dispatch
cadence.command.send("POWER_ON", {subsystem = "PAYLOAD"})
cadence.command.send_and_verify("POWER_ON", {subsystem = "PAYLOAD"}, timeout_ms)

-- Flow control
cadence.wait(milliseconds)
cadence.log("message")
cadence.checkpoint("step_name")  -- for resume after pause/failure
```

## Feature Details

### DAG Procedures

DAG (Directed Acyclic Graph) procedures organize work into sections, steps, and blocks:

#### Sections
Logical groupings of steps for UI organization. Can be collapsed/expanded.

#### Steps
The primary unit of work. Each step can:
- Contain multiple blocks (content, inputs, telemetry, commands)
- Require signoff from specific roles
- Depend on other steps completing first
- Have conditions that skip execution
- Define behavior on failure (`:abort`, `:continue`, `:pause`)

#### Blocks
Atomic units of content within a step. Block types include:

**Content Blocks (display only)**
- `:text` - Rich markdown text
- `:note` - Info callout
- `:caution` - Yellow warning callout
- `:warning` - Red critical warning callout
- `:reference` - Link to external document

**Data Collection Blocks**
- `:text_input` - Free text entry
- `:number_input` - Numeric with validation
- `:select_input` - Dropdown/radio selection
- `:checkbox_input` - Boolean or multi-select
- `:timestamp_input` - Date/time capture
- `:duration_input` - Time duration
- `:attachment_input` - File upload
- `:signature_input` - Operator signature

**Telemetry Blocks**
- `:telemetry_value` - Display current value
- `:telemetry_check` - Auto-validate against criteria
- `:telemetry_wait` - Wait for condition

**Command Blocks**
- `:command` - Send a single command
- `:command_sequence` - Send multiple commands in order

**Reference Blocks**
- `:input_reference` - Display value from earlier input
- `:variable_display` - Display procedure variable
- `:procedure_call` - Execute child procedure

### Step Dependencies

Steps can declare dependencies on other steps:

```elixir
%ProcedureStep{
  name: "enable_payload",
  depends_on: ["verify_power", "thermal_check"],
  dependency_logic: :all  # Must complete all (:all) or any one (:any)
}
```

### Signoff Requirements

Steps can require signoff from specific roles:

```elixir
%ProcedureStep{
  name: "critical_command",
  requires_signoff: true,
  required_roles: ["operator", "supervisor"],
  signoff_logic: :any  # Any role can sign off (:any) or all must (:all)
}
```

### Conditional Execution

Steps can be conditionally skipped:

```elixir
%ProcedureStep{
  name: "backup_heater",
  condition: "target.THERMAL.primary_heater_status == 'FAILED'"
}
```

### Automations

Simple trigger → action rules. Lighter weight than full procedures.

Triggers:
- Event-based (alarm triggered, pass started, etc.)
- Executed via Oban jobs via `lib/cadence/procedures/v2/automation_runner.ex`

### Scripts

Raw Lua access for power users. Full flexibility, requires code review for approval.
Source stored as `%{"code" => "lua source..."}` in procedure version.

### Campaigns (Deferred)

Orchestration across multiple targets over time. Examples:
- Firmware rollout to constellation
- Phased orbit adjustments
- Multi-day commissioning

## Execution State Machine

Procedure executions follow a strict state machine:

```
                    ┌──────────────┐
                    │   pending    │
                    └──────┬───────┘
                           │ start
                           ▼
    ┌──────────────────────────────────────┐
    │              running                  │
    └───┬────────┬────────┬────────┬───────┘
        │        │        │        │
        │pause   │complete│fail    │cancel
        ▼        │        │        │
    ┌───────┐    │        │        │
    │pausing│────┼────────┼────────┤
    └───┬───┘    │        │        │
        │        │        │        │
        │done    │        │        │
        ▼        ▼        ▼        ▼
    ┌──────┐ ┌─────────┐ ┌──────┐ ┌─────────┐
    │paused│ │completed│ │failed│ │cancelled│
    └──┬───┘ └─────────┘ └──────┘ └─────────┘
       │         (terminal states)
       │resume
       ▼
    (back to running)
```

### Valid Transitions

| From     | To                                        |
|----------|-------------------------------------------|
| pending  | running, cancelled                        |
| running  | pausing, completed, failed, cancelled     |
| pausing  | paused, running*, failed, cancelled       |
| paused   | running, cancelled                        |
| completed| (none - terminal)                         |
| failed   | (none - terminal)                         |
| cancelled| (none - terminal)                         |

*pausing → running: allowed for "cancel pause" before it takes effect

When paused, operators can:
1. **Resume** - Continue from checkpoint
2. **Cancel** - Stop entirely
3. **Skip step** - Jump over current step (escape hatch)

## Data Model

### procedures
`lib/cadence/procedures/schemas/procedure.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| organization_id | uuid | FK to organizations |
| mission_id | uuid | FK to missions (nullable for org-wide) |
| name | string | Procedure name (unique per org/mission) |
| description | string | Optional description |
| type | enum | `:dag` or `:script` |
| tags | array | Searchable tags |
| current_version_id | uuid | FK to latest approved/draft version |

### procedure_versions
`lib/cadence/procedures/schemas/procedure_version.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| procedure_id | uuid | FK to procedures |
| version_number | integer | Sequential version number |
| source | map | Step definitions (DAG) or `%{"code" => "..."}` (script) |
| parameters_schema | map | Runtime parameter definitions |
| status | enum | `:draft`, `:in_review`, `:changes_requested`, `:approved`, `:closed`, `:deprecated` |
| execution_mode | enum | `:manual`, `:assisted`, `:automatic` |
| allow_suggested_edits | boolean | Allow redlines during execution |
| allow_hazardous_commands | boolean | Bypass hazardous command confirmation |
| change_summary | string | Description of changes in this version |
| created_by_id | uuid | FK to users |
| approved_by_id | uuid | FK to users |
| approved_at | datetime | When approved |
| submitted_by_id | uuid | FK to users |
| submitted_at | datetime | When submitted for review |

### procedure_sections
`lib/cadence/procedures/schemas/procedure_section.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| procedure_version_id | uuid | FK to procedure_versions |
| name | string | Section name |
| description | string | Optional description |
| position | integer | Order within version |
| collapsed_by_default | boolean | UI display hint |

### procedure_steps
`lib/cadence/procedures/schemas/procedure_step.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| section_id | uuid | FK to procedure_sections |
| name | string | Step identifier (for dependencies) |
| title | string | Display title |
| position | integer | Order within section |
| requires_signoff | boolean | Requires operator signoff |
| required_roles | array | Roles that can sign off |
| signoff_logic | enum | `:any` or `:all` |
| depends_on | array | Step names this depends on |
| dependency_logic | enum | `:all` or `:any` |
| condition | string | Skip condition expression |
| on_fail | enum | `:abort`, `:continue`, `:pause` |
| estimated_duration_seconds | integer | Duration estimate |

### procedure_blocks
`lib/cadence/procedures/schemas/procedure_block.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| step_id | uuid | FK to procedure_steps |
| block_type | enum | See block types above |
| position | integer | Order within step |
| name | string | Block identifier (required for inputs) |
| label | string | Display label |
| required | boolean | Must be completed |
| content | map | Type-specific configuration |

### procedure_executions
`lib/cadence/procedures/schemas/procedure_execution.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| procedure_id | uuid | FK to procedures |
| procedure_version_id | uuid | FK to procedure_versions |
| organization_id | uuid | FK to organizations |
| mission_id | uuid | FK to missions |
| target_id | uuid | FK to targets (optional) |
| parameters | map | Runtime parameters |
| status | enum | `:pending`, `:running`, `:pausing`, `:paused`, `:completed`, `:failed`, `:cancelled` |
| started_at | datetime | When execution started |
| completed_at | datetime | When execution ended |
| error_message | string | Error details if failed |
| triggered_by | enum | `:manual`, `:schedule`, `:event` |
| triggered_by_user_id | uuid | FK to users |
| completed_steps | array | DAG tracking: completed step names |
| skipped_steps | array | DAG tracking: skipped step names |
| failed_steps | array | DAG tracking: failed step names |
| step_results | map | Results keyed by step name |

### step_executions
`lib/cadence/procedures/schemas/step_execution.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| procedure_execution_id | uuid | FK to procedure_executions |
| step_id | uuid | FK to procedure_steps |
| status | enum | `:pending`, `:active`, `:awaiting_signoff`, `:completed`, `:skipped`, `:failed`, `:blocked` |
| started_at | datetime | When step started |
| completed_at | datetime | When step ended |
| result | enum | `:pass`, `:fail`, `:skip` |
| error_message | string | Error details |
| skipped_reason | string | Why step was skipped |
| skipped_by_id | uuid | FK to users |

### block_executions
`lib/cadence/procedures/schemas/block_execution.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| step_execution_id | uuid | FK to step_executions |
| block_id | uuid | FK to procedure_blocks |
| status | enum | `:pending`, `:in_progress`, `:completed`, `:failed`, `:skipped` |
| value | map | Captured user input |
| passed | boolean | Validation result |
| validation_message | string | Validation details |
| command_result | map | Command dispatch outcome |
| telemetry_reading | map | Captured telemetry value |
| entered_by_id | uuid | FK to users |

### step_signoffs
`lib/cadence/procedures/schemas/step_signoff.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| step_execution_id | uuid | FK to step_executions |
| user_id | uuid | FK to users |
| role | string | Role used for signoff |
| note | string | Optional signoff note |
| inserted_at | datetime | When signed (immutable) |

### procedure_reviews
`lib/cadence/procedures/schemas/procedure_review.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| procedure_version_id | uuid | FK to procedure_versions |
| user_id | uuid | FK to users |
| decision | enum | `:approve`, `:request_changes` |
| body | string | Review comments (required for request_changes) |
| superseded | boolean | True if newer review exists |

### suggested_edits
`lib/cadence/procedures/schemas/suggested_edit.ex`

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Primary key |
| procedure_execution_id | uuid | FK to procedure_executions |
| step_execution_id | uuid | FK to step_executions |
| suggested_by_id | uuid | FK to users |
| edit_type | enum | `:add_step`, `:modify_step`, `:delete_step`, `:add_block`, `:modify_block`, `:delete_block` |
| status | enum | `:pending`, `:accepted`, `:rejected` |
| before_snapshot | map | Original content |
| after_snapshot | map | Proposed content |
| reason | string | Why the change is needed |
| resolved_by_id | uuid | FK to users |
| resolution_note | string | Acceptance/rejection reason |

## Key Implementation Files

### Schemas
- `lib/cadence/procedures/schemas/` - All Ecto schemas

### Execution Engine (V2)
- `lib/cadence/procedures/v2/execution_process.ex` - Main execution GenServer
- `lib/cadence/procedures/v2/execution_strategy.ex` - Strategy behavior
- `lib/cadence/procedures/v2/strategies/manual.ex` - Manual mode
- `lib/cadence/procedures/v2/strategies/assisted.ex` - Assisted mode
- `lib/cadence/procedures/v2/strategies/automatic.ex` - Automatic mode
- `lib/cadence/procedures/v2/execution_persistence.ex` - State persistence
- `lib/cadence/procedures/v2/execution_queries.ex` - Data loading
- `lib/cadence/procedures/v2/automation_runner.ex` - Automation execution

### Runtime API
- `lib/cadence/procedures/runtime/cadence_api.ex` - Lua API bindings

### Supporting Modules
- `lib/cadence/procedures/condition_evaluator.ex` - Condition expression evaluation
- `lib/cadence/procedures/parameters.ex` - Parameter validation
- `lib/cadence/procedures/diff.ex` - Version diffing
- `lib/cadence/procedures/input_references.ex` - Input reference resolution

### Data Sources
- `lib/cadence/procedures/data_sources/` - Telemetry and data resolution
  - `data_source.ex` - Data source behavior
  - `telemetry_resolver.ex` - Telemetry point resolution
  - `cvt.ex` - Current Value Table integration

## Oban Integration

Oban handles **triggering**, not **executing**:

```elixir
defmodule Cadence.Procedures.Jobs.ScheduledExecution do
  use Oban.Worker

  @impl true
  def perform(%{args: %{"procedure_id" => id, "target_id" => target_id, "params" => params}}) do
    case Cadence.Procedures.start_execution(id, target_id, params, triggered_by: :schedule) do
      {:ok, execution_id} -> :ok
      {:error, :at_concurrency_limit} -> {:snooze, 60}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

Scheduled triggers use Oban Cron.

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Procedure/Version schemas | ✅ Complete | Full CRUD, versioning |
| Section/Step/Block schemas | ✅ Complete | Hierarchical structure |
| Execution tracking schemas | ✅ Complete | StepExecution, BlockExecution |
| Review workflow | ✅ Complete | ProcedureReview, superseding |
| Suggested edits (redlines) | ✅ Complete | During-execution changes |
| V2 Execution Engine | ✅ Complete | Strategy-based execution |
| Manual execution mode | ✅ Complete | Operator-driven |
| Assisted execution mode | ✅ Complete | System-suggested |
| Automatic execution mode | ✅ Complete | Auto-advance |
| Signoff requirements | ✅ Complete | Role-based, any/all logic |
| Step dependencies | ✅ Complete | DAG execution |
| Condition evaluation | ✅ Complete | Skip conditions |
| Telemetry blocks | ✅ Complete | CVT integration |
| Command blocks | 🔄 In Progress | Basic dispatch |
| Automations | 🔄 In Progress | Event triggers |
| Campaigns | ⏳ Deferred | Multi-target orchestration |

## Future Considerations

- **Resource limits** - Per-tenant configuration (max concurrent, max duration, max steps)
- **Git integration** - Sync procedures with external repository
- **Campaigns** - Multi-target, multi-day orchestration
- **Procedure templates** - Reusable procedure patterns
- **Batch execution** - Execute same procedure across multiple targets
