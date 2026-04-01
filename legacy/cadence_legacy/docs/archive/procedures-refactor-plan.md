---
title: Procedures Refactoring Plan
tags: [design, procedures, refactor, implementation-plan, historical]
related:
  - "[[procedure]]"
  - "[[sequence]]"
  - "[[automation]]"
  - "[[procedures]]"
created: 2025-01-01
updated: 2026-01-29
status: superseded
---

# Procedures Feature Refactoring Plan

> [!NOTE]
> **STATUS: LARGELY SUPERSEDED**
>
> This document was written for the original procedure execution architecture.
> Much of this has been addressed by the **V2 Execution System** which uses a
> completely different architecture:
>
> - **Strategy-based execution** (`lib/cadence/procedures/v2/strategies/`)
> - **Unified persistence** (`lib/cadence/procedures/v2/execution_persistence.ex`)
> - **Step/Block execution tracking** (schemas in `lib/cadence/procedures/schemas/`)
>
> See the [Procedures Design Document](procedures.md) for current architecture.

This document outlines the plan to address architectural issues identified in the Procedures feature review.

## Issues Summary

| Issue | Status | Notes |
|-------|--------|-------|
| 1. OTP Supervision | ✅ RESOLVED | V2 has proper supervision |
| 2. Race Conditions | ✅ ADDRESSED | V2 strategy pattern eliminates Task.async pattern |
| 3. Transaction Boundaries | ✅ ADDRESSED | `execution_persistence.ex` uses transactions |
| 4. State Machine Gaps | ✅ RESOLVED | Full state machine in `procedure_execution.ex` |
| 5. Idempotency | ⚠️ PARTIALLY | Some recording-based idempotency, review needed |
| 6. Tight Coupling | ✅ ADDRESSED | V2 strategy pattern decouples execution |
| 7. Error Handling | ⚠️ ONGOING | Patterns documented, some inconsistencies remain |
| 8. Leaky Abstractions | ✅ ADDRESSED | `procedures_v2.ex` provides clean API |

## Original Issues (Historical Reference)

---

## Issue 2: Race Condition in Concurrent Step Execution

> **STATUS:** ✅ ADDRESSED by V2 architecture. The V2 system uses a strategy pattern
> (`lib/cadence/procedures/v2/execution_strategy.ex`) where execution is driven by
> explicit state transitions rather than Task.async, eliminating these race conditions.

### Problem (Original)
Control signals (pause/abort) are forwarded via `send(pid, {:control_signal, signal})` to the Task process running the DAG executor. The executor checks for signals via `check_control_signals/1` which does a non-blocking `receive after 0`. This creates several race windows:

1. A step might complete after a pause signal was sent but before the executor's next signal check
2. Multiple steps might start between signal send and signal processing
3. The 100ms timeout in `wait_for_step_completion/2` means up to 100ms delay in signal processing

### Current Flow
```
ExecutionProcess                    DAG Executor Task
     |                                    |
     |-- send(:pause) ------------------>|
     |                                    | (in middle of step)
     |                                    | step completes
     |                                    | starts next step  <- RACE
     |                                    | check_control_signals()
     |                                    | sees :pause
```

### Solution
Implement a proper cancellation token pattern using `:atomics` for lock-free signal propagation.

### Implementation Steps

#### Step 2.1: Create a CancellationToken module
Create `lib/cadence/procedures/dag/cancellation_token.ex`:

```elixir
defmodule Cadence.Procedures.Dag.CancellationToken do
  @moduledoc """
  Lock-free cancellation token for DAG execution control signals.

  Uses :atomics for thread-safe signal propagation without message passing delays.
  """

  # Signal values
  @none 0
  @pause 1
  @abort 2

  @type t :: %__MODULE__{ref: :atomics.atomics_ref()}

  defstruct [:ref]

  @doc "Creates a new cancellation token."
  @spec new() :: t()
  def new do
    %__MODULE__{ref: :atomics.new(1, signed: false)}
  end

  @doc "Requests pause. Returns :ok or :already_signaled."
  @spec request_pause(t()) :: :ok | :already_signaled
  def request_pause(%__MODULE__{ref: ref}) do
    case :atomics.compare_exchange(ref, 1, @none, @pause) do
      :ok -> :ok
      _ -> :already_signaled
    end
  end

  @doc "Requests abort. Always succeeds (abort overrides pause)."
  @spec request_abort(t()) :: :ok
  def request_abort(%__MODULE__{ref: ref}) do
    :atomics.put(ref, 1, @abort)
    :ok
  end

  @doc "Clears any signal (for resume)."
  @spec clear(t()) :: :ok
  def clear(%__MODULE__{ref: ref}) do
    :atomics.put(ref, 1, @none)
    :ok
  end

  @doc "Checks current signal state."
  @spec check(t()) :: :none | :pause | :abort
  def check(%__MODULE__{ref: ref}) do
    case :atomics.get(ref, 1) do
      @none -> :none
      @pause -> :pause
      @abort -> :abort
    end
  end

  @doc "Returns true if abort or pause is requested."
  @spec signaled?(t()) :: boolean()
  def signaled?(%__MODULE__{ref: ref}) do
    :atomics.get(ref, 1) != @none
  end
end
```

#### Step 2.2: Add token to ExecutionProcess State
In `lib/cadence/procedures/engine/execution_process.ex`:

```elixir
defmodule State do
  defstruct [
    # ... existing fields ...
    :cancellation_token  # NEW
  ]
end
```

#### Step 2.3: Create and use token in ExecutionProcess
Modify `init/1`:
```elixir
def init(opts) do
  # ... existing code ...
  cancellation_token = CancellationToken.new()

  state = %State{
    # ... existing fields ...
    cancellation_token: cancellation_token
  }
  # ...
end
```

Modify `handle_cast({:control_signal, signal}, state)`:
```elixir
def handle_cast({:control_signal, :pause}, state) do
  CancellationToken.request_pause(state.cancellation_token)
  # ... rest of existing logic ...
end

def handle_cast({:control_signal, :abort}, state) do
  CancellationToken.request_abort(state.cancellation_token)
  # ... rest of existing logic ...
end
```

#### Step 2.4: Pass token to DAG executor
```elixir
task = Task.async(fn ->
  Executor.execute(steps, step_executor, dag_context,
    Keyword.merge(opts, [cancellation_token: state.cancellation_token]))
end)
```

#### Step 2.5: Modify DAG Executor to check token atomically
In `lib/cadence/procedures/dag/executor.ex`:

Add to State struct:
```elixir
defstruct [
  # ... existing fields ...
  :cancellation_token
]
```

Replace `check_control_signals/1`:
```elixir
defp check_control_signals(%{cancellation_token: nil} = state) do
  # Fallback to message-based for backward compatibility
  receive do
    {:control_signal, signal} -> %{state | control_signal: signal}
  after
    0 -> state
  end
end

defp check_control_signals(%{cancellation_token: token} = state) do
  case CancellationToken.check(token) do
    :none -> state
    signal -> %{state | control_signal: signal}
  end
end
```

Add check BEFORE starting each step in `start_step/3`:
```elixir
defp start_step(state, step_name, on_status_change) do
  # Check for cancellation BEFORE starting
  if state.cancellation_token && CancellationToken.signaled?(state.cancellation_token) do
    state  # Don't start new steps if cancelled
  else
    # ... existing step start logic ...
  end
end
```

#### Step 2.6: Add tests
Create `test/cadence/procedures/dag/cancellation_token_test.exs`:
- Concurrent signal/check tests
- Abort overrides pause test
- Clear and re-signal test

---

## Issue 3: Missing Transaction Boundaries

> **STATUS:** ✅ ADDRESSED. The V2 system's `execution_persistence.ex` handles all
> persistence with proper transaction boundaries. Step/block execution records are
> created atomically with status updates.

### Problem (Original)
Several persistence operations lack proper transaction boundaries:

1. `persist_log/3` in ExecutionProcess (line 694-708) - no transaction
2. `persist_checkpoint/1` - no transaction
3. Status updates and log writes are separate operations

### Solution
Create a unified persistence module that wraps related operations in transactions.

### Implementation Steps

#### Step 3.1: Create ExecutionPersistence module
Create `lib/cadence/procedures/engine/execution_persistence.ex`:

```elixir
defmodule Cadence.Procedures.Engine.ExecutionPersistence do
  @moduledoc """
  Handles all database persistence for procedure executions.

  All public functions use transactions to ensure atomicity.
  """

  alias Cadence.Repo
  alias Cadence.Procedures
  alias Cadence.Procedures.ProcedureLog

  @doc """
  Updates execution status and creates a log entry atomically.
  """
  def update_status_with_log(execution, status_attrs, log_level, log_message) do
    Repo.transaction(fn ->
      case Procedures.update_execution_status(execution, status_attrs) do
        {:ok, updated} ->
          {:ok, _log} = create_log(updated.id, log_level, log_message)
          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Creates a log entry.
  """
  def create_log(execution_id, level, message, step_index \\ nil) do
    attrs = %{
      execution_id: execution_id,
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      step_index: step_index
    }

    %ProcedureLog{}
    |> ProcedureLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Saves checkpoint state atomically.
  """
  def save_checkpoint(execution, step_index, checkpoint_state \\ nil) do
    Repo.transaction(fn ->
      attrs = %{
        current_step_index: step_index,
        checkpoint_state: checkpoint_state
      }

      case Procedures.update_execution_status(execution, attrs) do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Persists step event with log entry atomically.
  Broadcasts AFTER transaction commits.
  """
  def persist_step_event(execution, step_name, status, data) do
    alias Cadence.Procedures.Events.StepEvent

    result = Repo.transaction(fn ->
      # Insert to outbox (source of truth)
      StepEvent.insert!(execution, step_name, status, data)

      # Insert log entry
      {level, message} = step_status_to_log(status, step_name, data)
      create_log(execution.id, level, message)

      {level, message}
    end)

    case result do
      {:ok, {level, message}} ->
        # Broadcast AFTER transaction commits
        topic = "procedure:#{execution.id}"
        event = dag_status_to_event(status, step_name, data)
        Phoenix.PubSub.broadcast(Cadence.PubSub, topic, event)
        Phoenix.PubSub.broadcast(Cadence.PubSub, topic, {:log, level, message})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp step_status_to_log(:running, step_name, _), do: {:info, "Step started: #{step_name}"}
  defp step_status_to_log(:completed, step_name, _), do: {:info, "Step completed: #{step_name}"}
  defp step_status_to_log(:failed, step_name, data) do
    reason = if is_map(data), do: Map.get(data, :error, inspect(data)), else: inspect(data)
    {:error, "Step failed: #{step_name} - #{reason}"}
  end
  defp step_status_to_log(:blocked, step_name, _), do: {:warn, "Step blocked: #{step_name}"}
  defp step_status_to_log(:skipped, step_name, _), do: {:info, "Step skipped: #{step_name}"}
  defp step_status_to_log(status, step_name, _), do: {:info, "Step #{status}: #{step_name}"}

  defp dag_status_to_event(:running, step_name, data), do: {:dag_step_started, step_name, data}
  defp dag_status_to_event(:completed, step_name, data), do: {:dag_step_completed, step_name, data}
  defp dag_status_to_event(:failed, step_name, data), do: {:dag_step_failed, step_name, data}
  defp dag_status_to_event(:blocked, step_name, data), do: {:dag_step_blocked, step_name, data}
  defp dag_status_to_event(:skipped, step_name, data), do: {:dag_step_skipped, step_name, data}
  defp dag_status_to_event(status, step_name, data), do: {:dag_step_status, step_name, status, data}
end
```

#### Step 3.2: Update ExecutionProcess to use new module
Replace direct `Repo.insert()` calls in `persist_log/3` and `persist_checkpoint/1`.

#### Step 3.3: Update on_status_change callback in execute_dag_sequence
Replace the inline transaction in `execute_dag_sequence/2` with:
```elixir
on_status_change = fn step_name, status, data ->
  ExecutionPersistence.persist_step_event(execution, step_name, status, data)
end
```

---

## Issue 4: State Machine Validation Gaps

> **STATUS:** ✅ RESOLVED. The state machine has been fully implemented in
> `lib/cadence/procedures/schemas/procedure_execution.ex` with the exact diagram
> shown below, including the `pausing` intermediate state and field validations.

### Problem (Original)
Current state transitions in `ProcedureExecution`:
- `running -> paused` is allowed but should require going through `pausing` first
- Missing documentation of state machine
- No validation of required fields per transition

### Solution
1. Fix transition rules
2. Add state machine diagram documentation
3. Add transition-specific field validations

### Implementation Steps

#### Step 4.1: Update valid_transition?/2
In `lib/cadence/procedures/schemas/procedure_execution.ex`:

```elixir
defp valid_transition?(from, to) do
  valid_transitions = %{
    pending: [:running, :cancelled],
    running: [:pausing, :completed, :failed, :cancelled],  # Remove direct :paused
    pausing: [:paused, :running, :failed, :cancelled],     # Add :running for cancel-pause
    paused: [:running, :cancelled],
    completed: [],
    failed: [],
    cancelled: []
  }

  to in Map.get(valid_transitions, from, [])
end
```

#### Step 4.2: Add state machine documentation
Add to module doc:

```elixir
@moduledoc """
...

## State Machine

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
    │pausing│    │        │        │
    └───┬───┘    │        │        │
        │        │        │        │
        │done    │        │        │
        ▼        ▼        ▼        ▼
    ┌──────┐ ┌─────────┐ ┌──────┐ ┌─────────┐
    │paused│ │completed│ │failed│ │cancelled│
    └──┬───┘ └─────────┘ └──────┘ └─────────┘
       │
       │resume
       ▼
    (back to running)
```
"""
```

#### Step 4.3: Add changeset validations for required fields per transition
```elixir
def status_changeset(execution, attrs) do
  execution
  |> cast(attrs, [...])
  |> validate_status_transition()
  |> validate_transition_requirements()  # NEW
end

defp validate_transition_requirements(changeset) do
  new_status = get_change(changeset, :status)

  case new_status do
    :running ->
      # started_at should be set when transitioning to running
      if is_nil(get_field(changeset, :started_at)) and is_nil(get_change(changeset, :started_at)) do
        add_error(changeset, :started_at, "must be set when starting execution")
      else
        changeset
      end

    :completed ->
      validate_required(changeset, [:completed_at])

    :failed ->
      # error_message should be provided for failures
      if is_nil(get_change(changeset, :error_message)) do
        add_error(changeset, :error_message, "should be provided for failed status")
      else
        changeset
      end

    _ ->
      changeset
  end
end
```

---

## Issue 5: No Idempotency for Resume Operations

### Problem
In `ExecutionCoordinator.maybe_copy_step_events/2`:
```elixir
Enum.each(completed_events, fn event ->
  StepEvent.insert!(new_execution, step_name, :completed, data)
end)
```

If resume fails mid-copy and is retried, events are duplicated.

### Solution
Add idempotency keys to step events and use upsert semantics.

### Implementation Steps

#### Step 5.1: Add idempotency_key to outbox_events table
Create migration:
```elixir
defmodule Cadence.Repo.Migrations.AddIdempotencyKeyToOutboxEvents do
  use Ecto.Migration

  def change do
    alter table(:outbox_events) do
      add :idempotency_key, :string
    end

    create unique_index(:outbox_events, [:idempotency_key],
      where: "idempotency_key IS NOT NULL",
      name: :outbox_events_idempotency_key_index)
  end
end
```

#### Step 5.2: Update OutboxEvent schema
```elixir
schema "outbox_events" do
  # ... existing fields ...
  field :idempotency_key, :string
end
```

#### Step 5.3: Update StepEvent.insert! to support idempotency
```elixir
def insert!(execution, step_name, status, data, opts \\ []) do
  idempotency_key = opts[:idempotency_key]

  attrs = %{
    # ... existing attrs ...
    idempotency_key: idempotency_key
  }

  %OutboxEvent{}
  |> changeset(attrs)
  |> Repo.insert!(
    on_conflict: :nothing,
    conflict_target: [:idempotency_key]
  )
end
```

#### Step 5.4: Update resume copy to use idempotency keys
In `ExecutionCoordinator.maybe_copy_step_events/2`:
```elixir
defp maybe_copy_step_events(new_execution, resume_from_execution_id) do
  events = StepEvent.list_for_execution(resume_from_execution_id)

  completed_events = Enum.filter(events, &(&1.event_type == "procedure_step_completed"))

  Enum.each(completed_events, fn event ->
    step_name = event.payload["step_name"]
    data = event.payload["data"]
    # Deterministic key ensures idempotency on retry
    idempotency_key = "resume:#{new_execution.id}:#{step_name}:completed"

    StepEvent.insert!(new_execution, step_name, :completed, data,
      idempotency_key: idempotency_key)
  end)

  :ok
end
```

---

## Issue 6: Tight Coupling Between DAG Executor and GenServer

### Problem
The `ExecutionProcess` GenServer spawns a `Task.async` for DAG execution:
1. Must handle Task completion, :DOWN messages, and control signal forwarding
2. Testing the executor requires mocking the GenServer environment
3. Complex interaction patterns between process types

### Assessment
**This is a larger refactor.** The current design works and the complexity is manageable. Consider deferring this to a v2 iteration after the more critical issues are resolved.

### Alternative: Incremental Improvements

Instead of a full refactor, apply these targeted improvements:

#### Step 6.1: Document the interaction pattern
Add comprehensive module docs explaining the ExecutionProcess <-> DAG Executor relationship.

#### Step 6.2: Extract message handling into helper functions
```elixir
# Instead of inline pattern matching in handle_info
defp handle_dag_task_result({:ok, dag_result}, state), do: handle_dag_completion(state, dag_result)
defp handle_dag_task_result({:error, {:validation_failed, reasons}}, state), do: ...
defp handle_dag_task_result({:error, {:steps_failed, dag_result}}, state), do: ...
defp handle_dag_task_result({:error, :aborted}, state), do: handle_abort(state)
defp handle_dag_task_result({:paused, dag_result}, state), do: handle_dag_pause(state, dag_result)
```

#### Step 6.3: Add integration tests
Create tests that exercise the full ExecutionProcess + Executor interaction.

---

## Issue 7: Inconsistent Error Handling Patterns

### Problem
The codebase mixes:
- `{:ok, _} / {:error, _}` tuples (Elixir convention)
- Exceptions (`raise`, `throw`)
- Bang functions (`insert!`)

### Solution
Standardize patterns and document guidelines.

### Implementation Steps

#### Step 7.1: Create error handling guidelines
Add `docs/design/error-handling.md`:

```markdown
# Error Handling Guidelines

## Principles

1. **Business logic errors** use `{:ok, result} | {:error, reason}` tuples
2. **Programmer errors** (bugs) may raise exceptions
3. **Control flow** never uses exceptions

## When to use each pattern

### Tuple returns `{:ok, _} | {:error, _}`
- Database operations that might fail (validation, conflicts)
- External service calls
- Anything the caller might want to handle differently

### Bang functions (raise on error)
- Internal consistency checks (should never fail in production)
- Cases where failure means a bug, not a recoverable error
- Must be documented with `@doc` noting the exception

### Never use
- `throw` for control flow
- Bare `raise` without a specific exception type
```

#### Step 7.2: Replace throw-based control flow in CadenceApi
In `lib/cadence/procedures/runtime/cadence_api.ex`:

```elixir
# Before
defp flow_abort(context, message) do
  send(context.execution_pid, {:abort_requested, message})
  throw({:procedure_abort, message})
end

# After
defp flow_abort(context, message) do
  send(context.execution_pid, {:abort_requested, message})
  # The abort signal will be processed by the execution process
  # Return a marker that Lua code can check if needed
  :aborted
end
```

Update the script executor to handle abort without catching throws:
```elixir
defp execute_script(state, %{"code" => code}) do
  # ... existing setup ...

  case :luerl.do(code, state.lua_state) do
    {:ok, _result, new_lua_state} ->
      # Check for abort signal after execution
      if state.control_signal == :abort do
        handle_abort(state)
      else
        # ... normal completion ...
      end

    {:error, reason, _lua_state} ->
      handle_failure(state, 0, reason)
  end
end
```

#### Step 7.3: Add non-bang versions where needed
```elixir
# In StepEvent module, add alongside existing insert!
def insert(execution, step_name, status, data, opts \\ []) do
  # ... same logic but returns {:ok, event} | {:error, changeset}
end
```

---

## Issue 8: Leaky Abstractions in LiveView

### Problem
LiveViews directly query GenServer registries and handle nil cases:

```elixir
defp get_execution_counts(mission_id) do
  case ExecutionCoordinator.whereis(mission_id) do
    nil -> %{running: 0, paused: 0, pending: 0}
    _pid -> ExecutionCoordinator.get_counts(mission_id)
  end
end
```

### Solution
Create a context module that provides a clean API.

### Implementation Steps

#### Step 8.1: Create Procedures.Runtime context module
Create `lib/cadence/procedures/runtime.ex`:

```elixir
defmodule Cadence.Procedures.Runtime do
  @moduledoc """
  Runtime operations for procedure executions.

  Provides a clean API for interacting with running executions,
  abstracting away process management details.
  """

  alias Cadence.Procedures.Engine.ExecutionCoordinator

  @doc """
  Gets execution counts for a mission.
  Returns counts even if no coordinator is running (all zeros).
  """
  @spec get_execution_counts(String.t()) :: %{running: integer(), paused: integer(), pending: integer()}
  def get_execution_counts(mission_id) do
    case coordinator_pid(mission_id) do
      nil -> %{running: 0, paused: 0, pending: 0}
      _pid -> ExecutionCoordinator.get_counts(mission_id)
    end
  end

  @doc """
  Lists active executions for a mission.
  """
  @spec list_active_executions(String.t()) :: [ProcedureExecution.t()]
  def list_active_executions(mission_id) do
    case coordinator_pid(mission_id) do
      nil -> []
      _pid -> ExecutionCoordinator.list_active(mission_id)
    end
  end

  @doc """
  Starts a new procedure execution.
  Returns error if coordinator is not available (mission not started).
  """
  @spec start_execution(String.t(), String.t(), keyword()) ::
          {:ok, ProcedureExecution.t()} | {:error, term()}
  def start_execution(mission_id, procedure_id, opts \\ []) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.start_execution(mission_id, procedure_id, opts)
    end
  end

  @doc "Pauses an execution."
  @spec pause_execution(String.t(), String.t()) :: :ok | {:error, term()}
  def pause_execution(mission_id, execution_id) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.pause(mission_id, execution_id)
    end
  end

  @doc "Resumes a paused execution."
  @spec resume_execution(String.t(), String.t()) :: :ok | {:error, term()}
  def resume_execution(mission_id, execution_id) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.resume(mission_id, execution_id)
    end
  end

  @doc "Aborts an execution."
  @spec abort_execution(String.t(), String.t()) :: :ok | {:error, term()}
  def abort_execution(mission_id, execution_id) do
    case coordinator_pid(mission_id) do
      nil -> {:error, :mission_not_running}
      _pid -> ExecutionCoordinator.abort(mission_id, execution_id)
    end
  end

  defp coordinator_pid(mission_id) do
    ExecutionCoordinator.whereis(mission_id)
  end
end
```

#### Step 8.2: Update LiveViews to use new module
In `lib/cadence_web/live/mission_live/procedures.ex`:

```elixir
alias Cadence.Procedures.Runtime

# Replace:
defp get_execution_counts(mission_id) do
  case ExecutionCoordinator.whereis(mission_id) do
    nil -> %{running: 0, paused: 0, pending: 0}
    _pid -> ExecutionCoordinator.get_counts(mission_id)
  end
end

# With:
defp get_execution_counts(mission_id) do
  Runtime.get_execution_counts(mission_id)
end

# Similarly for get_active_executions:
defp get_active_executions(mission_id) do
  Runtime.list_active_executions(mission_id)
end
```

#### Step 8.3: Update event handlers
```elixir
def handle_event("pause_execution", %{"id" => execution_id}, socket) do
  mission = socket.assigns.mission

  case Runtime.pause_execution(mission.id, execution_id) do
    :ok ->
      {:noreply, put_flash(socket, :info, "Execution paused")}

    {:error, :mission_not_running} ->
      {:noreply, put_flash(socket, :error, "Mission is not currently active")}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
  end
end
```

---

## Implementation Order

Recommended order based on impact and dependencies:

| Priority | Issue | Effort | Risk |
|----------|-------|--------|------|
| 1 | Issue 8: Leaky Abstractions | Low | Low |
| 2 | Issue 4: State Machine Gaps | Low | Low |
| 3 | Issue 7: Error Handling | Medium | Low |
| 4 | Issue 3: Transaction Boundaries | Medium | Medium |
| 5 | Issue 5: Idempotency | Medium | Medium (migration) |
| 6 | Issue 2: Race Conditions | Higher | Medium |
| 7 | Issue 6: Tight Coupling | Highest | Consider deferring |

---

## Testing Strategy

For each issue:

1. **Before fixing**: Write a test that demonstrates the problem (if possible)
2. **After fixing**: Ensure test passes
3. **Regression**: Add to CI

### Key Test Scenarios

**Race condition (Issue 2):**
- Concurrent pause signal during step execution
- Abort overrides pause
- No new steps start after signal received

**Transaction boundaries (Issue 3):**
- Failure mid-update rolls back completely
- Log + status update are atomic

**Idempotency (Issue 5):**
- Duplicate resume operations are safe
- Same idempotency key doesn't create duplicates

**State machine (Issue 4):**
- Invalid transitions are rejected with clear errors
- Required fields validated per transition

---

## Rollback Plan

Each change should be:
1. Behind a feature flag if behavioral change
2. Backward compatible for data changes
3. Deployable independently

### Migration strategy for Issue 5 (idempotency):
1. Deploy code that writes idempotency keys (optional field)
2. Backfill existing data if needed
3. Add unique constraint
4. Enable upsert behavior

---

## Success Criteria

- [ ] Race conditions eliminated via atomic cancellation token
- [ ] All persistence operations in transactions
- [ ] State machine transitions fully documented and validated
- [ ] Resume operations are idempotent
- [ ] LiveViews use clean Runtime API
- [ ] Error handling patterns documented and consistent
- [ ] All changes have test coverage
