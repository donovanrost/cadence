---
title: DAG-based Procedure Execution and Inputs
tags: [design, procedures, dag, inputs]
related:
  - "[[procedure]]"
  - "[[sequence]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Design: DAG-based Procedure Execution & Procedure Inputs

## Overview

This document proposes two enhancements to the Cadence Procedures system:

1. **DAG Execution Model** - Replace linear step sequences with a directed acyclic graph where steps declare dependencies and can execute concurrently
2. **Procedure Inputs** - Formal parameter definitions with validation, plus automatic trigger context for event-driven executions

---

## Part 1: DAG Execution Model

### Motivation

The current linear sequence model with `branch`/`label` has limitations:
- Steps execute one-at-a-time even when independent
- `goto` statements are error-prone and hard to visualize
- No clear way to express "do A and B, then C when both complete"

A DAG model addresses these by making dependencies explicit and enabling natural parallelism.

### Proposed Step Structure

Instead of an ordered list, steps become a map with named nodes:

```elixir
# Current (linear)
%{
  steps: [
    %{type: "check", condition: "..."},
    %{type: "command", name: "HEATER_ON"},
    %{type: "wait_for", item: "TEMP.value", ...}
  ]
}

# Proposed (DAG)
%{
  steps: %{
    "power_check" => %{
      type: "check",
      condition: "telemetry.EPS.bus_voltage >= 24",
      on_fail: "abort",
      message: "Insufficient bus voltage"
    },
    "thermal_check" => %{
      type: "check",
      condition: "telemetry.THERMAL.panel_temp < 80",
      on_fail: "abort",
      message: "Panel too hot"
    },
    "enable_heater" => %{
      type: "command",
      name: "HEATER_ON",
      args: %{zone: 1},
      depends_on: ["power_check", "thermal_check"]
    },
    "verify_heating" => %{
      type: "wait_for",
      item: "THERMAL.heater_status",
      operator: "==",
      value: "ON",
      timeout: 5000,
      depends_on: ["enable_heater"]
    }
  }
}
```

### Key Concepts

#### Step Names
- Each step has a unique string identifier (the map key)
- Used for dependency references and logging
- Should be descriptive: `"verify_safe_mode"` not `"step_5"`

#### Dependencies (`depends_on`)
- Array of step names that must complete successfully before this step runs
- Empty array or omitted = root node (runs immediately)
- Multiple dependencies = waits for ALL to complete (AND semantics)

#### Implicit Root and Terminal Nodes
- Steps with no `depends_on` are roots (start immediately)
- Steps that no other step depends on are terminals
- Execution completes when all terminals complete

### Execution Algorithm

```
1. Build dependency graph from step definitions
2. Validate graph is acyclic (detect cycles, reject if found)
3. Initialize:
   - completed = {}
   - failed = nil
   - running = {}

4. Loop:
   a. Find "ready" steps: depends_on ⊆ completed AND not in running AND not in completed
   b. If no ready steps and running is empty:
      - If all steps completed: SUCCESS
      - Else: FAILED (some steps never became ready)
   c. Start all ready steps concurrently (spawn tasks)
   d. Wait for any running step to complete
   e. On step completion:
      - If success: add to completed
      - If failure: set failed, cancel running steps, abort
   f. Repeat
```

### Parallel Execution Implementation

```elixir
defmodule Cadence.Procedures.Engine.DagExecutor do
  @moduledoc """
  Executes a procedure as a DAG with concurrent step execution.
  """

  defstruct [
    :steps,
    :dependencies,      # %{step_name => [dep_names]}
    :dependents,        # %{step_name => [dependent_names]} (reverse index)
    :completed,         # MapSet of completed step names
    :running,           # %{step_name => Task.t()}
    :context            # Execution context (params, trigger, telemetry access)
  ]

  def execute(steps, context) do
    executor = build(steps, context)

    case validate_acyclic(executor) do
      :ok -> run_loop(executor)
      {:error, cycle} -> {:error, {:cycle_detected, cycle}}
    end
  end

  defp run_loop(executor) do
    ready = find_ready_steps(executor)

    cond do
      # All done
      MapSet.size(executor.completed) == map_size(executor.steps) ->
        {:ok, :completed}

      # Nothing ready and nothing running = deadlock (shouldn't happen if validated)
      ready == [] and executor.running == %{} ->
        {:error, :deadlock}

      # Start ready steps
      ready != [] ->
        executor = start_steps(executor, ready)
        run_loop(executor)

      # Wait for running steps
      true ->
        case await_any(executor.running) do
          {:ok, step_name, result} ->
            executor = handle_completion(executor, step_name, result)
            run_loop(executor)

          {:error, step_name, reason} ->
            {:error, {:step_failed, step_name, reason}}
        end
    end
  end

  defp find_ready_steps(executor) do
    executor.steps
    |> Map.keys()
    |> Enum.filter(fn name ->
      not MapSet.member?(executor.completed, name) and
      not Map.has_key?(executor.running, name) and
      dependencies_satisfied?(executor, name)
    end)
  end

  defp dependencies_satisfied?(executor, step_name) do
    deps = Map.get(executor.dependencies, step_name, [])
    Enum.all?(deps, &MapSet.member?(executor.completed, &1))
  end
end
```

### Visualization

The DAG structure naturally maps to a flowchart:

```
    ┌─────────────────┐     ┌─────────────────┐
    │  power_check    │     │  thermal_check  │
    └────────┬────────┘     └────────┬────────┘
             │                       │
             └───────────┬───────────┘
                         │
                         ▼
               ┌─────────────────┐
               │  enable_heater  │
               └────────┬────────┘
                        │
                        ▼
               ┌─────────────────┐
               │ verify_heating  │
               └─────────────────┘
```

The UI can render this using a layout algorithm (e.g., Dagre) based on the dependency graph.

### Step Types in DAG Model

All existing step types work in the DAG model. Some considerations:

| Step Type | DAG Behavior |
|-----------|--------------|
| `check` | Runs when deps satisfied. `on_fail: "abort"` fails the whole DAG. |
| `command` | Sends command, completes on dispatch (or verification if configured) |
| `wait` | Completes after duration |
| `wait_for` | Completes when condition met or timeout |
| `log` | Completes immediately after logging |
| `set` | Sets variable, completes immediately |
| `assert` | Like check but always aborts on failure |
| `branch` | **Removed** - use conditional steps instead (see below) |
| `label` | **Removed** - replaced by step names |

### Conditional Execution

Replace `branch`/`label` with conditional step execution:

```elixir
"safe_mode_entry" => %{
  type: "command",
  name: "SAFE_MODE",
  depends_on: ["anomaly_check"],
  condition: "vars.anomaly_detected == true"  # Only runs if condition true
}
```

If `condition` evaluates to false, the step is marked "skipped" (counts as completed for dependency purposes).

### Alternative: Choice Nodes

For explicit either/or branches, add a `choice` step type:

```elixir
"mode_decision" => %{
  type: "choice",
  depends_on: ["diagnostics"],
  branches: [
    %{condition: "vars.battery_ok", goto: "normal_ops"},
    %{condition: "true", goto: "safe_mode"}  # default
  ]
}
```

This activates one branch and marks others as "not taken" (dependents of not-taken branches are skipped).

### Pause/Resume Considerations

With DAG execution, pause/resume becomes more complex:

- **Pause**: Stop starting new steps, let running steps complete (or interrupt if safe)
- **Resume**: Restart from the set of ready steps given current completion state

The `completed` set must be persisted to the database. This is simpler than serializing VM state since we just track which named steps finished.

```elixir
# In ProcedureExecution schema
field :completed_steps, {:array, :string}, default: []
field :step_results, :map, default: %{}  # %{step_name => result_data}
```

### Migration from Linear to DAG

Support both formats during transition:

```elixir
def normalize_steps(source) do
  case source do
    # Already DAG format
    %{"steps" => %{} = steps} when is_map(steps) ->
      {:dag, steps}

    # Legacy linear format - convert to DAG with sequential dependencies
    %{"steps" => steps} when is_list(steps) ->
      dag_steps = convert_linear_to_dag(steps)
      {:dag, dag_steps}
  end
end

defp convert_linear_to_dag(steps) do
  steps
  |> Enum.with_index()
  |> Enum.map(fn {step, idx} ->
    name = "step_#{idx}"
    deps = if idx == 0, do: [], else: ["step_#{idx - 1}"]
    {name, Map.put(step, "depends_on", deps)}
  end)
  |> Map.new()
end
```

---

## Part 2: Procedure Inputs

### Motivation

Procedures need to be reusable across:
- Different targets/spacecraft
- Different threshold values
- Different operational modes

And when triggered by events, procedures need access to:
- What triggered them (alarm, telemetry event)
- The values that caused the trigger
- Contextual information for logging/decisions

### Execution Context Model

Unify all inputs into an execution context:

```elixir
%ExecutionContext{
  # Author-defined parameters (validated against schema)
  params: %{
    target_id: "SC-001",
    temp_threshold: 50,
    retry_count: 3
  },

  # Automatic trigger context (populated based on how execution started)
  trigger: %{
    type: :alarm,                    # :manual | :schedule | :alarm | :telemetry_event
    source_id: "alarm-uuid",         # ID of triggering entity
    source_name: "BATTERY_LOW",      # Human-readable name
    triggered_at: ~U[2024-01-15 10:30:00Z],

    # Type-specific data
    data: %{
      severity: :warning,
      triggering_value: 23.5,
      threshold: 24.0,
      item_name: "EPS.battery_voltage"
    }
  },

  # Runtime state (set during execution)
  vars: %{},

  # Access to live telemetry
  telemetry: &Cadence.Telemetry.CVT.get/2
}
```

### Parameter Schema Definition

Define expected parameters in `ProcedureVersion.parameters_schema`:

```elixir
%{
  "parameters" => [
    %{
      "name" => "target_id",
      "type" => "target",           # Special type: validates against mission targets
      "required" => true,
      "description" => "Target spacecraft for this procedure"
    },
    %{
      "name" => "temp_threshold",
      "type" => "number",
      "required" => false,
      "default" => 50,
      "min" => 0,
      "max" => 100,
      "unit" => "celsius",
      "description" => "Temperature threshold for heater activation"
    },
    %{
      "name" => "mode",
      "type" => "enum",
      "required" => true,
      "options" => ["nominal", "safe", "emergency"],
      "description" => "Operating mode for the procedure"
    },
    %{
      "name" => "notify_emails",
      "type" => "array",
      "items" => %{"type" => "string", "format" => "email"},
      "required" => false,
      "default" => [],
      "description" => "Email addresses to notify on completion"
    }
  ]
}
```

### Supported Parameter Types

| Type | Validation | UI Component |
|------|------------|--------------|
| `string` | min/max length, pattern (regex) | Text input |
| `number` | min, max, step | Number input with constraints |
| `integer` | min, max | Integer input |
| `boolean` | - | Checkbox/toggle |
| `enum` | options array | Select dropdown |
| `array` | items schema, min/max items | Dynamic list input |
| `target` | Must be valid target ID for mission | Target selector dropdown |
| `telemetry_item` | Must be valid telemetry item | Telemetry item picker |
| `command` | Must be valid command name | Command selector |
| `datetime` | min, max | Datetime picker |
| `duration` | min, max (in ms) | Duration input |

### Parameter Validation

```elixir
defmodule Cadence.Procedures.Parameters do
  @moduledoc """
  Validates execution parameters against procedure schema.
  """

  def validate(params, schema, context) do
    schema["parameters"]
    |> Enum.reduce({%{}, []}, fn param_def, {validated, errors} ->
      name = param_def["name"]
      value = Map.get(params, name, param_def["default"])

      case validate_param(value, param_def, context) do
        {:ok, validated_value} ->
          {Map.put(validated, name, validated_value), errors}

        {:error, error} ->
          {validated, [{name, error} | errors]}
      end
    end)
    |> case do
      {validated, []} -> {:ok, validated}
      {_, errors} -> {:error, errors}
    end
  end

  defp validate_param(nil, %{"required" => true}, _context) do
    {:error, "is required"}
  end

  defp validate_param(nil, %{"required" => false}, _context) do
    {:ok, nil}
  end

  defp validate_param(value, %{"type" => "target"} = def, context) do
    if Cadence.Targets.exists?(context.mission_id, value) do
      {:ok, value}
    else
      {:error, "is not a valid target"}
    end
  end

  defp validate_param(value, %{"type" => "number", "min" => min, "max" => max}, _context)
       when is_number(value) do
    cond do
      min && value < min -> {:error, "must be at least #{min}"}
      max && value > max -> {:error, "must be at most #{max}"}
      true -> {:ok, value}
    end
  end

  defp validate_param(value, %{"type" => "enum", "options" => options}, _context) do
    if value in options do
      {:ok, value}
    else
      {:error, "must be one of: #{Enum.join(options, ", ")}"}
    end
  end

  # ... more type validations
end
```

### Trigger Context Population

When starting an execution, populate trigger context based on source:

```elixir
defmodule Cadence.Procedures.TriggerContext do
  def build(:manual, user) do
    %{
      type: :manual,
      source_id: user.id,
      source_name: user.email,
      triggered_at: DateTime.utc_now(),
      data: %{}
    }
  end

  def build(:schedule, schedule) do
    %{
      type: :schedule,
      source_id: schedule.id,
      source_name: schedule.name,
      triggered_at: DateTime.utc_now(),
      data: %{
        schedule_type: schedule.type,
        cron_expression: schedule.cron_expression
      }
    }
  end

  def build(:alarm, alarm_event) do
    %{
      type: :alarm,
      source_id: alarm_event.alarm_id,
      source_name: alarm_event.alarm.name,
      triggered_at: alarm_event.timestamp,
      data: %{
        severity: alarm_event.alarm.severity,
        state: alarm_event.new_state,
        triggering_value: alarm_event.triggering_value,
        threshold: alarm_event.threshold,
        item_name: alarm_event.telemetry_item
      }
    }
  end

  def build(:telemetry_event, event) do
    %{
      type: :telemetry_event,
      source_id: event.id,
      source_name: event.item_name,
      triggered_at: event.timestamp,
      data: %{
        value: event.value,
        previous_value: event.previous_value,
        item_name: event.item_name,
        packet_name: event.packet_name
      }
    }
  end
end
```

### Expression Language Updates

Extend the expression language to access context:

```
# Parameter access
params.target_id
params.temp_threshold

# Trigger context access
trigger.type                    # "alarm", "schedule", "manual"
trigger.source_name             # "BATTERY_LOW"
trigger.triggered_at            # timestamp
trigger.data.triggering_value   # 23.5
trigger.data.severity           # "warning"

# Existing access patterns (unchanged)
telemetry.PACKET.item
vars.my_variable

# String interpolation
"Alert: {{trigger.source_name}} fired with value {{trigger.data.triggering_value}}"
```

### Compiler Updates

Update the Lua compiler to inject context:

```elixir
defp compile_preamble(context) do
  """
  -- Execution context
  local params = #{encode_lua_table(context.params)}
  local trigger = #{encode_lua_table(context.trigger)}
  local vars = {}

  """
end
```

### Example: Multi-Target Procedure

```elixir
# Procedure definition
%{
  name: "Battery Check",
  parameters_schema: %{
    "parameters" => [
      %{"name" => "target_id", "type" => "target", "required" => true}
    ]
  },
  source: %{
    "steps" => %{
      "check_voltage" => %{
        type: "check",
        condition: "telemetry[params.target_id].EPS.voltage >= 24",
        on_fail: "abort",
        message: "Battery voltage too low on {{params.target_id}}"
      },
      "log_result" => %{
        type: "log",
        level: "info",
        message: "Battery check passed for {{params.target_id}}",
        depends_on: ["check_voltage"]
      }
    }
  }
}

# Start execution with parameters
Procedures.start_execution(procedure, %{
  params: %{target_id: "SC-001"},
  triggered_by: :manual,
  user: current_user
})
```

### Example: Alarm-Triggered Procedure

```elixir
# Procedure triggered by OVER_TEMP alarm
%{
  name: "Thermal Response",
  source: %{
    "steps" => %{
      "log_trigger" => %{
        type: "log",
        level: "warn",
        message: "Responding to {{trigger.source_name}}: temp={{trigger.data.triggering_value}}°C"
      },
      "disable_heater" => %{
        type: "command",
        name: "HEATER_OFF",
        args: %{zone: "{{trigger.data.zone}}"},
        depends_on: ["log_trigger"]
      },
      "wait_cooldown" => %{
        type: "wait_for",
        item: "THERMAL.temp",
        operator: "<",
        value: "{{trigger.data.threshold - 10}}",
        timeout: 60000,
        depends_on: ["disable_heater"]
      },
      "clear_alarm" => %{
        type: "command",
        name: "ACK_ALARM",
        args: %{alarm_id: "{{trigger.source_id}}"},
        depends_on: ["wait_cooldown"]
      }
    }
  }
}

# Automation triggers this when alarm fires
Automations.execute_action(%{
  action: :run_procedure,
  procedure_id: procedure.id,
  trigger: TriggerContext.build(:alarm, alarm_event)
})
```

---

## Schema Changes Summary

### ProcedureVersion

```elixir
# Existing fields
field :source, :map              # Now supports DAG format
field :parameters_schema, :map   # Now has defined structure

# New interpretation of source:
# %{"steps" => %{name => step_def}}  for DAG
# %{"steps" => [step_def]}           for legacy linear (auto-converted)
# %{"code" => "..."}                 for script mode (unchanged)
```

### ProcedureExecution

```elixir
# Existing
field :parameters, :map          # Validated params passed at start
field :current_step_index, :integer  # Deprecated for DAG

# New fields
field :completed_steps, {:array, :string}, default: []
field :skipped_steps, {:array, :string}, default: []
field :step_results, :map, default: %{}  # %{step_name => %{status, result, duration}}
field :trigger_context, :map     # The trigger context for this execution
```

### Migration

```elixir
def change do
  alter table(:procedure_executions) do
    add :completed_steps, {:array, :string}, default: []
    add :skipped_steps, {:array, :string}, default: []
    add :step_results, :map, default: %{}
    add :trigger_context, :map
  end
end
```

---

## Implementation Order

### Phase 1: Parameter System
1. Define parameter schema structure
2. Implement parameter validation
3. Update `start_execution` to validate params
4. Build UI for parameter input

### Phase 2: Trigger Context
1. Define trigger context structure
2. Update automation integration to pass context
3. Update expression evaluator for `trigger.*` access
4. Test with alarm-triggered procedures

### Phase 3: DAG Execution
1. Add DAG validation (cycle detection)
2. Implement `DagExecutor` with parallel execution
3. Update persistence for completed_steps
4. Implement pause/resume for DAG
5. Build DAG visualization component

### Phase 4: Migration & Polish
1. Add linear-to-DAG converter for existing procedures
2. Update procedure editor UI for DAG authoring
3. Documentation and examples

---

## Design Decisions

### 1. Step Failure Handling: User-Defined

Each step can specify its `on_fail` behavior. The DAG-level default is also configurable:

```elixir
# DAG-level default
%{
  "on_step_failure" => "abort",  # "abort" | "continue" | "pause"
  "steps" => %{...}
}

# Step-level override
"risky_command" => %{
  type: "command",
  name: "EXPERIMENTAL_OP",
  on_fail: "continue",  # Override: don't fail the whole DAG
  depends_on: ["setup"]
}
```

**Failure modes:**
- `abort` (default): Fail the entire DAG, cancel running steps
- `continue`: Mark step as failed, but continue independent branches. Dependent steps are marked "blocked"
- `pause`: Pause execution, allow operator to decide (resume, skip, or abort)

When `continue` is used, the final DAG status reflects partial completion:
```elixir
%{
  status: :completed_with_failures,
  completed_steps: ["a", "b", "c"],
  failed_steps: ["d"],
  blocked_steps: ["e", "f"],  # Depended on "d"
  skipped_steps: []
}
```

### 2. Variable Scoping: Step-Prefixed

Variables set by steps are internally prefixed with the step name to avoid conflicts:

```elixir
# Step "check_a" sets variable "result"
"check_a" => %{type: "set", name: "result", value: "..."}

# Internally stored as: vars["check_a.result"]

# Other steps can access it explicitly:
"use_result" => %{
  type: "log",
  message: "Result from check_a: {{vars.check_a.result}}",
  depends_on: ["check_a"]
}
```

For convenience, if a step only has one dependency, `vars.result` (unprefixed) resolves to that dependency's variable:

```elixir
"process" => %{
  type: "log",
  message: "{{vars.result}}",  # Resolves to vars.check_a.result
  depends_on: ["check_a"]      # Single dependency = implicit scope
}
```

If a step has multiple dependencies or needs to access variables from non-dependencies, explicit prefixing is required.

### 3. Telemetry Access: Dot Notation with Target

Multi-target telemetry uses dot notation: `telemetry.TARGET.PACKET.item`

```elixir
# Single target (current behavior)
"check" => %{
  condition: "telemetry.EPS.voltage >= 24"
}

# Multi-target with parameter
"check" => %{
  condition: "telemetry.{{params.target_id}}.EPS.voltage >= 24"
}

# Explicit target
"check" => %{
  condition: "telemetry.SC_001.EPS.voltage >= 24"
}
```

The expression evaluator resolves the target ID first, then fetches from CVT:
```elixir
# telemetry.SC_001.EPS.voltage becomes:
CVT.get("SC_001", "EPS.voltage")
```

### 4. UI for DAG Authoring: Hybrid Approach

Support both visual and text-based editing, similar to the current sequence editor:

**Visual Editor:**
- Drag-and-drop node placement
- Visual connection of dependencies
- Node inspector panel for step configuration
- Auto-layout with manual adjustment
- Export to JSON/YAML

**Text Editor:**
- YAML or JSON editing
- Syntax highlighting
- Validation feedback
- Import from visual editor

**Sync:**
- Changes in either editor update the underlying model
- Visual layout metadata stored separately from step logic
- Round-trip safe: text edits preserve visual positions where possible

```elixir
# Stored format includes optional layout hints
%{
  "steps" => %{...},
  "_layout" => %{
    "check_a" => %{"x" => 100, "y" => 50},
    "check_b" => %{"x" => 300, "y" => 50},
    "combine" => %{"x" => 200, "y" => 150}
  }
}
```

---

## Open Questions

1. **Step timeouts**: Should each step have an optional timeout, or rely on internal timeouts (like `wait_for`)?

2. **Sub-procedure calls**: Should we support calling other procedures as steps? If so, how do parameters flow?

3. **Retry logic**: Should steps support automatic retry with backoff? Or is that better handled by wrapping in a sub-procedure?
