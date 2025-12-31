defmodule Cadence.Automations.Engine.ActionExecutor do
  @moduledoc """
  Executes automation actions based on action type and configuration.

  Supported action types:
  - `execute_procedure` - Start a procedure execution
  - `acknowledge_alarm` - Acknowledge an alarm
  - `shelve_alarm` - Shelve an alarm for a period
  - `send_notification` - Send a notification (placeholder)
  """

  require Logger

  alias Cadence.Alarms
  alias Cadence.Procedures

  @doc """
  Executes an action based on the action type and configuration.

  Returns `{:ok, result_map}` on success or `{:error, reason}` on failure.
  """
  def execute(action_type, action_config, trigger_event, context)

  # Handle atom action types (from domain entity)
  def execute(:execute_procedure, config, trigger_event, context) do
    execute("execute_procedure", config, trigger_event, context)
  end

  def execute(:acknowledge_alarm, config, trigger_event, context) do
    execute("acknowledge_alarm", config, trigger_event, context)
  end

  def execute(:shelve_alarm, config, trigger_event, context) do
    execute("shelve_alarm", config, trigger_event, context)
  end

  def execute(:send_notification, config, trigger_event, context) do
    execute("send_notification", config, trigger_event, context)
  end

  def execute("execute_procedure", config, trigger_event, context) do
    procedure_id = config["procedure_id"]
    parameters = build_parameters(config, trigger_event)

    case Procedures.start_execution(
           procedure_id,
           parameters: parameters,
           triggered_by: :event,
           trigger_context: %{
             "event_id" => trigger_event[:event_id],
             "alarm_id" => trigger_event[:alarm_id]
           }
         ) do
      {:ok, execution} ->
        Logger.info("Started procedure execution #{execution.id} from automation")

        {:ok,
         %{
           action: "execute_procedure",
           procedure_id: procedure_id,
           execution_id: execution.id
         }}

      {:error, reason} ->
        Logger.error("Failed to start procedure: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def execute("acknowledge_alarm", config, trigger_event, _context) do
    note = config["note"] || "Auto-acknowledged by automation"

    with {:ok, alarm_id} <- fetch_alarm_id(trigger_event),
         {:ok, alarm} <- fetch_alarm(alarm_id),
         {:ok, _updated} <- Alarms.acknowledge_alarm(alarm, "automation", note) do
      Logger.info("Acknowledged alarm #{alarm_id} from automation")
      {:ok, %{action: "acknowledge_alarm", alarm_id: alarm_id}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def execute("shelve_alarm", config, trigger_event, _context) do
    duration_minutes = config["duration_minutes"] || 60
    reason = config["reason"] || "Auto-shelved by automation"

    with {:ok, alarm_id} <- fetch_alarm_id(trigger_event),
         {:ok, alarm} <- fetch_alarm(alarm_id),
         {:ok, _updated} <- Alarms.shelve_alarm(alarm, "automation", duration_minutes, reason) do
      Logger.info("Shelved alarm #{alarm_id} for #{duration_minutes} min from automation")

      {:ok,
       %{
         action: "shelve_alarm",
         alarm_id: alarm_id,
         duration_minutes: duration_minutes
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def execute("send_notification", config, trigger_event, _context) do
    # Placeholder for notification integration
    channel = config["channel"] || "default"
    message = build_notification_message(config, trigger_event)

    Logger.info("Would send notification to #{channel}: #{message}")

    {:ok,
     %{
       action: "send_notification",
       channel: channel,
       message: message,
       sent: false,
       reason: "notification system not implemented"
     }}
  end

  def execute(unknown_type, _config, _trigger_event, _context) do
    {:error, {:unknown_action_type, unknown_type}}
  end

  defp fetch_alarm_id(trigger_event) do
    case trigger_event[:alarm_id] do
      nil -> {:error, :no_alarm_in_event}
      alarm_id -> {:ok, alarm_id}
    end
  end

  defp fetch_alarm(alarm_id) do
    case Alarms.get_alarm(alarm_id) do
      nil -> {:error, :alarm_not_found}
      alarm -> {:ok, alarm}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_parameters(config, trigger_event) do
    base_params = config["parameters"] || %{}

    # Inject trigger event data into parameters
    trigger_params =
      case config["inject_trigger_data"] do
        true ->
          %{
            "_trigger" => %{
              "type" => "automation",
              "event" => Map.new(trigger_event, fn {k, v} -> {to_string(k), v} end)
            }
          }

        _ ->
          %{}
      end

    Map.merge(base_params, trigger_params)
  end

  defp build_notification_message(config, trigger_event) do
    template = config["message_template"] || "Automation triggered: {{trigger_type}}"

    template
    |> String.replace("{{trigger_type}}", to_string(trigger_event[:trigger_type] || "unknown"))
    |> String.replace("{{item_name}}", to_string(trigger_event[:item_name] || ""))
    |> String.replace("{{value}}", to_string(trigger_event[:value] || ""))
    |> String.replace("{{severity}}", to_string(trigger_event[:severity] || ""))
  end
end
