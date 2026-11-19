defmodule Cadence.Alarms.Sources do
  @moduledoc """
  Maps source records to `Cadence.Alarms.Episodes` observations.

  - **Catalog monitoring** (XTCE alarms, evaluated live in runtime partitions): `watch` and
    `warning` are caution; `distress`, `critical` and `severe` are critical; `normal` clears;
    `unknown` and `disabled` don't change an episode.
  - **Ground limits** (Limits & Alarming, evaluated by jobs): yellow is caution, red is
    critical, green clears, blue doesn't change an episode. Ground episodes record when they were
    last *evaluated*, so the UI can say "evaluated 3m ago" instead of implying live data.
  """

  alias Cadence.Limits.Event

  @catalog_levels %{
    "normal" => :normal,
    "watch" => :caution,
    "warning" => :caution,
    "distress" => :critical,
    "critical" => :critical,
    "severe" => :critical
  }

  @doc """
  Observation for one catalog monitoring transition. `match` is the rule that opened or escalated
  it (`MonitoringEvaluator.matched_rule/3`, or `nil`); its kind, id and label go into the episode
  `context` as `rule_kind`, `rule_id` and `rule_label` (flight events).
  """
  @spec catalog(map(), map(), String.t(), map() | nil) :: map()
  def catalog(evaluation_attrs, update, transition_id, match \\ nil) do
    to_state = evaluation_attrs.effective_state
    observed_at = update.generation_time || update.receipt_time

    %{
      source: "catalog_monitoring",
      organization_id: evaluation_attrs.organization_id,
      mission_id: evaluation_attrs.mission_id,
      spacecraft_id: evaluation_attrs.spacecraft_id,
      subject_key: evaluation_attrs.parameter_id <> "/" <> evaluation_attrs.policy_id,
      parameter_ref: evaluation_attrs.parameter_id,
      point_name: Map.get(update, :qualified_name),
      level: Map.get(@catalog_levels, to_state, :ignore),
      source_state: to_state,
      value: Map.get(update, :value),
      observed_at: observed_at,
      evaluated_at: update.receipt_time,
      ref: transition_id,
      context:
        Map.merge(
          %{
            "policy_id" => evaluation_attrs.policy_id,
            "mission_model_revision_id" => evaluation_attrs.mission_model_revision_id
          },
          rule_context(match)
        )
    }
  end

  defp rule_context(%{kind: kind, id: id, label: label}),
    do: %{"rule_kind" => kind, "rule_id" => id, "rule_label" => label}

  defp rule_context(_none), do: %{}

  @doc "Observation for one ground-limit evaluation event."
  @spec ground(Event.t(), DateTime.t()) :: map()
  def ground(%Event{} = event, evaluated_at) do
    %{
      source: "ground_limit",
      organization_id: nil,
      mission_id: event.mission_id,
      spacecraft_id: event.spacecraft_id,
      subject_key: event.point_id,
      parameter_ref: event.point_id,
      point_name: event.point_name,
      level: ground_level(event.normalized_state),
      source_state: to_string(event.limit_state),
      value: event.evaluated_value,
      observed_at: event.generation_time || event.receipt_time,
      evaluated_at: evaluated_at,
      ref: event.limit_event_id,
      context: %{
        "limit_definition_id" => event.limit_definition_id,
        "limit_definition_version" => event.limit_definition_version,
        "limit_set_name" => event.limit_set_name
      }
    }
  end

  defp ground_level(:red), do: :critical
  defp ground_level(:yellow), do: :caution
  defp ground_level(:green), do: :normal
  defp ground_level(_other), do: :ignore
end
