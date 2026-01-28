---
title: Recordables Implementation Plan
aliases: [recordings implementation, event sourcing plan]
tags: [architecture, implementation-plan, recordings, event-sourcing]
related:
  - "[[adding-recordable]]"
  - "[[recording]]"
  - "[[recordable]]"
  - "[[aggregate]]"
created: 2024-12-01
updated: 2025-01-27
status: active
---

# Recordables/Buckets Architecture Implementation Plan

> **Developer Guide:** For a practical guide on working with recordings, see [Adding a Recordable](../patterns/adding-recordable.md).

## Quick Start for Implementation

**What this is:** Event sourcing architecture where `recordings` is a pure index table pointing to separate `recordable` tables (one per event type). State is derived by replaying recordings.

**Key files to reference:**
- This plan document
- `lib/cadence/commands/target_dispatcher.ex` - Primary write path to modify
- `lib/cadence/alarms.ex` - Alarm write paths
- `lib/cadence/timeline.ex` - Primary read path to modify

**Implementation order (vertical slice):**
1. Create all migrations first (recordings + all recordable tables + buckets)
2. Implement Commands aggregate end-to-end (schema → write path → read path)
3. Then Alarms, then Procedures, then Automations, then Queue

**Critical patterns:**
- Recordings are PURE index - no data duplication from recordables
- Use Recordable protocol for uniform access to display fields
- Batch load recordables by type (not N+1)
- Cursor-based pagination using `(timestamp, id)` tuple
- Projections (alarms, procedure_executions) updated after recording creation

---

## Overview

Implement a **true event sourcing** architecture following the 37signals Recordables pattern:

- **Recordings** - Pure index table linking events to aggregates and buckets
- **Recordables** - Separate table per event type (some rich, some minimal)
- **Buckets** - Polymorphic containers with access control
- **Aggregates** - Entities whose state is derived from their recordings

---

## Architecture

### The 37signals Pattern

```
recordings (pure index)
    │
    ├── aggregate_type: "Command"     ← what entity
    ├── aggregate_id: uuid            ← which entity
    ├── recordable_type: "CommandDispatched"  ← what event
    ├── recordable_id: uuid           ← event details
    ├── bucket_id                     ← container (shift, mission)
    └── parent_id                     ← causality chain
            │
            ▼
    recordable tables (one per event type)
    ├── command_dispatcheds (rich: command_name, params, target)
    ├── command_sents (minimal: just timestamp via recording)
    ├── command_verifieds (medium: result, actual, expected)
    └── ...
```

### Key Principles

1. **Recordings are pure index** - No content duplication, just polymorphic references
2. **Each event type has its own table** - Some rich (many columns), some minimal (just ID)
3. **Immutability** - Recordings and recordables never change, only append
4. **State from replay** - Current state derived from replaying recordings
5. **Aggregate linking** - All events for an entity share `aggregate_id`

---

## Phase 1: Core Schema

### 1.1 Migration: `recordings` table

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_create_recordings.exs

create table(:recordings, primary_key: false) do
  add :id, :binary_id, primary_key: true

  # Multi-tenancy
  add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
  add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
  add :bucket_id, references(:buckets, type: :binary_id, on_delete: :nilify_all)

  # Aggregate reference (the entity this event is about)
  add :aggregate_type, :string, null: false  # "Command", "Alarm", "Procedure", "QueueEntry"
  add :aggregate_id, :binary_id, null: false

  # Recordable reference (the event details)
  add :recordable_type, :string, null: false  # "CommandDispatched", "AlarmTriggered", etc.
  add :recordable_id, :binary_id, null: false

  # Hierarchy (causality chain)
  add :parent_id, references(:recordings, type: :binary_id, on_delete: :nilify_all)
  add :root_id, :binary_id  # Denormalized for fast tree queries

  # Actor
  add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
  add :actor_type, :string, default: "user"  # "user", "system", "automation"

  # Target context (optional, for filtering)
  add :target_id, references(:targets, type: :binary_id, on_delete: :nilify_all)

  # Timestamp (when the event occurred)
  add :timestamp, :utc_datetime_usec, null: false

  timestamps(type: :utc_datetime_usec, updated_at: false)  # Immutable
end

# Primary query patterns
create index(:recordings, [:mission_id, :timestamp])
create index(:recordings, [:bucket_id, :timestamp])
create index(:recordings, [:aggregate_type, :aggregate_id, :timestamp])
create index(:recordings, [:recordable_type, :recordable_id], unique: true)
create index(:recordings, [:parent_id])
create index(:recordings, [:root_id, :timestamp])
create index(:recordings, [:target_id, :timestamp])
```

### 1.2 Recordable Tables: Commands

```elixir
# Command dispatched (rich - has all command details)
create table(:command_dispatcheds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :command_name, :string, null: false
  add :opcode, :integer
  add :parameters, :map, default: %{}
  add :encoded_binary, :binary
  add :target_id, :binary_id, null: false
  add :meta_command_id, :binary_id
  add :is_hazardous, :boolean, default: false
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Command sent to interface (minimal - just marks transmission)
create table(:command_sents, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :interface_id, :binary_id
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Command verified (medium - verification result)
create table(:command_verifieds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :verification_item, :string
  add :verification_expected, :string
  add :verification_actual, :string
  add :verification_result, :map
  add :stages_completed, {:array, :string}, default: []
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Command verification failed
create table(:command_verification_faileds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :error_reason, :string
  add :verification_actual, :string
  add :verification_expected, :string
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Command rejected (validation/authorization failure)
create table(:command_rejecteds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :error_reason, :string
  add :rejection_type, :string  # "validation", "authorization", "phase"
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Command errored (transmission/encoding failure)
create table(:command_erroreds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :error_reason, :string
  add :error_type, :string
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### 1.3 Recordable Tables: Alarms

```elixir
# Alarm triggered (rich - full alarm context)
create table(:alarm_triggereds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :alarm_type, :string, null: false
  add :severity, :string, null: false
  add :source_type, :string, null: false
  add :source_id, :string, null: false
  add :target_id, :binary_id
  add :message, :text
  add :trigger_value, :float
  add :limit_state, :string
  add :alarm_rule_id, :binary_id
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Alarm acknowledged (minimal - just user and note)
create table(:alarm_acknowledgeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :note, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Alarm cleared
create table(:alarm_cleareds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :clear_type, :string  # "automatic", "manual"
  add :final_value, :float
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Alarm shelved
create table(:alarm_shelveds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :shelve_until, :utc_datetime_usec
  add :reason, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Alarm unshelved
create table(:alarm_unshelveds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :unshelve_type, :string  # "manual", "timeout"
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Alarm escalated
create table(:alarm_escalateds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :previous_severity, :string
  add :new_severity, :string
  add :trigger_value, :float
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Alarm value updated (while still in violation)
create table(:alarm_value_updateds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :trigger_value, :float
  add :previous_value, :float
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### 1.4 Recordable Tables: Procedures

```elixir
# Procedure started (rich - full execution context)
create table(:procedure_starteds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :procedure_id, :binary_id, null: false
  add :procedure_version_id, :binary_id, null: false
  add :target_id, :binary_id
  add :parameters, :map, default: %{}
  add :triggered_by, :string  # "manual", "schedule", "event"
  add :trigger_context, :map
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure step completed
create table(:procedure_step_completeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :step_id, :string
  add :step_index, :integer
  add :result, :map
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure step skipped
create table(:procedure_step_skippeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :step_id, :string
  add :step_index, :integer
  add :reason, :string
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure paused
create table(:procedure_pauseds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :checkpoint_state, :binary
  add :current_step_index, :integer
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure resumed
create table(:procedure_resumeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure completed
create table(:procedure_completeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :completed_steps, {:array, :string}, default: []
  add :skipped_steps, {:array, :string}, default: []
  add :step_results, :map, default: %{}
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure failed
create table(:procedure_faileds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :error_message, :text
  add :error_step_index, :integer
  add :failed_steps, {:array, :string}, default: []
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure cancelled
create table(:procedure_cancelleds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :reason, :string
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### 1.5 Recordable Tables: Procedure Versions (Approval Workflow)

```elixir
# Procedure version created (initial draft)
create table(:procedure_version_createds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :procedure_id, :binary_id, null: false
  add :version_number, :integer
  add :source_code, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure version submitted for review
create table(:procedure_version_submitteds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :note, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure version withdrawn from review
create table(:procedure_version_withdrawns, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :reason, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Approval added to procedure version
create table(:procedure_approval_addeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :decision, :string, null: false  # "approved", "rejected"
  add :comment, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure version approved (met approval threshold)
create table(:procedure_version_approveds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure version rejected
create table(:procedure_version_rejecteds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :reason, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Procedure version deprecated
create table(:procedure_version_deprecateds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :reason, :text
  add :replacement_version_id, :binary_id
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### 1.6 Recordable Tables: Automations

```elixir
# Automation triggered
create table(:automation_triggereds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :automation_id, :binary_id, null: false
  add :trigger_event, :map
  add :trigger_type, :string  # "telemetry", "alarm", "schedule"
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Automation completed successfully
create table(:automation_completeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :action_result, :map
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Automation failed
create table(:automation_faileds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :error_message, :text
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Automation skipped (condition not met)
create table(:automation_skippeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :reason, :string
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### 1.7 Recordable Tables: Queue

```elixir
# Command queued
create table(:command_queueds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :command_name, :string, null: false
  add :parameters, :map, default: %{}
  add :target_id, :binary_id, null: false
  add :priority, :integer, default: 3
  add :scheduled_at, :utc_datetime_usec
  add :expires_at, :utc_datetime_usec
  add :max_attempts, :integer, default: 3
  add :dispatch_opts, :map, default: %{}
  timestamps(type: :utc_datetime_usec, updated_at: false)
end

# Command dequeued (executed, cancelled, or expired)
create table(:command_dequeueds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :reason, :string  # "executed", "cancelled", "expired"
  add :command_aggregate_id, :binary_id  # Links to the resulting command aggregate
  add :attempts, :integer
  add :last_error, :string
  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

---

## Phase 2: Recording Schema and Protocol

### 2.1 Recording Schema

```elixir
# lib/cadence/recordings/recording.ex
defmodule Cadence.Recordings.Recording do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "recordings" do
    field :aggregate_type, :string
    field :aggregate_id, :binary_id
    field :recordable_type, :string
    field :recordable_id, :binary_id
    field :parent_id, :binary_id
    field :root_id, :binary_id
    field :actor_type, :string, default: "user"
    field :timestamp, :utc_datetime_usec

    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :bucket, Cadence.Buckets.Bucket
    belongs_to :actor, Cadence.Accounts.User, foreign_key: :actor_id
    belongs_to :target, Cadence.Targets.Target
    belongs_to :parent, __MODULE__

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recording, attrs) do
    recording
    |> cast(attrs, [:organization_id, :mission_id, :bucket_id, :aggregate_type,
                    :aggregate_id, :recordable_type, :recordable_id, :parent_id,
                    :root_id, :actor_id, :actor_type, :target_id, :timestamp])
    |> validate_required([:organization_id, :mission_id, :aggregate_type,
                          :aggregate_id, :recordable_type, :recordable_id, :timestamp])
    |> maybe_set_root_id()
  end

  defp maybe_set_root_id(changeset) do
    if get_field(changeset, :root_id) || get_field(changeset, :parent_id) do
      changeset
    else
      put_change(changeset, :root_id, get_field(changeset, :aggregate_id))
    end
  end
end
```

### 2.2 Recordable Protocol

```elixir
# lib/cadence/recordings/recordable.ex
defprotocol Cadence.Recordings.Recordable do
  @doc "Returns the recording type name for this recordable"
  def recording_type(recordable)

  @doc "Returns the aggregate type this recordable belongs to"
  def aggregate_type(recordable)

  @doc "Returns display title for timeline"
  def title(recordable)

  @doc "Returns status string for filtering"
  def status(recordable)

  @doc "Returns severity if applicable"
  def severity(recordable)
end
```

### 2.3 Example Recordable Schema

```elixir
# lib/cadence/recordings/recordables/command_dispatched.ex
defmodule Cadence.Recordings.Recordables.CommandDispatched do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_dispatcheds" do
    field :command_name, :string
    field :opcode, :integer
    field :parameters, :map, default: %{}
    field :encoded_binary, :binary
    field :target_id, :binary_id
    field :meta_command_id, :binary_id
    field :is_hazardous, :boolean, default: false
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:command_name, :opcode, :parameters, :encoded_binary,
                    :target_id, :meta_command_id, :is_hazardous])
    |> validate_required([:command_name, :target_id])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandDispatched do
  def recording_type(_), do: "CommandDispatched"
  def aggregate_type(_), do: "Command"
  def title(r), do: r.command_name
  def status(_), do: "pending"
  def severity(_), do: nil
end
```

---

## Phase 3: Recordings Context

### 3.1 Context Module

```elixir
# lib/cadence/recordings.ex
defmodule Cadence.Recordings do
  import Ecto.Query
  alias Cadence.Repo
  alias Cadence.Recordings.{Recording, Recordable}
  alias Ecto.Multi

  @doc """
  Creates a recording with its recordable in a single transaction.
  """
  def create(recordable_module, recordable_attrs, recording_attrs) do
    Multi.new()
    |> Multi.insert(:recordable, recordable_module.changeset(struct(recordable_module), recordable_attrs))
    |> Multi.insert(:recording, fn %{recordable: recordable} ->
      Recording.changeset(%Recording{}, Map.merge(recording_attrs, %{
        recordable_type: Recordable.recording_type(recordable),
        recordable_id: recordable.id,
        aggregate_type: Recordable.aggregate_type(recordable)
      }))
    end)
    |> Repo.transaction()
  end

  @doc """
  Appends a recording creation to an existing Multi.
  """
  def append(multi, name, recordable_module, recordable_attrs, recording_attrs_fn) do
    multi
    |> Multi.insert(:"#{name}_recordable", recordable_module.changeset(struct(recordable_module), recordable_attrs))
    |> Multi.insert(:"#{name}_recording", fn changes ->
      recordable = Map.get(changes, :"#{name}_recordable")
      recording_attrs = recording_attrs_fn.(changes)

      Recording.changeset(%Recording{}, Map.merge(recording_attrs, %{
        recordable_type: Recordable.recording_type(recordable),
        recordable_id: recordable.id,
        aggregate_type: Recordable.aggregate_type(recordable)
      }))
    end)
  end

  @doc """
  Lists recordings for timeline display.
  """
  def list_recordings(mission_id, start_time, end_time, opts \\ []) do
    target_id = Keyword.get(opts, :target_id)
    aggregate_types = Keyword.get(opts, :aggregate_types)
    limit = Keyword.get(opts, :limit, 100)

    query =
      Recording
      |> where([r], r.mission_id == ^mission_id)
      |> where([r], r.timestamp >= ^start_time and r.timestamp <= ^end_time)
      |> order_by([r], desc: r.timestamp)
      |> limit(^limit)

    query =
      if target_id do
        where(query, [r], r.target_id == ^target_id)
      else
        query
      end

    query =
      if aggregate_types do
        where(query, [r], r.aggregate_type in ^aggregate_types)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets all recordings for an aggregate (entity history).
  """
  def get_aggregate_history(aggregate_type, aggregate_id) do
    Recording
    |> where([r], r.aggregate_type == ^aggregate_type and r.aggregate_id == ^aggregate_id)
    |> order_by([r], asc: r.timestamp)
    |> Repo.all()
  end

  @doc """
  Loads the recordable for a recording.
  """
  def load_recordable(%Recording{recordable_type: type, recordable_id: id}) do
    module = recordable_module(type)
    Repo.get(module, id)
  end

  # Command recordables
  defp recordable_module("CommandDispatched"), do: Cadence.Recordings.Recordables.CommandDispatched
  defp recordable_module("CommandSent"), do: Cadence.Recordings.Recordables.CommandSent
  defp recordable_module("CommandVerified"), do: Cadence.Recordings.Recordables.CommandVerified
  defp recordable_module("CommandVerificationFailed"), do: Cadence.Recordings.Recordables.CommandVerificationFailed
  defp recordable_module("CommandRejected"), do: Cadence.Recordings.Recordables.CommandRejected
  defp recordable_module("CommandErrored"), do: Cadence.Recordings.Recordables.CommandErrored

  # Alarm recordables
  defp recordable_module("AlarmTriggered"), do: Cadence.Recordings.Recordables.AlarmTriggered
  defp recordable_module("AlarmAcknowledged"), do: Cadence.Recordings.Recordables.AlarmAcknowledged
  defp recordable_module("AlarmCleared"), do: Cadence.Recordings.Recordables.AlarmCleared
  defp recordable_module("AlarmShelved"), do: Cadence.Recordings.Recordables.AlarmShelved
  defp recordable_module("AlarmUnshelved"), do: Cadence.Recordings.Recordables.AlarmUnshelved
  defp recordable_module("AlarmEscalated"), do: Cadence.Recordings.Recordables.AlarmEscalated
  defp recordable_module("AlarmValueUpdated"), do: Cadence.Recordings.Recordables.AlarmValueUpdated

  # Procedure recordables
  defp recordable_module("ProcedureStarted"), do: Cadence.Recordings.Recordables.ProcedureStarted
  defp recordable_module("ProcedureStepCompleted"), do: Cadence.Recordings.Recordables.ProcedureStepCompleted
  defp recordable_module("ProcedureStepSkipped"), do: Cadence.Recordings.Recordables.ProcedureStepSkipped
  defp recordable_module("ProcedurePaused"), do: Cadence.Recordings.Recordables.ProcedurePaused
  defp recordable_module("ProcedureResumed"), do: Cadence.Recordings.Recordables.ProcedureResumed
  defp recordable_module("ProcedureCompleted"), do: Cadence.Recordings.Recordables.ProcedureCompleted
  defp recordable_module("ProcedureFailed"), do: Cadence.Recordings.Recordables.ProcedureFailed
  defp recordable_module("ProcedureCancelled"), do: Cadence.Recordings.Recordables.ProcedureCancelled

  # Queue recordables
  defp recordable_module("CommandQueued"), do: Cadence.Recordings.Recordables.CommandQueued
  defp recordable_module("CommandDequeued"), do: Cadence.Recordings.Recordables.CommandDequeued
end
```

---

## Phase 4: Write Path Modifications

### 4.1 Command Dispatch

**File:** `lib/cadence/commands/target_dispatcher.ex`

```elixir
defp create_command_log(state, command, target, params, encoded, opts) do
  user_id = Keyword.get(opts, :user_id)
  aggregate_id = Ecto.UUID.generate()  # The command's identity

  recordable_attrs = %{
    command_name: command.name,
    opcode: command.opcode,
    parameters: params,
    encoded_binary: encoded,
    target_id: target.id,
    meta_command_id: command.id,
    is_hazardous: command.is_hazardous
  }

  recording_attrs = %{
    organization_id: state.mission.organization_id,
    mission_id: state.mission_id,
    bucket_id: get_active_bucket_id(state),  # Shift bucket
    aggregate_id: aggregate_id,
    actor_id: user_id,
    actor_type: "user",
    target_id: target.id,
    timestamp: DateTime.utc_now()
  }

  case Recordings.create(CommandDispatched, recordable_attrs, recording_attrs) do
    {:ok, %{recordable: recordable, recording: recording}} ->
      {:ok, %{aggregate_id: aggregate_id, recording: recording, recordable: recordable}}
    {:error, _, changeset, _} ->
      {:error, changeset}
  end
end

# When command is sent to interface
defp record_command_sent(aggregate_id, recording_attrs) do
  Recordings.create(CommandSent, %{interface_id: recording_attrs[:interface_id]}, %{
    aggregate_id: aggregate_id,
    # ... other attrs
  })
end

# When command is verified
defp record_command_verified(aggregate_id, verification_result, recording_attrs) do
  Recordings.create(CommandVerified, verification_result, %{
    aggregate_id: aggregate_id,
    parent_id: recording_attrs[:parent_recording_id],
    # ... other attrs
  })
end
```

### 4.2 Alarm Events

**File:** `lib/cadence/alarms.ex`

```elixir
def trigger_alarm(attrs) do
  aggregate_id = Ecto.UUID.generate()

  recordable_attrs = %{
    alarm_type: attrs.alarm_type,
    severity: attrs.severity,
    source_type: attrs.source_type,
    source_id: attrs.source_id,
    target_id: attrs.target_id,
    message: attrs.message,
    trigger_value: attrs.trigger_value,
    limit_state: attrs.limit_state,
    alarm_rule_id: attrs.alarm_rule_id
  }

  recording_attrs = %{
    organization_id: attrs.organization_id,
    mission_id: attrs.mission_id,
    bucket_id: attrs.bucket_id,
    aggregate_id: aggregate_id,
    actor_type: "system",
    target_id: attrs.target_id,
    timestamp: DateTime.utc_now()
  }

  Recordings.create(AlarmTriggered, recordable_attrs, recording_attrs)
end

def acknowledge_alarm(aggregate_id, user_id, note, recording_attrs) do
  Recordings.create(AlarmAcknowledged, %{note: note}, %{
    aggregate_id: aggregate_id,
    actor_id: user_id,
    actor_type: "user",
    # ... other attrs
  })
end
```

---

## Phase 5: Current State Projection

Since state is derived from recordings, we need projections for efficient queries.

### 5.1 Aggregate State Module

```elixir
# lib/cadence/recordings/aggregates/command.ex
defmodule Cadence.Recordings.Aggregates.Command do
  @moduledoc """
  Derives current command state from recordings.
  """

  alias Cadence.Recordings

  def get_state(aggregate_id) do
    recordings = Recordings.get_aggregate_history("Command", aggregate_id)

    Enum.reduce(recordings, %{status: nil}, fn recording, state ->
      apply_event(state, recording)
    end)
  end

  defp apply_event(state, %{recordable_type: "CommandDispatched"} = rec) do
    recordable = Recordings.load_recordable(rec)
    %{state |
      status: :pending,
      command_name: recordable.command_name,
      parameters: recordable.parameters,
      target_id: recordable.target_id,
      dispatched_at: rec.timestamp
    }
  end

  defp apply_event(state, %{recordable_type: "CommandSent"} = rec) do
    %{state | status: :sent, sent_at: rec.timestamp}
  end

  defp apply_event(state, %{recordable_type: "CommandVerified"} = rec) do
    recordable = Recordings.load_recordable(rec)
    %{state |
      status: :verified,
      verified_at: rec.timestamp,
      verification_result: recordable.verification_result
    }
  end

  defp apply_event(state, %{recordable_type: "CommandVerificationFailed"} = rec) do
    recordable = Recordings.load_recordable(rec)
    %{state | status: :verification_failed, error_reason: recordable.error_reason}
  end

  defp apply_event(state, %{recordable_type: "CommandRejected"} = rec) do
    recordable = Recordings.load_recordable(rec)
    %{state | status: :rejected, error_reason: recordable.error_reason}
  end

  defp apply_event(state, %{recordable_type: "CommandErrored"} = rec) do
    recordable = Recordings.load_recordable(rec)
    %{state | status: :error, error_reason: recordable.error_reason}
  end

  defp apply_event(state, _), do: state
end
```

### 5.2 Optional: Materialized Projections

For performance, maintain materialized current state:

```elixir
# Could keep command_logs table as a projection
# Updated by event handlers after recordings are created
```

---

## Phase 6: Outbox Integration

### Why We Still Need Outbox

Event sourcing and the outbox pattern serve different purposes:

| Aspect | Recordings (Event Sourcing) | Outbox |
|--------|----------------------------|--------|
| **Purpose** | Source of truth | Reliable delivery |
| **Lifetime** | Permanent | Transient (deleted after delivery) |
| **Focus** | What happened | Who needs to know |
| **Recovery** | Replay for state | Retry for delivery |

The outbox solves the **dual-write problem**: atomically persisting data AND notifying consumers. Without it, you risk:
- Publishing an event but failing to commit (ghost events)
- Committing but failing to publish (lost notifications)

### 6.1 Simplified Outbox Schema

With recordings as the source of truth, the outbox becomes a thin notification layer:

```elixir
# The outbox just points to recordings - no data duplication
create table(:outbox_events, primary_key: false) do
  add :id, :binary_id, primary_key: true

  # Reference to the recording (the actual event data)
  add :recording_id, references(:recordings, type: :binary_id, on_delete: :delete_all), null: false

  # Routing information (denormalized for efficient polling)
  add :topic, :string, null: false  # "mission:{id}", "target:{id}", etc.
  add :aggregate_type, :string, null: false
  add :recordable_type, :string, null: false

  # Delivery tracking
  add :status, :string, default: "pending"  # "pending", "processing", "delivered", "failed"
  add :attempts, :integer, default: 0
  add :last_error, :string
  add :scheduled_at, :utc_datetime_usec  # For retry backoff

  timestamps(type: :utc_datetime_usec, updated_at: false)
end

create index(:outbox_events, [:status, :scheduled_at])
create index(:outbox_events, [:recording_id])
```

### 6.2 Atomic Recording + Outbox Creation

Extend the Recordings context to optionally create outbox entries:

```elixir
# lib/cadence/recordings.ex

@doc """
Creates a recording with its recordable and outbox entry in a single transaction.
"""
def create(recordable_module, recordable_attrs, recording_attrs, opts \\ []) do
  topics = Keyword.get(opts, :topics, [])

  Multi.new()
  |> Multi.insert(:recordable, recordable_module.changeset(struct(recordable_module), recordable_attrs))
  |> Multi.insert(:recording, fn %{recordable: recordable} ->
    Recording.changeset(%Recording{}, Map.merge(recording_attrs, %{
      recordable_type: Recordable.recording_type(recordable),
      recordable_id: recordable.id,
      aggregate_type: Recordable.aggregate_type(recordable)
    }))
  end)
  |> maybe_add_outbox_entries(topics)
  |> Repo.transaction()
  |> case do
    {:ok, %{recording: recording} = result} ->
      # Optional: immediate local broadcast (best-effort, outbox is backup)
      broadcast_locally(recording, topics)
      {:ok, result}
    error ->
      error
  end
end

defp maybe_add_outbox_entries(multi, []), do: multi
defp maybe_add_outbox_entries(multi, topics) do
  Enum.reduce(topics, multi, fn topic, acc ->
    Multi.insert(acc, :"outbox_#{topic}", fn %{recording: recording} ->
      %OutboxEvent{}
      |> OutboxEvent.changeset(%{
        recording_id: recording.id,
        topic: topic,
        aggregate_type: recording.aggregate_type,
        recordable_type: recording.recordable_type,
        status: "pending",
        scheduled_at: DateTime.utc_now()
      })
    end)
  end)
end

defp broadcast_locally(recording, topics) do
  # Best-effort immediate notification via PubSub
  # If this fails, the outbox worker will deliver it
  Enum.each(topics, fn topic ->
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:recording_created, recording.id, recording.aggregate_type, recording.recordable_type}
    )
  end)
end
```

### 6.3 Usage in Write Paths

```elixir
# Command dispatch with outbox
defp create_command_recording(state, command, target, params, encoded, opts) do
  user_id = Keyword.get(opts, :user_id)
  aggregate_id = Ecto.UUID.generate()

  recordable_attrs = %{
    command_name: command.name,
    opcode: command.opcode,
    parameters: params,
    # ...
  }

  recording_attrs = %{
    organization_id: state.mission.organization_id,
    mission_id: state.mission_id,
    aggregate_id: aggregate_id,
    actor_id: user_id,
    target_id: target.id,
    timestamp: DateTime.utc_now()
  }

  # Specify who needs to know about this recording
  topics = [
    "mission:#{state.mission_id}",
    "target:#{target.id}",
    "commands:#{state.mission_id}"
  ]

  Recordings.create(CommandDispatched, recordable_attrs, recording_attrs, topics: topics)
end
```

### 6.4 Outbox Worker (Oban)

```elixir
# lib/cadence/workers/outbox_publisher.ex
defmodule Cadence.Workers.OutboxPublisher do
  use Oban.Worker, queue: :outbox, max_attempts: 10

  alias Cadence.Repo
  alias Cadence.Recordings.OutboxEvent
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Fetch pending outbox events
    events =
      OutboxEvent
      |> where([e], e.status == "pending")
      |> where([e], e.scheduled_at <= ^DateTime.utc_now())
      |> order_by([e], asc: e.scheduled_at)
      |> limit(100)
      |> Repo.all()
      |> Repo.preload(:recording)

    Enum.each(events, &publish_event/1)

    :ok
  end

  defp publish_event(event) do
    try do
      # Publish to external systems (Kafka, webhooks, etc.)
      :ok = publish_to_external(event)

      # Mark as delivered (or delete)
      Repo.delete!(event)
    rescue
      e ->
        # Update for retry with backoff
        event
        |> OutboxEvent.retry_changeset(%{
          attempts: event.attempts + 1,
          last_error: Exception.message(e),
          scheduled_at: calculate_backoff(event.attempts)
        })
        |> Repo.update!()
    end
  end

  defp publish_to_external(event) do
    # Implement based on your needs:
    # - Kafka producer
    # - Webhook dispatch
    # - Cross-classification bridge
    # - External audit log shipping
    :ok
  end

  defp calculate_backoff(attempts) do
    # Exponential backoff: 1s, 2s, 4s, 8s, ... up to 5 minutes
    delay = min(:math.pow(2, attempts) |> trunc(), 300)
    DateTime.add(DateTime.utc_now(), delay, :second)
  end
end
```

### 6.5 Consumer Recovery Pattern

When consumers reconnect, they can catch up from recordings:

```elixir
# lib/cadence_web/live/timeline_live.ex

def mount(%{"mission_id" => mission_id}, _session, socket) do
  if connected?(socket) do
    # Subscribe to real-time updates
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}")

    # Load recent recordings (catches anything missed during disconnect)
    recordings = Recordings.list_recordings(
      mission_id,
      DateTime.add(DateTime.utc_now(), -5, :minute),  # Last 5 minutes
      DateTime.utc_now(),
      limit: 100
    )

    {:ok, assign(socket, recordings: recordings)}
  else
    {:ok, assign(socket, recordings: [])}
  end
end

def handle_info({:recording_created, recording_id, _agg_type, _rec_type}, socket) do
  # Fetch full recording and add to list
  recording = Recordings.get_recording!(recording_id)
  {:noreply, update(socket, :recordings, &[recording | &1])}
end
```

### 6.6 Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         WRITE PATH                                   │
│                                                                      │
│   User Action                                                        │
│       │                                                              │
│       ▼                                                              │
│   ┌─────────────────────────────────────────────┐                   │
│   │            Repo.transaction                  │                   │
│   │  ┌─────────────────────────────────────┐    │                   │
│   │  │ 1. Insert recordable                 │    │                   │
│   │  │ 2. Insert recording                  │    │                   │
│   │  │ 3. Insert outbox_event(s)            │    │                   │
│   │  └─────────────────────────────────────┘    │                   │
│   └─────────────────────────────────────────────┘                   │
│       │                                                              │
│       ├──────────────────────────────────────────┐                  │
│       │                                          │                  │
│       ▼                                          ▼                  │
│   Phoenix.PubSub.broadcast              Outbox Worker (Oban)        │
│   (best-effort, immediate)              (guaranteed, async)         │
│       │                                          │                  │
│       ▼                                          ▼                  │
│   LiveView receives                      External Systems           │
│   {:recording_created, id}               (Kafka, webhooks, etc.)    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       RECOVERY PATH                                  │
│                                                                      │
│   Consumer reconnects                                                │
│       │                                                              │
│       ▼                                                              │
│   Query recordings table                                             │
│   (catch up on missed events)                                        │
│       │                                                              │
│       ▼                                                              │
│   Recordings = source of truth                                       │
│   (never loses data, supports replay)                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.7 When to Skip Outbox

For purely internal consumers (Phoenix LiveViews), you might simplify:

```elixir
def create_without_outbox(recordable_module, recordable_attrs, recording_attrs) do
  Multi.new()
  |> Multi.insert(:recordable, ...)
  |> Multi.insert(:recording, ...)
  |> Repo.transaction()
  |> case do
    {:ok, %{recording: recording}} ->
      # Broadcast after successful commit
      Phoenix.PubSub.broadcast(...)
      {:ok, recording}
    error -> error
  end
end
```

This works when:
- All consumers are internal (LiveViews)
- Consumers can query recordings on reconnect
- You don't need guaranteed delivery to external systems

---

## Phase 7: Buckets

### 7.1 Bucket Types

```elixir
create table(:buckets, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
  add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

  add :bucket_type, :string, null: false  # "mission", "shift", "anomaly", "target_group"
  add :bucketable_type, :string, null: false
  add :bucketable_id, :binary_id, null: false

  add :name, :string
  add :started_at, :utc_datetime_usec
  add :ended_at, :utc_datetime_usec
  add :metadata, :map, default: %{}

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:buckets, [:bucketable_type, :bucketable_id])
create index(:buckets, [:mission_id, :bucket_type])
create index(:buckets, [:organization_id, :bucket_type])
```

### 7.2 Shifts as Buckets

```elixir
create table(:shifts, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
  add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false

  add :name, :string  # "Alpha", "Bravo", "Day Shift"
  add :shift_type, :string  # "operational", "maintenance", "training"

  add :scheduled_start, :utc_datetime_usec, null: false
  add :scheduled_end, :utc_datetime_usec, null: false
  add :actual_start, :utc_datetime_usec
  add :actual_end, :utc_datetime_usec

  add :status, :string, default: "scheduled"  # "scheduled", "active", "completed", "cancelled"

  add :metadata, :map, default: %{}

  timestamps(type: :utc_datetime_usec)
end

# Shift becomes a bucket automatically via trigger or application code
```

### 7.3 Command Authority

```elixir
create table(:bucket_memberships, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :bucket_id, references(:buckets, type: :binary_id, on_delete: :delete_all), null: false
  add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

  add :role, :string, null: false  # "operator", "supervisor", "observer"

  # Command authority scoping
  add :can_command, :boolean, default: false
  add :target_group_ids, {:array, :binary_id}, default: []  # Empty = all targets
  add :max_hazard_level, :integer  # 0=emergency only, 5=all

  add :started_at, :utc_datetime_usec
  add :ended_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:bucket_memberships, [:bucket_id, :user_id],
  where: "ended_at IS NULL", name: :bucket_memberships_active_unique)
create index(:bucket_memberships, [:user_id, :bucket_id])
```

---

## Critical Files

**New files to create:**
- `lib/cadence/recordings/recording.ex`
- `lib/cadence/recordings/recordable.ex` (protocol)
- `lib/cadence/recordings/recordables/*.ex` (one per event type, ~30 files)
- `lib/cadence/recordings/aggregates/*.ex` (state derivation)
- `lib/cadence/recordings.ex` (context)
- `lib/cadence/buckets/bucket.ex`
- `lib/cadence/buckets/bucket_membership.ex`
- `lib/cadence/shifts/shift.ex`

**Files to modify (write paths):**
- `lib/cadence/commands/target_dispatcher.ex` - Use recordings instead of CommandLog (lines 824-859)
- `lib/cadence/commands/staging.ex` - Create CommandQueued recordings
- `lib/cadence/commands/target_queue.ex` - Create CommandDequeued recordings
- `lib/cadence/alarms.ex` - Use recordings instead of AlarmEvent inserts (lines 311-757)
- `lib/cadence/procedures/engine/execution_persistence.ex` - Create procedure recordings
- `lib/cadence/procedures/procedures.ex` - Create ProcedureVersion recordings for approval workflow
- `lib/cadence/automations/automations.ex` - Create automation recordings

**Files to modify (read paths):**
- `lib/cadence/timeline.ex` - Query recordings instead of command_logs/alarm_events
- `lib/cadence/timeline/event.ex` - Add from_recording/2 converter
- `lib/cadence_web/channels/execution_channel.ex` - Derive state from recordings

**Files to modify (event infrastructure):**
- `lib/cadence/outbox/event.ex` - Add recording_id, remove payload
- `lib/cadence/outbox.ex` - Update to reference recordings
- `lib/cadence/procedures/events/execution_event.ex` - Replace with recordings
- `lib/cadence/procedures/events/step_event.ex` - Replace with recordings

**Files to delete (replaced by recordings):**
- `lib/cadence/commands/command_log.ex`
- `lib/cadence/alarms/schemas/alarm_event.ex`
- `lib/cadence/procedures/schemas/procedure_version_event.ex`

---

## Migration Strategy

### Greenfield Approach (No Users, Droppable Database)

Since this is a greenfield project with no active users, we take the clean-slate approach:

#### Step 1: Identify Tables to Remove

**Delete these migrations/tables (replaced by recordings):**
- `command_logs` - history moves to recordings
- `alarm_events` - history moves to recordings

**Keep these as operational/projection tables:**
- `command_queue_entries` - active queue state (CommandQueued/CommandDequeued create recordings, but queue needs queryable current state)
- `procedure_executions` - current execution state (consider: keep as projection or derive from recordings?)
- `alarms` - projection for "show active alarms" (derived from recordings)

**Untouched (configuration/entities):**
- `organizations`, `missions`, `targets`, `users`
- `procedures`, `procedure_versions`, `procedure_steps`
- `interfaces`, `meta_commands`, `telemetry_points`
- `automation_rules`, etc.

#### Step 2: Clean Up Old Migrations

```bash
# Drop the database
mix ecto.drop

# DELETE - Tables replaced by recordings
rm priv/repo/migrations/20251126100000_create_command_logs.exs
rm priv/repo/migrations/20251128000003_create_alarm_events.exs
rm priv/repo/migrations/20251209000004_create_procedure_version_events.exs
rm priv/repo/migrations/20251215051529_add_verification_tracking_to_command_logs.exs

# MODIFY - Outbox needs to point to recordings instead of storing payload
# Edit 20251130000001_create_outbox_events.exs:
#   - Remove: add :payload, :map, default: %{}
#   - Add: add :recording_id, references(:recordings, type: :binary_id, on_delete: :delete_all)
#   - Add: add :topic, :string  (for routing)
#   - Keep: event_type, aggregate_type, aggregate_id, processing fields

# KEEP AS-IS - These work as projections/operational tables
# - 20251128000002_create_alarms.exs (projection, updated from recordings)
# - 20251202000003_create_procedure_executions.exs (projection)
# - 20251126200000_create_command_queue_entries.exs (operational queue state)
# - 20251202000004_create_procedure_logs.exs (debug logs, separate from recordings)
```

**Note on Missions:** The missions table does NOT need changes. The `buckets` table uses polymorphic association (`bucketable_type: "Mission", bucketable_id: <mission_id>`) to reference missions. When a mission is created, a corresponding bucket record is created.

#### Step 3: Create Recordings Infrastructure

Create a single comprehensive migration for the recordings system:

```bash
mix ecto.gen.migration create_recordings_infrastructure
```

This migration creates:
1. `recordings` table (the index)
2. All recordable tables (command_dispatcheds, alarm_triggereds, etc.)
3. `buckets` table
4. `bucket_memberships` table
5. `shifts` table
6. `outbox_events` table (simplified, points to recordings)

#### Step 4: Modify Retained Tables

Update existing tables to work with recordings:

```bash
mix ecto.gen.migration update_tables_for_recordings
```

- Add `bucket_id` to relevant tables if needed
- Remove redundant columns from projection tables
- Add any missing indexes

#### Step 5: Rebuild and Verify

```bash
mix ecto.create
mix ecto.migrate
mix test
```

### Table Decisions

| Table | Decision | Rationale |
|-------|----------|-----------|
| `command_logs` | **DELETE** | Replaced by CommandDispatched, CommandSent, CommandVerified, etc. recordings |
| `alarm_events` | **DELETE** | Replaced by AlarmTriggered, AlarmAcknowledged, AlarmCleared, etc. recordings |
| `procedure_version_events` | **DELETE** | Replaced by ProcedureVersionSubmitted, ProcedureApprovalAdded, etc. recordings |
| `alarms` | **KEEP as projection** | Fast queries for "active alarms"; updated after AlarmTriggered/AlarmCleared recordings |
| `command_queue_entries` | **KEEP as operational** | Need queryable queue state; recordings track history (CommandQueued/CommandDequeued) |
| `procedure_executions` | **KEEP as projection** | Complex state machine; easier to project than derive; recordings track history |
| `procedure_versions` | **KEEP as projection** | Approval workflow state; recordings track history |
| `procedure_approvals` | **KEEP as projection** | Query current approvals; ProcedureApprovalAdded recordings track history |
| `procedure_logs` | **KEEP as operational** | Debug-level logs during execution; too granular for recordings |
| `automation_executions` | **KEEP as projection** | Execution state; recordings track history |
| `outbox_events` | **MODIFY** | Remove `payload`, add `recording_id` reference; becomes thin notification layer |
| `missions` | **NO CHANGE** | Buckets table references missions via polymorphic association |

### Projection Update Strategy

For tables kept as projections, update them after recording creation:

```elixir
# In Recordings context, after successful transaction
def create(recordable_module, recordable_attrs, recording_attrs, opts \\ []) do
  # ... create recording ...
  |> Repo.transaction()
  |> case do
    {:ok, %{recording: recording} = result} ->
      # Update projections
      update_projections(recording)
      # Broadcast
      broadcast_locally(recording, topics)
      {:ok, result}
    error -> error
  end
end

defp update_projections(%Recording{aggregate_type: "Alarm"} = recording) do
  Cadence.Alarms.Projections.update_from_recording(recording)
end

defp update_projections(%Recording{aggregate_type: "Procedure"} = recording) do
  Cadence.Procedures.Projections.update_from_recording(recording)
end

defp update_projections(_), do: :ok
```

---

## Recordable Types Summary

| Aggregate | Event Types |
|-----------|-------------|
| **Command** | CommandDispatched, CommandSent, CommandVerified, CommandVerificationFailed, CommandRejected, CommandErrored |
| **Alarm** | AlarmTriggered, AlarmAcknowledged, AlarmCleared, AlarmShelved, AlarmUnshelved, AlarmEscalated, AlarmValueUpdated |
| **ProcedureExecution** | ProcedureStarted, ProcedureStepCompleted, ProcedureStepSkipped, ProcedurePaused, ProcedureResumed, ProcedureCompleted, ProcedureFailed, ProcedureCancelled |
| **ProcedureVersion** | ProcedureVersionCreated, ProcedureVersionSubmitted, ProcedureVersionWithdrawn, ProcedureApprovalAdded, ProcedureVersionApproved, ProcedureVersionRejected, ProcedureVersionDeprecated |
| **Automation** | AutomationTriggered, AutomationCompleted, AutomationFailed, AutomationSkipped |
| **QueueEntry** | CommandQueued, CommandDequeued |

---

## Testing Checklist

- [ ] Each recordable type has schema and protocol implementation
- [ ] Recordings are created atomically with recordables
- [ ] Aggregate state correctly derived from recordings
- [ ] Projections (alarms, procedure_executions) update correctly after recordings
- [ ] Timeline queries work with new structure
- [ ] Parent/root_id chains work for causality
- [ ] Bucket scoping works
- [ ] Outbox entries created and processed correctly
- [ ] PubSub broadcasts work for LiveView updates

---

## Implementation Patterns

### Batch Loading Recordables (Avoid N+1)

```elixir
def list_recordings_with_recordables(mission_id, cursor, opts) do
  # 1. Query recordings (1 query)
  recordings = list_recordings_before(mission_id, cursor, opts)

  # 2. Group by type
  by_type = Enum.group_by(recordings, & &1.recordable_type)

  # 3. Batch load each type (1 query per type present)
  recordables =
    Enum.flat_map(by_type, fn {type, recs} ->
      ids = Enum.map(recs, & &1.recordable_id)
      module = recordable_module(type)

      module
      |> where([r], r.id in ^ids)
      |> Repo.all()
      |> Enum.map(&{&1.id, &1})
    end)
    |> Map.new()

  # 4. Attach and use protocol for uniform access
  Enum.map(recordings, fn r ->
    recordable = Map.get(recordables, r.recordable_id)
    %{
      recording: r,
      recordable: recordable,
      title: Recordable.title(recordable),
      status: Recordable.status(recordable)
    }
  end)
end
```

### Cursor-Based Pagination

```elixir
def list_recordings_before(mission_id, cursor, opts) do
  limit = Keyword.get(opts, :limit, 50)

  query =
    Recording
    |> where([r], r.mission_id == ^mission_id)
    |> order_by([r], [desc: :timestamp, desc: :id])
    |> limit(^limit)

  query =
    if cursor do
      query
      |> where([r], r.timestamp < ^cursor.timestamp)
      |> or_where([r], r.timestamp == ^cursor.timestamp and r.id < ^cursor.id)
    else
      query
    end

  Repo.all(query)
end

# Cursor is: %{timestamp: last.timestamp, id: last.id}
```

### Projection Rebuild (If Out of Sync)

```elixir
def rebuild_alarm_projection(aggregate_id) do
  state = Recordings.Aggregates.Alarm.get_state(aggregate_id)

  %Alarm{id: aggregate_id}
  |> Alarm.projection_changeset(state)
  |> Repo.insert!(on_conflict: :replace_all, conflict_target: :id)
end
```

### Transaction Strategy

```elixir
# Recording + projection in same transaction (atomic)
Multi.new()
|> Recordings.append(:event, CommandDispatched, recordable_attrs, fn _ -> recording_attrs end)
|> Multi.run(:projection, fn _repo, %{event_recording: recording} ->
  # Update projection based on recording
  update_command_projection(recording)
end)
|> Repo.transaction()
```

---

## Questions to Consider

1. **Performance** - For high-frequency events (alarms with rapid value updates), do we need to batch or throttle recordings?

2. **Retention** - Different retention policies per recordable type? (e.g., keep CommandDispatched forever, prune AlarmValueUpdated after 90 days)

3. **Read optimization** - Do we need materialized views or CQRS-style projections for common queries? (Current plan: alarms and procedure_executions as projections)

4. **Bucket lifecycle** - How do shifts get created? Manual? Schedule-based? Auto-create on first command?

5. **Queue entries** - Should `command_queue_entries` remain a separate operational table, or become purely derived from CommandQueued/CommandDequeued recordings?
