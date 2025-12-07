# Procedures Design Document

## Overview

"Procedures" is decomposed into four distinct features with different complexity levels and user needs:

| Feature | Description | Complexity |
|---------|-------------|------------|
| **Sequences** | Ordered steps with checks, approval-focused | Medium |
| **Automations** | Trigger → Action rules | Low |
| **Scripts** | Sandboxed Lua for complex/custom operations | Medium-High |
| **Campaigns** | Orchestration across targets/time | High (deferred) |

All features share a common execution runtime built on Luerl (Lua in Erlang).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Triggers                                 │
│  (Oban Cron, Event subscriptions, Manual via LiveView)          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Execution Coordinator                         │
│  (GenServer per mission)                                        │
│                                                                  │
│  - Spawns/supervises execution processes                        │
│  - Routes control signals (pause, abort, resume)                │
│  - Tracks active executions                                     │
│  - Enforces concurrency limits                                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Execution Process                              │
│  (GenServer per execution - holds Luerl VM)                     │
│                                                                  │
│  - Runs steps, checking for signals between each                │
│  - Persists checkpoints to DB                                   │
│  - Emits events (step_started, step_completed, etc.)           │
│  - Can be paused (state serialized) or aborted                 │
└─────────────────────────────────────────────────────────────────┘
```

## Cadence Runtime API (Lua)

Exposed to all procedure types:

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

### Sequences

Step-based DSL that compiles to Lua. Optimized for:
- Predictability ("what will this do?")
- Approval workflows
- UI representation

Example step structure:
```elixir
%{
  steps: [
    %{
      type: "check",
      condition: "telemetry.POWER.bus_voltage >= params.min_voltage",
      on_fail: "abort",
      message: "Bus voltage {{telemetry.POWER.bus_voltage}}V below minimum"
    },
    %{
      type: "command",
      name: "HEATER_ON",
      args: %{zone: "params.heater_zone"}
    },
    %{
      type: "wait_for",
      item: "THERMAL.temp",
      operator: ">",
      value: "params.min_temp",
      timeout: 30000
    },
    %{
      type: "command",
      name: "PAYLOAD_ON"
    }
  ]
}
```

Step types:
- `check` - Evaluate condition, abort/skip/warn on failure
- `command` - Send command to target
- `wait` - Wait for duration
- `wait_for` - Wait for telemetry condition
- `branch` - Conditional goto
- `log` - Record message

### Automations

Simple trigger → action rules. Lighter weight than full sequences.

Triggers:
- Event-based (alarm triggered, pass started, etc.)
- Executed via Oban jobs that hand off to Execution Coordinator

### Scripts

Raw Lua access for power users. Full flexibility, requires code review for approval.

### Campaigns (Deferred)

Orchestration across multiple targets over time. Examples:
- Firmware rollout to constellation
- Phased orbit adjustments
- Multi-day commissioning

## Pause/Abort Handling

Control signals checked between steps:

```elixir
defp execute_next_step(%{control_signal: :pause} = state) do
  persist_checkpoint(state)
  broadcast_status_change(state.execution_id, :paused)
  {:noreply, %{state | status: :paused}}
end

defp execute_next_step(%{control_signal: :abort} = state) do
  broadcast_status_change(state.execution_id, :aborted)
  {:stop, :normal, state}
end
```

When paused, operators can:
1. **Resume** - Continue from checkpoint
2. **Abort** - Stop entirely
3. **Skip step** - Jump over current step (escape hatch)
4. **Inject command** - Send manual command, then resume

## Data Model

### procedures
- id
- organization_id
- mission_id (nullable for org-wide)
- name
- description
- type: sequence | script
- current_version_id (FK)

### procedure_versions
- id
- procedure_id
- version_number
- source (JSON for sequences, Lua text for scripts)
- parameters_schema (JSON)
- status: draft | in_review | approved | deprecated
- approved_by_id
- approved_at
- created_by_id
- created_at

### procedure_executions
- id
- procedure_version_id
- organization_id
- mission_id
- target_id (nullable for mission-level)
- parameters (JSON)
- status: pending | running | paused | completed | failed | cancelled
- started_at
- completed_at
- current_step_index
- checkpoint_state (binary - serialized Luerl state)
- error_message
- triggered_by: manual | schedule | event
- triggered_by_user_id
- trigger_event_id

### procedure_logs
- id
- execution_id
- timestamp
- level: debug | info | warn | error
- message
- step_index

### procedure_schedules
- id
- procedure_id
- organization_id
- mission_id
- target_id (nullable)
- cron_expression
- parameters (JSON)
- enabled
- next_run_at

### procedure_triggers (Automations)
- id
- procedure_id
- organization_id
- mission_id
- event_type
- conditions (JSON)
- parameters (JSON)
- enabled

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

## Build Order

1. Execution Process - GenServer with Luerl VM, pause/abort
2. Execution Coordinator - Per-mission supervisor
3. Sequences - Step DSL, schema, compiler
4. Manual triggers - LiveView UI
5. Automations - Event-triggered rules
6. Scheduled triggers - Oban Cron

## Future Considerations

- **Resource limits** - Per-tenant configuration (max concurrent, max duration, max steps)
- **Git integration** - Sync procedures with external repository
- **Campaigns** - Multi-target, multi-day orchestration
- **Visual DAG editor** - Could generate from/to Lua AST
