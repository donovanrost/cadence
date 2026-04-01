defmodule Cadence.Alarms.SuggestionStrategy.Default do
  @moduledoc """
  Default suggestion strategy that generates two rules per parameter.

  This is the basic strategy that creates:
  - One critical-severity rule for `red` limit states
  - One warning-severity rule for `yellow` limit states

  Messages are simple and uniform across all parameter types.
  """

  @behaviour Cadence.Alarms.SuggestionStrategy

  @impl true
  def name, do: "Default"

  @impl true
  def description do
    "Generates basic critical/warning rule pairs for all parameters"
  end

  @impl true
  def suggest(parameter, _context) do
    [
      build_suggestion(parameter, :critical, ["red"]),
      build_suggestion(parameter, :warning, ["yellow"])
    ]
  end

  defp build_suggestion(param, severity, limit_states) do
    severity_label = String.upcase(to_string(severity))

    %{
      name: "#{param.qualified_name} #{severity_label}",
      event_type: "telemetry_limit",
      conditions: %{
        "limit_state" => limit_states,
        "item_name" => [param.qualified_name]
      },
      severity: severity,
      message_template: build_message_template(param, severity),
      parameter: param,
      rationale: nil,
      confidence: 1.0
    }
  end

  defp build_message_template(param, :critical) do
    "CRITICAL: #{param.qualified_name} is {{limit_state}} ({{value}})"
  end

  defp build_message_template(param, :warning) do
    "WARNING: #{param.qualified_name} is {{limit_state}} ({{value}})"
  end

  defp build_message_template(param, :info) do
    "INFO: #{param.qualified_name} is {{limit_state}} ({{value}})"
  end
end
