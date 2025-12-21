defmodule Cadence.Alarms.Engine.Handlers.InterfaceConnectionHandler do
  @moduledoc """
  Handles InterfaceConnectionEvent to create, update, or clear alarms.

  This handler is called by the AlarmManager when an InterfaceConnectionEvent is received.
  It:
  1. Finds matching alarm rules for interface_connection trigger type
  2. Creates alarms when interfaces disconnect
  3. Clears alarms when interfaces reconnect

  ## Event Flow

      InterfaceConnectionEvent
            │
            ▼
      ┌─────────────────┐
      │ Check event     │
      │ type            │
      └────────┬────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
    Connected?    Disconnected?
       │               │
       ▼               ▼
    Clear alarm   Create alarm
  """

  require Logger

  alias Cadence.Alarms
  alias Cadence.Alarms.Alarm
  alias Cadence.Alarms.AlarmRule
  alias Cadence.Alarms.Engine.RuleCache
  alias Cadence.Alarms.Notifications.Dispatcher
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent

  @type handle_result ::
          {:created, Alarm.t(), AlarmRule.t() | nil}
          | {:cleared, Alarm.t()}
          | {:no_rule, InterfaceConnectionEvent.t()}
          | {:no_action, InterfaceConnectionEvent.t()}

  @doc """
  Handles an InterfaceConnectionEvent.

  Returns the action taken and the affected alarm (if any).
  """
  @spec handle(InterfaceConnectionEvent.t(), String.t()) :: handle_result()
  def handle(%InterfaceConnectionEvent{} = event, organization_id) do
    Logger.debug("Handling InterfaceConnectionEvent: #{InterfaceConnectionEvent.describe(event)}")

    cond do
      # Reconnection - clear any existing alarm
      InterfaceConnectionEvent.connected?(event) ->
        handle_reconnection(event)

      # Disconnection - create alarm
      InterfaceConnectionEvent.disconnected?(event) ->
        handle_disconnection(event, organization_id)

      # Should not happen
      true ->
        {:no_action, event}
    end
  end

  defp handle_reconnection(%InterfaceConnectionEvent{} = event) do
    case find_existing_alarm(event) do
      %Alarm{} = alarm ->
        Logger.info(
          "Clearing alarm #{alarm.id} due to interface reconnection: #{event.interface_name || event.interface_id}"
        )

        case Alarms.do_clear_alarm(alarm, nil) do
          {:ok, cleared} ->
            Dispatcher.dispatch(cleared, :cleared, nil)
            {:cleared, cleared}

          {:error, reason} ->
            Logger.error("Failed to clear alarm #{alarm.id}: #{inspect(reason)}")
            {:no_action, event}
        end

      nil ->
        {:no_action, event}
    end
  end

  defp handle_disconnection(%InterfaceConnectionEvent{} = event, organization_id) do
    rules =
      RuleCache.get_rules_for_event(
        organization_id,
        event.mission_id,
        nil,
        "interface_connection"
      )

    case find_matching_rule(rules, event) do
      %AlarmRule{} = rule ->
        create_alarm(event, rule, organization_id)

      nil ->
        # No rule configured - create default alarm for visibility
        create_default_alarm(event, organization_id)
    end
  end

  defp find_matching_rule(rules, event) do
    Enum.find(rules, fn rule ->
      conditions = rule.conditions || %{}

      # Check interface_id filter if specified
      interface_filter = Map.get(conditions, "interface_id")

      cond do
        is_nil(interface_filter) -> true
        is_binary(interface_filter) -> interface_filter == event.interface_id
        is_list(interface_filter) -> event.interface_id in interface_filter
        true -> true
      end
    end)
  end

  defp create_alarm(%InterfaceConnectionEvent{} = event, %AlarmRule{} = rule, organization_id) do
    message = render_message(rule.message_template, event)
    severity = rule.severity || :warning

    attrs = build_alarm_attrs(event, organization_id, severity, message, rule.id)

    case Alarms.create_alarm(attrs) do
      {:ok, alarm} ->
        Logger.info(
          "Created alarm #{alarm.id} for interface disconnection: #{event.interface_name || event.interface_id}"
        )

        Dispatcher.dispatch(alarm, :triggered, rule)
        {:created, alarm, rule}

      {:error, reason} ->
        Logger.error("Failed to create alarm for interface disconnection: #{inspect(reason)}")
        {:no_action, event}
    end
  end

  defp create_default_alarm(%InterfaceConnectionEvent{} = event, organization_id) do
    message = "Interface #{event.interface_name || event.interface_id} disconnected - no clients connected"

    attrs = build_alarm_attrs(event, organization_id, :warning, message, nil)

    case Alarms.create_alarm(attrs) do
      {:ok, alarm} ->
        Logger.info(
          "Created default alarm #{alarm.id} for interface disconnection: #{event.interface_name || event.interface_id}"
        )

        {:created, alarm, nil}

      {:error, reason} ->
        Logger.error("Failed to create default alarm: #{inspect(reason)}")
        {:no_action, event}
    end
  end

  defp build_alarm_attrs(event, organization_id, severity, message, rule_id) do
    %{
      organization_id: organization_id,
      mission_id: event.mission_id,
      target_id: nil,
      alarm_rule_id: rule_id,
      alarm_type: "interface_connection",
      severity: severity,
      status: :active,
      source_type: "interface",
      source_id: event.interface_id,
      message: message,
      triggered_at: event.timestamp || DateTime.utc_now(),
      metadata: %{
        "interface_name" => event.interface_name,
        "previous_state" => to_string(event.previous_state),
        "client_info" => event.client_info
      }
    }
  end

  defp find_existing_alarm(%InterfaceConnectionEvent{} = event) do
    Alarms.find_active_alarm(
      event.mission_id,
      nil,
      "interface",
      event.interface_id
    )
  end

  defp render_message(nil, event) do
    "Interface #{event.interface_name || event.interface_id} disconnected"
  end

  defp render_message(template, event) when is_binary(template) do
    template
    |> String.replace("{{interface_id}}", event.interface_id || "")
    |> String.replace("{{interface_name}}", event.interface_name || event.interface_id || "")
    |> String.replace("{{mission_id}}", event.mission_id || "")
  end
end
