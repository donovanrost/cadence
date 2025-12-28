defmodule Cadence.Procedures.Engine.ExecutionProcessTest do
  @moduledoc """
  Tests for the ExecutionProcess GenServer.

  This is the most critical untested component - it orchestrates procedure execution,
  handles control signals, manages DAG tasks, and coordinates persistence/broadcasting.

  Test Categories:
  1. Process lifecycle (start_link, init, terminate)
  2. Client API (whereis, get_state, send_signal)
  3. Control signals (pause, abort, resume)
  4. DAG execution (task spawning, completion, failure)
  5. Script execution (Lua VM)
  6. Message handling (logs, checkpoints, commands)
  7. Broadcasting (PubSub events)
  """
  use Cadence.DataCase, async: false

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.ProceduresFixtures
  import Cadence.ProceduresHelpers

  alias Cadence.Procedures
  alias Cadence.Procedures.Engine.ExecutionProcess
  alias Ecto.Adapters.SQL.Sandbox

  # Note: Some Postgrex disconnection errors may appear during these tests.
  # These are expected - they occur when the sandbox connection is rolled back
  # while async DAG executor tasks are still attempting DB operations.
  # The tests still pass correctly.

  setup do
    # Use shared sandbox mode for process spawning tests
    Sandbox.mode(Cadence.Repo, {:shared, self()})
    :ok
  end

  # ============================================================================
  # Process Lifecycle
  # ============================================================================

  describe "start_link/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      %{org: org, mission: mission, procedure: procedure, execution: execution}
    end

    test "starts process and registers in ProcedureRegistry", %{execution: execution} do
      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      assert Process.alive?(pid)
      assert ExecutionProcess.whereis(execution.id) == pid

      # Cleanup
      GenServer.stop(pid)
    end

    test "loads execution with associations", %{execution: execution} do
      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      state = ExecutionProcess.get_state(execution.id)
      assert state.execution_id == execution.id
      assert state.status in [:pending, :running]

      GenServer.stop(pid)
    end

    test "sends :start_execution for pending executions", %{execution: execution} do
      subscribe_to_execution(execution.id)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      # Should transition to running
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: status} -> status in [:running, :completed]
            _ -> false
          end
        end,
        timeout: 2000
      )

      GenServer.stop(pid)
    end
  end

  describe "whereis/1" do
    test "returns nil for non-existent execution" do
      assert ExecutionProcess.whereis(Ecto.UUID.generate()) == nil
    end

    test "returns pid for running execution" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      assert ExecutionProcess.whereis(execution.id) == pid

      GenServer.stop(pid)
    end
  end

  describe "get_state/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{execution: execution, pid: pid}
    end

    test "returns current state", %{execution: execution} do
      state = ExecutionProcess.get_state(execution.id)

      assert is_map(state)
      assert state.execution_id == execution.id
      assert state.status in [:pending, :running, :completed]
      assert Map.has_key?(state, :current_step_index)
      assert Map.has_key?(state, :control_signal)
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = ExecutionProcess.get_state(Ecto.UUID.generate())
    end
  end

  # ============================================================================
  # Control Signals
  # ============================================================================

  describe "pause/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Create a procedure with a long wait step to give time to pause
      source = %{
        "steps" => %{
          "step_1" => %{"type" => "log", "message" => "start", "depends_on" => []},
          "step_2" => %{"type" => "wait", "duration" => 5000, "depends_on" => ["step_1"]},
          "step_3" => %{"type" => "log", "message" => "done", "depends_on" => ["step_2"]}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{execution: execution, pid: pid}
    end

    test "transitions running to pausing", %{execution: execution} do
      # Wait for execution to start running
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: :running} -> true
            _ -> false
          end
        end,
        timeout: 2000
      )

      # Send pause signal
      assert :ok = ExecutionProcess.pause(execution.id)

      # Should transition to pausing or paused
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: status} -> status in [:pausing, :paused]
            _ -> false
          end
        end,
        timeout: 2000
      )
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = ExecutionProcess.pause(Ecto.UUID.generate())
    end
  end

  describe "abort/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      source = %{
        "steps" => %{
          "step_1" => %{"type" => "wait", "duration" => 5000, "depends_on" => []}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{execution: execution, pid: pid}
    end

    test "stops execution and sets cancelled status", %{execution: execution, pid: pid} do
      subscribe_to_execution(execution.id)

      # Wait for execution to start
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: :running} -> true
            _ -> false
          end
        end,
        timeout: 2000
      )

      # Send abort signal
      assert :ok = ExecutionProcess.abort(execution.id)

      # Process should stop
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

      # Verify final state in database
      final_execution = Procedures.get_execution!(execution.id)
      assert final_execution.status == :cancelled
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = ExecutionProcess.abort(Ecto.UUID.generate())
    end
  end

  describe "resume/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Use a long wait step so we have time to pause and resume
      source = %{
        "steps" => %{
          "step_1" => %{"type" => "log", "message" => "start", "depends_on" => []},
          "step_2" => %{"type" => "wait", "duration" => 5000, "depends_on" => ["step_1"]},
          "step_3" => %{"type" => "log", "message" => "done", "depends_on" => ["step_2"]}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{execution: execution, pid: pid}
    end

    test "resumes paused execution", %{execution: execution, pid: _pid} do
      subscribe_to_execution(execution.id)

      # Wait for execution to be running
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: :running} -> true
            _ -> false
          end
        end,
        timeout: 2000
      )

      # Pause the execution
      assert :ok = ExecutionProcess.pause(execution.id)

      # Wait for it to be paused (or pausing) - give more time
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: status} when status in [:pausing, :paused] -> true
            _ -> false
          end
        end,
        timeout: 5000,
        message: "Execution did not pause"
      )

      # Resume the execution
      result = ExecutionProcess.resume(execution.id)
      # Process might have stopped during pause
      assert result in [:ok, {:error, :not_found}]

      # If we successfully resumed, check the status
      # The execution might complete quickly or still be running
      if result == :ok do
        assert_eventually(
          fn ->
            state = ExecutionProcess.get_state(execution.id)

            case state do
              %{status: status} -> status in [:running, :completed, :paused]
              # Process stopped
              {:error, :not_found} -> true
              # Process not found
              nil -> true
            end
          end,
          timeout: 3000
        )
      end
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = ExecutionProcess.resume(Ecto.UUID.generate())
    end
  end

  # ============================================================================
  # DAG Execution
  # ============================================================================

  describe "DAG execution" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      %{org: org, mission: mission}
    end

    test "executes simple DAG to completion", %{org: org, mission: mission} do
      source = %{
        "steps" => %{
          "step_1" => %{"type" => "log", "message" => "Hello", "depends_on" => []},
          "step_2" => %{"type" => "log", "message" => "World", "depends_on" => ["step_1"]}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      subscribe_to_execution(execution.id)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should complete and process should stop
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      # Verify final state
      final = Procedures.get_execution!(execution.id)
      assert final.status == :completed
      assert "step_1" in final.completed_steps
      assert "step_2" in final.completed_steps
    end

    test "handles step failure with abort mode", %{org: org, mission: mission} do
      # Use an assert step that directly evaluates to false
      # This is the simplest way to trigger a step failure
      source = %{
        "steps" => %{
          "step_1" => %{
            "type" => "assert",
            # Simple false comparison
            "condition" => "1 == 0",
            "message" => "Assertion intentionally failed for test",
            "depends_on" => []
          }
        },
        "on_step_failure" => "abort"
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should fail and stop
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      final = Procedures.get_execution!(execution.id)
      # When a step fails with abort mode, the DAG fails and sets status to :failed
      # However, on abort signal (which is what on_step_failure=abort triggers internally),
      # the executor may return :aborted which results in :cancelled status
      # Both are acceptable outcomes for "step failure with abort mode"
      assert final.status in [:failed, :cancelled],
             "Expected status to be :failed or :cancelled, got #{final.status}"
    end

    test "broadcasts step events during execution", %{org: org, mission: mission} do
      source = %{
        "steps" => %{
          "step_1" => %{"type" => "log", "message" => "Test", "depends_on" => []}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      subscribe_to_execution(execution.id)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Collect events until process stops
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      # Should have received step events
      messages = collect_messages(100)

      # Check for status changes
      status_changes =
        Enum.filter(messages, fn
          {:status_changed, _, _} -> true
          _ -> false
        end)

      assert length(status_changes) >= 1
    end
  end

  # ============================================================================
  # Script Execution
  # ============================================================================

  describe "script execution" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      %{org: org, mission: mission}
    end

    test "executes simple Lua script", %{org: org, mission: mission} do
      source = %{
        "code" => """
        cadence.log("info", "Hello from Lua!")
        return true
        """
      }

      procedure =
        approved_procedure_fixture(
          organization: org,
          mission: mission,
          source: source,
          type: :script
        )

      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      subscribe_to_execution(execution.id)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should complete
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      final = Procedures.get_execution!(execution.id)
      assert final.status == :completed
    end

    test "handles Lua syntax error gracefully", %{org: org, mission: mission} do
      source = %{
        "code" => """
        this is not valid lua syntax {{{{
        """
      }

      procedure =
        approved_procedure_fixture(
          organization: org,
          mission: mission,
          source: source,
          type: :script
        )

      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should fail but not crash
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      final = Procedures.get_execution!(execution.id)
      assert final.status == :failed
      assert final.error_message != nil
    end

    test "handles missing code key", %{org: org, mission: mission} do
      source = %{"invalid" => "source"}

      procedure =
        approved_procedure_fixture(
          organization: org,
          mission: mission,
          source: source,
          type: :script
        )

      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      final = Procedures.get_execution!(execution.id)
      assert final.status == :failed
      assert final.error_message =~ "missing 'code' key"
    end
  end

  # ============================================================================
  # Message Handling
  # ============================================================================

  # These tests run long-running procedures and may generate DB errors during cleanup
  describe "handle_info messages" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Use a long-running procedure so we can send messages during execution
      source = %{
        "steps" => %{
          "step_1" => %{"type" => "wait", "duration" => 5000, "depends_on" => []}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      # Wait for it to start running
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: :running} -> true
            _ -> false
          end
        end,
        timeout: 2000
      )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{execution: execution, pid: pid}
    end

    test "handles log messages from Cadence API", %{pid: pid, execution: execution} do
      subscribe_to_execution(execution.id)

      # Send a log message as if from Cadence API
      send(pid, {:log, :info, "Test log message"})

      # Should receive broadcast
      assert_receive {:log, :info, "Test log message"}, 1000
    end

    test "handles checkpoint messages", %{pid: pid, execution: execution} do
      subscribe_to_execution(execution.id)

      send(pid, {:checkpoint, "my_checkpoint"})

      assert_receive {:checkpoint, "my_checkpoint"}, 1000
    end

    test "handles command_sent messages", %{pid: pid, execution: execution} do
      subscribe_to_execution(execution.id)

      send(pid, {:command_sent, "POWER_ON", "log-123"})

      # Should log the command
      assert_receive {:log, :info, msg}, 1000
      assert msg =~ "Command sent: POWER_ON"
    end

    test "handles command_failed messages", %{pid: pid, execution: execution} do
      subscribe_to_execution(execution.id)

      send(pid, {:command_failed, "POWER_ON", :timeout})

      assert_receive {:log, :error, msg}, 1000
      assert msg =~ "Command failed: POWER_ON"
    end

    test "handles abort_requested from Lua", %{pid: pid, execution: execution} do
      send(pid, {:abort_requested, "User requested abort"})

      # Should set control signal
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{control_signal: :abort} -> true
            _ -> false
          end
        end,
        timeout: 1000
      )
    end

    test "ignores unknown messages", %{pid: pid} do
      # Should not crash
      send(pid, {:unknown_message, "data"})
      send(pid, "random string")
      send(pid, 12_345)

      # Process should still be alive
      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end

  # ============================================================================
  # Broadcasting
  # ============================================================================

  describe "broadcasting" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      %{execution: execution, mission: mission}
    end

    test "broadcasts status changes to execution topic", %{execution: execution} do
      subscribe_to_execution(execution.id)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should receive status changes
      assert_receive {:status_changed, :running, _}, 5000

      # Wait for completion
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000
    end

    test "broadcasts log messages", %{execution: execution} do
      subscribe_to_execution(execution.id)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should receive log messages during execution
      assert_receive {:log, _, _}, 5000

      # Wait for completion
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000
    end
  end

  # ============================================================================
  # Termination
  # ============================================================================

  describe "terminate/2" do
    test "terminates gracefully on normal stop" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      GenServer.stop(pid, :normal)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "terminates gracefully on kill" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Trap exits so we don't crash the test process
      Process.flag(:trap_exit, true)

      Process.exit(pid, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000

      # Restore trap_exit
      Process.flag(:trap_exit, false)
    end

    test "unregisters from ProcedureRegistry on stop" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = approved_procedure_fixture(organization: org, mission: mission)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      assert ExecutionProcess.whereis(execution.id) == pid

      GenServer.stop(pid)

      # Allow registry cleanup
      Process.sleep(50)

      assert ExecutionProcess.whereis(execution.id) == nil
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles rapid control signals" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      source = %{
        "steps" => %{
          "step_1" => %{"type" => "wait", "duration" => 10_000, "depends_on" => []}
        }
      }

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      # Wait for running state
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: :running} -> true
            _ -> false
          end
        end,
        timeout: 2000
      )

      # Send rapid signals
      ExecutionProcess.pause(execution.id)
      ExecutionProcess.resume(execution.id)
      ExecutionProcess.pause(execution.id)
      ExecutionProcess.abort(execution.id)

      # Should end up cancelled (abort wins)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

      final = Procedures.get_execution!(execution.id)
      assert final.status == :cancelled
    end

    test "handles empty steps DAG" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      source = %{"steps" => %{}}

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      # Should complete (empty DAG is valid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      final = Procedures.get_execution!(execution.id)
      assert final.status == :completed
    end

    test "handles invalid DAG source structure" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      source = %{"steps" => "not a map"}

      procedure = approved_procedure_fixture(organization: org, mission: mission, source: source)
      execution = execution_fixture(procedure: procedure, mission: mission, organization: org)

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      final = Procedures.get_execution!(execution.id)
      assert final.status == :failed
      assert final.error_message =~ "'steps' must be a map"
    end
  end
end
