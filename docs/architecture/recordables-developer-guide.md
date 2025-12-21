# Recordables Pattern - Developer Guide

## Overview

Cadence uses the **37signals Recordables pattern** for event sourcing. This provides a complete audit trail of all domain events while keeping the schema flexible and queries efficient.

**Key insight:** Instead of one giant `events` table with a JSON blob, we have:
- A `recordings` table (pure index) that links events to aggregates
- Separate `recordable` tables for each event type (strongly typed)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         recordings (index)                          │
├─────────────────────────────────────────────────────────────────────┤
│ id │ aggregate_type │ aggregate_id │ recordable_type │ recordable_id│
├────┼────────────────┼──────────────┼─────────────────┼──────────────┤
│ r1 │ Command        │ cmd-123      │ CommandDispatched│ cd-456      │
│ r2 │ Command        │ cmd-123      │ CommandSent       │ cs-789      │
│ r3 │ Command        │ cmd-123      │ CommandVerified   │ cv-012      │
│ r4 │ Alarm          │ alm-555      │ AlarmTriggered    │ at-333      │
└────┴────────────────┴──────────────┴─────────────────┴──────────────┘
         │                                      │
         │                                      ▼
         │                    ┌─────────────────────────────────────┐
         │                    │    command_dispatcheds (rich)       │
         │                    ├─────────────────────────────────────┤
         │                    │ id: cd-456                          │
         │                    │ command_name: "SET_MODE"            │
         │                    │ parameters: %{mode: 1}              │
         │                    │ target_id: target-xyz               │
         │                    │ is_hazardous: false                 │
         │                    └─────────────────────────────────────┘
         │
         ▼
    Aggregate: Command cmd-123
    State derived by replaying r1 → r2 → r3
```

## Core Concepts

### Recordings
The `recordings` table is a **pure index**. It contains:
- `aggregate_type` / `aggregate_id` - What entity this event is about
- `recordable_type` / `recordable_id` - Polymorphic reference to event details
- `parent_id` / `root_id` - Causality chain (which event caused this one)
- `actor_id` / `actor_type` - Who/what triggered this event
- `timestamp` - When the event occurred
- `target_id` - Optional filter for target-scoped queries

### Recordables
Each event type has its own table. Some are **rich** (many columns), some are **minimal** (just an ID):

| Recordable | Richness | Example Columns |
|------------|----------|-----------------|
| `CommandDispatched` | Rich | command_name, parameters, target_id, is_hazardous |
| `CommandSent` | Minimal | interface_id |
| `CommandVerified` | Medium | verification_result, stages_completed |
| `AlarmTriggered` | Rich | alarm_type, severity, message, trigger_value |
| `AlarmAcknowledged` | Minimal | note |

### Aggregates
Aggregates are entities whose state is derived from their recordings:
- `Command` - State: dispatched → sent → verified/failed
- `Alarm` - State: triggered → acknowledged → cleared
- `ProcedureExecution` - State: started → running → completed/failed
- `QueueEntry` - State: queued → dequeued

### The Recordable Protocol
All recordable structs implement the `Cadence.Recordings.Recordable` protocol:

```elixir
defprotocol Cadence.Recordings.Recordable do
  def recording_type(recordable)  # e.g., "CommandDispatched"
  def aggregate_type(recordable)  # e.g., "Command"
  def title(recordable)           # Display title for timeline
  def status(recordable)          # Status string for display
  def severity(recordable)        # Severity level (alarms)
end
```

## Creating Recordings

### Basic Usage

```elixir
alias Cadence.Recordings
alias Cadence.Recordings.Recordables.CommandDispatched

# Create a recording with its recordable atomically
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
      aggregate_id: Ecto.UUID.generate(),  # New command = new aggregate
      actor_id: user_id,
      actor_type: "user",
      target_id: target_id,
      timestamp: DateTime.utc_now()
    }
  )
```

### Chaining Events with Ecto.Multi

For related events (causality chain), use `Recordings.append/5`:

```elixir
alias Ecto.Multi

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
|> Recordings.append(:sent, CommandSent, %{interface_id: interface_id}, fn changes ->
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

## Querying Recordings

### Timeline Queries

```elixir
alias Cadence.Recordings

# List recordings for a time range
recordings = Recordings.list_recordings(mission_id, start_time, end_time,
  aggregate_types: ["Command", "Alarm"],
  target_id: target_id,
  limit: 100
)

# Cursor-based pagination (for infinite scroll)
recordings = Recordings.list_recordings_before(mission_id, cursor,
  aggregate_types: ["Command"],
  limit: 50
)

# Load with recordables (batch loaded to avoid N+1)
recordings_with_data = Recordings.load_recordables_for_recordings(recordings)
# Returns: [%{recording: r, recordable: rd, title: "...", status: "...", severity: "..."}]
```

### Aggregate History

```elixir
# Get all recordings for a specific entity
recordings = Recordings.get_aggregate_history("Command", command_aggregate_id)

# With recordables loaded
history = Recordings.get_aggregate_history_with_recordables("Alarm", alarm_id)
```

### Single Recording

```elixir
recording = Recordings.get_recording!(id)
recordable = Recordings.load_recordable(recording)
```

## Adding a New Recordable Type

### Step 1: Create the Migration

Add a new table to the recordings migration or create a new migration:

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

Add to `@recordable_modules` in `lib/cadence/recordings.ex`:

```elixir
@recordable_modules %{
  # ... existing entries ...
  "MyNewEvent" => Cadence.Recordings.Recordables.MyNewEvent
}
```

### Step 4: Create Recordings in Your Domain Logic

```elixir
def do_something(params, opts) do
  # ... your logic ...

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

## Existing Recordable Types

### Commands
| Type | Description |
|------|-------------|
| `CommandDispatched` | Command sent to target (rich: name, params, target) |
| `CommandSent` | Transmitted to interface (minimal) |
| `CommandVerified` | Verification passed (medium: result) |
| `CommandVerificationFailed` | Verification failed (medium: error) |
| `CommandRejected` | Validation/auth failed |
| `CommandErrored` | Transmission error |
| `CommandQueued` | Added to queue |
| `CommandDequeued` | Removed from queue |

### Alarms
| Type | Description |
|------|-------------|
| `AlarmTriggered` | Alarm fired (rich: type, severity, message) |
| `AlarmAcknowledged` | User acknowledged (minimal: note) |
| `AlarmCleared` | Condition resolved |
| `AlarmShelved` | Temporarily suppressed |
| `AlarmUnshelved` | Unsuppressed |
| `AlarmEscalated` | Severity increased |
| `AlarmValueUpdated` | Value changed while active |

### Procedures
| Type | Description |
|------|-------------|
| `ProcedureStarted` | Execution began (rich: params, trigger) |
| `ProcedureStepCompleted` | Step finished |
| `ProcedureStepSkipped` | Step skipped |
| `ProcedurePaused` | Execution paused |
| `ProcedureResumed` | Execution resumed |
| `ProcedureCompleted` | Finished successfully |
| `ProcedureFailed` | Finished with error |
| `ProcedureCancelled` | Manually cancelled |

### Procedure Versions (Approval Workflow)
| Type | Description |
|------|-------------|
| `ProcedureVersionCreated` | Draft created |
| `ProcedureVersionSubmitted` | Submitted for review |
| `ProcedureVersionWithdrawn` | Withdrawn from review |
| `ProcedureApprovalAdded` | Approval/rejection added |
| `ProcedureVersionApproved` | Met approval threshold |
| `ProcedureVersionRejected` | Rejected |
| `ProcedureVersionDeprecated` | Marked deprecated |

### Automations
| Type | Description |
|------|-------------|
| `AutomationTriggered` | Automation fired |
| `AutomationCompleted` | Action succeeded |
| `AutomationFailed` | Action failed |
| `AutomationSkipped` | Condition not met |

## Best Practices

1. **Recordings are immutable** - Never update a recording or recordable. Append new events.

2. **Use aggregate_id consistently** - All recordings for the same entity share the same `aggregate_id`.

3. **Link causality** - Use `parent_id` to connect related events (e.g., CommandSent → CommandDispatched).

4. **Batch load recordables** - Always use `load_recordables_for_recordings/1` for lists to avoid N+1 queries.

5. **Rich vs Minimal** - Put data that's needed for display/filtering in recordables. Data that's only needed for the recording index goes in recordings.

6. **Timestamps** - Use `timestamp` field for when the event occurred (business time), not `inserted_at` (database time).

## References

- [37signals Writebook on Recordables](https://dev.37signals.com/vanilla-rails-is-plenty/)
- Implementation plan: `docs/architecture/recordables-implementation-plan.md`
- Core module: `lib/cadence/recordings.ex`
- Protocol: `lib/cadence/recordings/recordable.ex`
- Recording schema: `lib/cadence/recordings/recording.ex`
