defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractSourceEndpointNoDataTimeSeriesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias Cadence.Management.DataSources

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)
  @optional_link_context_paths [
    logical_source: [:logical_source],
    observable_id: [:observable_id],
    scope_kind: [:scope, :primary, :kind],
    time_mode: [:time, :mode],
    time_axis: [:time, :axis],
    realm: [:data, :realm],
    data_source_id: [:data, :data_source_id],
    source_binding_id: [:data, :source_binding_id],
    source_request_id: [:source_request_id]
  ]

  test "golden source-endpoint no-data time-series fixture explains direct source endpoint filtering" do
    document = load_fixture!("source_endpoint_no_data_time_series.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_power_trend_source_endpoint_no_data" => %{width_px: 640, height_px: 256}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    registry_opts = time_series_source_registry_opts(validate_dashboard_contract?: true)
    plan = Engine.plan(request, registry_opts)

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    result =
      Engine.resolve(
        request,
        time_series_source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_endpoint_no_data_time_series_source_opts(parent)
        )
      )

    assert_receive {:source_endpoint_decimated_history_opts, "tlm.hk.battery_voltage",
                    voltage_opts}

    assert_receive {:source_endpoint_decimated_history_opts, "tlm.hk.bus_current", current_opts}
    assert voltage_opts[:source_endpoint_ids] == ["source-endpoint-golden-1"]
    assert current_opts[:source_endpoint_ids] == ["source-endpoint-golden-1"]
    refute Keyword.has_key?(voltage_opts, :spacecraft_id)

    refute result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert [%ResolveWarning{code: :physical_aggregate_semantics, severity: :info}] =
             result.dashboard_warnings

    assert %{
             "placement_power_trend_source_endpoint_no_data" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :telemetry,
                     shape: :wide,
                     meta: %{observable_id: "tlm.hk.battery_voltage"} = voltage_meta
                   } = voltage_frame,
                   %Frame{
                     source: :telemetry,
                     shape: :wide,
                     meta: %{observable_id: "tlm.hk.bus_current"} = current_meta
                   } = current_frame
                 ],
                 overlays: %{},
                 warnings: [%ResolveWarning{code: :physical_aggregate_semantics}]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(voltage_frame, "bucket_start") == []
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == []
    assert field_values(current_frame, "bucket_start") == []
    assert field_values(current_frame, "tlm.hk.bus_current_value") == []
    assert voltage_meta.returned_points == 0
    assert current_meta.returned_points == 0
    assert voltage_meta.source_endpoint_ids == ["source-endpoint-golden-1"]
    assert current_meta.source_endpoint_ids == ["source-endpoint-golden-1"]
    assert source_watermark_confidences(voltage_frame) == [:best_effort]
    assert source_watermark_freshness_states(voltage_frame) == [:fresh]

    voltage_link = link_by_target(voltage_frame, :telemetry_point)

    assert_link_runtime_context(voltage_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "source_endpoint",
      scope_id: "source-endpoint-golden-1",
      time_mode: "archive",
      time_axis: "receipt_time",
      realm: "flight",
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry",
      source_request_id: voltage_frame.meta.source_request_id
    )

    assert WidgetPresentation.backfill(nil, placement_frames, render_widget(document)) == nil

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :no_data,
             lifecycle: %{
               state: :no_data,
               severity: :info,
               warning_codes: [:physical_aggregate_semantics]
             },
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               warning_codes: [:physical_aggregate_semantics],
               logical_sources: [:telemetry],
               data_source_ids: ["native-decimating-questdb"],
               source_binding_ids: ["default_flight_telemetry"],
               time_modes: ["archive"],
               time_axes: ["receipt_time"],
               scope_kinds: ["source_endpoint"],
               scope_ids: ["source-endpoint-golden-1"],
               source_endpoint_ids: ["source-endpoint-golden-1"],
               empty_reason: :source_endpoint_scope_no_data
             }
           } = data

    refute Map.has_key?(data.source_status, :contact_ids)

    assert data.source_status.watermarks
           |> Enum.map(&{&1.confidence, &1.freshness_state})
           |> Enum.uniq() == [{:best_effort, :fresh}]
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp time_series_source_registry_opts(opts) do
    native_telemetry_source = %{
      DataSources.default_managed_data_source()
      | data_source_id: "native-decimating-questdb",
        capabilities:
          DataSources.default_managed_data_source().capabilities
          |> Map.put(:native_decimation?, true)
    }

    telemetry_binding = %{
      DataSources.default_flight_telemetry_binding()
      | data_source_id: "native-decimating-questdb"
    }

    Keyword.merge(
      [
        data_sources: [
          native_telemetry_source,
          DataSources.default_limits_data_source(),
          DataSources.default_events_data_source()
        ],
        data_bindings: [
          telemetry_binding,
          DataSources.default_flight_limits_binding(),
          DataSources.default_flight_events_binding()
        ]
      ],
      opts
    )
  end

  defp source_endpoint_no_data_time_series_source_opts(parent) do
    %{
      telemetry: [
        decimated_history_fun: fn _organization_id, _mission_id, point_id, opts ->
          send(parent, {:source_endpoint_decimated_history_opts, point_id, opts})
          []
        end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp best_effort_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-17 12:00:01Z],
       latest_receipt_time: ~U[2026-06-17 12:00:01Z],
       retention_starts_at: ~U[2026-06-15 00:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_by_target(%Frame{meta: meta}, target) do
    Enum.find(Map.get(meta, :links, []), &(&1.target == target))
  end

  defp assert_link_runtime_context(link, opts) do
    refute is_nil(link)

    assert_context_texts(link, [
      {[:organization_id], "org_dashboards"},
      {[:mission_id], "mission_dashboards"}
    ])

    assert_context_texts(link, optional_context_texts(opts))
    assert_scope_id(link, Keyword.get(opts, :scope_id))
  end

  defp optional_context_texts(opts) do
    for {key, path} <- @optional_link_context_paths,
        expected = Keyword.get(opts, key),
        not is_nil(expected),
        do: {path, expected}
  end

  defp assert_context_texts(link, expected_values) do
    Enum.each(expected_values, fn {path, expected} ->
      assert context_text(context_value(link.context, path)) == expected
    end)
  end

  defp assert_scope_id(_link, nil), do: :ok

  defp assert_scope_id(link, expected) do
    assert context_value(link.context, [:scope, :primary, :ids]) == [expected]
  end

  defp context_value(context, path) when is_map(context) and is_list(path) do
    Enum.reduce(path, context, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key, Map.get(acc, Atom.to_string(key)))
        _other -> nil
      end
    end)
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)

  defp source_watermark_confidences(%Frame{meta: meta}) do
    meta
    |> Map.get(:source_watermarks, [])
    |> Enum.map(&Map.fetch!(&1, :confidence))
  end

  defp source_watermark_freshness_states(%Frame{meta: meta}) do
    meta
    |> Map.get(:source_watermarks, [])
    |> Enum.map(&Map.fetch!(&1, :freshness_state))
  end
end
