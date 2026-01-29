---
title: Adding a Recordable
aliases: [recordables pattern, event sourcing guide]
tags: [pattern, recordings, event-sourcing]
related:
  - "[[recording]]"
  - "[[recordable]]"
  - "[[aggregate]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Adding a Recordable

This pattern shows how to add new event types to Cadence's [recordings](../glossary/recording.md) system.

## Background

Cadence uses the **37signals Recordables pattern** for event sourcing. Instead of one giant `events` table with a JSON blob, we have:

- A `recordings` table (pure index) that links events to [aggregates](../glossary/aggregate.md)
- Separate [recordable](../glossary/recordable.md) tables for each event type (strongly typed)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         recordings (index)                          │
├─────────────────────────────────────────────────────────────────────┤
│ id │ aggregate_type │ aggregate_id │ recordable_type │ recordable_id│
├────┼────────────────┼──────────────┼─────────────────┼──────────────┤
│ r1 │ Command        │ cmd-123      │ CommandDispatched│ cd-456      │
│ r2 │ Command        │ cmd-123      │ CommandSent       │ cs-789      │
│ r3 │ Command        │ cmd-123      │ CommandVerified   │ cv-012      │
└────┴────────────────┴──────────────┴─────────────────┴──────────────┘
         │                                      │
         │                                      ▼
         │                    ┌─────────────────────────────────────┐
         │                    │    command_dispatcheds (rich)       │
         │                    ├─────────────────────────────────────┤
         │                    │ id: cd-456                          │
         │                    │ command_name: "SET_MODE"            │
         │                    │ parameters: %{mode: 1}              │
         │                    └─────────────────────────────────────┘
         │
         ▼
    Aggregate: Command cmd-123
    State derived by replaying r1 → r2 → r3
```

---

## Steps to Add a New Recordable

### Step 1: Create the Migration

Add a new table for your recordable:

```elixir
create table(:my_new_events, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :some_field, :string, null: false
  add :another_field, :map, default: %{}
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### Step 2: Create the Recordable Module

```elixir
# lib/cadence/recordings/recordables/my_new_event.ex

defmodule Cadence.Recordings.Recordables.MyNewEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "my_new_events" do
    field :some_field, :string
    field :another_field, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:some_field, :another_field])
    |> validate_required([:some_field])
  end
end

# Implement the protocol
defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.MyNewEvent do
  def recording_type(_), do: "MyNewEvent"
  def aggregate_type(_), do: "MyAggregate"
  def title(r), do: r.some_field
  def status(_), do: "pending"
  def severity(_), do: nil
end
```

### Step 3: Register in Recordings Module

Add to `@recordable_modules` in `Cadence.Recordings`:

```elixir
@recordable_modules %{
  # ... existing entries ...
  "MyNewEvent" => Cadence.Recordings.Recordables.MyNewEvent
}
```

### Step 4: Use in Domain Logic

```elixir
def do_something(params, opts) do
  Recordings.create(
    MyNewEvent,
    %{some_field: "value", another_field: %{key: "data"}},
    %{
      organization_id: org_id,
      mission_id: mission_id,
      aggregate_id: entity_id,
      actor_id: user_id,
      timestamp: DateTime.utc_now()
    }
  )
end
```

---

## Creating Recordings

### Basic Usage

```elixir
alias Cadence.Recordings
alias Cadence.Recordings.Recordables.CommandDispatched

{:ok, %{recordable: recordable, recording: recording}} =
  Recordings.create(
    CommandDispatched,
    # Recordable attributes (event-specific data)
    %{
      command_name: "SET_MODE",
      parameters: %{mode: 1},
      target_id: target_id,
      is_hazardous: false
    },
    # Recording attributes (index data)
    %{
      organization_id: org_id,
      mission_id: mission_id,
      aggregate_id: Ecto.UUID.generate(),
      actor_id: user_id,
      actor_type: "user",
      target_id: target_id,
      timestamp: DateTime.utc_now()
    }
  )
```

### Chaining Events (Causality)

For related events, use `Recordings.append/5` with `Ecto.Multi`:

```elixir
Multi.new()
|> Recordings.append(:dispatch, CommandDispatched, dispatch_attrs, fn _changes ->
  %{
    organization_id: org_id,
    mission_id: mission_id,
    aggregate_id: aggregate_id,
    actor_id: user_id,
    timestamp: DateTime.utc_now()
  }
end)
|> Recordings.append(:sent, CommandSent, %{transport_id: transport_id}, fn changes ->
  %{
    organization_id: org_id,
    mission_id: mission_id,
    aggregate_id: aggregate_id,
    parent_id: changes.dispatch_recording.id,  # Link to parent
    root_id: aggregate_id,
    actor_type: "system",
    timestamp: DateTime.utc_now()
  }
end)
|> Repo.transaction()
```

---

## Querying Recordings

### Timeline Queries

```elixir
# List recordings for a time range
recordings = Recordings.list_recordings(mission_id, start_time, end_time,
  aggregate_types: ["Command", "Alarm"],
  target_id: target_id,
  limit: 100
)

# Cursor-based pagination
recordings = Recordings.list_recordings_before(mission_id, cursor,
  aggregate_types: ["Command"],
  limit: 50
)

# Load with recordables (batch loaded to avoid N+1)
recordings_with_data = Recordings.load_recordables_for_recordings(recordings)
```

### Aggregate History

```elixir
# All recordings for a specific entity
recordings = Recordings.get_aggregate_history("Command", command_aggregate_id)

# With recordables loaded
history = Recordings.get_aggregate_history_with_recordables("Alarm", alarm_id)
```

---

## Existing Recordable Types

### Commands

| Type | Richness | Description |
|------|----------|-------------|
| `CommandDispatched` | Rich | Command sent to target (name, params, target) |
| `CommandSent` | Minimal | Transmitted to interface |
| `CommandVerified` | Medium | Verification passed (result) |
| `CommandVerificationFailed` | Medium | Verification failed (error) |
| `CommandRejected` | Medium | Validation/auth failed |
| `CommandErrored` | Medium | Transmission error |
| `CommandQueued` | Minimal | Added to queue |
| `CommandDequeued` | Minimal | Removed from queue |

### Alarms

| Type | Richness | Description |
|------|----------|-------------|
| `AlarmTriggered` | Rich | Alarm fired (type, severity, message) |
| `AlarmAcknowledged` | Minimal | User acknowledged (note) |
| `AlarmCleared` | Minimal | Condition resolved |
| `AlarmShelved` | Minimal | Temporarily suppressed |
| `AlarmUnshelved` | Minimal | Unsuppressed |
| `AlarmEscalated` | Medium | Severity increased |
| `AlarmValueUpdated` | Medium | Value changed while active |

### Procedures

| Type | Richness | Description |
|------|----------|-------------|
| `ProcedureStarted` | Rich | Execution began (params, trigger) |
| `ProcedureStepCompleted` | Medium | Step finished |
| `ProcedureStepSkipped` | Medium | Step skipped |
| `ProcedurePaused` | Minimal | Execution paused |
| `ProcedureResumed` | Minimal | Execution resumed |
| `ProcedureCompleted` | Minimal | Finished successfully |
| `ProcedureFailed` | Medium | Finished with error |
| `ProcedureCancelled` | Minimal | Manually cancelled |

### Procedure Versions (Approval Workflow)

| Type | Richness | Description |
|------|----------|-------------|
| `ProcedureVersionCreated` | Rich | Draft created |
| `ProcedureVersionSubmitted` | Minimal | Submitted for review |
| `ProcedureVersionWithdrawn` | Minimal | Withdrawn from review |
| `ProcedureApprovalAdded` | Medium | Approval/rejection added |
| `ProcedureVersionApproved` | Minimal | Met approval threshold |
| `ProcedureVersionRejected` | Medium | Rejected |
| `ProcedureVersionDeprecated` | Minimal | Marked deprecated |

### Automations

| Type | Richness | Description |
|------|----------|-------------|
| `AutomationTriggered` | Rich | Automation fired |
| `AutomationCompleted` | Minimal | Action succeeded |
| `AutomationFailed` | Medium | Action failed |
| `AutomationSkipped` | Medium | Condition not met |

---

## Best Practices

1. **Recordings are immutable** - Never update a recording or recordable. Append new events.

2. **Use aggregate_id consistently** - All recordings for the same entity share the same `aggregate_id`.

3. **Link causality** - Use `parent_id` to connect related events (e.g., CommandSent → CommandDispatched).

4. **Batch load recordables** - Always use `load_recordables_for_recordings/1` for lists to avoid N+1 queries.

5. **Rich vs Minimal** - Put display/filter data in recordables. Index-only data goes in recordings.

6. **Timestamps** - Use `timestamp` field for business time, not `inserted_at` (database time).

---

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Recordings` | Context module - create, query, load |
| `Cadence.Recordings.Recording` | Recording schema |
| `Cadence.Recordings.Recordable` | Protocol definition |
| `Cadence.Recordings.Recordables.*` | Individual recordable schemas |

## Test Coverage

| Module | Test Module |
|--------|-------------|
| `Cadence.Recordings` | `Cadence.RecordingsTest` |

---

## References

- [37signals Writebook on Recordables](https://dev.37signals.com/vanilla-rails-is-plenty/)
- [Recordables Implementation Plan](../architecture/recordables-implementation-plan.md)
