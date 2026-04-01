---
title: Procedure Inputs and Trigger Bindings
tags: [design, procedures, inputs, triggers]
related:
  - "[[procedure]]"
  - "[[automation]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Procedure Inputs and Trigger Bindings

## Overview

Procedures need to accept inputs/parameters that can be used within steps. These inputs can be provided:
- Manually by a user at execution time
- Statically configured when setting up a schedule or automation
- Dynamically bound to values from triggering events

This document defines the input system, type validation, and binding mechanisms.

## Input Definitions

Inputs are defined at the procedure level and specify what values the procedure needs to execute.

### Schema

```yaml
inputs:
  <input_name>:
    type: <type>
    description: <string>
    required: <boolean>        # default: true
    default: <value>           # optional, makes input optional
    enum: [<values>]           # optional, constrains allowed values
    min: <number>              # optional, for numeric types
    max: <number>              # optional, for numeric types
```

### Supported Types

| Type | Description | Example Values |
|------|-------------|----------------|
| `string` | Text value | `"EPS"`, `"subsystem_a"` |
| `number` | Integer or float | `42`, `3.14`, `-10` |
| `integer` | Integer only | `42`, `-10` |
| `boolean` | True/false | `true`, `false` |
| `duration` | Milliseconds | `5000`, `30000` |
| `datetime` | ISO8601 timestamp | `"2025-01-15T10:30:00Z"` |
| `telemetry_item` | Qualified parameter name | `"EPS.battery_voltage"` |
| `command` | Qualified command name | `"EPS.POWER_CYCLE"` |

### Example

```yaml
inputs:
  target_subsystem:
    type: string
    description: "Which subsystem to power cycle"
    required: true
    enum: [EPS, ADCS, COMMS, PAYLOAD]

  wait_duration:
    type: duration
    description: "How long to wait after power off (ms)"
    default: 5000
    min: 1000
    max: 60000

  force:
    type: boolean
    description: "Skip safety checks"
    default: false

  threshold:
    type: number
    description: "Voltage threshold for verification"
    required: true
    min: 0
    max: 50
```

## Referencing Inputs in Steps

Inputs are referenced in step configuration using template syntax: `${input.<name>}`

### Example

```yaml
inputs:
  target_subsystem:
    type: string
    required: true
  wait_duration:
    type: duration
    default: 5000

steps:
  send_command:
    type: command
    name: "${input.target_subsystem}.POWER_OFF"

  wait_for_shutdown:
    type: wait
    duration: "${input.wait_duration}"

  verify_off:
    type: check
    condition: "${input.target_subsystem}.power_state == 'OFF'"
```

## Execution Contexts

### Manual Execution

User triggers procedure via UI. A form is generated from input definitions:
- Required inputs without defaults must be filled
- Inputs with defaults show the default, user can override
- Enum inputs render as dropdowns
- Type-appropriate input controls (number spinner, checkbox, etc.)

### Schedule Trigger

All inputs must be statically bound when the schedule is configured:

```yaml
schedule:
  name: "Daily EPS Health Check"
  cron: "0 6 * * *"
  procedure_id: "abc-123"
  inputs:
    target_subsystem: "EPS"
    wait_duration: 10000
    force: false
```

### Event/Automation Trigger

Inputs can be statically bound or dynamically bound to event context:

```yaml
automation:
  name: "Auto-recover on battery warning"
  trigger:
    type: alarm
    alarm_name: "EPS.low_battery"
    state: warning
  procedure_id: "abc-123"
  inputs:
    # Static binding
    target_subsystem: "EPS"
    force: false
    # Dynamic binding - value comes from the triggering event
    threshold: "${event.trigger_value}"
```

## Event Schemas

To validate dynamic bindings at configuration time, we define schemas for each event type. These schemas are derived from existing system definitions.

### Alarm Event

Triggered when an alarm changes state.

```
event.alarm_id        : string    - Unique alarm instance ID
event.alarm_name      : string    - Alarm rule name (e.g., "EPS.low_battery")
event.state           : string    - New state: "nominal", "warning", "critical"
event.previous_state  : string    - Previous state
event.parameter_name  : string    - Underlying parameter name
event.parameter_value : <varies>  - Current parameter value (type from param definition)
event.trigger_value   : <varies>  - Threshold that was crossed (type from alarm rule)
event.timestamp       : datetime  - When the alarm triggered
event.mission_id      : string    - Mission context
```

### Telemetry Event

Triggered on telemetry value changes (for watched parameters).

```
event.parameter_name  : string    - Qualified parameter name
event.value           : <varies>  - New value (type from parameter definition)
event.previous_value  : <varies>  - Previous value
event.timestamp       : datetime  - Packet timestamp
event.mission_id      : string    - Mission context
```

### Command Event

Triggered on command lifecycle events.

```
event.command_name    : string    - Qualified command name
event.command_id      : string    - Unique command instance ID
event.status          : string    - "queued", "sent", "acknowledged", "completed", "failed"
event.arguments       : map       - Command arguments (types from command definition)
event.error           : string    - Error message if failed (nullable)
event.timestamp       : datetime  - Event timestamp
event.mission_id      : string    - Mission context
```

### Schedule Event

Triggered when a schedule fires.

```
event.schedule_id     : string    - Schedule ID
event.schedule_name   : string    - Schedule name
event.scheduled_time  : datetime  - When it was supposed to run
event.timestamp       : datetime  - Actual trigger time
event.mission_id      : string    - Mission context
```

## Dynamic Binding Syntax

### Template Syntax

Concise, familiar to programmers:

```yaml
inputs:
  threshold: "${event.trigger_value}"
  param_name: "${event.parameter_name}"
```

### Parsing

Templates are parsed into a structured form internally:

```elixir
%DynamicBinding{
  source: :event,
  path: ["trigger_value"],
  transform: nil
}
```

### Transforms (Future)

For cases where type coercion is needed:

```yaml
# Future: explicit transforms
message: "${event.parameter_value | to_string}"
rounded: "${event.parameter_value | round}"
```

## Validation

### Level 1: Procedure Definition

When a procedure is saved:
- Input names are valid identifiers
- Types are supported
- Defaults match declared type
- Enum values match declared type
- Min/max are valid for numeric types
- Required inputs without defaults are flagged

### Level 2: Step References

When procedure steps are validated:
- All `${input.<name>}` references point to defined inputs
- Input types are compatible with step field expectations

### Level 3: Trigger Binding

When a schedule or automation is configured:
- All required inputs have bindings (static or dynamic)
- Static values match input type and constraints
- Dynamic paths exist in the event schema
- Source field type is compatible with target input type

### Type Compatibility Matrix

| Source Type | Target Type | Compatible | Notes |
|-------------|-------------|------------|-------|
| integer | integer | Yes | |
| integer | number | Yes | Widening |
| number | number | Yes | |
| number | integer | No | Potential precision loss |
| string | string | Yes | |
| * | string | Future | With explicit transform |
| boolean | boolean | Yes | |
| datetime | datetime | Yes | |
| duration | duration | Yes | |
| duration | integer | Yes | Both are ms |
| integer | duration | Yes | Both are ms |

## Database Schema

### Procedure Inputs

Stored as JSONB on the procedure_versions table:

```sql
ALTER TABLE procedure_versions
ADD COLUMN inputs JSONB DEFAULT '{}';
```

### Schedule Bindings

```sql
CREATE TABLE schedules (
  id UUID PRIMARY KEY,
  -- ... existing fields ...
  input_bindings JSONB DEFAULT '{}'  -- Static values only
);
```

### Automation Bindings

```sql
CREATE TABLE automations (
  id UUID PRIMARY KEY,
  -- ... existing fields ...
  input_bindings JSONB DEFAULT '{}'  -- Static and dynamic bindings
);
```

### Binding Storage Format

```json
{
  "target_subsystem": {
    "type": "static",
    "value": "EPS"
  },
  "threshold": {
    "type": "dynamic",
    "source": "event",
    "path": "trigger_value"
  }
}
```

## Execution Engine Integration

### Input Resolution

At execution time, the engine resolves all inputs:

```elixir
defmodule Cadence.Procedures.InputResolver do
  def resolve(input_bindings, event_context) do
    Enum.map(input_bindings, fn {name, binding} ->
      value = case binding do
        %{type: "static", value: v} -> v
        %{type: "dynamic", source: "event", path: path} ->
          get_in(event_context, path)
      end
      {name, value}
    end)
    |> Map.new()
  end
end
```

### Step Interpolation

Before executing each step, template references are replaced:

```elixir
defmodule Cadence.Procedures.StepInterpolator do
  def interpolate(step_config, resolved_inputs) do
    # Recursively walk the step config
    # Replace ${input.<name>} with resolved values
  end
end
```

## UI Considerations

### Procedure Editor

- New "Inputs" section/panel in the DAG editor
- Add/edit/remove input definitions
- Show input references in step tooltips
- Autocomplete `${input.` in step configuration fields

### Manual Execution Dialog

- Generate form from input definitions
- Validate on submit before starting execution
- Show descriptions as help text
- Remember last-used values (optional)

### Schedule/Automation Configuration

- Show required inputs from selected procedure
- Input fields for static values
- Dropdown to select event fields for dynamic bindings
- Real-time validation of bindings

## Implementation Plan

### Phase 1: Core Input System
1. Add `inputs` field to procedure_versions schema
2. Update procedure editor UI to define inputs
3. Implement input reference syntax in steps
4. Add validation for input definitions

### Phase 2: Manual Execution
1. Generate execution form from inputs
2. Implement input resolution
3. Implement step interpolation
4. Update execution engine

### Phase 3: Schedule Integration
1. Add input_bindings to schedules
2. UI for configuring static bindings
3. Validation at schedule creation

### Phase 4: Automation Integration
1. Add input_bindings to automations
2. Define event schemas
3. UI for static and dynamic bindings
4. Dynamic binding resolution in execution engine

### Phase 5: Enhanced Validation
1. Cross-reference input types with step field expectations
2. Event schema type checking for dynamic bindings
3. Editor warnings/errors for type mismatches
