defmodule Cadence.Dashboards.Sources.OperationalObservables.AntennaPointingFrames do
  @moduledoc """
  Builds latest and historical ground-station antenna-pointing frames.
  """

  alias Cadence.Dashboards.{DataLinks, Field, Frame, PlannedSourceRequest}

  @spec latest(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def latest(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:ground_station_antenna_pointing_state",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields:
        [
          field("observable_id", :string, rows, :observable_id),
          field("resource_id", :string, rows, :resource_id),
          field("label", :string, rows, :label),
          field("scope_kind", :enum, rows, :scope_kind),
          field("transport_id", :string, rows, :transport_id),
          field("source_endpoint_id", :string, rows, :source_endpoint_id),
          field("ground_station_id", :string, rows, :ground_station_id),
          field("link_id", :string, rows, :link_id),
          field("adapter_key", :enum, rows, :adapter_key),
          field("state", :enum, rows, :state),
          field("normalized_state", :enum, rows, :normalized_state),
          field("observed_at", :time, rows, :observed_at),
          field("freshness_state", :enum, rows, :freshness_state),
          field("age_ms", :number, rows, :age_ms)
        ] ++ interval_identity_fields(rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :ground_station_antenna_pointing_state,
          product_family: :ground_station,
          state_color_policy: :antenna_pointing_state,
          observable_ids: observable_ids(rows),
          observable_id: "ground.station.antenna_pointing_state",
          returned_points: length(rows),
          freshness_policy: latest_freshness_policy(rows),
          freshness_checked_at: latest_freshness_checked_at(rows),
          warning_codes: latest_freshness_warning_codes(rows),
          links: operational_links(request, rows),
          evidence_refs: interval_evidence_refs(rows)
        })
    }
  end

  @spec history(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def history(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:ground_station_antenna_pointing_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "time",
            kind: :time,
            values: values(rows, :observed_at),
            metadata: %{axis: :occurred_at}
          },
          field("observable_id", :string, rows, :observable_id),
          field("resource_id", :string, rows, :resource_id),
          field("lane_id", :string, rows, :ground_station_id),
          field("label", :string, rows, :label),
          field("scope_kind", :enum, rows, :scope_kind),
          field("transport_id", :string, rows, :transport_id),
          field("source_endpoint_id", :string, rows, :source_endpoint_id),
          field("ground_station_id", :string, rows, :ground_station_id),
          field("link_id", :string, rows, :link_id),
          field("adapter_key", :enum, rows, :adapter_key),
          field("state", :enum, rows, :state),
          field("normalized_state", :enum, rows, :normalized_state)
        ] ++ interval_identity_fields(rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :event_history,
          supported_capability: :ground_station_antenna_pointing_state_history,
          product_family: :ground_station,
          state_color_policy: :antenna_pointing_state,
          observable_ids: observable_ids(rows),
          observable_id: "ground.station.antenna_pointing_state",
          returned_points: length(rows),
          warning_codes: [],
          links: operational_links(request, rows),
          evidence_refs: interval_evidence_refs(rows)
        })
    }
  end

  defp field(name, kind, rows, key) do
    %Field{name: name, kind: kind, values: values(rows, key)}
  end

  defp values(rows, key), do: Enum.map(rows, &attr(&1, key))

  defp interval_identity_fields(rows) do
    if Enum.any?(rows, &(attr(&1, :interval_id) || attr(&1, :source_event_id))) do
      [
        field("interval_id", :string, rows, :interval_id),
        field("source_event_id", :string, rows, :source_event_id)
      ]
    else
      []
    end
  end

  defp observable_ids(rows), do: rows |> values(:observable_id) |> Enum.uniq()

  defp latest_freshness_warning_codes(rows) do
    rows
    |> values(:freshness_state)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      :stale -> [:stale_data]
      :missing -> [:missing_snapshot]
      :unknown -> [:watermark_unknown]
      _state -> []
    end)
    |> Enum.uniq()
  end

  defp latest_freshness_policy([%{freshness_policy: policy} | _rows]), do: policy
  defp latest_freshness_policy(_rows), do: %{}

  defp latest_freshness_checked_at([row | _rows]) do
    case attr(row, :freshness_checked_at) do
      %DateTime{} = checked_at -> checked_at
      _value -> nil
    end
  end

  defp latest_freshness_checked_at(_rows), do: nil

  defp operational_links(request, rows) do
    DataLinks.operational_resource_links(request, rows, source: :frame) ++
      DataLinks.operational_event_links(request, rows, source: :frame)
  end

  defp interval_evidence_refs(rows) do
    rows
    |> values(:interval)
    |> DataLinks.operational_interval_evidence_refs(source: :operational_observables)
  end

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
