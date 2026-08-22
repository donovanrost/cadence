defmodule CadenceWeb.OpsDashboardShowLive.LifecycleRuntimeCorrelation do
  @moduledoc false

  alias Cadence.Dashboards.LifecycleEvent

  @version_change_events [:published, :reverted, :archived, :restored]

  def runtime_impact(%LifecycleEvent{} = event, invalidations) when is_list(invalidations) do
    if version_change_event?(event) do
      event
      |> matching_invalidation(invalidations)
      |> runtime_impact_for_match()
    else
      empty_runtime_impact("not_applicable")
    end
  end

  def runtime_impact(_event, _invalidations), do: empty_runtime_impact("not_applicable")

  def activity_event(invalidation, lifecycle_events)
      when is_map(invalidation) and is_list(lifecycle_events) do
    Enum.find(lifecycle_events, &activity_event_matches?(&1, invalidation))
  end

  def activity_event(_invalidation, _lifecycle_events), do: nil

  def activity_event_id(invalidation, lifecycle_events) do
    case activity_event(invalidation, lifecycle_events) do
      %LifecycleEvent{dashboard_lifecycle_event_id: event_id} -> event_id
      nil -> nil
    end
  end

  def empty_runtime_impact(state) do
    %{
      state: state,
      label: runtime_impact_label(state, nil),
      invalidation_id: nil,
      context_match: nil,
      refresh_allowed: nil,
      refresh_action: nil,
      context_reason: nil,
      refresh_reason: nil
    }
  end

  defp matching_invalidation(%LifecycleEvent{} = event, invalidations) do
    Enum.find(invalidations, &activity_event_matches?(event, &1))
  end

  defp activity_event_matches?(%LifecycleEvent{} = lifecycle_event, invalidation)
       when is_map(invalidation) do
    lifecycle_action = Map.get(invalidation, :lifecycle_action)
    target_version = Map.get(invalidation, :document_version)
    source_version = Map.get(invalidation, :source_version)

    Atom.to_string(lifecycle_event.event_type) == lifecycle_action and
      version_attr_value(lifecycle_event.dashboard_version) == target_version and
      source_version_matches?(lifecycle_event.event_type, source_version, lifecycle_event)
  end

  defp activity_event_matches?(_event, _invalidation), do: false

  defp source_version_matches?(:reverted, source_version, lifecycle_event) do
    version_attr_value(LifecycleEvent.source_version(lifecycle_event)) == source_version
  end

  defp source_version_matches?(_event_type, _source_version, _lifecycle_event), do: true

  defp runtime_impact_for_match(nil), do: empty_runtime_impact("not_observed")

  defp runtime_impact_for_match(invalidation) when is_map(invalidation) do
    context_match = Map.get(invalidation, :context_match)
    refresh_allowed = Map.get(invalidation, :refresh_allowed)

    state =
      cond do
        context_match == "false" -> "context_filtered"
        refresh_allowed == "true" -> "refresh_allowed"
        refresh_allowed == "false" -> "refresh_suppressed"
        true -> "observed"
      end

    %{
      state: state,
      label: runtime_impact_label(state, invalidation),
      invalidation_id: Map.get(invalidation, :id),
      context_match: context_match,
      refresh_allowed: refresh_allowed,
      refresh_action: Map.get(invalidation, :refresh_action),
      context_reason: Map.get(invalidation, :context_reason_label),
      refresh_reason: Map.get(invalidation, :refresh_allowed_reason_label)
    }
  end

  defp runtime_impact_label("not_applicable", _invalidation), do: nil
  defp runtime_impact_label("not_observed", _invalidation), do: "No runtime invalidation observed"

  defp runtime_impact_label("context_filtered", invalidation) do
    "Runtime invalidation filtered: #{Map.get(invalidation, :context_reason_label, "-")}"
  end

  defp runtime_impact_label("refresh_allowed", invalidation) do
    "Runtime refresh allowed: #{Map.get(invalidation, :refresh_action, "-")}"
  end

  defp runtime_impact_label("refresh_suppressed", invalidation) do
    "Runtime refresh suppressed: #{Map.get(invalidation, :refresh_allowed_reason_label, "-")}"
  end

  defp runtime_impact_label(_state, _invalidation), do: "Runtime invalidation observed"

  defp version_change_event?(%LifecycleEvent{event_type: event_type}) do
    event_type in @version_change_events
  end

  defp version_attr_value(nil), do: "-"
  defp version_attr_value(version) when is_integer(version), do: Integer.to_string(version)
  defp version_attr_value(version) when is_binary(version), do: version
  defp version_attr_value(version), do: to_string(version)
end
