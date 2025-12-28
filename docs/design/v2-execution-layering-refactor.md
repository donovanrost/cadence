# V2 Procedure Execution - Layering Refactor Plan

## Problem Statement

The current V2 procedure execution architecture has several layering violations:

1. **LiveView → GenServer**: Web layer directly calls `ExecutionProcess` methods
2. **Runtime → Database**: `ExecutionProcess` and `Executor` make direct `Repo` calls
3. **No clear boundaries**: Business logic, persistence, and runtime state are intertwined

This creates:
- Tight coupling between layers
- Difficulty testing components in isolation
- Risk of inconsistent state (broadcasts before commits)
- No single point for authorization/validation

## Target Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              WEB LAYER                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  LiveView (execution_show.ex)                                         │  │
│  │  - Renders UI                                                         │  │
│  │  - Handles user events                                                │  │
│  │  - Subscribes to PubSub                                               │  │
│  │  - Calls ONLY V2 Context                                              │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                           CONTEXT LAYER (Boundary)                          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  V2 Context (procedures_v2.ex)                                        │  │
│  │  - Public API for all V2 operations                                   │  │
│  │  - Authorization checks                                               │  │
│  │  - Input validation                                                   │  │
│  │  - Coordinates between persistence and runtime                        │  │
│  │  - Returns consistent response types                                  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
┌───────────────────────────────────┐  ┌───────────────────────────────────┐
│        RUNTIME LAYER              │  │      PERSISTENCE LAYER            │
│  ┌─────────────────────────────┐  │  │  ┌─────────────────────────────┐  │
│  │  ExecutionProcess           │  │  │  │  ExecutionPersistence       │  │
│  │  (GenServer)                │  │  │  │                             │  │
│  │  - In-memory execution state│  │  │  │  - All Repo operations      │  │
│  │  - Step/block lifecycle     │  │  │  │  - Transaction management   │  │
│  │  - Control signals          │  │  │  │  - Ecto.Multi for atomicity │  │
│  │  - Automation coordination  │  │  │  │  - Outbox event creation    │  │
│  │  - NO direct Repo calls     │  │  │  │  - Broadcast after commit   │  │
│  └─────────────────────────────┘  │  │  └─────────────────────────────┘  │
│                                   │  │                                   │
│  ┌─────────────────────────────┐  │  │  ┌─────────────────────────────┐  │
│  │  AutomationRunner           │  │  │  │  ExecutionQueries           │  │
│  │  - Block execution          │  │  │  │  - Read-only queries        │  │
│  │  - Already well-separated   │  │  │  │  - Preload helpers          │  │
│  └─────────────────────────────┘  │  │  │  - List/filter operations   │  │
│                                   │  │  └─────────────────────────────┘  │
└───────────────────────────────────┘  └───────────────────────────────────┘
                    │                               │
                    └───────────────┬───────────────┘
                                    ▼
                    ┌───────────────────────────────┐
                    │         DATABASE              │
                    │  ┌─────────────────────────┐  │
                    │  │  Ecto Repo              │  │
                    │  └─────────────────────────┘  │
                    └───────────────────────────────┘
```

## Refactoring Phases

### Phase 1: Create Persistence Layer

**Goal**: Extract all database operations from `ExecutionProcess` and `Executor` into a dedicated persistence module.

#### 1.1 Create `ExecutionPersistenceV2` Module

**File**: `lib/cadence/procedures/v2/execution_persistence.ex`

```elixir
defmodule Cadence.Procedures.V2.ExecutionPersistence do
  @moduledoc """
  Persistence operations for V2 procedure executions.

  All database writes go through this module, ensuring:
  - Atomic transactions via Ecto.Multi
  - Consistent broadcast-after-commit pattern
  - Outbox event creation for reliable delivery
  """

  alias Ecto.Multi
  alias Cadence.Repo
  alias Cadence.Procedures.{
    ProcedureExecution,
    StepExecution,
    BlockExecution,
    StepSignoff
  }

  # ── Execution Lifecycle ─────────────────────────────────────────────

  @doc """
  Creates a new execution with all step and block executions.
  Returns {:ok, execution} or {:error, reason}.
  Broadcasts :execution_started after commit.
  """
  def create_execution(procedure_version, params, opts) do
    Multi.new()
    |> Multi.insert(:execution, build_execution_changeset(procedure_version, params, opts))
    |> Multi.run(:step_executions, &create_step_executions/2)
    |> Multi.run(:block_executions, &create_block_executions/2)
    |> Repo.transaction()
    |> handle_result(:execution_started)
  end

  @doc """
  Updates execution status atomically.
  """
  def update_execution_status(execution, status, opts \\ []) do
    Multi.new()
    |> Multi.update(:execution, build_status_changeset(execution, status, opts))
    |> maybe_add_outbox_event(status)
    |> Repo.transaction()
    |> handle_result({:execution_status_changed, status})
  end

  # ── Step Operations ─────────────────────────────────────────────────

  @doc """
  Activates a step. Returns {:ok, step_execution} after commit.
  """
  def activate_step(step_execution) do
    Multi.new()
    |> Multi.update(:step, build_activation_changeset(step_execution))
    |> Repo.transaction()
    |> handle_result(:step_activated)
  end

  @doc """
  Completes a step. Returns {:ok, step_execution} after commit.
  """
  def complete_step(step_execution) do
    Multi.new()
    |> Multi.update(:step, build_completion_changeset(step_execution))
    |> Repo.transaction()
    |> handle_result(:step_completed)
  end

  @doc """
  Skips a step with reason. Returns {:ok, step_execution} after commit.
  """
  def skip_step(step_execution, reason) do
    Multi.new()
    |> Multi.update(:step, build_skip_changeset(step_execution, reason))
    |> Repo.transaction()
    |> handle_result(:step_skipped)
  end

  # ── Block Operations ────────────────────────────────────────────────

  @doc """
  Updates a block execution value.
  """
  def update_block_value(block_execution, value) do
    Multi.new()
    |> Multi.update(:block, build_value_changeset(block_execution, value))
    |> Repo.transaction()
    |> handle_result(:block_updated)
  end

  @doc """
  Updates a block execution result (for automated blocks).
  """
  def update_block_result(block_execution, result) do
    Multi.new()
    |> Multi.update(:block, build_result_changeset(block_execution, result))
    |> Repo.transaction()
    |> handle_result(:block_updated)
  end

  # ── Signoff Operations ──────────────────────────────────────────────

  @doc """
  Creates a signoff for a step.
  """
  def create_signoff(step_execution, user_id, role, note) do
    Multi.new()
    |> Multi.insert(:signoff, build_signoff_changeset(step_execution, user_id, role, note))
    |> Repo.transaction()
    |> handle_result(:signoff_added)
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp handle_result({:ok, changes}, event_type) do
    # Broadcast AFTER transaction commits
    broadcast_event(changes, event_type)
    {:ok, extract_primary_result(changes)}
  end

  defp handle_result({:error, _step, reason, _changes}, _event_type) do
    {:error, reason}
  end

  defp broadcast_event(changes, event_type) do
    # Implementation: broadcast via PubSub
  end
end
```

#### 1.2 Create `ExecutionQueries` Module

**File**: `lib/cadence/procedures/v2/execution_queries.ex`

```elixir
defmodule Cadence.Procedures.V2.ExecutionQueries do
  @moduledoc """
  Read-only queries for V2 procedure executions.
  """

  import Ecto.Query
  alias Cadence.Repo

  @doc """
  Gets an execution with all associations for display.
  """
  def get_execution_with_details(execution_id) do
    # Query implementation
  end

  @doc """
  Gets a step execution with block executions.
  """
  def get_step_execution(step_execution_id) do
    # Query implementation
  end

  @doc """
  Gets a block execution by step and block ID.
  """
  def get_block_execution(step_execution_id, block_id) do
    # Query implementation
  end

  @doc """
  Lists step executions for an execution.
  """
  def list_step_executions(execution_id, opts \\ []) do
    # Query implementation
  end
end
```

### Phase 2: Refactor ExecutionProcess

**Goal**: Remove all direct Repo calls, delegate to persistence layer.

#### 2.1 Update ExecutionProcess to Use Persistence

**Current** (problematic):
```elixir
defp do_submit_input(step_id, block_id, value, state) do
  with {:ok, block_exec} <- get_block_execution(step_id, block_id) do
    {:ok, block_exec} =
      block_exec
      |> Ecto.Changeset.change(value: value, status: :completed)
      |> Repo.update()  # DIRECT REPO CALL

    broadcast(state, {:block_updated, block_exec})
    {:ok, state}
  end
end
```

**Refactored**:
```elixir
defp do_submit_input(step_id, block_id, value, state) do
  with {:ok, block_exec} <- ExecutionQueries.get_block_execution(step_id, block_id),
       {:ok, updated} <- ExecutionPersistence.update_block_value(block_exec, value) do
    # Broadcast happens inside persistence layer after commit
    {:ok, %{state | execution: reload_execution(state.execution.id)}}
  end
end
```

#### 2.2 ExecutionProcess State Management

The GenServer should focus ONLY on:
- Tracking in-memory execution state
- Coordinating step/block lifecycle
- Managing control signals (pause/resume/abort)
- Spawning AutomationRunner tasks
- Checking dependencies

### Phase 3: Expand V2 Context as Boundary

**Goal**: Make `procedures_v2.ex` the single entry point from web layer.

#### 3.1 Add Execution Operations to V2 Context

**File**: `lib/cadence/procedures/procedures_v2.ex` (expand existing)

```elixir
defmodule Cadence.Procedures.V2 do
  # ... existing code ...

  # ════════════════════════════════════════════════════════════════════
  # Execution Operations (NEW - boundary for LiveView)
  # ════════════════════════════════════════════════════════════════════

  @doc """
  Submits an input value for a block during execution.

  ## Authorization
  User must have :execute_procedure permission on the mission.

  ## Returns
  - {:ok, block_execution} on success
  - {:error, :not_found} if execution/step/block not found
  - {:error, :not_active} if step is not active
  - {:error, :unauthorized} if user lacks permission
  """
  def submit_input(execution_id, step_id, block_id, value, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :execute_procedure, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.submit_input(pid, step_id, block_id, value)
    end
  end

  @doc """
  Signs off a step in an execution.
  """
  def sign_off_step(execution_id, step_id, role, note, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :sign_off_step, execution, role),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.sign_off(pid, step_id, role, note)
    end
  end

  @doc """
  Marks a step as complete.
  """
  def complete_step(execution_id, step_id, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :execute_procedure, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.complete_step(pid, step_id)
    end
  end

  @doc """
  Skips a step with a reason.
  """
  def skip_step(execution_id, step_id, reason, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :execute_procedure, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.skip_step(pid, step_id, reason)
    end
  end

  @doc """
  Pauses an execution.
  """
  def pause_execution(execution_id, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :control_execution, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.pause(pid)
    end
  end

  @doc """
  Resumes a paused execution.
  """
  def resume_execution(execution_id, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :control_execution, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.resume(pid)
    end
  end

  @doc """
  Aborts an execution.
  """
  def abort_execution(execution_id, reason, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :control_execution, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.abort(pid, reason)
    end
  end

  @doc """
  Executes a command block manually.
  """
  def execute_block(execution_id, step_id, block_id, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :execute_procedure, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.execute_block(pid, step_id, block_id)
    end
  end

  @doc """
  Retries a failed block.
  """
  def retry_block(execution_id, step_id, block_id, user) do
    with {:ok, execution} <- get_execution(execution_id),
         :ok <- authorize(user, :execute_procedure, execution),
         {:ok, pid} <- get_or_start_process(execution) do
      ExecutionProcess.retry_block(pid, step_id, block_id)
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp get_execution(execution_id) do
    case ExecutionQueries.get_execution_with_details(execution_id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  defp get_or_start_process(execution) do
    case ExecutionProcess.whereis(execution.id) do
      nil -> ExecutionProcess.start_or_attach(execution.id)
      pid -> {:ok, pid}
    end
  end

  defp authorize(user, action, execution, opts \\ []) do
    # Delegate to policy module
    case Bodyguard.permit(Cadence.Procedures.Policy, action, user, execution, opts) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end
end
```

### Phase 4: Update LiveView to Use Context

**Goal**: LiveView only calls V2 context, never ExecutionProcess directly.

#### 4.1 Refactor execution_show.ex

**Current** (problematic):
```elixir
def handle_event("submit_input", %{"step_id" => step_id, "block_id" => block_id, "value" => value}, socket) do
  case socket.assigns.execution_process do
    nil ->
      {:noreply, put_flash(socket, :error, "No execution process")}

    pid ->
      case ExecutionProcess.submit_input(pid, step_id, block_id, value) do
        :ok -> {:noreply, socket}
        {:error, reason} -> {:noreply, put_flash(socket, :error, inspect(reason))}
      end
  end
end
```

**Refactored**:
```elixir
def handle_event("submit_input", %{"step_id" => step_id, "block_id" => block_id, "value" => value}, socket) do
  execution_id = socket.assigns.execution.id
  user = socket.assigns.current_scope.user

  case V2.submit_input(execution_id, step_id, block_id, value, user) do
    {:ok, _block_exec} ->
      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "You don't have permission to do this")}

    {:error, :not_active} ->
      {:noreply, put_flash(socket, :error, "This step is not active")}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
  end
end
```

#### 4.2 Remove execution_process from Socket Assigns

The LiveView no longer needs to track the GenServer PID. The context handles process management internally.

```elixir
# REMOVE this from mount:
execution_process = ExecutionProcess.start_or_attach(execution_id, user_id: user_id)

# Context handles it internally when needed
```

### Phase 5: Add Policy Module

**Goal**: Centralize authorization logic.

**File**: `lib/cadence/procedures/policy.ex`

```elixir
defmodule Cadence.Procedures.Policy do
  @behaviour Bodyguard.Policy

  alias Cadence.Procedures.ProcedureExecution

  # Execute procedure actions (submit input, complete step, etc.)
  def authorize(:execute_procedure, user, %ProcedureExecution{} = execution) do
    # Check user has execute permission on this mission
    Cadence.Missions.Policy.authorize(:send_command, user, execution.mission_id)
  end

  # Sign off requires specific role
  def authorize(:sign_off_step, user, %ProcedureExecution{} = execution, role: role) do
    with :ok <- authorize(:execute_procedure, user, execution) do
      # Verify user can sign off with this role
      verify_signoff_role(user, role)
    end
  end

  # Control execution (pause/resume/abort)
  def authorize(:control_execution, user, %ProcedureExecution{} = execution) do
    # May require elevated permissions
    Cadence.Missions.Policy.authorize(:control_procedure, user, execution.mission_id)
  end

  defp verify_signoff_role(user, role) do
    # Implementation based on user roles
  end
end
```

## Migration Strategy

### Step 1: Create New Modules (Non-Breaking)
1. Create `ExecutionPersistence` module
2. Create `ExecutionQueries` module
3. Add new functions to V2 context
4. Create Policy module

### Step 2: Parallel Implementation
1. Add new context functions that use new persistence layer
2. Keep existing ExecutionProcess working
3. Write tests for new path

### Step 3: Migrate LiveView (One Handler at a Time)
1. Update one `handle_event` to use V2 context
2. Test thoroughly
3. Repeat for each handler

### Step 4: Remove Dead Code
1. Remove direct Repo calls from ExecutionProcess
2. Remove `execution_process` from socket assigns
3. Remove unused functions

## Testing Strategy

### Unit Tests

```elixir
# Test persistence layer in isolation
defmodule Cadence.Procedures.V2.ExecutionPersistenceTest do
  test "create_execution/3 creates execution with steps and blocks" do
    # Test database operations
  end

  test "create_execution/3 broadcasts after commit" do
    # Verify broadcast timing
  end
end

# Test context layer with mocked persistence
defmodule Cadence.Procedures.V2Test do
  test "submit_input/5 authorizes user" do
    # Test authorization
  end

  test "submit_input/5 returns error for inactive step" do
    # Test business logic
  end
end
```

### Integration Tests

```elixir
# Test full flow through LiveView
defmodule CadenceWeb.ProcedureV2Live.ExecutionShowTest do
  test "submitting input updates block value" do
    # Test with real LiveView
  end
end
```

## Success Criteria

1. **No direct Repo calls** in `ExecutionProcess` or `Executor`
2. **No direct ExecutionProcess calls** in LiveView
3. **All authorization** happens in context layer
4. **Broadcasts only after commits** succeed
5. **Full test coverage** of each layer independently
6. **No regression** in existing functionality

## Timeline Estimate

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| Phase 1: Persistence Layer | Medium | None |
| Phase 2: Refactor ExecutionProcess | Medium | Phase 1 |
| Phase 3: Expand V2 Context | Small | Phase 1 |
| Phase 4: Update LiveView | Medium | Phase 3 |
| Phase 5: Policy Module | Small | None |

Phases 1, 3, and 5 can be done in parallel.
