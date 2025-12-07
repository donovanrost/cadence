defmodule Cadence.Alarms.Engine.Matcher do
  @moduledoc """
  Evaluates alarm rule conditions against incoming events.

  ## Supported Conditions

  For `telemetry_limit` events:

  - `limit_state` - List of states to match (e.g., `["red", "yellow"]`)
  - `item_name` - List of exact item names to match
  - `item_name_pattern` - Regex pattern for item names (e.g., `"POWER.*"`)
  - `target_id` - List of target IDs to match

  ## Matching Logic

  All specified conditions must match (AND logic). If a condition key is not
  specified, it matches any value.

  ## Examples

      # Matches any RED violation
      conditions = %{"limit_state" => ["red"]}
      Matcher.matches?(conditions, event)

      # Matches RED or YELLOW on specific items
      conditions = %{
        "limit_state" => ["red", "yellow"],
        "item_name" => ["HEALTH.cpu_temp", "HEALTH.battery_temp"]
      }
      Matcher.matches?(conditions, event)

      # Matches any violation on POWER.* items
      conditions = %{
        "limit_state" => ["red", "yellow", "blue"],
        "item_name_pattern" => "POWER\\..*"
      }
      Matcher.matches?(conditions, event)
  """

  alias Cadence.Alarms.AlarmRule
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

  @doc """
  Checks if an event matches a rule's conditions.
  """
  @spec matches?(AlarmRule.t(), TelemetryLimitEvent.t()) :: boolean()
  def matches?(%AlarmRule{conditions: conditions}, %TelemetryLimitEvent{} = event) do
    matches_conditions?(conditions, event)
  end

  @doc """
  Checks if an event matches a set of conditions.
  """
  @spec matches_conditions?(map(), TelemetryLimitEvent.t()) :: boolean()
  def matches_conditions?(conditions, %TelemetryLimitEvent{} = event) when is_map(conditions) do
    Enum.all?(conditions, fn {key, value} ->
      matches_condition?(key, value, event)
    end)
  end

  def matches_conditions?(_, _), do: false

  @doc """
  Finds the first matching rule from a list of rules.

  Rules should be pre-sorted by specificity (most specific first).
  """
  @spec find_matching_rule([AlarmRule.t()], TelemetryLimitEvent.t()) :: AlarmRule.t() | nil
  def find_matching_rule(rules, %TelemetryLimitEvent{} = event) do
    Enum.find(rules, &matches?(&1, event))
  end

  @doc """
  Finds all matching rules from a list.
  """
  @spec find_all_matching_rules([AlarmRule.t()], TelemetryLimitEvent.t()) :: [AlarmRule.t()]
  def find_all_matching_rules(rules, %TelemetryLimitEvent{} = event) do
    Enum.filter(rules, &matches?(&1, event))
  end

  # ============================================================================
  # Condition Matchers
  # ============================================================================

  # limit_state - matches if event's new_state is in the list
  defp matches_condition?("limit_state", states, %TelemetryLimitEvent{new_state: new_state})
       when is_list(states) do
    state_string = to_string(new_state)
    state_string in states or new_state in states
  end

  # item_name - matches if event's item_name is in the list
  defp matches_condition?("item_name", names, %TelemetryLimitEvent{item_name: item_name})
       when is_list(names) do
    item_name in names
  end

  # item_name_pattern - matches if event's item_name matches the regex
  defp matches_condition?("item_name_pattern", pattern, %TelemetryLimitEvent{item_name: item_name})
       when is_binary(pattern) do
    # Fallback for non-cached rules - compile on the fly
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, item_name)
      {:error, _} -> false
    end
  end

  # Pre-compiled regex from RuleCache - use directly without recompiling
  defp matches_condition?(:compiled_item_name_pattern, %Regex{} = regex, %TelemetryLimitEvent{item_name: item_name}) do
    Regex.match?(regex, item_name)
  end

  # target_id - matches if event's target_id is in the list
  defp matches_condition?("target_id", targets, %TelemetryLimitEvent{target_id: target_id})
       when is_list(targets) do
    target_id in targets
  end

  # Unknown condition - ignore (matches anything)
  defp matches_condition?(_, _, _), do: true

  # ============================================================================
  # Message Template Rendering
  # ============================================================================

  @doc """
  Renders a message template with event data.

  ## Variables

  - `{{item_name}}` - Telemetry item name
  - `{{value}}` - Current value
  - `{{limit_state}}` - New limit state
  - `{{previous_state}}` - Previous limit state
  - `{{target_id}}` - Target identifier
  - `{{limit_set}}` - Active limit set name

  ## Example

      template = "{{item_name}} is {{limit_state}} (value: {{value}})"
      render_message(template, event)
      #=> "HEALTH.cpu_temp is red (value: 105.2)"
  """
  @spec render_message(String.t() | nil, TelemetryLimitEvent.t()) :: String.t()
  def render_message(nil, %TelemetryLimitEvent{} = event) do
    # Default message
    "#{event.item_name} transitioned to #{event.new_state}" <>
      if event.value, do: " (value: #{event.value})", else: ""
  end

  def render_message(template, %TelemetryLimitEvent{} = event) when is_binary(template) do
    template
    |> String.replace("{{item_name}}", event.item_name || "")
    |> String.replace("{{value}}", format_value(event.value))
    |> String.replace("{{limit_state}}", to_string(event.new_state))
    |> String.replace("{{previous_state}}", to_string(event.previous_state))
    |> String.replace("{{target_id}}", event.target_id || "")
    |> String.replace("{{limit_set}}", event.limit_set || "")
  end

  defp format_value(nil), do: "N/A"
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_value(value), do: to_string(value)

  # ============================================================================
  # Severity Mapping
  # ============================================================================

  @doc """
  Maps a limit state to a default severity if not specified by the rule.
  """
  @spec default_severity_for_state(atom()) :: :info | :warning | :critical
  def default_severity_for_state(:red), do: :critical
  def default_severity_for_state(:yellow), do: :warning
  def default_severity_for_state(:blue), do: :info
  def default_severity_for_state(_), do: :info
end
