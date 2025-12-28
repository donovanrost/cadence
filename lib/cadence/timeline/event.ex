defmodule Cadence.Timeline.Event do
  @moduledoc """
  Normalized timeline event struct for UI consumption.

  All event sources (commands, alarms, procedures, automations) are
  transformed into this common structure for unified display in the
  Timeline Mode.
  """

  alias Cadence.Recordings.Recordable
  alias Cadence.Recordings.Recording

  @type event_type :: :command | :alarm | :procedure | :automation | :system
  @type status ::
          :pending | :success | :error | :active | :cleared | :running | :completed | :failed

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
  Convert a Recording to a Timeline.Event.

  Uses the Recordable protocol to extract display information from the
  associated recordable.
  """
  def from_recording(%Recording{} = recording, opts \\ []) do
    target = Keyword.get(opts, :target)
    user = Keyword.get(opts, :user)

    # Load the recordable if not already loaded
    recordable = Keyword.get(opts, :recordable) || Cadence.Recordings.load_recordable(recording)

    # Use the Recordable protocol for display info
    title = if recordable, do: Recordable.title(recordable), else: recording.recordable_type
    status_str = if recordable, do: Recordable.status(recordable), else: "pending"
    severity = if recordable, do: Recordable.severity(recordable), else: nil

    %__MODULE__{
      id: "rec-#{recording.id}",
      type: map_aggregate_to_event_type(recording.aggregate_type),
      timestamp: recording.timestamp,
      target_id: nil,
      target_name: target && target.name,
      target_group: nil,
      title: title,
      description: recording.recordable_type,
      status: map_status_string(status_str),
      status_label: String.upcase(status_str || "PENDING"),
      user_id: recording.actor_id,
      user_name: user && user.email,
      is_future: false,
      metadata: %{
        recordable_type: recording.recordable_type,
        aggregate_type: recording.aggregate_type,
        aggregate_id: recording.aggregate_id,
        severity: severity,
        parent_id: recording.parent_id,
        root_id: recording.root_id,
        bucket_id: recording.bucket_id
      },
      source_id: recording.id,
      source_table: :recordings
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

  defp map_aggregate_to_event_type("Command"), do: :command
  defp map_aggregate_to_event_type("Alarm"), do: :alarm
  defp map_aggregate_to_event_type("ProcedureExecution"), do: :procedure
  defp map_aggregate_to_event_type("ProcedureVersion"), do: :procedure
  defp map_aggregate_to_event_type("Automation"), do: :automation
  defp map_aggregate_to_event_type("QueueEntry"), do: :command
  defp map_aggregate_to_event_type(_), do: :system

  defp map_status_string("pending"), do: :pending
  defp map_status_string("sent"), do: :pending
  defp map_status_string("verified"), do: :success
  defp map_status_string("error"), do: :error
  defp map_status_string("failed"), do: :error
  defp map_status_string("active"), do: :active
  defp map_status_string("triggered"), do: :active
  defp map_status_string("cleared"), do: :cleared
  defp map_status_string("acknowledged"), do: :active
  defp map_status_string("running"), do: :running
  defp map_status_string("completed"), do: :completed
  defp map_status_string("draft"), do: :pending
  defp map_status_string("pending_review"), do: :pending
  defp map_status_string("approved"), do: :success
  defp map_status_string("rejected"), do: :error
  defp map_status_string(_), do: :pending

  defp build_procedure_description(%{
         status: :completed,
         completed_at: completed_at,
         started_at: started_at
       })
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
