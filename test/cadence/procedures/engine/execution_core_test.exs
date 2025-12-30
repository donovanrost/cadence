defmodule Cadence.Procedures.Engine.ExecutionCoreTest do
  use Cadence.PureCase, async: true

  alias Cadence.Procedures.Engine.ExecutionCore

  test "control_action returns pause when pause is set" do
    state = %{control_signal: :pause}
    assert {:pause, ^state} = ExecutionCore.control_action(state)
  end

  test "control_action returns abort when abort is set" do
    state = %{control_signal: :abort}
    assert {:abort, ^state} = ExecutionCore.control_action(state)
  end

  test "control_action continues when no control signal is set" do
    state = %{control_signal: nil}
    assert {:continue, ^state} = ExecutionCore.control_action(state)
  end

  test "on_step_failure defaults to abort" do
    assert :abort == ExecutionCore.on_step_failure(%{})
  end

  test "on_step_failure returns configured behavior" do
    assert :continue == ExecutionCore.on_step_failure(%{"on_step_failure" => "continue"})
    assert :pause == ExecutionCore.on_step_failure(%{"on_step_failure" => "pause"})
    assert :abort == ExecutionCore.on_step_failure(%{"on_step_failure" => "abort"})
  end

  test "pause_transition builds paused status and log details" do
    transition = ExecutionCore.pause_transition()
    assert transition.status == :paused
    assert transition.attrs == %{}
    assert transition.log_level == :info
    assert transition.log_message == "Execution paused"
  end

  test "abort_transition without message cancels execution" do
    transition = ExecutionCore.abort_transition(3)
    assert transition.status == :cancelled
    assert transition.attrs == %{}
    assert transition.log_level == :warn
    assert transition.log_message == "Execution cancelled"
  end

  test "abort_transition with message fails execution" do
    transition = ExecutionCore.abort_transition(2, "Boom")
    assert transition.status == :failed
    assert transition.attrs == %{error_message: "Boom", error_step_index: 2}
    assert transition.log_level == :error
    assert transition.log_message == "Execution aborted: Boom"
  end

  test "failure_transition formats error and builds failure attrs" do
    transition = ExecutionCore.failure_transition(1, :bad_things)
    assert transition.status == :failed
    assert transition.attrs == %{error_message: "bad_things", error_step_index: 1}
    assert transition.log_level == :error
    assert transition.log_message == "Step 1 failed: bad_things"
  end

  test "completion_transition builds completion attrs" do
    now = DateTime.utc_now()
    transition = ExecutionCore.completion_transition(now)
    assert transition.status == :completed
    assert transition.attrs == %{completed_at: now}
    assert transition.log_level == :info
    assert transition.log_message == "Execution completed successfully"
  end

  test "start_attrs sets running status and started_at" do
    now = DateTime.utc_now()
    attrs = ExecutionCore.start_attrs(now)
    assert attrs.status == :running
    assert attrs.attrs == %{started_at: now}
  end

  test "resume_transition builds running status and log details" do
    transition = ExecutionCore.resume_transition()
    assert transition.status == :running
    assert transition.attrs == %{}
    assert transition.log_level == :info
    assert transition.log_message == "Execution resumed"
  end

  test "build_dag_context uses state fields" do
    state = %{
      execution_id: "exec-1",
      execution: %{trigger_context: %{foo: :bar}, triggered_by_user_id: "user-1"},
      context: %{
        mission_id: "mission-1",
        organization_id: "org-1",
        target_id: "target-1",
        params: %{"a" => 1},
        allow_hazardous_commands: true
      }
    }

    assert ExecutionCore.build_dag_context(state) == %{
             mission_id: "mission-1",
             organization_id: "org-1",
             target_id: "target-1",
             execution_id: "exec-1",
             params: %{"a" => 1},
             trigger: %{foo: :bar},
             vars: %{},
             user_id: "user-1",
             allow_hazardous_commands: true
           }
  end

  test "build_api_context uses execution and version fields" do
    execution = %{
      mission_id: "mission-1",
      organization_id: "org-1",
      target_id: "target-1",
      parameters: %{"p" => 1}
    }

    version = %{allow_hazardous_commands: true}
    pid = self()

    assert ExecutionCore.build_api_context(execution, version, "exec-1", pid) == %{
             mission_id: "mission-1",
             organization_id: "org-1",
             target_id: "target-1",
             execution_id: "exec-1",
             execution_pid: pid,
             params: %{"p" => 1},
             allow_hazardous_commands: true
           }
  end

  test "build_api_context defaults nil params and flags" do
    execution = %{
      mission_id: "mission-1",
      organization_id: "org-1",
      target_id: nil,
      parameters: nil
    }

    version = %{}

    assert ExecutionCore.build_api_context(execution, version, "exec-1", self()) == %{
             mission_id: "mission-1",
             organization_id: "org-1",
             target_id: nil,
             execution_id: "exec-1",
             execution_pid: self(),
             params: %{},
             allow_hazardous_commands: false
           }
  end

  test "step_event_type maps statuses to event types" do
    assert ExecutionCore.step_event_type(:running) == "procedure_step_started"
    assert ExecutionCore.step_event_type(:completed) == "procedure_step_completed"
    assert ExecutionCore.step_event_type(:failed) == "procedure_step_failed"
    assert ExecutionCore.step_event_type(:skipped) == "procedure_step_skipped"
    assert ExecutionCore.step_event_type(:blocked) == "procedure_step_blocked"
    assert ExecutionCore.step_event_type(:timed_out) == "procedure_step_timed_out"
    assert ExecutionCore.step_event_type(:unknown) == "procedure_step_status"
  end

  test "step_status_to_log formats log messages" do
    assert ExecutionCore.step_status_to_log(:running, "step_1", %{}) ==
             {:info, "Step started: step_1"}

    assert ExecutionCore.step_status_to_log(:completed, "step_2", %{}) ==
             {:info, "Step completed: step_2"}

    assert ExecutionCore.step_status_to_log(:failed, "step_3", %{error: "boom"}) ==
             {:error, "Step failed: step_3 - boom"}
  end

  test "dag_status_to_event maps to event tuples" do
    assert ExecutionCore.dag_status_to_event(:running, "step_1", %{}) ==
             {:dag_step_started, "step_1", %{}}

    assert ExecutionCore.dag_status_to_event(:completed, "step_1", %{}) ==
             {:dag_step_completed, "step_1", %{}}

    assert ExecutionCore.dag_status_to_event(:failed, "step_1", %{}) ==
             {:dag_step_failed, "step_1", %{}}

    assert ExecutionCore.dag_status_to_event(:unknown, "step_1", %{a: 1}) ==
             {:dag_step_status, "step_1", :unknown, %{a: 1}}
  end

  test "procedure_kind maps types" do
    assert ExecutionCore.procedure_kind(:dag) == :dag
    assert ExecutionCore.procedure_kind(:script) == :script
    assert ExecutionCore.procedure_kind(:other) == :unknown
  end

  test "execution_mode validates types" do
    assert ExecutionCore.execution_mode(:dag) == {:ok, :dag}
    assert ExecutionCore.execution_mode(:script) == {:ok, :script}
    assert ExecutionCore.execution_mode(:unknown) == {:error, "Unknown procedure type"}
  end

  test "dag_source validates steps map" do
    assert ExecutionCore.dag_source(%{"steps" => %{"a" => %{}}}) ==
             {:ok, %{"steps" => %{"a" => %{}}}}

    assert ExecutionCore.dag_source(%{"steps" => []}) ==
             {:error, "Invalid DAG source: 'steps' must be a map"}
  end

  test "script_source validates code" do
    assert ExecutionCore.script_source(%{"code" => "cadence.log('hi')"}) ==
             {:ok, "cadence.log('hi')"}

    assert ExecutionCore.script_source(%{"nope" => "x"}) ==
             {:error, "Invalid script source: missing 'code' key"}
  end

  test "dag log messages are consistent" do
    assert ExecutionCore.dag_start_message(3) == "Executing DAG sequence with 3 steps"
    assert ExecutionCore.dag_completed_message() == "DAG execution completed successfully"

    assert ExecutionCore.dag_failed_message(["step_1", "step_2"]) ==
             "DAG execution failed: steps failed: step_1, step_2"

    assert ExecutionCore.dag_paused_message() == "DAG execution paused"
    assert ExecutionCore.dag_paused_summary(4) == "DAG execution paused: 4 completed so far"
  end

  test "control and command log messages are consistent" do
    assert ExecutionCore.control_signal_received(:pause, "exec-1") ==
             "Received control signal :pause for execution exec-1"

    assert ExecutionCore.pause_requested_message() ==
             "Pause requested, waiting for current step to complete..."

    assert ExecutionCore.command_sent_message("POWER_ON", "log-1") ==
             "Command sent: POWER_ON (log_id: log-1)"

    assert ExecutionCore.command_failed_message("POWER_ON", :timeout) ==
             "Command failed: POWER_ON - :timeout"
  end

  test "wait and checkpoint log messages are consistent" do
    assert ExecutionCore.wait_message(250) == "Waiting 250ms"

    assert ExecutionCore.wait_for_message("battery", "<", 25) ==
             "Waiting for battery < 25"

    assert ExecutionCore.abort_requested_message("stop now") ==
             "Abort requested: stop now"

    assert ExecutionCore.checkpoint_message("alpha", 2) ==
             "Checkpoint reached: alpha at step 2"
  end

  test "execution log messages are consistent" do
    assert ExecutionCore.execution_starting_message("exec-1") ==
             "Starting ExecutionProcess for execution_id=exec-1"

    assert ExecutionCore.execution_terminating_message("exec-1", :normal) ==
             "ExecutionProcess terminating: execution_id=exec-1, reason=:normal"

    assert ExecutionCore.execute_next_message(:dag) ==
             "execute_next: procedure.type=:dag"
  end

  test "DAG executor and persistence messages are consistent" do
    assert ExecutionCore.dag_executor_crashed_message(:boom) ==
             "DAG executor crashed: :boom"

    assert ExecutionCore.dag_executor_failure_reason(:boom) ==
             "DAG executor crashed: :boom"

    assert ExecutionCore.dag_persist_failure_message() ==
             "Failed to update DAG execution status"

    assert ExecutionCore.dag_update_failure_message(:db_down) ==
             "Failed to update DAG execution: :db_down"

    assert ExecutionCore.status_update_failure_message(:paused) ==
             "Failed to update execution status to paused"

    assert ExecutionCore.forward_signal_message(:pause, self()) ==
             "Forwarded pause signal to DAG executor #{inspect(self())}"

    assert ExecutionCore.dag_completion_summary(2, 1) ==
             "DAG execution completed: 2 completed, 1 skipped"
  end
end
