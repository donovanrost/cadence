defmodule Cadence.Runtime.Alarms.Handlers.TelemetryLimitHandler do
  @moduledoc """
  Handles TelemetryLimitEvent to create, update, or clear alarms.

  This handler is called by the AlarmManager when a TelemetryLimitEvent is received.
  It:
  1. Finds matching alarm rules
  2. Creates new alarms or updates existing ones
  3. Clears alarms when conditions resolve
  4. Queues notifications via the dispatcher

  ## Event Flow

      TelemetryLimitEvent
            │
            ▼
      ┌─────────────────┐
      │ Find matching   │
      │ rules           │
      └────────┬────────┘
               │
               ▼
      ┌─────────────────┐
      │ Check for       │
      │ existing alarm  │
      └────────┬────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
    Recovery?      Violation?
       │               │
       ▼               ▼
    Clear alarm   Create/Update
                     alarm
  """

  require Logger

  alias Cadence.Alarms
  alias Cadence.Alarms.Alarm
  alias Cadence.Alarms.AlarmRule
  alias Cadence.Runtime.Alarms.{Matcher, RuleCache}
  alias Cadence.Alarms.Notifications.Dispatcher
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

  @type handle_result ::
          {:created, Alarm.t(), AlarmRule.t() | nil}
          | {:updated, Alarm.t(), AlarmRule.t() | nil}
          | {:cleared, Alarm.t()}
          | {:no_rule, TelemetryLimitEvent.t()}
          | {:no_action, TelemetryLimitEvent.t()}

  @doc """
  Handles a TelemetryLimitEvent.

  Returns the action taken and the affected alarm (if any).
  """
  @spec handle(TelemetryLimitEvent.t(), String.t()) :: handle_result()
  def handle(%TelemetryLimitEvent{} = event, organization_id) do
    Logger.debug("Handling TelemetryLimitEvent: #{TelemetryLimitEvent.describe(event)}")

    cond do
      # Recovery - clear any existing alarm
      TelemetryLimitEvent.recovery?(event) and event.new_state == :green ->
        handle_recovery(event)

      # Violation (including stale) - create or update alarm
      event.new_state in [:yellow, :red, :blue] ->
        handle_violation(event, organization_id)

      # No action needed (e.g., green -> green)
      true ->
        {:no_action, event}
    end
  end

  # ============================================================================
  # Recovery Handling
  # ============================================================================

  # Note: This handler is called from within AlarmManager, so we use the internal
  # do_* functions directly to avoid deadlock (calling back into the GenServer).
  # The AlarmManager handles cache updates after this handler returns.

  defp handle_recovery(%TelemetryLimitEvent{} = event) do
    case find_existing_alarm(event) do
      %Alarm{} = alarm ->
        Logger.info("Clearing alarm #{alarm.id} due to recovery: #{event.item_name}")

        case Alarms.do_clear_alarm(alarm, nil) do
          {:ok, cleared} ->
            # Notify about clearing
            Dispatcher.dispatch(cleared, :cleared, nil)
            {:cleared, cleared}

          {:error, reason} ->
            Logger.error("Failed to clear alarm #{alarm.id}: #{inspect(reason)}")
            {:no_action, event}
        end

      nil ->
        # No existing alarm to clear
        {:no_action, event}
    end
  end

  # ============================================================================
  # Violation Handling
  # ============================================================================

  defp handle_violation(%TelemetryLimitEvent{} = event, organization_id) do
    # Find matching rules
    rules =
      RuleCache.get_rules_for_event(
        organization_id,
        event.mission_id,
        event.target_id,
        "telemetry_limit"
      )

    case Matcher.find_matching_rule(rules, event) do
      %AlarmRule{} = rule ->
        handle_violation_with_rule(event, rule, organization_id)

      nil ->
        Logger.debug("No matching rule for event: #{event.item_name}")
        {:no_rule, event}
    end
  end

  defp handle_violation_with_rule(%TelemetryLimitEvent{} = event, %AlarmRule{} = rule, org_id) do
    case find_existing_alarm(event) do
      %Alarm{} = alarm ->
        update_existing_alarm(alarm, event, rule)

      nil ->
        create_new_alarm(event, rule, org_id)
    end
  end

  defp create_new_alarm(%TelemetryLimitEvent{} = event, %AlarmRule{} = rule, organization_id) do
    message = Matcher.render_message(rule.message_template, event)
    severity = rule.severity || Matcher.default_severity_for_state(event.new_state)

    attrs = %{
      organization_id: organization_id,
      mission_id: event.mission_id,
      target_id: event.target_id,
      alarm_rule_id: rule.id,
      alarm_type: "telemetry_limit",
      severity: severity,
      status: :active,
      source_type: "telemetry_item",
      source_id: event.item_name,
      limit_state: event.new_state,
      current_value: event.value,
      message: message,
      triggered_at: event.timestamp || DateTime.utc_now(),
      metadata: %{
        "limit_set" => event.limit_set,
        "previous_state" => to_string(event.previous_state),
        "rule_name" => rule.name
      }
    }

    case Alarms.create_alarm(attrs) do
      {:ok, alarm} ->
        Logger.info("Created alarm #{alarm.id} for #{event.item_name} (#{event.new_state})")

        # Handle auto-acknowledge if configured
        alarm = maybe_auto_acknowledge(alarm, rule)

        # Handle auto-shelve if configured
        alarm = maybe_auto_shelve(alarm, rule)

        # Dispatch notifications
        Dispatcher.dispatch(alarm, :triggered, rule)

        {:created, alarm, rule}

      {:error, reason} ->
        Logger.error("Failed to create alarm for #{event.item_name}: #{inspect(reason)}")
        {:no_action, event}
    end
  end

  defp update_existing_alarm(
         %Alarm{} = alarm,
         %TelemetryLimitEvent{} = event,
         %AlarmRule{} = rule
       ) do
    # Determine if severity should change based on limit state change
    new_severity = determine_severity(alarm, event, rule)
    message = Matcher.render_message(rule.message_template, event)

    # Use internal function to avoid deadlock (we're called from AlarmManager)
    case Alarms.do_update_alarm_value(
           alarm,
           event.value,
           event.new_state,
           new_severity,
           message
         ) do
      {:ok, updated} ->
        event_type = if updated.severity != alarm.severity, do: :escalated, else: :value_updated

        Logger.debug(
          "Updated alarm #{alarm.id}: #{event.item_name} = #{event.value} (#{event_type})"
        )

        # Dispatch notifications for escalations
        if event_type == :escalated do
          Dispatcher.dispatch(updated, :escalated, rule)
        end

        {:updated, updated, rule}

      {:error, reason} ->
        Logger.error("Failed to update alarm #{alarm.id}: #{inspect(reason)}")
        {:no_action, event}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp find_existing_alarm(%TelemetryLimitEvent{} = event) do
    Alarms.find_active_alarm(
      event.mission_id,
      event.target_id,
      "telemetry_item",
      event.item_name
    )
  end

  defp determine_severity(%Alarm{} = alarm, %TelemetryLimitEvent{} = event, %AlarmRule{} = rule) do
    # If rule has explicit severity, use it
    # Otherwise, derive from limit state and potentially escalate
    rule_severity = rule.severity
    state_severity = Matcher.default_severity_for_state(event.new_state)

    # Take the higher severity between rule default and state-derived
    max_severity(rule_severity || state_severity, state_severity)
    |> max_severity(alarm.severity)
  end

  defp max_severity(a, b) do
    if severity_rank(a) >= severity_rank(b), do: a, else: b
  end

  defp severity_rank(:critical), do: 2
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 0
  defp severity_rank(_), do: 0

  # Use internal functions to avoid deadlock (we're called from AlarmManager)
  defp maybe_auto_acknowledge(%Alarm{} = alarm, %AlarmRule{auto_acknowledge: true}) do
    case Alarms.do_acknowledge_alarm(alarm, nil, "Auto-acknowledged by rule") do
      {:ok, acknowledged} -> acknowledged
      {:error, _} -> alarm
    end
  end

  defp maybe_auto_acknowledge(alarm, _rule), do: alarm

  defp maybe_auto_shelve(%Alarm{} = alarm, %AlarmRule{auto_shelve_duration_minutes: minutes})
       when is_integer(minutes) and minutes > 0 do
    case Alarms.do_shelve_alarm(alarm, nil, minutes, "Auto-shelved by rule") do
      {:ok, shelved} -> shelved
      {:error, _} -> alarm
    end
  end

  defp maybe_auto_shelve(alarm, _rule), do: alarm
end
