defmodule Cadence.Dashboards.Sources.OperationalObservables.OperationalMetricFrames do
  @moduledoc """
  Builds latest and historical frames for numeric operational metrics.

  The source adapter supplies materialized rows and source identity. This module
  owns the RF metric, transport bitrate, ingress latency, and wide-history field
  contracts plus their operational evidence metadata.
  """

  alias Cadence.Dashboards.{DataLinks, Field, Frame, PlannedSourceRequest}
  alias Cadence.Dashboards.Sources.OperationalObservables.ProductPolicy

  @spec link_rf_latest(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def link_rf_latest(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:link_rf_metric",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: metric_fields(rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :link_rf_metric,
          product_family: :link_rf,
          observable_ids: observable_ids(rows),
          returned_points: length(rows),
          freshness_policy: latest_freshness_policy(rows),
          freshness_checked_at: latest_freshness_checked_at(rows),
          warning_codes: latest_freshness_warning_codes(rows),
          links: operational_links(request, rows),
          evidence_refs: operational_evidence_refs(rows)
        })
    }
  end

  @spec transport_bitrate_latest(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def transport_bitrate_latest(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:transport_bitrate",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: metric_fields(rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :transport_bitrate,
          observable_ids: observable_ids(rows),
          observable_id: single_observable_id(rows),
          unit: "bit/s",
          returned_points: length(rows),
          freshness_policy: latest_freshness_policy(rows),
          freshness_checked_at: latest_freshness_checked_at(rows),
          warning_codes: latest_freshness_warning_codes(rows),
          links: operational_links(request, rows),
          evidence_refs: operational_evidence_refs(rows)
        })
    }
  end

  @spec ingress_latency_latest(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def ingress_latency_latest(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:ingress_processing_latency",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: ingress_latency_fields(rows),
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :ingress_processing_latency,
          product_family: :runtime_ingress,
          observable_ids: observable_ids(rows),
          observable_id: "ingress.processing_latency_ms",
          unit: "ms",
          returned_points: length(rows),
          freshness_policy: latest_freshness_policy(rows),
          freshness_checked_at: latest_freshness_checked_at(rows),
          warning_codes: latest_freshness_warning_codes(rows),
          links: operational_links(request, rows),
          evidence_refs: operational_evidence_refs(rows)
        })
    }
  end

  @spec history(PlannedSourceRequest.t(), [map()], atom(), map()) :: [Frame.t()]
  def history(%PlannedSourceRequest{} = request, rows, capability, source_context) do
    rows
    |> Enum.group_by(&history_series_key/1)
    |> Enum.sort_by(fn {series_key, _rows} -> series_key end)
    |> Enum.map(fn {_series_key, series_rows} ->
      history_frame(request, series_rows, capability, source_context)
    end)
    |> mark_partial_history_frames()
  end

  defp metric_fields(rows) do
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
      field("value", :number, rows, :value),
      field("unit", :string, rows, :unit),
      field("observed_at", :time, rows, :observed_at),
      field("freshness_state", :enum, rows, :freshness_state),
      field("age_ms", :number, rows, :age_ms)
    ]
  end

  defp ingress_latency_fields(rows) do
    [
      field("observable_id", :string, rows, :observable_id),
      field("resource_id", :string, rows, :resource_id),
      field("label", :string, rows, :label),
      field("scope_kind", :enum, rows, :scope_kind),
      field("source_endpoint_id", :string, rows, :source_endpoint_id),
      field("transport_id", :string, rows, :transport_id),
      field("ground_station_id", :string, rows, :ground_station_id),
      field("link_id", :string, rows, :link_id),
      field("contact_id", :string, rows, :contact_id),
      field("adapter_key", :enum, rows, :adapter_key),
      field("spacecraft_id", :string, rows, :spacecraft_id),
      field("value", :number, rows, :value),
      field("unit", :string, rows, :unit),
      field("observed_at", :time, rows, :observed_at),
      field("freshness_state", :enum, rows, :freshness_state),
      field("age_ms", :number, rows, :age_ms),
      field("error", :boolean, rows, :error?)
    ]
  end

  defp history_frame(request, rows, capability, source_context) do
    [%{observable_id: observable_id} = first_row | _rest] = rows
    data_rows = Enum.reject(rows, &Map.get(&1, :empty_series?, false))
    resource_links = DataLinks.operational_resource_links(request, [first_row], source: :frame)
    resource_link_id = operational_resource_link_id(resource_links)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:#{first_row.resource_id}",
      source: :operational_observables,
      shape: :wide,
      time_axis: :occurred_at,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: values(data_rows, :observed_at),
          metadata: %{axis: :occurred_at}
        },
        %Field{
          name: observable_id,
          kind: :number,
          values: values(data_rows, :value),
          metadata:
            %{
              observable_id: observable_id,
              label: first_row.label,
              unit: first_row.unit,
              resource_id: first_row.resource_id,
              scope_kind: first_row.scope_kind,
              transport_id: first_row.transport_id,
              source_endpoint_id: first_row.source_endpoint_id,
              ground_station_id: first_row.ground_station_id,
              link_id: first_row.link_id,
              contact_id: Map.get(first_row, :contact_id),
              adapter_key: first_row.adapter_key,
              resource_link_id: resource_link_id,
              links: resource_links
            }
            |> Map.reject(fn {_key, value} -> is_nil(value) end)
        }
      ],
      meta:
        source_context
        |> Map.merge(%{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :raw_series,
          supported_capability: capability,
          product_family: ProductPolicy.metric_history_product_family(observable_id),
          observable_ids: [observable_id],
          observable_id: observable_id,
          resource_id: first_row.resource_id,
          scope_kind: first_row.scope_kind,
          transport_id: first_row.transport_id,
          source_endpoint_id: first_row.source_endpoint_id,
          ground_station_id: first_row.ground_station_id,
          link_id: first_row.link_id,
          adapter_key: first_row.adapter_key,
          unit: first_row.unit,
          returned_points: length(data_rows),
          warning_codes: [],
          resource_link_id: resource_link_id,
          links:
            resource_links ++
              DataLinks.operational_event_links(request, data_rows, source: :frame),
          evidence_refs: operational_evidence_refs(data_rows)
        })
        |> maybe_put_contact_id(Map.get(first_row, :contact_id))
    }
  end

  defp mark_partial_history_frames(frames) do
    returned? = Enum.any?(frames, &(frame_returned_points(&1) > 0))
    empty? = Enum.any?(frames, &(frame_returned_points(&1) == 0))

    if returned? and empty? do
      Enum.map(frames, &put_frame_warning_code(&1, :partial_data))
    else
      frames
    end
  end

  defp frame_returned_points(%Frame{meta: meta}) when is_map(meta) do
    case attr(meta, :returned_points) do
      count when is_integer(count) -> count
      _other -> 0
    end
  end

  defp frame_returned_points(_frame), do: 0

  defp put_frame_warning_code(%Frame{meta: meta} = frame, code) when is_atom(code) do
    warning_codes =
      meta
      |> attr(:warning_codes)
      |> List.wrap()
      |> Kernel.++([code])
      |> Enum.uniq()

    %Frame{frame | meta: Map.put(meta, :warning_codes, warning_codes)}
  end

  defp field(name, kind, rows, key) do
    %Field{name: name, kind: kind, values: values(rows, key)}
  end

  defp values(rows, key), do: Enum.map(rows, &attr(&1, key))

  defp observable_ids(rows) do
    rows
    |> values(:observable_id)
    |> Enum.uniq()
  end

  defp single_observable_id(rows) do
    case observable_ids(rows) do
      [observable_id] -> observable_id
      _observable_ids -> nil
    end
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

  defp operational_evidence_refs(rows) do
    DataLinks.operational_event_evidence_refs(rows, source: :operational_observables)
  end

  defp operational_resource_link_id(links) do
    Enum.find_value(links, fn
      %{link_id: link_id} when is_binary(link_id) and link_id != "" -> link_id
      _link -> nil
    end)
  end

  defp history_series_key(row), do: {row.observable_id, row.resource_id}

  defp maybe_put_contact_id(meta, contact_id) when contact_id in [nil, ""], do: meta
  defp maybe_put_contact_id(meta, contact_id), do: Map.put(meta, :contact_id, contact_id)

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
