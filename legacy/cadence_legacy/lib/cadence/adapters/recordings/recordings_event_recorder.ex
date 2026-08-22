defmodule Cadence.Adapters.Recordings.RecordingsEventRecorder do
  @moduledoc """
  Production adapter for recording domain events.

  Implements the EventRecorder port by mapping domain events to recordable
  modules and calling the Recordings context.

  This adapter:
  - Maps domain event types to their corresponding recordable modules
  - Extracts relevant attributes from domain entities
  - Builds recording context from entity fields
  - Creates recordings via Recordings.create/3
  """

  @behaviour Cadence.Ports.Recordings.EventRecorder

  alias Cadence.Recordings
  alias Cadence.Recordings.Recordables
  alias Cadence.Time, as: CadenceTime

  # ===========================================================================
  # EventRecorder Implementation
  # ===========================================================================

  @impl true
  def record(event_type, aggregate, actor_id, attrs) do
    context = build_context_from_aggregate(aggregate, actor_id)
    record_with_context(event_type, aggregate, actor_id, attrs, context)
  end

  @impl true
  def record_with_context(event_type, aggregate, actor_id, attrs, context) do
    with {:ok, recordable_module} <- get_recordable_module(event_type),
         recordable_attrs <- build_recordable_attrs(event_type, aggregate, attrs),
         recording_attrs <- build_recording_attrs(aggregate, actor_id, context) do
      case Recordings.create(recordable_module, recordable_attrs, recording_attrs) do
        {:ok, _result} -> :ok
        {:error, _operation, changeset, _changes} -> {:error, changeset_to_error(changeset)}
      end
    end
  end

  # ===========================================================================
  # Event Type to Recordable Module Mapping
  # ===========================================================================

  @event_module_map %{
    # Alarm events
    alarm_triggered: Recordables.AlarmTriggered,
    alarm_acknowledged: Recordables.AlarmAcknowledged,
    alarm_cleared: Recordables.AlarmCleared,
    alarm_shelved: Recordables.AlarmShelved,
    alarm_unshelved: Recordables.AlarmUnshelved,
    alarm_escalated: Recordables.AlarmEscalated,
    alarm_value_updated: Recordables.AlarmValueUpdated,
    # Queue events
    command_queued: Recordables.CommandQueued,
    command_dequeued: Recordables.CommandDequeued,
    # Procedure version events
    procedure_version_created: Recordables.ProcedureVersionCreated,
    procedure_version_submitted: Recordables.ProcedureVersionSubmitted,
    procedure_version_approved: Recordables.ProcedureVersionApproved,
    procedure_version_rejected: Recordables.ProcedureVersionRejected,
    procedure_version_withdrawn: Recordables.ProcedureVersionWithdrawn,
    procedure_version_deprecated: Recordables.ProcedureVersionDeprecated,
    # Automation events
    automation_triggered: Recordables.AutomationTriggered,
    automation_completed: Recordables.AutomationCompleted,
    automation_failed: Recordables.AutomationFailed,
    automation_skipped: Recordables.AutomationSkipped,
    # Contact lifecycle events
    contact_started: Recordables.ContactStarted,
    contact_ended: Recordables.ContactEnded,
    contact_activation_failed: Recordables.ContactActivationFailed,
    contact_blocked: Recordables.ContactBlocked,
    contact_skipped: Recordables.ContactSkipped,
    contact_ready: Recordables.ContactReady,
    contact_action_dispatched: Recordables.ContactActionDispatched,
    contact_action_completed: Recordables.ContactActionCompleted,
    contact_action_failed: Recordables.ContactActionFailed,
    contact_action_skipped: Recordables.ContactActionSkipped
  }

  defp get_recordable_module(event_type) do
    case Map.get(@event_module_map, event_type) do
      nil -> {:error, {:unknown_event_type, event_type}}
      module -> {:ok, module}
    end
  end

  # ===========================================================================
  # Recordable Attributes Building
  # ===========================================================================

  # Alarm events
  defp build_recordable_attrs(:alarm_triggered, alarm, _attrs) do
    %{
      alarm_type: alarm.alarm_type,
      severity: to_string(alarm.severity),
      source_type: alarm.source_type,
      source_id: alarm.source_id,
      message: alarm.message,
      current_value: alarm.current_value,
      limit_state: alarm.limit_state && to_string(alarm.limit_state)
    }
  end

  defp build_recordable_attrs(:alarm_acknowledged, _alarm, attrs) do
    %{note: Map.get(attrs, :note)}
  end

  defp build_recordable_attrs(:alarm_cleared, alarm, attrs) do
    %{
      clear_type: Map.get(attrs, :clear_type, :manual),
      final_value: alarm.current_value
    }
  end

  defp build_recordable_attrs(:alarm_shelved, alarm, _attrs) do
    %{
      duration_minutes: calculate_shelve_duration(alarm),
      reason: alarm.shelve_reason
    }
  end

  defp build_recordable_attrs(:alarm_unshelved, _alarm, attrs) do
    %{
      unshelve_type: Map.get(attrs, :unshelve_type, :manual)
    }
  end

  defp build_recordable_attrs(:alarm_escalated, alarm, attrs) do
    %{
      from_severity: to_string(Map.get(attrs, :from_severity)),
      to_severity: to_string(alarm.severity)
    }
  end

  defp build_recordable_attrs(:alarm_value_updated, _alarm, attrs) do
    %{
      trigger_value: Map.get(attrs, :trigger_value),
      previous_value: Map.get(attrs, :previous_value)
    }
  end

  # Queue events
  defp build_recordable_attrs(:command_queued, cmd, _attrs) do
    %{
      command_name: cmd.command_name,
      parameters: cmd.parameters,
      priority: cmd.priority,
      scheduled_at: cmd.scheduled_at,
      expires_at: cmd.expires_at,
      max_attempts: cmd.max_attempts,
      dispatch_opts: cmd.dispatch_opts
    }
  end

  defp build_recordable_attrs(:command_dequeued, cmd, attrs) do
    %{
      command_name: cmd.command_name,
      reason: Map.get(attrs, :reason, to_string(cmd.status))
    }
  end

  # Contact readiness & action events
  defp build_recordable_attrs(:contact_ready, _aggregate, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      gate: Map.get(attrs, :gate),
      details: Map.get(attrs, :details, %{})
    }
  end

  defp build_recordable_attrs(:contact_action_dispatched, _aggregate, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      contact_action_id: Map.get(attrs, :contact_action_id),
      gate: Map.get(attrs, :gate),
      command_ref: Map.get(attrs, :command_ref, %{}),
      details: Map.get(attrs, :details, %{})
    }
  end

  defp build_recordable_attrs(:contact_action_completed, _aggregate, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      contact_action_id: Map.get(attrs, :contact_action_id),
      result: Map.get(attrs, :result, %{})
    }
  end

  defp build_recordable_attrs(:contact_action_failed, _aggregate, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      contact_action_id: Map.get(attrs, :contact_action_id),
      error_code: Map.get(attrs, :error_code),
      error_message: Map.get(attrs, :error_message),
      details: Map.get(attrs, :details, %{})
    }
  end

  defp build_recordable_attrs(:contact_action_skipped, _aggregate, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      contact_action_id: Map.get(attrs, :contact_action_id),
      reason: Map.get(attrs, :reason),
      details: Map.get(attrs, :details, %{})
    }
  end

  # Procedure version events
  defp build_recordable_attrs(:procedure_version_created, version, _attrs) do
    %{
      version_number: version.version_number,
      description: version.description,
      change_summary: version.change_summary
    }
  end

  defp build_recordable_attrs(:procedure_version_submitted, _version, _attrs) do
    %{}
  end

  defp build_recordable_attrs(:procedure_version_approved, _version, _attrs) do
    %{}
  end

  defp build_recordable_attrs(:procedure_version_rejected, version, _attrs) do
    %{reason: version.rejection_reason}
  end

  defp build_recordable_attrs(:procedure_version_withdrawn, _version, _attrs) do
    %{}
  end

  defp build_recordable_attrs(:procedure_version_deprecated, _version, _attrs) do
    %{}
  end

  # Automation events
  defp build_recordable_attrs(:automation_triggered, automation, attrs) do
    %{
      automation_id: automation.id,
      trigger_type: automation.trigger_type,
      trigger_event: Map.get(attrs, :trigger_event)
    }
  end

  defp build_recordable_attrs(:automation_completed, _automation, attrs) do
    %{
      action_result: Map.get(attrs, :action_result)
    }
  end

  defp build_recordable_attrs(:automation_failed, _automation, attrs) do
    %{
      error_message: Map.get(attrs, :error_message)
    }
  end

  defp build_recordable_attrs(:automation_skipped, _automation, attrs) do
    %{
      reason: Map.get(attrs, :reason)
    }
  end

  # Contact lifecycle events
  defp build_recordable_attrs(:contact_started, _contact, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      spacecraft_target_id: Map.get(attrs, :spacecraft_target_id),
      ground_station_target_id: Map.get(attrs, :ground_station_target_id),
      antenna_id: Map.get(attrs, :antenna_id),
      direction: Map.get(attrs, :direction),
      resolved_transport_ids: Map.get(attrs, :resolved_transport_ids, [])
    }
  end

  defp build_recordable_attrs(:contact_ended, _contact, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      spacecraft_target_id: Map.get(attrs, :spacecraft_target_id),
      ground_station_target_id: Map.get(attrs, :ground_station_target_id),
      antenna_id: Map.get(attrs, :antenna_id),
      direction: Map.get(attrs, :direction),
      reason: Map.get(attrs, :reason, "completed")
    }
  end

  defp build_recordable_attrs(:contact_activation_failed, _contact, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      spacecraft_target_id: Map.get(attrs, :spacecraft_target_id),
      ground_station_target_id: Map.get(attrs, :ground_station_target_id),
      antenna_id: Map.get(attrs, :antenna_id),
      direction: Map.get(attrs, :direction),
      error_code: Map.get(attrs, :error_code),
      error_message: Map.get(attrs, :error_message),
      details: Map.get(attrs, :details, %{})
    }
  end

  defp build_recordable_attrs(:contact_blocked, _contact, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      spacecraft_target_id: Map.get(attrs, :spacecraft_target_id),
      ground_station_target_id: Map.get(attrs, :ground_station_target_id),
      antenna_id: Map.get(attrs, :antenna_id),
      direction: Map.get(attrs, :direction),
      blocked_by_contact_id: Map.get(attrs, :blocked_by_contact_id),
      policy: Map.get(attrs, :policy),
      message: Map.get(attrs, :message),
      details: Map.get(attrs, :details, %{})
    }
  end

  defp build_recordable_attrs(:contact_skipped, _contact, attrs) do
    %{
      mission_id: Map.get(attrs, :mission_id),
      contact_id: Map.get(attrs, :contact_id),
      spacecraft_target_id: Map.get(attrs, :spacecraft_target_id),
      ground_station_target_id: Map.get(attrs, :ground_station_target_id),
      antenna_id: Map.get(attrs, :antenna_id),
      direction: Map.get(attrs, :direction),
      reason: Map.get(attrs, :reason, "resource_unavailable"),
      details: Map.get(attrs, :details, %{})
    }
  end

  # ===========================================================================
  # Recording Attributes Building
  # ===========================================================================

  defp build_recording_attrs(aggregate, actor_id, context) do
    %{
      organization_id: get_organization_id(aggregate, context),
      bucket_id: Map.get(context, :bucket_id),
      aggregate_id: get_aggregate_id(aggregate),
      actor_id: actor_id,
      actor_type: if(actor_id, do: "user", else: "system"),
      parent_id: Map.get(context, :parent_id),
      root_id: Map.get(context, :root_id),
      timestamp: CadenceTime.now()
    }
  end

  defp build_context_from_aggregate(aggregate, _actor_id) do
    %{
      organization_id: get_organization_id(aggregate, %{}),
      mission_id: get_mission_id(aggregate),
      target_id: get_target_id(aggregate)
    }
  end

  # ===========================================================================
  # Entity Field Extractors
  # ===========================================================================

  defp get_organization_id(aggregate, context) do
    Map.get(context, :organization_id) ||
      Map.get(aggregate, :organization_id)
  end

  defp get_mission_id(aggregate) do
    Map.get(aggregate, :mission_id)
  end

  defp get_target_id(aggregate) do
    Map.get(aggregate, :target_id)
  end

  defp get_aggregate_id(aggregate) do
    # For queue entries and commands, prefer command_aggregate_id for consistent lifecycle tracking
    Map.get(aggregate, :command_aggregate_id) || Map.get(aggregate, :id)
  end

  defp calculate_shelve_duration(%{shelved_at: shelved_at, shelved_until: shelved_until})
       when not is_nil(shelved_at) and not is_nil(shelved_until) do
    div(DateTime.diff(shelved_until, shelved_at, :second), 60)
  end

  defp calculate_shelve_duration(_), do: nil

  # ===========================================================================
  # Error Handling
  # ===========================================================================

  defp changeset_to_error(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    {:validation, errors}
  end

  defp changeset_to_error(error), do: error
end
