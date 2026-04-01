defmodule Cadence.Runtime.Alarms.Handlers.TransportConnectionHandler do
  @moduledoc """
  Handles TransportConnectionEvent to create, update, or clear alarms.

  This handler is called by the AlarmManager when a TransportConnectionEvent is received.
  It:
  1. Finds matching alarm rules for transport_connection trigger type
  2. Creates alarms when transports disconnect
  3. Clears alarms when transports reconnect

  ## Event Flow

      TransportConnectionEvent
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
  alias Cadence.Alarms.Notifications.Dispatcher
  alias Cadence.Runtime.Alarms.RuleCache
  alias Cadence.Transports.Events.TransportConnectionEvent

  @type handle_result ::
          {:created, Alarm.t(), AlarmRule.t() | nil}
          | {:cleared, Alarm.t()}
          | {:no_rule, TransportConnectionEvent.t()}
          | {:no_action, TransportConnectionEvent.t()}

  @doc """
  Handles a TransportConnectionEvent.

  Returns the action taken and the affected alarm (if any).
  """
  @spec handle(TransportConnectionEvent.t(), String.t()) :: handle_result()
  def handle(%TransportConnectionEvent{} = event, organization_id) do
    Logger.debug("Handling TransportConnectionEvent: #{TransportConnectionEvent.describe(event)}")

    cond do
      # Reconnection - clear any existing alarm
      TransportConnectionEvent.connected?(event) ->
        handle_reconnection(event)

      # Disconnection - create alarm
      TransportConnectionEvent.disconnected?(event) ->
        handle_disconnection(event, organization_id)

      # Should not happen
      true ->
        {:no_action, event}
    end
  end

  defp handle_reconnection(%TransportConnectionEvent{} = event) do
    case find_existing_alarm(event) do
      %Alarm{} = alarm ->
        Logger.info(
          "Clearing alarm #{alarm.id} due to transport reconnection: #{event.transport_name || event.transport_id}"
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

  defp handle_disconnection(%TransportConnectionEvent{} = event, organization_id) do
    rules =
      RuleCache.get_rules_for_event(
        organization_id,
        event.mission_id,
        nil,
        "transport_connection"
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

      # Check transport_id filter if specified
      transport_filter = Map.get(conditions, "transport_id")

      cond do
        is_nil(transport_filter) -> true
        is_binary(transport_filter) -> transport_filter == event.transport_id
        is_list(transport_filter) -> event.transport_id in transport_filter
        true -> true
      end
    end)
  end

  defp create_alarm(%TransportConnectionEvent{} = event, %AlarmRule{} = rule, organization_id) do
    message = render_message(rule.message_template, event)
    severity = rule.severity || :warning

    attrs = build_alarm_attrs(event, organization_id, severity, message, rule.id)

    case Alarms.create_alarm(attrs) do
      {:ok, alarm} ->
        Logger.info(
          "Created alarm #{alarm.id} for transport disconnection: #{event.transport_name || event.transport_id}"
        )

        Dispatcher.dispatch(alarm, :triggered, rule)
        {:created, alarm, rule}

      {:error, reason} ->
        Logger.error("Failed to create alarm for transport disconnection: #{inspect(reason)}")
        {:no_action, event}
    end
  end

  defp create_default_alarm(%TransportConnectionEvent{} = event, organization_id) do
    message =
      "Transport #{event.transport_name || event.transport_id} disconnected - no clients connected"

    attrs = build_alarm_attrs(event, organization_id, :warning, message, nil)

    case Alarms.create_alarm(attrs) do
      {:ok, alarm} ->
        Logger.info(
          "Created default alarm #{alarm.id} for transport disconnection: #{event.transport_name || event.transport_id}"
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
      alarm_type: "transport_connection",
      severity: severity,
      status: :active,
      source_type: "transport",
      source_id: event.transport_id,
      message: message,
      triggered_at: event.timestamp || Cadence.Time.now(),
      metadata: %{
        "transport_name" => event.transport_name,
        "previous_state" => to_string(event.previous_state),
        "client_info" => event.client_info
      }
    }
  end

  defp find_existing_alarm(%TransportConnectionEvent{} = event) do
    Alarms.find_active_alarm(
      event.mission_id,
      nil,
      "transport",
      event.transport_id
    )
  end

  defp render_message(nil, event) do
    "Transport #{event.transport_name || event.transport_id} disconnected"
  end

  defp render_message(template, event) when is_binary(template) do
    template
    |> String.replace("{{transport_id}}", event.transport_id || "")
    |> String.replace("{{transport_name}}", event.transport_name || event.transport_id || "")
    |> String.replace("{{mission_id}}", event.mission_id || "")
  end
end
