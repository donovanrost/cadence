defmodule CadenceWeb.OpsDashboardShowLive.EvidenceAttrs do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery

  @spec source_health(map()) :: map()
  def source_health(source) when is_map(source) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "source",
      "source-evidence-mode" => "health",
      "source-request-id" => event_value(source, :request_id),
      "logical-source" => event_value(source, :logical_source),
      "realm" => event_value(source, :realm),
      "data-source-id" => event_value(source, :data_source_id),
      "source-binding-id" => event_value(source, :source_binding_id),
      "source-health-event-id" => event_value(source, :source_health_event_id),
      "source-health-reason" => event_value(source, :source_health_reason),
      "source-health-probe-kind" => event_value(source, :source_health_probe_kind),
      "source-health-probe-message" => event_value(source, :source_health_probe_message),
      "source-health-probe-metadata" => event_value(source, :source_health_probe_metadata_text)
    })
  end

  def source_health(_source), do: %{}

  @spec source_status(map()) :: map()
  def source_status(source_status) when is_map(source_status) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "source",
      "source-evidence-mode" => source_status_evidence_mode(source_status),
      "source-evidence-state" => event_value(source_status, :state),
      "source-request-id" => first_event_value(source_status, :source_request_ids),
      "logical-source" => first_event_value(source_status, :logical_sources),
      "realm" => first_event_value(source_status, :realms),
      "data-source-id" => first_event_value(source_status, :data_source_ids),
      "source-binding-id" => first_event_value(source_status, :source_binding_ids),
      "time-mode" => first_event_value(source_status, :time_modes),
      "time-axis" => first_event_value(source_status, :time_axes),
      "replay-run-id" => first_event_value(source_status, :replay_run_ids),
      "scope-kind" => first_event_value(source_status, :scope_kinds),
      "scope-id" => first_event_value(source_status, :scope_ids),
      "scope-ids" => event_values(source_status, :scope_ids),
      "contact-id" => first_event_value(source_status, :contact_ids),
      "contact-ids" => event_values(source_status, :contact_ids),
      "source-endpoint-id" => first_event_value(source_status, :source_endpoint_ids),
      "source-health-state" => first_event_value(source_status, :source_health_states),
      "source-health-event-id" => first_event_value(source_status, :source_health_event_ids),
      "source-health-reason" => first_event_value(source_status, :source_health_reasons),
      "source-empty-reason" => event_value(source_status, :empty_reason)
    })
  end

  def source_status(_source_status), do: %{}

  @spec frame(term(), term()) :: map()
  def frame(placement_id, observable_id) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "frame",
      "placement-id" => event_value(placement_id),
      "observable-id" => event_value(observable_id)
    })
  end

  @spec widget_frame(term(), term(), term()) :: map()
  def widget_frame(placement_id, observable_id, %{rows: [row | _]}) when is_map(row) do
    row =
      if is_nil(observable_id) or observable_id == "" do
        row
      else
        Map.put(row, :frame_observable_id, observable_id)
      end

    row_frame(placement_id, row)
  end

  def widget_frame(placement_id, observable_id, data) when is_map(data) do
    data =
      if is_nil(observable_id) or observable_id == "" do
        data
      else
        Map.put(data, :frame_observable_id, observable_id)
      end

    if frame_source_context?(data) do
      row_frame(placement_id, data)
    else
      frame(placement_id, observable_id)
    end
  end

  def widget_frame(placement_id, observable_id, _data), do: frame(placement_id, observable_id)

  @spec row_frame(term(), map()) :: map()
  def row_frame(placement_id, row) when is_map(row) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "frame",
      "placement-id" => event_value(placement_id),
      "observable-id" => event_value(frame_observable_id(row)),
      "source-request-id" => event_value(row, :source_request_id),
      "logical-source" => event_value(row, :logical_source),
      "realm" => event_value(row, :realm),
      "data-source-id" => event_value(row, :data_source_id),
      "source-binding-id" => event_value(row, :source_binding_id),
      "replay-run-id" => event_value(row, :replay_run_id),
      "scope-kind" => row_scope_kind(row),
      "scope-id" => row_scope_id(row),
      "scope-ids" => row_scope_ids(row),
      "requested-dataset" => event_value(row, :dataset)
    })
  end

  def row_frame(placement_id, _row), do: frame(placement_id, nil)

  @spec warning(map(), term()) :: map()
  def warning(warning, placement_id) when is_map(warning) do
    details = Map.get(warning, :details, %{})

    EvidenceQuery.phx_value_attrs(%{
      "kind" => "warning",
      "warning-code" => event_value(warning, :code_text),
      "placement-id" => event_value(placement_id),
      "source-request-id" => event_value(details, :source_request_id),
      "logical-source" => event_value(details, :logical_source),
      "realm" => event_value(details, :realm),
      "data-source-id" => event_value(details, :data_source_id),
      "source-binding-id" => event_value(details, :source_binding_id)
    })
  end

  def warning(_warning, placement_id), do: warning(%{}, placement_id)

  @spec cache(map()) :: map()
  def cache(item) when is_map(item) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "source",
      "source-evidence-mode" => cache_source_evidence_mode(item),
      "source-evidence-state" => cache_event_value(item, :evidence_state),
      "cache-evidence-layer" => cache_event_value(item, :layer),
      "cache-evidence-status" => cache_event_value(item, :status),
      "cache-evidence-reasons" => cache_event_value(item, :reasons),
      "source-request-id" => cache_event_value(item, :request_id),
      "logical-source" => cache_event_value(item, :logical_source),
      "realm" => cache_event_value(item, :realm),
      "data-source-id" => cache_event_value(item, :data_source_id),
      "source-binding-id" => cache_event_value(item, :source_binding_id),
      "requested-realm" => cache_event_value(item, :realm),
      "requested-data-source-id" => cache_event_value(item, :data_source_id),
      "requested-source-binding-id" => cache_event_value(item, :source_binding_id)
    })
  end

  def cache(_item), do: %{}

  @spec degraded_source(map()) :: map()
  def degraded_source(drilldown) when is_map(drilldown) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "source",
      "source-evidence-mode" => "execution",
      "source-request-id" => event_value(drilldown, :request_id),
      "logical-source" => event_value(drilldown, :logical_source),
      "realm" => event_value(drilldown, :realm),
      "data-source-id" => event_value(drilldown, :data_source_id),
      "source-binding-id" => event_value(drilldown, :source_binding_id)
    })
  end

  def degraded_source(_drilldown), do: %{}

  @spec source_capability_posture(map()) :: map()
  def source_capability_posture(posture) when is_map(posture) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "source",
      "source-evidence-mode" => "execution",
      "source-capability-status" => event_value(posture, :status),
      "source-request-id" => event_value(posture, :request_id),
      "logical-source" => event_value(posture, :logical_source),
      "realm" => event_value(posture, :realm),
      "data-source-id" => event_value(posture, :data_source_id),
      "source-binding-id" => event_value(posture, :source_binding_id),
      "requested-time-axis" => event_value(posture, :requested_time_axis),
      "executed-time-axis" => event_value(posture, :executed_time_axis),
      "supported-time-axes" => event_value(posture, :supported_time_axes),
      "requested-sampling" => event_value(posture, :requested_sampling),
      "supported-sampling" => event_value(posture, :supported_sampling),
      "requested-products" => event_value(posture, :requested_products),
      "supported-products" => event_value(posture, :supported_products),
      "source-capability-fallbacks" => event_value(posture, :fallbacks),
      "source-capability-unsupported" => event_value(posture, :unsupported)
    })
  end

  def source_capability_posture(_posture), do: %{}

  defp frame_observable_id(row) do
    Map.get(row, :frame_observable_id) || Map.get(row, :observable_id)
  end

  defp row_scope_kind(row) do
    event_value(row, :query_scope_kind) || event_value(row, :scope_kind)
  end

  defp row_scope_id(row) do
    first_event_value(row, :query_scope_ids) || event_value(row, :query_scope_id) ||
      event_value(row, :scope_id)
  end

  defp row_scope_ids(row) do
    event_values(row, :query_scope_ids) || event_values(row, :scope_ids)
  end

  defp frame_source_context?(data) do
    Enum.any?(
      [
        :source_request_id,
        :logical_source,
        :realm,
        :data_source_id,
        :source_binding_id,
        :query_scope_kind,
        :query_scope_id,
        :query_scope_ids
      ],
      fn key ->
        present?(Map.get(data, key))
      end
    )
  end

  defp present?(value), do: value not in [nil, "", []]

  defp cache_source_evidence_mode(%{incident_status_text: status}) when status not in [nil, "-"],
    do: "execution"

  defp cache_source_evidence_mode(_item), do: "health"

  defp source_status_evidence_mode(source_status) do
    case Map.get(source_status, :state, Map.get(source_status, "state")) do
      state when state in [:unavailable, "unavailable"] -> "execution"
      _state -> "health"
    end
  end

  defp first_event_value(map, key) when is_map(map) do
    map
    |> Map.get(key, Map.get(map, Atom.to_string(key)))
    |> List.wrap()
    |> List.first()
    |> event_value()
  end

  defp event_values(map, key) when is_map(map) do
    values =
      map
      |> Map.get(key, Map.get(map, Atom.to_string(key)))
      |> List.wrap()
      |> Enum.map(&event_value/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    if length(values) > 1, do: Enum.join(values, ",")
  end

  defp cache_event_value(map, key) do
    case event_value(map, key) do
      "-" -> nil
      value -> value
    end
  end

  defp event_value(map, key) when is_map(map), do: event_value(Map.get(map, key))
  defp event_value(nil), do: nil
  defp event_value(value) when is_atom(value), do: Atom.to_string(value)
  defp event_value(value), do: to_string(value)
end
