defmodule CadenceWeb.API.MissionJSON do
  @moduledoc "Mission projection response serialization boundary."

  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.MissionEvents.Entry, as: MissionEventEntry
  alias Cadence.Reads.MissionHealth

  def mission_event(organization_id, %MissionEventEntry{} = mission_event) do
    %{
      mission_event_id: mission_event.mission_event_id,
      organization_id: organization_id,
      mission_id: mission_event.mission_id,
      occurred_at: iso8601(mission_event.occurred_at),
      category: maybe_atom_to_string(mission_event.category),
      kind: maybe_atom_to_string(mission_event.kind),
      severity: maybe_atom_to_string(mission_event.severity),
      status: mission_event.status,
      title: mission_event.title,
      summary: mission_event.summary,
      source_record_kind: maybe_atom_to_string(mission_event.source_record_kind),
      source_record_id: mission_event.source_record_id,
      subject_kind: maybe_atom_to_string(mission_event.subject_kind),
      subject_id: mission_event.subject_id,
      correlation_key: mission_event.correlation_key,
      spacecraft_id: mission_event.spacecraft_id,
      source_endpoint_ref: mission_event.source_endpoint_ref,
      scheduled_contact_id: mission_event.scheduled_contact_id,
      realized_contact_id: mission_event.realized_contact_id,
      path_id: mission_event.path_id,
      capability_instance_id: mission_event.capability_instance_id,
      activation_id: mission_event.activation_id,
      actor: mission_event.actor,
      metadata: mission_event.metadata
    }
  end

  def mission_health(organization_id, %MissionHealth{} = mission_health) do
    %{
      organization_id: organization_id,
      mission_id: mission_health.mission_id,
      total_points: mission_health.total_points,
      violating_points: mission_health.violating_points,
      normalized_state_counts: mission_health.normalized_state_counts,
      worst_normalized_state: maybe_atom_to_string(mission_health.worst_normalized_state),
      updated_at: iso8601(mission_health.updated_at),
      point_buckets: point_buckets(mission_health.point_buckets),
      scope_summaries: Enum.map(mission_health.scope_summaries, &scope_summary/1)
    }
  end

  defp scope_summary(scope_summary) do
    %{
      scope_id: scope_summary.scope_id,
      scope_kind: maybe_atom_to_string(scope_summary.scope_kind),
      scope_label: scope_summary.scope_label,
      spacecraft_id: scope_summary.spacecraft_id,
      total_points: scope_summary.total_points,
      violating_points: scope_summary.violating_points,
      normalized_state_counts: scope_summary.normalized_state_counts,
      worst_normalized_state: maybe_atom_to_string(scope_summary.worst_normalized_state),
      updated_at: iso8601(scope_summary.updated_at),
      point_buckets: point_buckets(scope_summary.point_buckets)
    }
  end

  defp point_buckets(point_buckets) when is_map(point_buckets) do
    %{
      red: Enum.map(Map.get(point_buckets, :red, []), &limit_event/1),
      yellow: Enum.map(Map.get(point_buckets, :yellow, []), &limit_event/1),
      green: Enum.map(Map.get(point_buckets, :green, []), &limit_event/1),
      blue: Enum.map(Map.get(point_buckets, :blue, []), &limit_event/1)
    }
  end

  defp limit_event(%LimitEvent{} = limit_event) do
    %{
      limit_event_id: limit_event.limit_event_id,
      mission_id: limit_event.mission_id,
      spacecraft_id: limit_event.spacecraft_id,
      point_id: limit_event.point_id,
      point_name: limit_event.point_name,
      source_sample_type: maybe_atom_to_string(limit_event.source_sample_type),
      sample_id: limit_event.sample_id,
      limit_definition_id: limit_event.limit_definition_id,
      limit_definition_version: limit_event.limit_definition_version,
      limit_set_name: limit_event.limit_set_name,
      evaluated_value: limit_event.evaluated_value,
      limit_state: maybe_atom_to_string(limit_event.limit_state),
      normalized_state: maybe_atom_to_string(limit_event.normalized_state),
      violation: limit_event.violation,
      generation_time: iso8601(limit_event.generation_time),
      receipt_time: iso8601(limit_event.receipt_time),
      provenance: limit_event.provenance
    }
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value
  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
