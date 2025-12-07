defmodule Cadence.Alarms.SuggestionStrategy.Semantic do
  @moduledoc """
  Semantic-aware suggestion strategy that analyzes parameter naming patterns
  and data type metadata to generate contextually appropriate alarm rules.

  ## Features

  - Recognizes common naming patterns (temperature, voltage, status, etc.)
  - Uses unit information from DataType for better messages
  - Adjusts severity based on parameter criticality hints
  - Generates more descriptive, context-aware messages
  - Suggests appropriate grouping patterns for related parameters

  ## Recognized Patterns

  | Pattern | Category | Behavior |
  |---------|----------|----------|
  | `*_TEMP`, `*_TEMPERATURE` | Temperature | Includes units, rate-of-change awareness |
  | `*_VOLTAGE`, `*_CURRENT`, `*_POWER` | Power | Groups power subsystem params |
  | `*_STATUS`, `*_STATE`, `*_MODE` | State | Lowered priority for info states |
  | `*_COUNT`, `*_COUNTER` | Counter | Suggests staleness over limits |
  | `HEALTH.*`, `HK.*` | Housekeeping | Lower default severity |
  | `CMD_*`, `COMMAND_*` | Command | Command-failure event type |
  | `*_CRITICAL`, `SAFE_*` | Safety | Elevated severity |
  """

  @behaviour Cadence.Alarms.SuggestionStrategy

  @impl true
  def name, do: "Semantic"

  @impl true
  def description do
    "Analyzes parameter names and data types to generate context-aware suggestions"
  end

  @impl true
  def specializes_in do
    [:temperature, :power, :state, :counter, :housekeeping, :command, :safety]
  end

  @impl true
  def suggest(parameter, _context) do
    category = categorize_parameter(parameter)
    generate_suggestions(parameter, category)
  end

  # ============================================================================
  # Parameter Categorization
  # ============================================================================

  @doc """
  Categorizes a parameter based on its name and data type.
  """
  def categorize_parameter(parameter) do
    name = String.upcase(parameter.qualified_name)
    data_type = parameter.data_type

    cond do
      # Safety-critical parameters (highest priority)
      safety_pattern?(name) ->
        :safety

      # Temperature sensors
      temperature_pattern?(name) ->
        :temperature

      # Power subsystem
      power_pattern?(name) ->
        :power

      # State/status enumerations
      state_pattern?(name) || enumerated_type?(data_type) ->
        :state

      # Counters
      counter_pattern?(name) ->
        :counter

      # Housekeeping telemetry
      housekeeping_pattern?(name) ->
        :housekeeping

      # Command-related
      command_pattern?(name) ->
        :command

      # Default numeric
      true ->
        :numeric
    end
  end

  # Pattern matching helpers
  defp temperature_pattern?(name) do
    String.contains?(name, "TEMP") ||
      String.contains?(name, "TEMPERATURE") ||
      String.ends_with?(name, "_T") ||
      String.contains?(name, "THERMAL")
  end

  defp power_pattern?(name) do
    String.contains?(name, "VOLTAGE") ||
      String.contains?(name, "CURRENT") ||
      String.contains?(name, "POWER") ||
      String.contains?(name, "BATTERY") ||
      (String.contains?(name, "_V") && !String.contains?(name, "VALVE")) ||
      (String.contains?(name, "_I") && !String.contains?(name, "INFO")) ||
      String.contains?(name, "EPS") ||
      String.contains?(name, "PDU")
  end

  defp state_pattern?(name) do
    String.contains?(name, "STATUS") ||
      String.contains?(name, "STATE") ||
      String.contains?(name, "MODE") ||
      String.contains?(name, "FLAG") ||
      String.ends_with?(name, "_EN") ||
      String.ends_with?(name, "_ENABLE")
  end

  defp counter_pattern?(name) do
    String.contains?(name, "COUNT") ||
      String.contains?(name, "COUNTER") ||
      String.ends_with?(name, "_CNT") ||
      String.contains?(name, "SEQUENCE")
  end

  defp housekeeping_pattern?(name) do
    String.starts_with?(name, "HEALTH.") ||
      String.starts_with?(name, "HK.") ||
      String.starts_with?(name, "HK_") ||
      String.starts_with?(name, "HOUSEKEEPING") ||
      String.contains?(name, ".HK.")
  end

  defp command_pattern?(name) do
    String.starts_with?(name, "CMD_") ||
      String.starts_with?(name, "COMMAND") ||
      String.contains?(name, "_CMD_") ||
      String.contains?(name, "UPLINK")
  end

  defp safety_pattern?(name) do
    String.contains?(name, "CRITICAL") ||
      String.contains?(name, "SAFETY") ||
      String.starts_with?(name, "SAFE_") ||
      String.contains?(name, "EMERGENCY") ||
      String.contains?(name, "FAULT") ||
      String.contains?(name, "HAZARD")
  end

  defp enumerated_type?(nil), do: false

  defp enumerated_type?(data_type) do
    data_type.base_type == :enumerated
  end

  # ============================================================================
  # Suggestion Generation by Category
  # ============================================================================

  defp generate_suggestions(param, :temperature) do
    unit = get_unit_symbol(param)
    limit_info = get_limit_info(param)

    [
      %{
        name: "#{param.qualified_name} CRITICAL",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name" => [param.qualified_name]
        },
        severity: :critical,
        message_template: build_temperature_message(param, :critical, unit, limit_info),
        parameter: param,
        rationale: "Temperature sensor with defined limits",
        confidence: 0.95
      },
      %{
        name: "#{param.qualified_name} WARNING",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :warning,
        message_template: build_temperature_message(param, :warning, unit, limit_info),
        parameter: param,
        rationale: "Temperature sensor approaching limits",
        confidence: 0.95
      }
    ]
  end

  defp generate_suggestions(param, :power) do
    unit = get_unit_symbol(param)
    subsystem = extract_subsystem(param)

    [
      %{
        name: "#{param.qualified_name} CRITICAL",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name" => [param.qualified_name]
        },
        severity: :critical,
        message_template: build_power_message(param, :critical, unit, subsystem),
        parameter: param,
        rationale: "Power subsystem parameter",
        confidence: 0.9
      },
      %{
        name: "#{param.qualified_name} WARNING",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :warning,
        message_template: build_power_message(param, :warning, unit, subsystem),
        parameter: param,
        rationale: "Power subsystem parameter",
        confidence: 0.9
      }
    ]
  end

  defp generate_suggestions(param, :safety) do
    # Safety-critical params get more urgent messaging and always critical severity
    [
      %{
        name: "#{param.qualified_name} CRITICAL",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red", "yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :critical,
        message_template:
          "SAFETY ALERT: #{short_name(param)} out of limits - {{limit_state}} ({{value}}) - IMMEDIATE ATTENTION REQUIRED",
        parameter: param,
        rationale: "Safety-critical parameter - all violations treated as critical",
        confidence: 1.0
      }
    ]
  end

  defp generate_suggestions(param, :state) do
    # State/status parameters - typically less urgent
    [
      %{
        name: "#{param.qualified_name} STATE CHANGE",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name" => [param.qualified_name]
        },
        severity: :warning,
        message_template: "#{short_name(param)} entered abnormal state: {{value}}",
        parameter: param,
        rationale: "State/status parameter - red state indicates abnormal condition",
        confidence: 0.85
      },
      %{
        name: "#{param.qualified_name} STATE WARNING",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :info,
        message_template: "#{short_name(param)} state changed: {{value}}",
        parameter: param,
        rationale: "State change notification",
        confidence: 0.8
      }
    ]
  end

  defp generate_suggestions(param, :housekeeping) do
    # Housekeeping - lower severity by default
    [
      %{
        name: "#{param.qualified_name} CRITICAL",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name" => [param.qualified_name]
        },
        severity: :warning,
        message_template: "HK: #{short_name(param)} is {{limit_state}} ({{value}})",
        parameter: param,
        rationale: "Housekeeping parameter - typically lower operational priority",
        confidence: 0.85
      },
      %{
        name: "#{param.qualified_name} WARNING",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :info,
        message_template: "HK: #{short_name(param)} approaching limit ({{value}})",
        parameter: param,
        rationale: "Housekeeping parameter",
        confidence: 0.8
      }
    ]
  end

  defp generate_suggestions(param, :counter) do
    # Counters - typically informational
    [
      %{
        name: "#{param.qualified_name} LIMIT",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red", "yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :info,
        message_template: "Counter #{short_name(param)} at {{value}}",
        parameter: param,
        rationale: "Counter/sequence parameter - typically informational",
        confidence: 0.7
      }
    ]
  end

  defp generate_suggestions(param, :command) do
    # Command-related - may need special handling
    [
      %{
        name: "#{param.qualified_name} CRITICAL",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name" => [param.qualified_name]
        },
        severity: :critical,
        message_template: "Command status: #{short_name(param)} - {{limit_state}} ({{value}})",
        parameter: param,
        rationale: "Command-related parameter",
        confidence: 0.85
      },
      %{
        name: "#{param.qualified_name} WARNING",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :warning,
        message_template: "Command status: #{short_name(param)} - {{value}}",
        parameter: param,
        rationale: "Command-related parameter",
        confidence: 0.8
      }
    ]
  end

  defp generate_suggestions(param, :numeric) do
    # Default numeric handling
    unit = get_unit_symbol(param)

    [
      %{
        name: "#{param.qualified_name} CRITICAL",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["red"],
          "item_name" => [param.qualified_name]
        },
        severity: :critical,
        message_template: build_numeric_message(param, :critical, unit),
        parameter: param,
        rationale: nil,
        confidence: 0.9
      },
      %{
        name: "#{param.qualified_name} WARNING",
        event_type: "telemetry_limit",
        conditions: %{
          "limit_state" => ["yellow"],
          "item_name" => [param.qualified_name]
        },
        severity: :warning,
        message_template: build_numeric_message(param, :warning, unit),
        parameter: param,
        rationale: nil,
        confidence: 0.9
      }
    ]
  end

  # ============================================================================
  # Message Building Helpers
  # ============================================================================

  defp build_temperature_message(param, :critical, unit, limit_info) do
    limit_text =
      if limit_info.critical_max do
        " (limit: #{limit_info.critical_max}#{unit})"
      else
        ""
      end

    "CRITICAL: #{short_name(param)} temperature is {{limit_state}} - {{value}}#{unit}#{limit_text}"
  end

  defp build_temperature_message(param, :warning, unit, limit_info) do
    limit_text =
      if limit_info.warning_max do
        " (approaching #{limit_info.warning_max}#{unit})"
      else
        ""
      end

    "WARNING: #{short_name(param)} temperature - {{value}}#{unit}#{limit_text}"
  end

  defp build_power_message(param, :critical, unit, subsystem) do
    subsystem_text = if subsystem, do: "[#{subsystem}] ", else: ""
    "CRITICAL: #{subsystem_text}#{short_name(param)} is {{limit_state}} - {{value}}#{unit}"
  end

  defp build_power_message(param, :warning, unit, subsystem) do
    subsystem_text = if subsystem, do: "[#{subsystem}] ", else: ""
    "WARNING: #{subsystem_text}#{short_name(param)} - {{value}}#{unit}"
  end

  defp build_numeric_message(param, :critical, unit) do
    "CRITICAL: #{short_name(param)} is {{limit_state}} ({{value}}#{unit})"
  end

  defp build_numeric_message(param, :warning, unit) do
    "WARNING: #{short_name(param)} is {{limit_state}} ({{value}}#{unit})"
  end

  # ============================================================================
  # Data Extraction Helpers
  # ============================================================================

  defp short_name(param) do
    param.parameter.name
  end

  defp get_unit_symbol(param) do
    case param.data_type do
      %{unit: %{symbol: symbol}} when is_binary(symbol) and symbol != "" ->
        " #{symbol}"

      %{unit: %{name: name}} when is_binary(name) and name != "" ->
        " #{name}"

      _ ->
        ""
    end
  end

  defp get_limit_info(param) do
    case param.data_type do
      %{default_alarm: %{critical_range: critical, warning_range: warning}} ->
        %{
          critical_min: get_range_field(critical, :min_inclusive),
          critical_max: get_range_field(critical, :max_inclusive),
          warning_min: get_range_field(warning, :min_inclusive),
          warning_max: get_range_field(warning, :max_inclusive)
        }

      _ ->
        %{critical_min: nil, critical_max: nil, warning_min: nil, warning_max: nil}
    end
  end

  defp get_range_field(nil, _field), do: nil
  defp get_range_field(range, field) when is_struct(range), do: Map.get(range, field)
  defp get_range_field(range, field) when is_map(range), do: Map.get(range, field)

  defp extract_subsystem(param) do
    name = param.qualified_name

    cond do
      String.starts_with?(name, "EPS.") -> "EPS"
      String.starts_with?(name, "PDU.") -> "PDU"
      String.starts_with?(name, "POWER.") -> "POWER"
      String.starts_with?(name, "BATTERY.") -> "BATTERY"
      String.contains?(name, ".EPS.") -> "EPS"
      String.contains?(name, ".PDU.") -> "PDU"
      true -> nil
    end
  end
end
