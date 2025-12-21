defmodule Cadence.Application.Alerting.AlarmOperations do
  @moduledoc """
  Use case module for alarm state transitions.

  This module provides operations for changing alarm state:
  acknowledge, shelve, unshelve, clear, and value updates.

  All operations:
  1. Validate the transition using domain entity logic
  2. Persist the change via repository
  3. Record the event for audit trail
  4. Broadcast for cache/UI updates

  ## Usage

      # Acknowledge an alarm
      {:ok, alarm} = AlarmOperations.acknowledge(alarm_id, user_id, "Investigating")

      # Shelve for 30 minutes
      {:ok, alarm} = AlarmOperations.shelve(alarm_id, user_id, 30, "Known transient")

      # Clear an alarm
      {:ok, alarm} = AlarmOperations.clear(alarm_id)
  """

  alias Cadence.Domain.Alerting.Entities.Alarm
  alias Cadence.Application.Alerting.AlarmQueries

  @type alarm_id :: String.t()
  @type user_id :: String.t()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :alarm_repository,
      Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository
    )
  end

  # Get configured event publisher
  defp event_publisher do
    Application.get_env(
      :cadence,
      :event_publisher,
      Cadence.Adapters.Messaging.PhoenixEventPublisher
    )
  end

  # Get configured event recorder
  defp recorder do
    Cadence.Ports.Recordings.EventRecorder.impl()
  end

  @doc """
  Acknowledges an alarm.

  Transitions the alarm from `:active` to `:acknowledged` status.
  Records the user who acknowledged and optional note.

  ## Parameters

  - `alarm_id` - UUID of the alarm to acknowledge
  - `user_id` - UUID of the user acknowledging (nil for system)
  - `note` - Optional acknowledgment note

  ## Returns

  - `{:ok, alarm}` - Successfully acknowledged
  - `{:error, :not_found}` - Alarm not found
  - `{:error, {:invalid_transition, from, to}}` - Invalid state transition
  """
  @spec acknowledge(alarm_id(), user_id() | nil, String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def acknowledge(alarm_id, user_id, note \\ nil) do
    with {:ok, alarm} <- AlarmQueries.find(alarm_id),
         {:ok, updated} <- Alarm.acknowledge(alarm, user_id, note),
         {:ok, saved} <- repo().save(updated) do
      broadcast_alarm_change(saved, :acknowledged)
      record_acknowledged(saved, user_id, note)
      {:ok, saved}
    end
  end

  @doc """
  Shelves an alarm for a specified duration.

  Temporarily silences the alarm until the shelve period expires.
  Can shelve from `:active` or `:acknowledged` status.

  ## Parameters

  - `alarm_id` - UUID of the alarm to shelve
  - `user_id` - UUID of the user shelving (nil for system)
  - `duration_minutes` - How long to shelve (must be positive)
  - `reason` - Optional reason for shelving

  ## Returns

  - `{:ok, alarm}` - Successfully shelved
  - `{:error, :not_found}` - Alarm not found
  - `{:error, :invalid_duration}` - Duration not positive
  - `{:error, {:invalid_transition, from, to}}` - Invalid state transition
  """
  @spec shelve(alarm_id(), user_id() | nil, pos_integer(), String.t() | nil) ::
          {:ok, Alarm.t()} | {:error, term()}
  def shelve(alarm_id, user_id, duration_minutes, reason \\ nil) do
    with {:ok, alarm} <- AlarmQueries.find(alarm_id),
         {:ok, updated} <- Alarm.shelve(alarm, user_id, duration_minutes, reason),
         {:ok, saved} <- repo().save(updated) do
      broadcast_alarm_change(saved, :shelved)
      record_shelved(saved, user_id, reason)
      {:ok, saved}
    end
  end

  @doc """
  Unshelves an alarm.

  Returns the alarm to its previous state (`:active` or `:acknowledged`).
  Can be triggered manually by a user or automatically on timeout.

  ## Parameters

  - `alarm_id` - UUID of the alarm to unshelve
  - `user_id` - UUID of the user unshelving (nil for timeout)

  ## Returns

  - `{:ok, alarm}` - Successfully unshelved
  - `{:error, :not_found}` - Alarm not found
  - `{:error, {:not_shelved, status}}` - Alarm not in shelved status
  """
  @spec unshelve(alarm_id(), user_id() | nil) :: {:ok, Alarm.t()} | {:error, term()}
  def unshelve(alarm_id, user_id \\ nil) do
    with {:ok, alarm} <- AlarmQueries.find(alarm_id),
         {:ok, updated} <- Alarm.unshelve(alarm),
         {:ok, saved} <- repo().save(updated) do
      unshelve_type = if user_id, do: "manual", else: "timeout"
      broadcast_alarm_change(saved, :unshelved)
      record_unshelved(saved, user_id, unshelve_type)
      {:ok, saved}
    end
  end

  @doc """
  Clears an alarm.

  Transitions the alarm to terminal `:cleared` status.
  Can be triggered manually by a user or automatically when
  the alarm condition is resolved.

  ## Parameters

  - `alarm_id` - UUID of the alarm to clear
  - `user_id` - UUID of the user clearing (nil for automatic)

  ## Returns

  - `{:ok, alarm}` - Successfully cleared
  - `{:error, :not_found}` - Alarm not found
  - `{:error, {:invalid_transition, from, to}}` - Already cleared
  """
  @spec clear(alarm_id(), user_id() | nil) :: {:ok, Alarm.t()} | {:error, term()}
  def clear(alarm_id, user_id \\ nil) do
    with {:ok, alarm} <- AlarmQueries.find(alarm_id),
         {:ok, updated} <- Alarm.clear(alarm),
         {:ok, saved} <- repo().save(updated) do
      clear_type = if user_id, do: "manual", else: "automatic"
      broadcast_alarm_change(saved, :cleared)
      record_cleared(saved, user_id, clear_type)
      {:ok, saved}
    end
  end

  @doc """
  Updates an alarm's current value.

  Used when a telemetry item is still in violation but the value changed.
  Can optionally update severity and limit_state.

  ## Parameters

  - `alarm_id` - UUID of the alarm
  - `value` - New current value
  - `opts` - Options:
    - `:severity` - New severity level
    - `:limit_state` - New limit state

  ## Returns

  - `{:ok, alarm}` - Successfully updated
  - `{:error, :not_found}` - Alarm not found
  """
  @spec update_value(alarm_id(), float(), keyword()) :: {:ok, Alarm.t()} | {:error, term()}
  def update_value(alarm_id, value, opts \\ []) do
    with {:ok, alarm} <- AlarmQueries.find(alarm_id),
         {:ok, updated} <- Alarm.update_value(alarm, value, opts),
         {:ok, saved} <- repo().save(updated) do
      # Only record escalation when severity increased
      if severity_increased?(alarm.severity, saved.severity) do
        record_escalated(saved, alarm.severity, value)
      else
        record_value_updated(saved, alarm.current_value, value)
      end

      broadcast_alarm_change(saved, :updated)
      {:ok, saved}
    end
  end

  defp severity_increased?(old_severity, new_severity) do
    severity_rank(new_severity) > severity_rank(old_severity)
  end

  defp severity_rank(:info), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:critical), do: 2

  @doc """
  Escalates an alarm to a higher severity.

  ## Parameters

  - `alarm_id` - UUID of the alarm
  - `new_severity` - Target severity (must be higher than current)

  ## Returns

  - `{:ok, alarm}` - Successfully escalated
  - `{:error, :not_found}` - Alarm not found
  - `{:error, :cannot_deescalate}` - New severity not higher
  """
  @spec escalate(alarm_id(), :warning | :critical) :: {:ok, Alarm.t()} | {:error, term()}
  def escalate(alarm_id, new_severity) do
    with {:ok, alarm} <- AlarmQueries.find(alarm_id),
         {:ok, updated} <- Alarm.escalate(alarm, new_severity),
         {:ok, saved} <- repo().save(updated) do
      record_escalated(saved, alarm.severity, alarm.current_value)
      broadcast_alarm_change(saved, :escalated)
      {:ok, saved}
    end
  end

  @doc """
  Unshelves all alarms with expired shelve periods.

  Called periodically by a background job.

  ## Returns

  - `{:ok, count}` - Number of alarms unshelved
  """
  @spec unshelve_expired() :: {:ok, non_neg_integer()}
  def unshelve_expired do
    alarms = repo().list_expired_shelved()

    Enum.each(alarms, fn alarm ->
      unshelve(alarm.id, nil)
    end)

    {:ok, length(alarms)}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp broadcast_alarm_change(%Alarm{mission_id: mission_id} = alarm, event_type) do
    topic = "mission:#{mission_id}:alarms"

    event_publisher().publish(topic, %{
      type: :alarm_changed,
      event: event_type,
      alarm_id: alarm.id,
      status: alarm.status,
      severity: alarm.severity
    })
  rescue
    # Don't fail operations if broadcasting fails
    _ -> :ok
  end

  # Recording functions - delegate to event recorder port

  defp record_acknowledged(alarm, user_id, note) do
    recorder().record(:alarm_acknowledged, alarm, user_id, %{note: note})
  end

  defp record_shelved(alarm, user_id, reason) do
    recorder().record(:alarm_shelved, alarm, user_id, %{reason: reason})
  end

  defp record_unshelved(alarm, user_id, unshelve_type) do
    recorder().record(:alarm_unshelved, alarm, user_id, %{unshelve_type: unshelve_type})
  end

  defp record_cleared(alarm, user_id, clear_type) do
    recorder().record(:alarm_cleared, alarm, user_id, %{clear_type: clear_type})
  end

  defp record_escalated(alarm, previous_severity, _value) do
    recorder().record(:alarm_escalated, alarm, nil, %{from_severity: previous_severity})
  end

  defp record_value_updated(alarm, previous_value, new_value) do
    recorder().record(:alarm_value_updated, alarm, nil, %{
      previous_value: previous_value,
      trigger_value: new_value
    })
  end
end
