---
title: Procedures Testing Plan
tags: [design, procedures, testing]
related:
  - "[[procedure]]"
  - "[[sequence]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Procedures Feature Testing Plan

## Overview

This document outlines the plan to comprehensively test the Procedures feature. The current test coverage is ~27% (1,900 lines of tests for 7,000 lines of implementation), with critical gaps in the runtime execution engine.

## Current State

### Well Tested (Keep as-is)
- `dag/validator_test.exs` - DAG structure validation
- `dag/executor_test.exs` - DAG execution logic with mock executors
- `dag/step_executor_test.exs` - Individual step type execution
- `dag/cancellation_token_test.exs` - Atomic signal handling
- `parameters_test.exs` - Parameter schema validation
- `input_references_test.exs` - Input reference parsing/interpolation
- `procedures_test.exs` - Basic CRUD operations

### Critical Gaps (Must Fix)
- `ExecutionProcess` - 705 lines, 0 tests
- `ExecutionPersistence` - 373 lines, 0 tests
- `ConditionEvaluator` - 353 lines, 0 tests
- `CadenceApi` - 385 lines, 0 tests
- Integration/E2E tests - None exist

---

## Phase 1: Test Infrastructure (Foundation)

### 1.1 Add Test Helpers Module

Create `test/support/procedures_helpers.ex` with:

```elixir
defmodule Cadence.ProceduresHelpers do
  @moduledoc """
  Test helpers for Procedures feature testing.
  """

  import ExUnit.Assertions

  @doc """
  Waits for a condition to become true, polling at intervals.
  Fails if condition not met within timeout.

  ## Examples

      assert_eventually(fn -> Process.alive?(pid) end)
      assert_eventually(fn -> Repo.get(Execution, id).status == :completed end, timeout: 5000)
  """
  def assert_eventually(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 10)
    message = Keyword.get(opts, :message, "Condition not met within #{timeout}ms")
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(fun, deadline, interval, message)
  end

  defp do_assert_eventually(fun, deadline, interval, message) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk(message)
      else
        Process.sleep(interval)
        do_assert_eventually(fun, deadline, interval, message)
      end
    end
  end

  @doc """
  Collects all messages matching a pattern within a timeout.
  """
  def collect_messages(timeout \\ 100) do
    collect_messages_loop([], timeout)
  end

  defp collect_messages_loop(acc, timeout) do
    receive do
      msg -> collect_messages_loop([msg | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  @doc """
  Subscribes to procedure execution PubSub topic.
  """
  def subscribe_to_execution(execution_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution_id}")
  end

  @doc """
  Waits for a specific status change message.
  """
  def await_status(expected_status, timeout \\ 5000) do
    receive do
      {:status_changed, ^expected_status, execution} -> {:ok, execution}
      {:status_changed, other, _} -> {:error, {:unexpected_status, other}}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Waits for execution to reach a terminal state.
  """
  def await_completion(timeout \\ 5000) do
    receive do
      {:status_changed, status, execution} when status in [:completed, :failed, :cancelled] ->
        {:ok, status, execution}
    after
      timeout -> {:error, :timeout}
    end
  end
end
```

### 1.2 Add Test Builders Module

Create `test/support/procedures_builders.ex` for struct construction without DB:

```elixir
defmodule Cadence.ProceduresBuilders do
  @moduledoc """
  Builders for Procedures structs without database interaction.
  Use for pure unit tests that don't need persistence.
  """

  alias Cadence.Procedures.{Procedure, ProcedureVersion, ProcedureExecution, ProcedureLog}

  def build_execution(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      procedure_id: Ecto.UUID.generate(),
      procedure_version_id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      mission_id: Ecto.UUID.generate(),
      status: :pending,
      parameters: %{},
      triggered_by: :manual,
      current_step_index: 0,
      completed_steps: [],
      failed_steps: [],
      skipped_steps: [],
      blocked_steps: [],
      step_results: %{},
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(ProcedureExecution, Map.merge(defaults, to_map(overrides)))
  end

  def build_procedure(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      mission_id: Ecto.UUID.generate(),
      name: "Test Procedure",
      description: "A test procedure",
      type: :dag,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(Procedure, Map.merge(defaults, to_map(overrides)))
  end

  def build_version(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      procedure_id: Ecto.UUID.generate(),
      version_number: 1,
      status: :draft,
      source: default_dag_source(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(ProcedureVersion, Map.merge(defaults, to_map(overrides)))
  end

  def build_dag_steps(configs) when is_list(configs) do
    configs
    |> Enum.with_index(1)
    |> Enum.map(fn {config, idx} ->
      name = config[:name] || "step_#{idx}"
      {name, build_step(config)}
    end)
    |> Map.new()
  end

  def build_step(config) do
    base = %{
      "type" => to_string(config[:type] || "log"),
      "depends_on" => config[:depends_on] || []
    }

    extra = Map.drop(to_map(config), [:name, :type, :depends_on])

    extra_stringified =
      extra
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()

    Map.merge(base, extra_stringified)
  end

  def default_dag_source do
    %{
      "steps" => %{
        "step_1" => %{"type" => "log", "message" => "Starting", "depends_on" => []},
        "step_2" => %{"type" => "wait", "duration" => 10, "depends_on" => ["step_1"]},
        "step_3" => %{"type" => "log", "message" => "Done", "depends_on" => ["step_2"]}
      }
    }
  end

  def build_context(overrides \\ %{}) do
    defaults = %{
      mission_id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      target_id: nil,
      execution_id: Ecto.UUID.generate(),
      params: %{},
      vars: %{},
      trigger: nil
    }

    Map.merge(defaults, to_map(overrides))
  end

  defp to_map(kw) when is_list(kw), do: Map.new(kw)
  defp to_map(map) when is_map(map), do: map
end
```

### 1.3 Update test_helper.exs

Add the new modules to compilation:

```elixir
# In test/test_helper.exs, the support files are auto-compiled
# Just ensure they're in test/support/
```

---

## Phase 2: Pure Function Tests (Layer 1)

### 2.1 ConditionEvaluator Tests

Create `test/cadence/procedures/condition_evaluator_test.exs`:

**Priority: HIGH** - This is safety-critical code that determines abort/continue behavior.

Test cases needed:
- Boolean literals ("true", "false", true, false, nil, "")
- Telemetry conditions with CVT lookup (mock CVT)
- Parameter conditions with nested paths
- Variable conditions with step results
- Generic comparisons without prefix
- All comparison operators (>=, <=, >, <, ==, !=)
- Type coercion edge cases
- Error cases (unknown format, missing params, CVT errors)

### 2.2 CadenceApi Tests (Lua Bridge)

Create `test/cadence/procedures/runtime/cadence_api_test.exs`:

**Priority: HIGH** - This is the bridge between Lua and Elixir.

Test cases needed:
- `install/2` creates cadence namespace correctly
- Telemetry API: get, wait_for with polling
- Command API: send, send_and_verify (mock dispatcher)
- Flow API: wait (chunked), log, checkpoint, abort
- Context installation (params, mission_id, target_id)
- Lua table <-> Elixir map conversion
- Error handling in each API function

---

## Phase 3: State Machine Tests (Layer 2)

### 3.1 Execution State Machine

Extract and test the state machine explicitly:

Create `lib/cadence/procedures/execution_state_machine.ex`:
```elixir
defmodule Cadence.Procedures.ExecutionStateMachine do
  @transitions %{
    pending: [:running, :cancelled],
    running: [:pausing, :paused, :completed, :failed, :cancelled],
    pausing: [:paused, :failed, :cancelled],
    paused: [:running, :cancelled],
    completed: [],
    failed: [],
    cancelled: []
  }

  def valid_transition?(from, to), do: to in Map.get(@transitions, from, [])
  def terminal?(status), do: status in [:completed, :failed, :cancelled]
  def can_pause?(status), do: status == :running
  def can_resume?(status), do: status == :paused
end
```

Create `test/cadence/procedures/execution_state_machine_test.exs`:
- Test all valid transitions
- Test all invalid transitions
- Test terminal state detection
- Test can_pause?/can_resume? predicates

### 3.2 ExecutionProcess Tests

Create `test/cadence/procedures/engine/execution_process_test.exs`:

**Priority: CRITICAL** - This is the most important untested code.

Structure:
```elixir
defmodule Cadence.Procedures.Engine.ExecutionProcessTest do
  use Cadence.DataCase, async: false

  import Cadence.ProceduresFixtures
  import Cadence.ProceduresHelpers

  alias Cadence.Procedures.Engine.ExecutionProcess

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})
    :ok
  end

  describe "start_link/1" do
    test "starts process and registers in ProcedureRegistry"
    test "loads execution with associations"
    test "initializes Lua state for script procedures"
    test "sends :start_execution for pending executions"
    test "does not auto-start non-pending executions"
  end

  describe "control signals" do
    test "pause transitions running to pausing"
    test "pause is no-op for non-running status"
    test "abort stops execution and sets cancelled"
    test "resume transitions paused to running"
    test "resume is no-op for non-paused status"
  end

  describe "DAG execution" do
    test "spawns Task for DAG execution"
    test "handles successful DAG completion"
    test "handles DAG failure with failed steps"
    test "handles DAG validation errors"
    test "forwards pause signal to DAG task"
    test "handles Task crash gracefully"
  end

  describe "script execution" do
    test "executes Lua script"
    test "handles Lua syntax errors"
    test "handles procedure_abort throw"
  end

  describe "persistence" do
    test "updates status in database"
    test "persists logs during execution"
    test "saves checkpoint on pause"
  end

  describe "broadcasting" do
    test "broadcasts status changes via PubSub"
    test "broadcasts step events for DAG"
    test "broadcasts log messages"
  end

  describe "get_state/1" do
    test "returns current execution state"
    test "returns error for unknown execution"
  end
end
```

### 3.3 ExecutionPersistence Tests

Create `test/cadence/procedures/engine/execution_persistence_test.exs`:

**Priority: HIGH** - Transaction boundaries and outbox pattern.

Test cases:
- `update_status_with_log/6` - atomic status + log + outbox
- `persist_step_event/5` - atomic step event + log
- `persist_dag_result/3` - final status with all step tracking
- `save_checkpoint/3` - checkpoint state saving
- Idempotency key handling for resume
- Broadcast-after-commit guarantee
- Transaction rollback on failure

### 3.4 ExecutionCoordinator Tests (Expand)

Expand `test/cadence/procedures/engine/execution_coordinator_test.exs`:

Add tests for:
- `pause/2` - signal propagation to ExecutionProcess
- `abort/2` - signal propagation to ExecutionProcess
- `resume/2` - signal propagation to ExecutionProcess
- `get_execution_state/2` - delegates to ExecutionProcess
- Process cleanup on execution completion
- Mission-scoped isolation (executions don't leak between missions)

---

## Phase 4: Integration Tests (Layer 4)

### 4.1 DAG Execution Integration

Create `test/cadence/procedures/integration/dag_execution_test.exs`:

**Priority: CRITICAL** - Proves the system works end-to-end.

```elixir
defmodule Cadence.Procedures.Integration.DagExecutionTest do
  use Cadence.DataCase, async: false

  import Cadence.ProceduresFixtures
  import Cadence.ProceduresHelpers

  alias Cadence.Procedures
  alias Cadence.Procedures.Engine.ExecutionCoordinator

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})

    org = organization_fixture()
    mission = mission_fixture(organization: org)

    {:ok, coord_pid} = ExecutionCoordinator.start_link(
      mission_id: mission.id,
      organization_id: org.id
    )

    on_exit(fn ->
      if Process.alive?(coord_pid), do: GenServer.stop(coord_pid)
    end)

    %{org: org, mission: mission}
  end

  describe "simple DAG execution" do
    test "executes log-wait-log sequence", %{org: org, mission: mission} do
      procedure = procedure_fixture(organization: org, mission: mission)

      {:ok, execution} = ExecutionCoordinator.start_execution(
        mission.id,
        procedure.id
      )

      subscribe_to_execution(execution.id)

      assert {:ok, :completed, final} = await_completion(10_000)
      assert final.completed_steps == ["step_1", "step_2", "step_3"]
      assert final.failed_steps == []
    end

    test "executes parallel branches concurrently", %{org: org, mission: mission} do
      source = %{
        "steps" => %{
          "init" => %{"type" => "log", "message" => "start", "depends_on" => []},
          "branch_a" => %{"type" => "wait", "duration" => 50, "depends_on" => ["init"]},
          "branch_b" => %{"type" => "wait", "duration" => 50, "depends_on" => ["init"]},
          "join" => %{"type" => "log", "message" => "done", "depends_on" => ["branch_a", "branch_b"]}
        }
      }

      procedure = procedure_fixture(organization: org, mission: mission, source: source)

      start_time = System.monotonic_time(:millisecond)
      {:ok, execution} = ExecutionCoordinator.start_execution(mission.id, procedure.id)

      subscribe_to_execution(execution.id)
      assert {:ok, :completed, _} = await_completion(10_000)

      elapsed = System.monotonic_time(:millisecond) - start_time
      # Parallel execution should be ~100ms, not ~150ms
      assert elapsed < 200
    end
  end

  describe "failure handling" do
    test "step failure with abort mode stops execution", ctx do
      # ... test with check step that fails
    end

    test "step failure with continue mode completes other branches", ctx do
      # ... test with parallel branches where one fails
    end
  end

  describe "pause and resume" do
    test "pause stops at step boundary and resume continues", ctx do
      # ... test with long wait step, pause during, resume
    end

    test "paused state persists across process restart", ctx do
      # ... test pause, kill process, verify can resume
    end
  end

  describe "abort" do
    test "abort stops running execution immediately", ctx do
      # ... test abort during execution
    end
  end
end
```

### 4.2 Script Execution Integration

Create `test/cadence/procedures/integration/script_execution_test.exs`:

Test cases:
- Simple Lua script execution
- Script with cadence.log() calls
- Script with cadence.wait()
- Script with cadence.abort()
- Script syntax error handling
- Script runtime error handling

### 4.3 Pause/Resume Integration

Create `test/cadence/procedures/integration/pause_resume_test.exs`:

Test cases:
- Pause during DAG execution
- Resume from paused state
- State persistence across pause/resume
- Multiple pause/resume cycles
- Pause during long wait step

---

## Phase 5: Failure Mode Tests

### 5.1 Process Crash Recovery

Create `test/cadence/procedures/integration/failure_recovery_test.exs`:

Test cases:
- ExecutionProcess crash recovery
- DAG Task crash handling
- Database unavailability during execution
- Orphaned execution cleanup

---

## Implementation Order

### Week 1: Foundation + Critical Gaps
1. [ ] Create `test/support/procedures_helpers.ex`
2. [ ] Create `test/support/procedures_builders.ex`
3. [ ] Create `condition_evaluator_test.exs` (HIGH priority)
4. [ ] Create basic `execution_process_test.exs` (start_link, get_state)

### Week 2: ExecutionProcess + Integration
5. [ ] Complete `execution_process_test.exs` (control signals, DAG execution)
6. [ ] Create `dag_execution_test.exs` (simple E2E test)
7. [ ] Expand `execution_coordinator_test.exs` (control operations)

### Week 3: Persistence + Runtime
8. [ ] Create `execution_persistence_test.exs`
9. [ ] Create `cadence_api_test.exs`
10. [ ] Create `script_execution_test.exs`

### Week 4: Advanced Scenarios
11. [ ] Create `pause_resume_test.exs`
12. [ ] Create `failure_recovery_test.exs`
13. [ ] Add execution state machine extraction + tests

---

## Success Criteria

- [ ] Test:code ratio improves from 27% to >60%
- [ ] All critical modules have >80% coverage
- [ ] At least one E2E integration test passes
- [ ] No `Process.sleep()` in tests (use `assert_eventually`)
- [ ] All tests pass with `async: true` where possible
- [ ] CI runs all tests in <60 seconds

---

## Notes

- Use `{:shared, self()}` sandbox mode for tests that spawn processes
- Prefer message-based synchronization over timing-based
- Mock external dependencies (CVT, CommandDispatcher) in unit tests
- Use real dependencies in integration tests
- Keep integration tests focused on happy paths + critical error paths
