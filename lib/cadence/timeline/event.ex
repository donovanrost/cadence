defmodule Cadence.Timeline.Event do
  @moduledoc """
  Normalized timeline event struct for UI consumption.

  All event sources (commands, alarms, procedures, automations) are
  transformed into this common structure for unified display in the
  Timeline Mode.
  """

  @type event_type :: :command | :alarm | :procedure | :automation | :system
  @type status :: :pending | :success | :error | :active | :cleared | :running | :completed | :failed

  @type t :: %__MODULE__{
          id: binary(),
          type: event_type(),
          timestamp: DateTime.t(),
          target_id: binary() | nil,
          target_name: String.t() | nil,
          target_group: String.t() | nil,
          title: String.t(),
          description: String.t() | nil,
          status: status(),
          status_label: String.t() | nil,
          user_id: binary() | nil,
          user_name: String.t() | nil,
          is_future: boolean(),
          metadata: map(),
          source_id: binary(),
          source_table: atom()
        }

  defstruct [
    :id,
    :type,
    :timestamp,
    :target_id,
    :target_name,
    :target_group,
    :title,
    :description,
    :status,
    :status_label,
    :user_id,
    :user_name,
    :is_future,
    :metadata,
    :source_id,
    :source_table
  ]

  @doc """
  Convert a CommandLog to a Timeline.Event.
  """
  def from_command_log(%Cadence.Commands.CommandLog{} = log, opts \\ []) do
    target = Keyword.get(opts, :target)
    user = Keyword.get(opts, :user)

    %__MODULE__{
      id: "cmd-#{log.id}",
      type: :command,
      timestamp: log.sent_at || log.inserted_at,
      target_id: log.target_id,
      target_name: target && target.name,
      target_group: nil,
      title: log.command_name,
      description: build_command_description(log),
      status: map_command_status(log.status),
      status_label: format_command_status(log.status),
      user_id: log.user_id,
      user_name: user && user.email,
      is_future: false,
      metadata: %{
        opcode: log.opcode,
        parameters: log.parameters,
        verification_status: log.verification_status,
        verification_stages_completed: log.verification_stages_completed,
        error_reason: log.error_reason,
        sent_at: log.sent_at,
        verified_at: log.verified_at
      },
      source_id: log.id,
      source_table: :command_logs
    }
  end

  @doc """
  Convert an AlarmEvent to a Timeline.Event.
  """
  def from_alarm_event(%Cadence.Alarms.AlarmEvent{} = event, opts \\ []) do
    alarm = Keyword.get(opts, :alarm)
    target = Keyword.get(opts, :target)
    user = Keyword.get(opts, :user)

    %__MODULE__{
      id: "alm-#{event.id}",
      type: :alarm,
      timestamp: event.inserted_at,
      target_id: alarm && alarm.target_id,
      target_name: target && target.name,
      target_group: nil,
      title: (alarm && (alarm.message || alarm.alarm_type)) || "Alarm",
      description: build_alarm_description(event, alarm),
      status: map_alarm_event_status(event.event_type),
      status_label: format_alarm_event_type(event.event_type),
      user_id: event.user_id,
      user_name: user && user.email,
      is_future: false,
      metadata: %{
        event_type: event.event_type,
        severity: alarm && alarm.severity,
        trigger_value: event.trigger_value,
        note: event.note,
        previous_state: event.previous_state,
        new_state: event.new_state
      },
      source_id: event.id,
      source_table: :alarm_events
    }
  end

  @doc """
  Convert a ProcedureExecution to a Timeline.Event.
  """
  def from_procedure_execution(%Cadence.Procedures.ProcedureExecution{} = exec, opts \\ []) do
    procedure = Keyword.get(opts, :procedure)
    target = Keyword.get(opts, :target)
    user = Keyword.get(opts, :user)

    %__MODULE__{
      id: "proc-#{exec.id}",
      type: :procedure,
      timestamp: exec.started_at || exec.inserted_at,
      target_id: exec.target_id,
      target_name: target && target.name,
      target_group: nil,
      title: (procedure && procedure.name) || "Procedure",
      description: build_procedure_description(exec),
      status: map_procedure_status(exec.status),
      status_label: format_procedure_status(exec.status),
      user_id: exec.triggered_by_user_id,
      user_name: user && user.email,
      is_future: exec.status == :pending,
      metadata: %{
        procedure_id: exec.procedure_id,
        triggered_by: exec.triggered_by,
        current_step_index: exec.current_step_index,
        error_message: exec.error_message,
        started_at: exec.started_at,
        completed_at: exec.completed_at
      },
      source_id: exec.id,
      source_table: :procedure_executions
    }
  end

  @doc """
  Convert a scheduled command (QueueEntry with future scheduled_at) to a Timeline.Event.
  """
  def from_scheduled_command(%Cadence.Commands.QueueEntry{} = entry, opts \\ []) do
    target = Keyword.get(opts, :target)
    user = Keyword.get(opts, :user)

    %__MODULE__{
      id: "sched-cmd-#{entry.id}",
      type: :command,
      timestamp: entry.scheduled_at,
      target_id: entry.target_id,
      target_name: target && target.name,
      target_group: nil,
      title: entry.command_name,
      description: "Scheduled",
      status: :pending,
      status_label: "SCHEDULED",
      user_id: entry.user_id,
      user_name: user && user.email,
      is_future: true,
      metadata: %{
        parameters: entry.parameters,
        priority: entry.priority,
        scheduled_at: entry.scheduled_at
      },
      source_id: entry.id,
      source_table: :command_queue_entries
    }
  end

  # Private helpers

  defp build_command_description(%{status: :verified, verified_at: verified_at, sent_at: sent_at})
       when not is_nil(verified_at) and not is_nil(sent_at) do
    delta_ms = DateTime.diff(verified_at, sent_at, :millisecond)
    "Verified in #{format_duration(delta_ms)}"
  end

  defp build_command_description(%{status: :error, error_reason: reason}) when is_binary(reason) do
    "Error: #{reason}"
  end

  defp build_command_description(%{status: :verification_failed, error_reason: reason})
       when is_binary(reason) do
    "Verification failed: #{reason}"
  end

  defp build_command_description(%{status: :rejected, error_reason: reason})
       when is_binary(reason) do
    "Rejected: #{reason}"
  end

  defp build_command_description(_), do: nil

  defp build_alarm_description(event, alarm) do
    case event.event_type do
      :triggered ->
        if event.trigger_value do
          "Triggered at #{event.trigger_value}"
        else
          "Triggered"
        end

      :acknowledged ->
        "Acknowledged"

      :cleared ->
        "Cleared"

      :shelved ->
        "Shelved"

      :unshelved ->
        "Unshelved"

      :escalated ->
        "Escalated to #{alarm && alarm.severity}"

      _ ->
        to_string(event.event_type)
    end
  end

  defp build_procedure_description(%{status: :completed, completed_at: completed_at, started_at: started_at})
       when not is_nil(completed_at) and not is_nil(started_at) do
    delta_ms = DateTime.diff(completed_at, started_at, :millisecond)
    "Completed in #{format_duration(delta_ms)}"
  end

  defp build_procedure_description(%{status: :failed, error_message: msg}) when is_binary(msg) do
    "Failed: #{msg}"
  end

  defp build_procedure_description(%{status: :running, current_step_index: idx})
       when is_integer(idx) do
    "Running step #{idx + 1}"
  end

  defp build_procedure_description(%{status: status}), do: to_string(status)

  defp map_command_status(:verified), do: :success
  defp map_command_status(:sent), do: :pending
  defp map_command_status(:pending), do: :pending
  defp map_command_status(:error), do: :error
  defp map_command_status(:verification_failed), do: :error
  defp map_command_status(:rejected), do: :error
  defp map_command_status(_), do: :pending

  defp format_command_status(:verified), do: "VERIFIED"
  defp format_command_status(:sent), do: "SENT"
  defp format_command_status(:pending), do: "PENDING"
  defp format_command_status(:error), do: "ERROR"
  defp format_command_status(:verification_failed), do: "VERIFY FAILED"
  defp format_command_status(:rejected), do: "REJECTED"
  defp format_command_status(status), do: status |> to_string() |> String.upcase()

  defp map_alarm_event_status(:triggered), do: :active
  defp map_alarm_event_status(:cleared), do: :cleared
  defp map_alarm_event_status(:acknowledged), do: :active
  defp map_alarm_event_status(:shelved), do: :active
  defp map_alarm_event_status(_), do: :active

  defp format_alarm_event_type(:triggered), do: "TRIGGERED"
  defp format_alarm_event_type(:cleared), do: "CLEARED"
  defp format_alarm_event_type(:acknowledged), do: "ACKNOWLEDGED"
  defp format_alarm_event_type(:shelved), do: "SHELVED"
  defp format_alarm_event_type(:unshelved), do: "UNSHELVED"
  defp format_alarm_event_type(:escalated), do: "ESCALATED"
  defp format_alarm_event_type(type), do: type |> to_string() |> String.upcase()

  defp map_procedure_status(:completed), do: :completed
  defp map_procedure_status(:running), do: :running
  defp map_procedure_status(:pending), do: :pending
  defp map_procedure_status(:failed), do: :failed
  defp map_procedure_status(:paused), do: :running
  defp map_procedure_status(:cancelled), do: :error
  defp map_procedure_status(_), do: :pending

  defp format_procedure_status(:completed), do: "COMPLETED"
  defp format_procedure_status(:running), do: "RUNNING"
  defp format_procedure_status(:pending), do: "PENDING"
  defp format_procedure_status(:failed), do: "FAILED"
  defp format_procedure_status(:paused), do: "PAUSED"
  defp format_procedure_status(:cancelled), do: "CANCELLED"
  defp format_procedure_status(status), do: status |> to_string() |> String.upcase()

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"
end
