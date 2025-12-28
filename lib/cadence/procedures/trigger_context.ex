defmodule Cadence.Procedures.TriggerContext do
  @moduledoc """
  Builds trigger context for procedure executions.

  When a procedure is triggered by an external event (alarm, schedule, telemetry event),
  the trigger context captures relevant information that the procedure can access.

  ## Trigger Types

  - `:manual` - User initiated via UI
  - `:schedule` - Cron/scheduled execution
  - `:alarm` - Triggered by alarm state change
  - `:telemetry_event` - Triggered by telemetry condition

  ## Context Structure

  All trigger contexts have:
  - `type` - The trigger type atom
  - `source_id` - ID of the triggering entity
  - `source_name` - Human-readable name
  - `triggered_at` - UTC timestamp
  - `data` - Type-specific additional data

  ## Usage in Procedures

  Access trigger context in expressions:

      # In a log step
      %{
        "type" => "log",
        "level" => "info",
        "message" => "Triggered by {{trigger.source_name}} at {{trigger.triggered_at}}"
      }

      # In a condition
      %{
        "type" => "check",
        "condition" => "trigger.data.severity == 'critical'"
      }
  """

  @type trigger_type :: :manual | :schedule | :alarm | :telemetry_event

  @type t :: %{
          type: trigger_type(),
          source_id: String.t() | nil,
          source_name: String.t(),
          triggered_at: DateTime.t(),
          data: map()
        }

  @doc """
  Builds trigger context for different trigger types.

  ## Manual Trigger

  For user-initiated executions:

      iex> TriggerContext.build(:manual, user)
      %{type: :manual, source_id: "user-uuid", source_name: "user@example.com", ...}

  ## Schedule Trigger

  For scheduled/cron executions:

      iex> TriggerContext.build(:schedule, schedule)
      %{type: :schedule, source_name: "Daily Health Check", data: %{cron_expression: "0 8 * * *"}, ...}

  ## Alarm Trigger

  For alarm-triggered executions:

      iex> TriggerContext.build(:alarm, alarm_event)
      %{type: :alarm, source_name: "BATTERY_LOW", data: %{severity: :warning, triggering_value: 23.5}, ...}

  ## Telemetry Event Trigger

  For telemetry condition triggers:

      iex> TriggerContext.build(:telemetry_event, event)
      %{type: :telemetry_event, source_name: "EPS.battery_voltage", data: %{value: 23.5}, ...}
  """
  @spec build(atom(), map() | nil) :: t()
  def build(type, arg)

  def build(:manual, nil) do
    build_context(:manual, nil, "system", DateTime.utc_now(), %{})
  end

  def build(:manual, user) do
    build_context(:manual, user.id, user.email || "unknown", DateTime.utc_now(), %{
      user_id: user.id,
      user_email: user.email
    })
  end

  def build(:schedule, schedule) do
    build_context(
      :schedule,
      schedule.id,
      schedule.name || "Scheduled Execution",
      DateTime.utc_now(),
      %{
        schedule_id: schedule.id,
        schedule_name: schedule.name,
        cron_expression: Map.get(schedule, :cron_expression),
        schedule_type: Map.get(schedule, :type, :cron)
      }
    )
  end

  def build(:alarm, alarm_event) do
    alarm = Map.get(alarm_event, :alarm, %{})

    build_context(
      :alarm,
      alarm_source_id(alarm_event),
      alarm_source_name(alarm_event, alarm),
      alarm_event[:timestamp] || DateTime.utc_now(),
      %{
        alarm_id: alarm_source_id(alarm_event),
        alarm_name: alarm_source_name(alarm_event, alarm),
        severity: alarm[:severity] || alarm_event[:severity],
        state: alarm_event[:new_state] || alarm_event[:state],
        previous_state: alarm_event[:previous_state],
        triggering_value: alarm_event[:triggering_value],
        threshold: alarm_event[:threshold],
        item_name: alarm_event[:telemetry_item] || alarm_event[:item_name],
        rule_id: alarm_event[:rule_id]
      }
    )
  end

  def build(:telemetry_event, event) do
    build_context(
      :telemetry_event,
      event[:id] || Ecto.UUID.generate(),
      event[:item_name] || "Telemetry Event",
      event[:timestamp] || DateTime.utc_now(),
      %{
        item_name: event[:item_name],
        packet_name: event[:packet_name],
        value: event[:value],
        previous_value: event[:previous_value],
        timestamp: event[:timestamp],
        target_id: event[:target_id]
      }
    )
  end

  @doc """
  Builds trigger context from a generic map.

  Useful when the trigger context is already partially constructed
  or when building from stored data.
  """
  @spec build(map()) :: t()
  def build(%{type: type} = context)
      when type in [:manual, :schedule, :alarm, :telemetry_event] do
    build_context(
      type,
      context[:source_id],
      context[:source_name] || to_string(type),
      context[:triggered_at] || DateTime.utc_now(),
      context[:data] || %{}
    )
  end

  def build(context) when is_map(context) do
    type = context[:type] || context["type"] || :manual

    build_context(
      normalize_type(type),
      context[:source_id] || context["source_id"],
      context[:source_name] || context["source_name"] || to_string(type),
      normalize_timestamp(context[:triggered_at] || context["triggered_at"]),
      context[:data] || context["data"] || %{}
    )
  end

  @doc """
  Converts trigger context to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(context) do
    %{
      "type" => to_string(context.type),
      "source_id" => context.source_id,
      "source_name" => context.source_name,
      "triggered_at" => DateTime.to_iso8601(context.triggered_at),
      "data" => stringify_keys(context.data)
    }
  end

  @doc """
  Reconstructs trigger context from a stored map (e.g., from database).
  """
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(map) when is_map(map) do
    build(map)
  end

  defp build_context(type, source_id, source_name, triggered_at, data) do
    %{
      type: type,
      source_id: source_id,
      source_name: source_name,
      triggered_at: triggered_at,
      data: data
    }
  end

  defp alarm_source_id(alarm_event) do
    alarm_event[:alarm_id] || alarm_event[:id]
  end

  defp alarm_source_name(alarm_event, alarm) do
    alarm[:name] || alarm_event[:alarm_name] || "Unknown Alarm"
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type("manual"), do: :manual
  defp normalize_type("schedule"), do: :schedule
  defp normalize_type("alarm"), do: :alarm
  defp normalize_type("telemetry_event"), do: :telemetry_event
  defp normalize_type(_), do: :manual

  defp normalize_timestamp(nil), do: DateTime.utc_now()
  defp normalize_timestamp(%DateTime{} = dt), do: dt

  defp normalize_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp normalize_timestamp(_), do: DateTime.utc_now()

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp stringify_value(v) when is_atom(v) and not is_nil(v), do: to_string(v)
  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v), do: v
end
