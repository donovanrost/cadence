defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractStaleTimeSeriesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden stale time-series fixture renders data while carrying degraded freshness lifecycle" do
    document = load_fixture!("stale_data_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_stale" => %{width_px: 640, height_px: 256}
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
          source_opts: stale_time_series_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z]
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :stale_data
           ]

    assert [%ResolveWarning{code: :stale_data, severity: :warning} = warning] =
             Enum.filter(result.dashboard_warnings, &(&1.code == :stale_data))

    assert warning.message == "Source watermark is older than freshness policy"
    assert warning.details.confidence == :best_effort
    assert warning.details.freshness_state == :stale
    assert warning.details.freshness_policy == %{stale_after_ms: 1_000}
    assert warning.details.freshness_checked_at == ~U[2026-06-17 12:05:02Z]
    assert warning.details.complete_through == ~U[2026-06-16 00:00:01Z]
    assert warning.details.data_source_id == "native-decimating-questdb"
    assert warning.details.source_binding_id == "default_flight_telemetry"

    assert Enum.map(warning.details.actions, & &1.target) == [
             :source_health,
             :source_inventory
           ]

    assert %{
             "placement_power_trend_stale" =>
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
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert placement_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :stale_data
           ]

    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert field_values(current_frame, "tlm.hk.bus_current_value") == [4.5]
    assert voltage_meta.returned_points == 1
    assert current_meta.returned_points == 1
    assert source_watermark_confidences(voltage_frame) == [:best_effort]
    assert source_watermark_freshness_states(voltage_frame) == [:stale]

    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 points: [[1_781_568_000_000, 12.25]],
                 envelope: %{
                   points: [[1_781_568_000_000, 11.5, 12.75, %{sample_count: 120}]]
                 }
               },
               %{
                 id: "tlm.hk.bus_current",
                 points: [[1_781_568_000_000, 4.5]],
                 envelope: %{
                   points: [[1_781_568_000_000, 4.0, 4.8, %{sample_count: 120}]]
                 }
               }
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: %{
               raw_value: 12.25,
               engineering_value: 12.25
             },
             lifecycle_state: :stale,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: lifecycle_warnings
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               warning_codes: source_warning_codes,
               logical_sources: [:telemetry],
               data_source_ids: ["native-decimating-questdb"],
               source_binding_ids: ["default_flight_telemetry"],
               time_modes: ["archive"],
               time_axes: ["receipt_time"]
             }
           } = data

    assert Enum.sort(lifecycle_warnings) == [
             :physical_aggregate_semantics,
             :stale_data
           ]

    assert Enum.sort(source_warning_codes) == [
             :physical_aggregate_semantics,
             :stale_data
           ]

    assert data.source_status.watermarks
           |> Enum.map(&{&1.confidence, &1.freshness_state, &1.complete_through})
           |> Enum.uniq() == [{:best_effort, :stale, ~U[2026-06-16 00:00:01Z]}]
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

  defp stale_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: &stale_best_effort_watermark/4
      ]
    }
  end

  defp decimated_history_buckets(_organization_id, _mission_id, point_id, _opts) do
    value = if point_id == "tlm.hk.bus_current", do: 4.5, else: 12.25
    min = if point_id == "tlm.hk.bus_current", do: 4.0, else: 11.5
    max = if point_id == "tlm.hk.bus_current", do: 4.8, else: 12.75
    unit = if point_id == "tlm.hk.bus_current", do: "A", else: "V"

    [
      %{
        bucket_start: ~U[2026-06-16 00:00:00Z],
        bucket_end: ~U[2026-06-16 00:05:00Z],
        min: min,
        max: max,
        mean: value,
        unit: unit,
        sample_count: 120,
        worst_quality_state: :good
      }
    ]
  end

  defp stale_best_effort_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:00:01Z],
       latest_receipt_time: ~U[2026-06-16 00:00:01Z],
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
