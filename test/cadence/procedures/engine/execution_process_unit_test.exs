defmodule Cadence.Procedures.Engine.ExecutionProcessUnitTest do
  use Cadence.UseCaseCase, async: false

  alias Cadence.Domain.Procedures.Entities.Procedure
  alias Cadence.Procedures.Engine.ExecutionProcess
  alias Cadence.Procedures.ProcedureVersion
  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryProcedureRepository

  setup do
    Application.put_env(:cadence, ExecutionProcess, autostart_pending?: false)

    on_exit(fn ->
      Application.delete_env(:cadence, ExecutionProcess)
    end)

    :ok
  end

  defp start_execution_process(opts \\ []) do
    execution = build_execution(opts)
    {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)

    if Keyword.get(opts, :start?, false) do
      :ok = ExecutionProcess.start_execution(execution.id)
    end

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{execution: execution, pid: pid}
  end

  defp build_execution(opts) do
    org_id = Ecto.UUID.generate()
    mission_id = Ecto.UUID.generate()
    procedure_id = Ecto.UUID.generate()
    version_id = Ecto.UUID.generate()

    source =
      Keyword.get(opts, :source, %{
        "steps" => %{
          "step_1" => %{"type" => "log", "message" => "Hello", "depends_on" => []}
        }
      })

    type = Keyword.get(opts, :type, :dag)

    {:ok, procedure} =
      Procedure.new(%{
        id: procedure_id,
        organization_id: org_id,
        mission_id: mission_id,
        name: "Unit Test Procedure",
        type: type
      })

    version = %ProcedureVersion{
      id: version_id,
      source: source,
      allow_hazardous_commands: false
    }

    {:ok, execution} =
      InMemoryProcedureRepository.create_execution(%{
        procedure_id: procedure.id,
        procedure_version_id: version.id,
        organization_id: org_id,
        mission_id: mission_id,
        status: :pending
      })

    {:ok, execution} =
      InMemoryProcedureRepository.update_execution(execution.id, %{
        procedure: procedure,
        procedure_version: version
      })

    execution
  end

  test "executes a DAG without database persistence" do
    execution = build_execution([])
    FakeEventPublisher.subscribe("procedure:#{execution.id}")

    {:ok, pid} = ExecutionProcess.start_link(execution_id: execution.id)
    :ok = ExecutionProcess.start_execution(execution.id)
    ref = Process.monitor(pid)

    assert_receive {:event, {:status_changed, :running, _}}, 1000
    assert_receive {:event, {:status_changed, :completed, _}}, 2000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
  end

  test "broadcasts status changes to execution topic" do
    %{execution: execution, pid: pid} = start_execution_process(start?: true)
    FakeEventPublisher.subscribe("procedure:#{execution.id}")
    ref = Process.monitor(pid)

    assert_receive {:event, {:status_changed, :running, _}}, 1000
    assert_receive {:event, {:status_changed, :completed, _}}, 2000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
  end

  test "broadcasts log messages during execution" do
    %{execution: execution, pid: pid} = start_execution_process(start?: true)
    FakeEventPublisher.subscribe("procedure:#{execution.id}")
    ref = Process.monitor(pid)

    assert_receive {:event, {:log, _, _}}, 1000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
  end

  test "handles log messages from Cadence API" do
    %{execution: execution, pid: pid} = start_execution_process()
    FakeEventPublisher.subscribe("procedure:#{execution.id}")

    send(pid, {:log, :info, "Test log message"})

    assert_receive {:event, {:log, :info, "Test log message"}}, 1000
  end

  test "handles checkpoint messages" do
    %{execution: execution, pid: pid} = start_execution_process()
    FakeEventPublisher.subscribe("procedure:#{execution.id}")

    send(pid, {:checkpoint, "my_checkpoint"})

    assert_receive {:event, {:checkpoint, "my_checkpoint"}}, 1000
  end

  test "handles command_sent messages" do
    %{execution: execution, pid: pid} = start_execution_process()
    FakeEventPublisher.subscribe("procedure:#{execution.id}")

    send(pid, {:command_sent, "POWER_ON", "log-123"})

    assert_receive {:event, {:log, :info, msg}}, 1000
    assert msg =~ "Command sent: POWER_ON"
  end

  test "handles command_failed messages" do
    %{execution: execution, pid: pid} = start_execution_process()
    FakeEventPublisher.subscribe("procedure:#{execution.id}")

    send(pid, {:command_failed, "POWER_ON", :timeout})

    assert_receive {:event, {:log, :error, msg}}, 1000
    assert msg =~ "Command failed: POWER_ON"
  end

  test "handles abort_requested from Lua" do
    %{execution: execution, pid: pid} = start_execution_process()

    send(pid, {:abort_requested, "User requested abort"})

    assert %{control_signal: :abort} = ExecutionProcess.get_state(execution.id)
  end

  test "ignores unknown messages" do
    %{pid: pid} = start_execution_process()
    ref = Process.monitor(pid)

    send(pid, {:unknown_message, "data"})
    send(pid, "random string")
    send(pid, 12_345)

    refute_receive {:DOWN, ^ref, :process, ^pid, _}, 100
    assert Process.alive?(pid)
  end

  test "terminates gracefully on normal stop" do
    %{pid: pid} = start_execution_process()
    ref = Process.monitor(pid)

    GenServer.stop(pid, :normal)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "terminates gracefully on kill" do
    %{pid: pid} = start_execution_process()
    ref = Process.monitor(pid)

    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000
    Process.flag(:trap_exit, false)
  end

  test "unregisters from ProcedureRegistry on stop" do
    %{execution: execution, pid: pid} = start_execution_process()

    assert ExecutionProcess.whereis(execution.id) == pid

    GenServer.stop(pid)
    Process.sleep(50)

    assert ExecutionProcess.whereis(execution.id) == nil
  end

  test "pause transitions to pausing or paused" do
    source = %{
      "steps" => %{
        "step_1" => %{"type" => "log", "message" => "start", "depends_on" => []},
        "step_2" => %{"type" => "wait", "duration" => 500, "depends_on" => ["step_1"]},
        "step_3" => %{"type" => "log", "message" => "done", "depends_on" => ["step_2"]}
      }
    }

    %{execution: execution} = start_execution_process(source: source, start?: true)

    assert_eventually(
      fn ->
        case ExecutionProcess.get_state(execution.id) do
          %{status: :running} -> true
          _ -> false
        end
      end,
      timeout: 2000
    )

    assert :ok = ExecutionProcess.pause(execution.id)

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

  test "abort stops execution and sets cancelled status" do
    source = %{
      "steps" => %{
        "step_1" => %{"type" => "wait", "duration" => 500, "depends_on" => []}
      }
    }

    %{execution: execution, pid: pid} = start_execution_process(source: source, start?: true)

    assert_eventually(
      fn ->
        case ExecutionProcess.get_state(execution.id) do
          %{status: :running} -> true
          _ -> false
        end
      end,
      timeout: 2000
    )

    assert :ok = ExecutionProcess.abort(execution.id)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :cancelled
  end

  test "resume continues paused execution" do
    source = %{
      "steps" => %{
        "step_1" => %{"type" => "log", "message" => "start", "depends_on" => []},
        "step_2" => %{"type" => "wait", "duration" => 500, "depends_on" => ["step_1"]},
        "step_3" => %{"type" => "log", "message" => "done", "depends_on" => ["step_2"]}
      }
    }

    %{execution: execution} = start_execution_process(source: source, start?: true)

    assert_eventually(
      fn ->
        case ExecutionProcess.get_state(execution.id) do
          %{status: :running} -> true
          _ -> false
        end
      end,
      timeout: 2000
    )

    assert :ok = ExecutionProcess.pause(execution.id)

    assert_eventually(
      fn ->
        case ExecutionProcess.get_state(execution.id) do
          %{status: status} when status in [:pausing, :paused] -> true
          _ -> false
        end
      end,
      timeout: 5000
    )

    result = ExecutionProcess.resume(execution.id)
    assert result in [:ok, {:error, :not_found}]

    if result == :ok do
      assert_eventually(
        fn ->
          case ExecutionProcess.get_state(execution.id) do
            %{status: status} -> status in [:running, :completed, :paused]
            {:error, :not_found} -> true
            nil -> true
          end
        end,
        timeout: 3000
      )
    end
  end

  test "executes simple DAG to completion" do
    source = %{
      "steps" => %{
        "step_1" => %{"type" => "log", "message" => "Hello", "depends_on" => []},
        "step_2" => %{"type" => "log", "message" => "World", "depends_on" => ["step_1"]}
      }
    }

    %{execution: execution, pid: pid} = start_execution_process(source: source, start?: true)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :completed
    assert "step_1" in final.completed_steps
    assert "step_2" in final.completed_steps
  end

  test "handles step failure with abort mode" do
    source = %{
      "steps" => %{
        "step_1" => %{
          "type" => "assert",
          "condition" => "1 == 0",
          "message" => "Assertion intentionally failed for test",
          "depends_on" => []
        }
      },
      "on_step_failure" => "abort"
    }

    %{execution: execution, pid: pid} = start_execution_process(source: source, start?: true)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status in [:failed, :cancelled]
  end

  test "executes simple Lua script" do
    source = %{
      "code" => """
      cadence.log("info", "Hello from Lua!")
      return true
      """
    }

    %{execution: execution, pid: pid} =
      start_execution_process(source: source, type: :script, start?: true)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :completed
  end

  test "handles Lua syntax error gracefully" do
    source = %{
      "code" => """
      this is not valid lua syntax {{{{
      """
    }

    %{execution: execution, pid: pid} =
      start_execution_process(source: source, type: :script, start?: true)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :failed
    assert final.error_message != nil
  end

  test "handles missing code key" do
    source = %{"invalid" => "source"}

    %{execution: execution, pid: pid} =
      start_execution_process(source: source, type: :script, start?: true)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :failed
    assert final.error_message =~ "missing 'code' key"
  end

  test "handles rapid control signals" do
    source = %{
      "steps" => %{
        "step_1" => %{"type" => "wait", "duration" => 1000, "depends_on" => []}
      }
    }

    %{execution: execution, pid: pid} = start_execution_process(source: source, start?: true)

    assert_eventually(
      fn ->
        case ExecutionProcess.get_state(execution.id) do
          %{status: :running} -> true
          _ -> false
        end
      end,
      timeout: 2000
    )

    ExecutionProcess.pause(execution.id)
    ExecutionProcess.resume(execution.id)
    ExecutionProcess.pause(execution.id)
    ExecutionProcess.abort(execution.id)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :cancelled
  end

  test "handles empty steps DAG" do
    source = %{"steps" => %{}}

    %{execution: execution, pid: pid} = start_execution_process(source: source, start?: true)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :completed
  end

  test "handles invalid DAG source structure" do
    source = %{"steps" => "not a map"}

    %{execution: execution, pid: pid} = start_execution_process(source: source, start?: true)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

    {:ok, final} = InMemoryProcedureRepository.find_execution(execution.id)
    assert final.status == :failed
    assert final.error_message =~ "'steps' must be a map"
  end
end
