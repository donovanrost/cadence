---
title: Recordings Architecture
tags: [architecture, recordings, event-sourcing, runtime]
created: 2026-01-29
updated: 2026-01-29
status: active
---

# Recordings Architecture

## Overview

The recordings system is a **pure event sourcing architecture** for auditability. Events are stored once and never modified, enabling perfect audit trails and state replay.

**Location:** `lib/cadence/recordings/`

## High-Level Flow

```
Domain Use Case (e.g., acknowledge alarm)
       ↓
recorder().record(:alarm_acknowledged, alarm, user_id, attrs)
       ↓
EventRecorder Adapter (build attrs, resolve module)
       ↓
Recordings.create(recordable_module, recordable_attrs, recording_attrs)
       ↓
Ecto.Multi transaction:
  1. Insert recordable (e.g., AlarmAcknowledged)
  2. Insert recording (index entry)
       ↓
PubSub broadcast (optional)
```

## Core Components

### Recording Schema

**File:** `recordings/recording.ex`

Pure index table linking events to aggregates:

```
%Recording{
  id: UUID,
  organization_id: UUID,        # Tenant isolation
  bucket_id: UUID | nil,        # Shift/mission scoping

  aggregate_type: String,       # "Command", "Alarm", "Procedure"
  aggregate_id: UUID,           # Entity instance ID

  recordable_type: String,      # "CommandDispatched"
  recordable_id: UUID,          # FK to specific recordable table

  parent_id: UUID | nil,        # Causality chain
  root_id: UUID | nil,          # Denormalized root

  actor_id: UUID | nil,         # User who triggered
  actor_type: String,           # "user" or "system"

  timestamp: DateTime           # Event occurrence time
}
```

### Recordable Protocol

**File:** `recordings/recordable.ex`

Interface that all event types implement:

- `recording_type/1` - Event type name (e.g., "AlarmTriggered")
- `aggregate_type/1` - Entity type (e.g., "Alarm")
- `title/1` - Human-readable title for timeline
- `status/1` - Status for filtering
- `severity/1` - Severity for alarms

### Recordable Types

**Location:** `recordings/recordables/`

**Command Lifecycle (8 types):**
- `CommandQueued` - Queue entry with priority
- `CommandDequeued` - Queue exit (executed/cancelled/expired)
- `CommandDispatched` - Sent to dispatcher with parameters
- `CommandSent` - Transmitted via transport
- `CommandVerified` - Verification stages complete
- `CommandVerificationFailed` - Verification requirement not met
- `CommandRejected` - Validation/authorization failed
- `CommandErrored` - Transmission/encoding failed

**Alarm Management (7 types):**
- `AlarmTriggered` - Alarm activated with severity
- `AlarmAcknowledged` - User acknowledgement
- `AlarmCleared` - Manual or automatic clearance
- `AlarmShelved` - Temporary suppression
- `AlarmUnshelved` - Suppression removed
- `AlarmEscalated` - Severity change
- `AlarmValueUpdated` - Value change while active

**Procedure Execution (8 types):**
- `ProcedureStarted` - Execution began
- `ProcedureStepCompleted` - Step finished
- `ProcedureStepSkipped` - Step skipped with reason
- `ProcedurePaused` - Execution paused
- `ProcedureResumed` - Execution resumed
- `ProcedureCompleted` - Execution finished
- `ProcedureFailed` - Execution failed
- `ProcedureCancelled` - Execution cancelled

**Procedure Versioning (7 types):**
- `ProcedureVersionCreated` - Draft created
- `ProcedureVersionSubmitted` - Submitted for review
- `ProcedureVersionWithdrawn` - Withdrawn from review
- `ProcedureVersionApproved` - Approved
- `ProcedureVersionRejected` - Rejected with reason
- `ProcedureVersionDeprecated` - Marked deprecated
- `ProcedureVersionClosed` - Closed without merging

**Review Workflow (6 types):**
- `ProcedureReviewSubmitted` - Version submitted for review
- `ProcedureReviewRequested` - Specific reviewer requested
- `ProcedureReviewApproved` - Reviewer approved
- `ProcedureChangesRequested` - Changes requested
- `ProcedureReviewCommentAdded` - Threaded comment
- `ProcedureThreadResolved` - Thread resolved

**Automation (4 types):**
- `AutomationTriggered` - Automation rule fired
- `AutomationCompleted` - Action completed
- `AutomationFailed` - Action failed
- `AutomationSkipped` - Action skipped

## Port/Adapter Pattern

### EventRecorder Port

**File:** `ports/recordings/event_recorder.ex`

```elixir
@callback record(event_type, aggregate, actor_id, attrs) :: :ok | {:error, error}
@callback record_with_context(event_type, aggregate, actor_id, attrs, context) :: :ok | {:error, error}
```

### Adapter Implementation

**File:** `adapters/recordings/recordings_event_recorder.ex`

1. Maps event atom → recordable module
2. Extracts event-specific attrs from aggregate
3. Builds recording attrs with context
4. Creates both in single transaction

## Querying

### Timeline Queries

```elixir
# List recordings in time range
Recordings.list_recordings(start_time, end_time, opts)

# Cursor-based pagination
Recordings.list_recordings_before(cursor, opts)

# With recordables loaded (avoids N+1)
Recordings.list_recordings_with_recordables(cursor, opts)
```

### Aggregate History

```elixir
# All events for an entity
Recordings.get_aggregate_history(aggregate_type, aggregate_id)

# With recordables loaded
Recordings.get_aggregate_history_with_recordables(aggregate_type, aggregate_id)
```

### Causality Chains

```elixir
# All events in a chain
Recordings.get_causality_chain(root_id)

# Child events of a parent
Recordings.get_children(parent_id)
```

## Batch Loading

Groups recordings by type, queries each type once:

```elixir
def load_recordables_for_recordings(recordings) do
  by_type = Enum.group_by(recordings, & &1.recordable_type)

  recordables =
    Enum.flat_map(by_type, fn {type, recs} ->
      ids = Enum.map(recs, & &1.recordable_id)
      module = recordable_module(type)
      module |> where([r], r.id in ^ids) |> Repo.all()
    end)
    |> Map.new(&{&1.id, &1})

  Enum.map(recordings, fn r ->
    recordable = Map.get(recordables, r.recordable_id)
    %{recording: r, recordable: recordable, ...}
  end)
end
```

## Causality Tracking

Events link via `parent_id` and `root_id`:

```
CommandDispatched (root)
  root_id: nil → set to aggregate_id
  parent_id: nil
        ↓
CommandSent (child)
  root_id: aggregate_id
  parent_id: dispatch_recording_id
        ↓
CommandVerified (grandchild)
  root_id: aggregate_id
  parent_id: sent_recording_id
```

## Key Design Points

1. **Immutability** - Events never modified, only created
2. **Separation** - Index table + type-specific tables
3. **Protocol Polymorphism** - Uniform access to 50+ event types
4. **Atomic Transactions** - Recordable + recording together
5. **Batch Loading** - N+1 avoidance via type grouping
6. **Multi-Tenancy** - Organization isolation at recording level
