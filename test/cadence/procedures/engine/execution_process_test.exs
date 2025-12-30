defmodule Cadence.Procedures.Engine.ExecutionProcessTest do
  @moduledoc """
  Tests for the ExecutionProcess GenServer.

  Pure tests for ExecutionProcess lifecycle and lookup behavior.

  Test Categories:
  1. Process lifecycle (start_link, init)
  2. Client API (whereis, get_state)
  """
  use Cadence.PureCase, async: false

  import Cadence.ProceduresBuilders
  import Cadence.ProceduresHelpers

  alias Cadence.Procedures.Engine.ExecutionProcess
  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryExecutionPersistence
  alias Cadence.Test.Adapters.InMemoryProcedureRepository

  setup do
    {:ok, _} = InMemoryProcedureRepository.start_link()
    {:ok, _} = InMemoryExecutionPersistence.start_link()
    {:ok, _} = FakeEventPublisher.start_link()

    Application.put_env(:cadence, :execution_operations, InMemoryProcedureRepository)
    Application.put_env(:cadence, :execution_persistence, InMemoryExecutionPersistence)
    Application.put_env(:cadence, :event_publisher, FakeEventPublisher)
    Application.put_env(:cadence, ExecutionProcess, autostart_pending?: false)

    on_exit(fn -> stop_execution_processes() end)

    on_exit(fn ->
      Application.delete_env(:cadence, :execution_operations)
      Application.delete_env(:cadence, :execution_persistence)
      Application.delete_env(:cadence, :event_publisher)
      Application.delete_env(:cadence, ExecutionProcess)
      InMemoryExecutionPersistence.stop()
      InMemoryProcedureRepository.stop()
      FakeEventPublisher.stop()
    end)

    :ok
  end

  defp build_execution_record do
    procedure = build_procedure(type: :dag)
    version = build_approved_version(procedure_id: procedure.id)

    {:ok, _} = InMemoryProcedureRepository.save(procedure)
    {:ok, _} = InMemoryProcedureRepository.save_version(version)

    {:ok, execution} =
      InMemoryProcedureRepository.create_execution(%{
        procedure_id: procedure.id,
        procedure_version_id: version.id,
        organization_id: procedure.organization_id,
        mission_id: procedure.mission_id,
        status: :pending
      })

    {:ok, execution} =
      InMemoryProcedureRepository.update_execution(execution.id, %{
        procedure: procedure,
        procedure_version: version
      })

    %{procedure: procedure, version: version, execution: execution}
  end

  # ============================================================================
  # Process Lifecycle
  # ============================================================================

  describe "start_link/1" do
    setup do
      build_execution_record()
    end

    test "starts process and registers in ProcedureRegistry", %{execution: execution} do
      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      assert Process.alive?(pid)
      assert ExecutionProcess.whereis(execution.id) == pid

      # Cleanup
      stop_execution_process(pid)
    end

    test "loads execution with associations", %{execution: execution} do
      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      state = ExecutionProcess.get_state(execution.id)
      assert state.execution_id == execution.id
      assert state.status in [:pending, :running]

      stop_execution_process(pid)
    end
  end

  describe "whereis/1" do
    test "returns nil for non-existent execution" do
      assert ExecutionProcess.whereis(Ecto.UUID.generate()) == nil
    end

    test "returns pid for running execution" do
      %{execution: execution} = build_execution_record()

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      assert ExecutionProcess.whereis(execution.id) == pid

      stop_execution_process(pid)
    end
  end

  describe "get_state/1" do
    setup do
      %{execution: execution} = build_execution_record()

      {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

      on_exit(fn ->
        stop_execution_process(pid)
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
end
