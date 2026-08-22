defmodule Cadence.Dashboards.Sources.OperationalObservables.ConnectionFrames do
  @moduledoc """
  Builds latest and historical connection-state operational frames.

  The source adapter supplies resolved connection rows and source identity.
  This module owns the connection field contract, freshness presentation,
  operational links, and interval evidence metadata.
  """

  alias Cadence.Dashboards.{DataLinks, Field, Frame, PlannedSourceRequest}

  @spec latest(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def latest(%PlannedSourceRequest{} = request, connection_rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:connection_state",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields:
        [
          field("observable_id", :string, connection_rows, :observable_id),
          field("resource_id", :string, connection_rows, :resource_id),
          field("label", :string, connection_rows, :label),
          field("scope_kind", :enum, connection_rows, :scope_kind),
          field("transport_id", :string, connection_rows, :transport_id),
          field("source_endpoint_id", :string, connection_rows, :source_endpoint_id),
          field("ground_station_id", :string, connection_rows, :ground_station_id),
          field("link_id", :string, connection_rows, :link_id),
          field("adapter_key", :enum, connection_rows, :adapter_key),
          field("connection_state", :enum, connection_rows, :connection_state),
          field("observed_at", :time, connection_rows, :observed_at),
          field("freshness_state", :enum, connection_rows, :freshness_state),
          field("age_ms", :number, connection_rows, :age_ms)
        ] ++ interval_identity_fields(connection_rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :connection_state,
          observable_ids: observable_ids(connection_rows),
          returned_points: length(connection_rows),
          freshness_policy: latest_freshness_policy(connection_rows),
          freshness_checked_at: latest_freshness_checked_at(connection_rows),
          warning_codes: latest_freshness_warning_codes(connection_rows),
          links: operational_links(request, connection_rows),
          evidence_refs: interval_evidence_refs(connection_rows)
        })
    }
  end

  @spec history(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def history(%PlannedSourceRequest{} = request, connection_rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:connection_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "time",
            kind: :time,
            values: values(connection_rows, :observed_at),
            metadata: %{axis: :occurred_at}
          },
          field("observable_id", :string, connection_rows, :observable_id),
          field("resource_id", :string, connection_rows, :resource_id),
          field("label", :string, connection_rows, :label),
          field("scope_kind", :enum, connection_rows, :scope_kind),
          field("transport_id", :string, connection_rows, :transport_id),
          field("source_endpoint_id", :string, connection_rows, :source_endpoint_id),
          field("ground_station_id", :string, connection_rows, :ground_station_id),
          field("link_id", :string, connection_rows, :link_id),
          field("adapter_key", :enum, connection_rows, :adapter_key),
          field("connection_state", :enum, connection_rows, :connection_state),
          field("normalized_state", :enum, connection_rows, :connection_state)
        ] ++ interval_identity_fields(connection_rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :event_history,
          supported_capability: :connection_state_history,
          observable_ids: observable_ids(connection_rows),
          returned_points: length(connection_rows),
          warning_codes: [],
          links: operational_links(request, connection_rows),
          evidence_refs: interval_evidence_refs(connection_rows)
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

  defp observable_ids(rows) do
    rows
    |> values(:observable_id)
    |> Enum.uniq()
  end

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
    Map.get(value, key) || Map.get(value, Atom.to_string(key))
  end

  defp attr(_value, _key), do: nil
end
