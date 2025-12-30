defmodule Cadence.Procedures.Engine.ExecutionCore do
  @moduledoc """
  Pure execution logic for v1 procedures.

  This module isolates deterministic decision-making from IO (DB, PubSub),
  enabling fast, dependency-free unit tests.
  """

  @type control_action :: :pause | :abort | :continue

  @type transition :: %{
          status: atom(),
          attrs: map(),
          log_level: atom(),
          log_message: String.t()
        }

  @spec control_action(map()) :: {control_action(), map()}
  def control_action(%{control_signal: :pause} = state), do: {:pause, state}
  def control_action(%{control_signal: :abort} = state), do: {:abort, state}
  def control_action(state), do: {:continue, state}

  @spec on_step_failure(map()) :: :continue | :pause | :abort
  def on_step_failure(%{"on_step_failure" => "continue"}), do: :continue
  def on_step_failure(%{"on_step_failure" => "pause"}), do: :pause
  def on_step_failure(_), do: :abort

  @spec start_attrs(DateTime.t()) :: map()
  def start_attrs(now) do
    %{status: :running, attrs: %{started_at: now}}
  end

  @spec resume_transition() :: transition()
  def resume_transition do
    %{
      status: :running,
      attrs: %{},
      log_level: :info,
      log_message: "Execution resumed"
    }
  end

  @spec build_dag_context(map()) :: map()
  def build_dag_context(state) do
    %{
      mission_id: state.context.mission_id,
      organization_id: state.context.organization_id,
      target_id: state.context.target_id,
      execution_id: state.execution_id,
      params: state.context.params,
      trigger: state.execution.trigger_context,
      vars: %{},
      user_id: state.execution.triggered_by_user_id,
      allow_hazardous_commands: state.context.allow_hazardous_commands
    }
  end

  @spec build_api_context(map(), map(), String.t(), pid()) :: map()
  def build_api_context(execution, version, execution_id, execution_pid) do
    %{
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      execution_id: execution_id,
      execution_pid: execution_pid,
      params: execution.parameters || %{},
      allow_hazardous_commands: Map.get(version, :allow_hazardous_commands, false)
    }
  end

  @spec procedure_kind(term()) :: :dag | :script | :unknown
  def procedure_kind(:dag), do: :dag
  def procedure_kind(:script), do: :script
  def procedure_kind(_), do: :unknown

  @spec dag_source(term()) :: {:ok, map()} | {:error, String.t()}
  def dag_source(%{"steps" => steps} = source) when is_map(steps), do: {:ok, source}
  def dag_source(_), do: {:error, "Invalid DAG source: 'steps' must be a map"}

  @spec script_source(term()) :: {:ok, String.t()} | {:error, String.t()}
  def script_source(%{"code" => code}) when is_binary(code), do: {:ok, code}
  def script_source(_), do: {:error, "Invalid script source: missing 'code' key"}

  @spec execution_mode(atom()) :: {:ok, :dag | :script} | {:error, String.t()}
  def execution_mode(:dag), do: {:ok, :dag}
  def execution_mode(:script), do: {:ok, :script}
  def execution_mode(_), do: {:error, "Unknown procedure type"}

  @spec dag_start_message(non_neg_integer()) :: String.t()
  def dag_start_message(step_count) do
    "Executing DAG sequence with #{step_count} steps"
  end

  @spec dag_completed_message() :: String.t()
  def dag_completed_message do
    "DAG execution completed successfully"
  end

  @spec dag_failed_message([String.t()] | nil) :: String.t()
  def dag_failed_message(failed_steps) do
    failed_names = Enum.join(failed_steps || [], ", ")
    "DAG execution failed: steps failed: #{failed_names}"
  end

  @spec dag_paused_message() :: String.t()
  def dag_paused_message do
    "DAG execution paused"
  end

  @spec dag_paused_summary(non_neg_integer()) :: String.t()
  def dag_paused_summary(completed_count) do
    "DAG execution paused: #{completed_count} completed so far"
  end

  @spec control_signal_received(atom(), String.t()) :: String.t()
  def control_signal_received(signal, execution_id) do
    "Received control signal #{inspect(signal)} for execution #{execution_id}"
  end

  @spec pause_requested_message() :: String.t()
  def pause_requested_message do
    "Pause requested, waiting for current step to complete..."
  end

  @spec command_sent_message(String.t(), String.t()) :: String.t()
  def command_sent_message(name, log_id) do
    "Command sent: #{name} (log_id: #{log_id})"
  end

  @spec command_failed_message(String.t(), term()) :: String.t()
  def command_failed_message(name, reason) do
    "Command failed: #{name} - #{inspect(reason)}"
  end

  @spec wait_message(non_neg_integer()) :: String.t()
  def wait_message(milliseconds) do
    "Waiting #{milliseconds}ms"
  end

  @spec wait_for_message(String.t(), String.t(), term()) :: String.t()
  def wait_for_message(item, op, value) do
    "Waiting for #{item} #{op} #{inspect(value)}"
  end

  @spec abort_requested_message(String.t()) :: String.t()
  def abort_requested_message(message) do
    "Abort requested: #{message}"
  end

  @spec checkpoint_message(String.t(), non_neg_integer()) :: String.t()
  def checkpoint_message(name, step_index) do
    "Checkpoint reached: #{name} at step #{step_index}"
  end

  @spec execution_starting_message(String.t()) :: String.t()
  def execution_starting_message(execution_id) do
    "Starting ExecutionProcess for execution_id=#{execution_id}"
  end

  @spec execution_terminating_message(String.t(), term()) :: String.t()
  def execution_terminating_message(execution_id, reason) do
    "ExecutionProcess terminating: execution_id=#{execution_id}, reason=#{inspect(reason)}"
  end

  @spec execute_next_message(term()) :: String.t()
  def execute_next_message(procedure_type) do
    "execute_next: procedure.type=#{inspect(procedure_type)}"
  end

  @spec dag_executor_crashed_message(term()) :: String.t()
  def dag_executor_crashed_message(reason) do
    "DAG executor crashed: #{inspect(reason)}"
  end

  @spec dag_executor_failure_reason(term()) :: String.t()
  def dag_executor_failure_reason(reason) do
    "DAG executor crashed: #{inspect(reason)}"
  end

  @spec dag_persist_failure_message() :: String.t()
  def dag_persist_failure_message do
    "Failed to update DAG execution status"
  end

  @spec dag_update_failure_message(term()) :: String.t()
  def dag_update_failure_message(reason) do
    "Failed to update DAG execution: #{inspect(reason)}"
  end

  @spec status_update_failure_message(atom()) :: String.t()
  def status_update_failure_message(new_status) do
    "Failed to update execution status to #{new_status}"
  end

  @spec forward_signal_message(atom(), pid()) :: String.t()
  def forward_signal_message(signal, pid) do
    "Forwarded #{signal} signal to DAG executor #{inspect(pid)}"
  end

  @spec dag_completion_summary(non_neg_integer(), non_neg_integer()) :: String.t()
  def dag_completion_summary(completed_count, skipped_count) do
    "DAG execution completed: #{completed_count} completed, #{skipped_count} skipped"
  end

  @spec pause_transition() :: transition()
  def pause_transition do
    %{
      status: :paused,
      attrs: %{},
      log_level: :info,
      log_message: "Execution paused"
    }
  end

  @spec abort_transition(integer(), String.t() | nil) :: transition()
  def abort_transition(step_index, message \\ nil) do
    if is_binary(message) do
      %{
        status: :failed,
        attrs: %{error_message: message, error_step_index: step_index},
        log_level: :error,
        log_message: "Execution aborted: #{message}"
      }
    else
      %{
        status: :cancelled,
        attrs: %{},
        log_level: :warn,
        log_message: "Execution cancelled"
      }
    end
  end

  @spec failure_transition(integer(), term()) :: transition()
  def failure_transition(step_index, reason) do
    error_message = format_error_reason(reason)

    %{
      status: :failed,
      attrs: %{error_message: error_message, error_step_index: step_index},
      log_level: :error,
      log_message: "Step #{step_index} failed: #{error_message}"
    }
  end

  @spec completion_transition(DateTime.t()) :: transition()
  def completion_transition(now) do
    %{
      status: :completed,
      attrs: %{completed_at: now},
      log_level: :info,
      log_message: "Execution completed successfully"
    }
  end

  @spec format_error_reason(term()) :: String.t()
  def format_error_reason(reason) when is_binary(reason), do: reason
  def format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  def format_error_reason(reason) when is_list(reason), do: inspect(reason)
  def format_error_reason({:lua_error, error, _stacktrace}), do: "Lua error: #{inspect(error)}"
  def format_error_reason(reason), do: inspect(reason)

  @spec step_event_type(atom()) :: String.t()
  def step_event_type(:running), do: "procedure_step_started"
  def step_event_type(:completed), do: "procedure_step_completed"
  def step_event_type(:failed), do: "procedure_step_failed"
  def step_event_type(:skipped), do: "procedure_step_skipped"
  def step_event_type(:blocked), do: "procedure_step_blocked"
  def step_event_type(:timed_out), do: "procedure_step_timed_out"
  def step_event_type(_), do: "procedure_step_status"

  @spec step_status_to_log(atom(), String.t(), term()) :: {atom(), String.t()}
  def step_status_to_log(:running, step_name, _data) do
    {:info, "Step started: #{step_name}"}
  end

  def step_status_to_log(:completed, step_name, _data) do
    {:info, "Step completed: #{step_name}"}
  end

  def step_status_to_log(:failed, step_name, data) do
    reason = extract_error_from_data(data)
    {:error, "Step failed: #{step_name} - #{reason}"}
  end

  def step_status_to_log(:blocked, step_name, _data) do
    {:warn, "Step blocked: #{step_name}"}
  end

  def step_status_to_log(:skipped, step_name, _data) do
    {:info, "Step skipped: #{step_name}"}
  end

  def step_status_to_log(:timed_out, step_name, _data) do
    {:error, "Step timed out: #{step_name}"}
  end

  def step_status_to_log(status, step_name, _data) do
    {:info, "Step #{status}: #{step_name}"}
  end

  @spec dag_status_to_event(atom(), String.t(), term()) :: tuple()
  def dag_status_to_event(:running, step_name, data), do: {:dag_step_started, step_name, data}
  def dag_status_to_event(:completed, step_name, data), do: {:dag_step_completed, step_name, data}
  def dag_status_to_event(:failed, step_name, data), do: {:dag_step_failed, step_name, data}
  def dag_status_to_event(:blocked, step_name, data), do: {:dag_step_blocked, step_name, data}
  def dag_status_to_event(:skipped, step_name, data), do: {:dag_step_skipped, step_name, data}
  def dag_status_to_event(:timed_out, step_name, data), do: {:dag_step_timed_out, step_name, data}

  def dag_status_to_event(status, step_name, data),
    do: {:dag_step_status, step_name, status, data}

  defp extract_error_from_data(data) when is_map(data) do
    Map.get(data, :error) || Map.get(data, "error") || inspect(data)
  end

  defp extract_error_from_data(data), do: inspect(data)
end
