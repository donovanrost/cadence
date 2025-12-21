defmodule Cadence.Application.Alerting.TriggerAlarm do
  @moduledoc """
  Use case module for triggering new alarms.

  This module handles the creation of new alarms, including:
  - Deduplication (only one active alarm per source)
  - Rule matching
  - Event recording
  - Notification dispatch

  ## Usage

      # Trigger from telemetry violation
      {:ok, alarm, :created} = TriggerAlarm.from_telemetry(%{
        organization_id: org_id,
        mission_id: mission_id,
        target_id: target_id,
        source_id: "HEALTH.cpu_temp",
        severity: :warning,
        current_value: 85.5,
        message: "CPU temp exceeded warning threshold"
      })

      # May return existing alarm if already active
      {:ok, alarm, :existing} = TriggerAlarm.from_telemetry(...)
  """

  alias Cadence.Domain.Alerting.Entities.Alarm
  alias Cadence.Application.Alerting.AlarmQueries

  @type trigger_attrs :: %{
          required(:organization_id) => String.t(),
          required(:mission_id) => String.t(),
          required(:alarm_type) => String.t(),
          required(:severity) => :info | :warning | :critical,
          required(:source_type) => String.t(),
          required(:source_id) => String.t(),
          optional(:target_id) => String.t() | nil,
          optional(:alarm_rule_id) => String.t() | nil,
          optional(:message) => String.t() | nil,
          optional(:current_value) => float() | nil,
          optional(:limit_state) => :yellow | :red | :blue | nil,
          optional(:metadata) => map()
        }

  @type trigger_result :: {:ok, Alarm.t(), :created | :existing} | {:error, term()}

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :alarm_repository,
      Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository
    )
  end

  @doc """
  Triggers an alarm from a telemetry limit violation.

  Handles deduplication - if an active alarm already exists for this
  source, returns the existing alarm instead of creating a duplicate.

  ## Parameters

  - `attrs` - Alarm attributes (see type spec)

  ## Returns

  - `{:ok, alarm, :created}` - New alarm was created
  - `{:ok, alarm, :existing}` - Existing active alarm found
  - `{:error, reason}` - Validation or other error
  """
  @spec from_telemetry(trigger_attrs()) :: trigger_result()
  def from_telemetry(attrs) do
    attrs = Map.merge(attrs, %{
      alarm_type: attrs[:alarm_type] || "telemetry_limit",
      source_type: attrs[:source_type] || "telemetry_item",
      triggered_at: DateTime.utc_now()
    })

    find_or_create(attrs)
  end

  @doc """
  Triggers an alarm from an interface connection event.

  ## Parameters

  - `attrs` - Alarm attributes including:
    - `:source_type` - "interface"
    - `:source_id` - Interface identifier
  """
  @spec from_interface_event(trigger_attrs()) :: trigger_result()
  def from_interface_event(attrs) do
    attrs = Map.merge(attrs, %{
      alarm_type: attrs[:alarm_type] || "interface_connection",
      source_type: "interface",
      triggered_at: DateTime.utc_now()
    })

    find_or_create(attrs)
  end

  @doc """
  Triggers an alarm manually (operator-initiated).

  ## Parameters

  - `attrs` - Alarm attributes
  - `user_id` - UUID of user creating the alarm
  """
  @spec manual(trigger_attrs(), String.t()) :: trigger_result()
  def manual(attrs, user_id) do
    attrs = Map.merge(attrs, %{
      source_origin: :manual,
      triggered_at: DateTime.utc_now(),
      metadata: Map.merge(attrs[:metadata] || %{}, %{"created_by" => user_id})
    })

    find_or_create(attrs)
  end

  @doc """
  Triggers an alarm from a mission database definition.

  Used when alarms are pre-defined in the mission database
  rather than created by rules.
  """
  @spec from_mission_db(trigger_attrs(), String.t()) :: trigger_result()
  def from_mission_db(attrs, definition_set_id) do
    attrs = Map.merge(attrs, %{
      source_origin: :mission_db,
      triggered_at: DateTime.utc_now(),
      metadata: Map.merge(attrs[:metadata] || %{}, %{
        "source_definition_set_id" => definition_set_id
      })
    })

    find_or_create(attrs)
  end

  # ===========================================================================
  # Private Implementation
  # ===========================================================================

  defp find_or_create(attrs) do
    mission_id = attrs[:mission_id]
    target_id = attrs[:target_id]
    source_type = attrs[:source_type]
    source_id = attrs[:source_id]

    # First check for existing active alarm
    case AlarmQueries.find_active_by_source(mission_id, target_id, source_type, source_id) do
      {:ok, existing} ->
        {:ok, existing, :existing}

      {:error, :not_found} ->
        # Try to create new alarm, handling race condition with retry
        create_alarm_with_retry(attrs, mission_id, target_id, source_type, source_id)
    end
  end

  defp create_alarm_with_retry(attrs, mission_id, target_id, source_type, source_id) do
    with {:ok, alarm} <- Alarm.new(attrs),
         {:ok, saved} <- repo().save(alarm) do
      # Note: Broadcasting is handled by AlarmManager when called through that path
      # Only record the event here - AlarmManager handles cache and broadcast
      record_alarm_triggered(saved, attrs)
      {:ok, saved, :created}
    else
      # Handle unique constraint violation (race condition - another process created it first)
      {:error, errors} when is_map(errors) ->
        if has_unique_constraint_error?(errors) do
          # Retry finding the alarm that was created by the concurrent process
          case AlarmQueries.find_active_by_source(mission_id, target_id, source_type, source_id) do
            {:ok, existing} -> {:ok, existing, :existing}
            {:error, :not_found} -> {:error, errors}
          end
        else
          {:error, errors}
        end

      error ->
        error
    end
  end

  defp has_unique_constraint_error?(errors) when is_map(errors) do
    # Check for unique constraint violation error in the changeset errors
    Enum.any?(errors, fn
      {_field, messages} when is_list(messages) ->
        Enum.any?(messages, fn msg ->
          is_binary(msg) and String.contains?(msg, "already exists")
        end)
      _ ->
        false
    end)
  end

  defp record_alarm_triggered(alarm, _attrs) do
    recorder().record(:alarm_triggered, alarm, nil, %{})
  end

  defp recorder do
    Cadence.Ports.Recordings.EventRecorder.impl()
  end
end
