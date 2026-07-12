defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractSourceDegradedTimeSeriesTest do
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
    ResolveWarning,
    SourceHealthEvent,
    SourceHealthStatus
  }

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden source-degraded time-series fixture renders data while carrying degraded source health" do
    document = load_fixture!("source_degraded_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_source_degraded" => %{width_px: 640, height_px: 256}
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
          source_health_events?: true,
          record_source_health_events?: false,
          source_health_statuses: [degraded_source_health_status()],
          now: ~U[2026-06-17 12:05:02Z],
          source_opts: source_degraded_time_series_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z]
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert Enum.map(result.dashboard_warnings, & &1.code) == [:physical_aggregate_semantics]

    assert %{
             "placement_power_trend_source_degraded" =>
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

    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert field_values(current_frame, "tlm.hk.bus_current_value") == [4.5]
    assert voltage_meta.returned_points == 1
    assert current_meta.returned_points == 1

    for meta <- [voltage_meta, current_meta] do
      assert meta.source_health == :degraded
      assert meta.source_health_freshness == :fresh
      assert meta.source_health_reason == :source_probe_failed
      assert meta.source_health_event_id == "source-health-event-native-decimating-questdb"
      assert meta.source_health_probe_kind == :connection_test
      assert meta.source_health_connection_test_result == :degraded
      assert meta.durable_source_health?

      assert Enum.any?(
               meta.evidence,
               &match?(
                 %{
                   kind: :source_health_event,
                   id: "source-health-event-native-decimating-questdb"
                 },
                 &1
               )
             )
    end

    assert %{
             version: 1,
             series: [
               %{id: "tlm.hk.battery_voltage", points: [[1_781_568_000_000, 12.25]]},
               %{id: "tlm.hk.bus_current", points: [[1_781_568_000_000, 4.5]]}
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             sample: %{
               raw_value: 12.25,
               engineering_value: 12.25
             },
             lifecycle_state: :ready,
             lifecycle: %{
               state: :ready,
               severity: :ok,
               warning_codes: [:physical_aggregate_semantics]
             },
             source_status: %{
               state: :degraded,
               severity: :warning,
               data_state: :ready,
               stale?: false,
               warning_codes: [:physical_aggregate_semantics, :source_degraded],
               logical_sources: [:telemetry],
               data_source_ids: ["native-decimating-questdb"],
               source_binding_ids: ["default_flight_telemetry"],
               time_modes: ["archive"],
               time_axes: ["receipt_time"],
               source_health_states: [:degraded],
               source_health_reasons: [:source_probe_failed],
               source_health_event_ids: ["source-health-event-native-decimating-questdb"]
             }
           } = data
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

  defp source_degraded_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp degraded_source_health_status do
    %SourceHealthStatus{
      source_health_key:
        SourceHealthEvent.source_health_key(%{
          organization_id: "org_dashboards",
          mission_id: "mission_dashboards",
          logical_source: :telemetry,
          data_source_id: "native-decimating-questdb",
          source_binding_id: "default_flight_telemetry",
          realm: :flight,
          replay_run_id: nil,
          dataset: "flight"
        }),
      source_health_event_id: "source-health-event-native-decimating-questdb",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      logical_source: :telemetry,
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry",
      realm: :flight,
      replay_run_id: nil,
      dataset: "flight",
      event_type: :degraded,
      source_health: :degraded,
      previous_source_health: :healthy,
      reason: :source_probe_failed,
      observed_at: ~U[2026-06-17 12:05:00Z],
      last_seen_at: ~U[2026-06-17 12:05:00Z],
      transition_count: 2,
      payload: %{
        probe_kind: :connection_test,
        probe_message: "Connection test degraded",
        connection_test_result: :degraded,
        connection_test_kind: :http,
        connection_test_message: "QuestDB probe latency exceeded policy"
      }
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
end
