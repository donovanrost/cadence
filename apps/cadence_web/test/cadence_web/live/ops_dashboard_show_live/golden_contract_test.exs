defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem,
    ResolveWarning,
    SourceCircuitBreaker,
    SourceExecutionSemantics,
    SourceHealthEvent,
    SourceHealthStatus
  }

  alias Cadence.Jobs.Job
  alias Cadence.Limits.DefinitionInterval
  alias Cadence.Limits.Event
  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{BackfillLifecycleEvent, ObservationIdentityState}
  alias CadenceWeb.OpsDashboardShowLive.{DataLinkSelection, RenderPageModel, WidgetPresentation}

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
    dataset: [:data, :dataset],
    source_request_id: [:source_request_id]
  ]

  test "golden value tile fixture resolves through engine contract into presenter data" do
    document = load_fixture!("value_tile_latest.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request = resolve_request(document)
    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 2

    assert plan.planned_source_requests
           |> Enum.map(&request_summary/1)
           |> Enum.sort_by(&request_sort_key/1) == [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest,
               products: [],
               overlays: [:quality],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry"
             },
             %{
               logical_source: :limits,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest_state,
               products: [:latest_state],
               overlays: [],
               target_points: nil,
               time_axis: "generation_time",
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             }
           ]

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_opts()
        )
      )

    assert result.plan_metadata.executed_source_request_count == 2
    assert result.plan_metadata.returned_frame_count == 2

    assert [%ResolveWarning{code: :capability_fallback, severity: :info} = warning] =
             result.dashboard_warnings

    assert warning.details.unresolved_capability == :overlays
    assert warning.details.requested_overlays == [:quality]
    assert warning.details.data_source_id == "managed_questdb_primary"
    assert warning.details.source_binding_id == "default_flight_telemetry"

    assert Enum.map(warning.details.actions, & &1.target) == [
             :telemetry_explore,
             :source_health,
             :source_inventory
           ]

    assert %{
             "placement_battery_voltage" =>
               %PlacementFrames{
                 primary: [%Frame{source: :telemetry, shape: :scalar} = telemetry_frame],
                 overlays: %{limits: [%Frame{source: :limits, shape: :scalar} = limits_frame]},
                 warnings: [%ResolveWarning{code: :capability_fallback}]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(telemetry_frame, "tlm.hk.battery_voltage") == [12.25]
    assert field_values(telemetry_frame, "time") == [~U[2026-06-17 12:00:00Z]]
    assert telemetry_frame.scope.spacecraft_id == "sc_001"
    assert telemetry_frame.meta.data_source_id == "managed_questdb_primary"
    assert telemetry_frame.meta.source_binding_id == "default_flight_telemetry"
    assert telemetry_frame.meta.warning_codes == [:capability_fallback]
    assert source_watermark_confidences(telemetry_frame) == [:best_effort]
    assert source_watermark_freshness_states(telemetry_frame) == [:fresh]
    assert link_targets(telemetry_frame) == [:telemetry_point, :telemetry_sample]

    telemetry_point_link = link_by_target(telemetry_frame, :telemetry_point)
    telemetry_sample_link = link_by_target(telemetry_frame, :telemetry_sample)

    assert_link_runtime_context(telemetry_point_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry",
      source_request_id: telemetry_frame.meta.source_request_id
    )

    assert DataLinkSelection.selected_ref(telemetry_sample_link, %{
             "placement-id" => "placement_battery_voltage",
             "timestamp-ms" => "1781697600000"
           }) == %{
             "link_id" => telemetry_sample_link.link_id,
             "target" => "telemetry_sample",
             "target_id" => "sample-golden-1",
             "target_text" => "telemetry sample",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "placement_battery_voltage",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc_001",
             "spacecraft_id" => "sc_001",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_questdb_primary",
             "source_binding_id" => "default_flight_telemetry",
             "limit_mode" => "observed",
             "observable_id" => "tlm.hk.battery_voltage"
           }

    assert field_values(limits_frame, "normalized_state") == [:yellow]
    assert field_values(limits_frame, "limit_state") == [:yellow_high]
    assert field_values(limits_frame, "violation") == [true]
    assert limits_frame.meta.data_source_id == "managed_limits_projection"
    assert limits_frame.meta.source_binding_id == "default_flight_limits"
    assert limits_frame.meta.limit_event_id == "limit-event-golden-tlm-hk-battery-voltage"
    assert source_watermark_confidences(limits_frame) == [:best_effort]
    assert source_watermark_freshness_states(limits_frame) == [:fresh]

    assert link_targets(limits_frame) == [
             :telemetry_point,
             :limit_event,
             :limit_definition,
             :telemetry_sample
           ]

    assert_link_runtime_context(link_by_target(limits_frame, :limit_event),
      logical_source: "limits",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_limits_projection",
      source_binding_id: "default_flight_limits",
      source_request_id: limits_frame.meta.source_request_id
    )

    assert_link_runtime_context(hd(warning.links),
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry"
    )

    assert [render_item] = RenderItem.from_document(document)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             sample: %{
               sample_id: "sample-golden-1",
               raw_value: 12.25,
               engineering_value: 12.25,
               receipt_time: ~U[2026-06-17 12:00:00Z],
               generation_time: ~U[2026-06-17 12:00:00Z],
               quality_state: :good
             },
             limit_event: %{
               normalized_state: :yellow,
               limit_state: :yellow_high,
               limit_event_id: "limit-event-golden-tlm-hk-battery-voltage"
             }
           } = WidgetPresentation.data(nil, placement_frames, render_item.widget)
  end

  test "golden time-series fixture resolves history, overlays, markers, and chart data" do
    document = load_fixture!("time_series_with_limits.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend" => %{width_px: 640, height_px: 256}
      })

    registry_opts = time_series_source_registry_opts(validate_dashboard_contract?: true)
    plan = Engine.plan(request, registry_opts)

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 4

    assert plan.planned_source_requests
           |> Enum.map(&request_summary/1)
           |> Enum.sort_by(&request_sort_key/1) == [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :decimated_envelope,
               products: [],
               overlays: [:quality],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "native-decimating-questdb",
               source_binding_id: "default_flight_telemetry"
             },
             %{
               logical_source: :limits,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :definition_intervals,
               products: [:definition_intervals],
               overlays: [],
               target_points: nil,
               time_axis: :receipt_time,
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             },
             %{
               logical_source: :limits,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :analysis_buckets,
               products: [:analysis_buckets],
               overlays: [],
               target_points: nil,
               time_axis: :receipt_time,
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             },
             %{
               logical_source: :events,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :event_history,
               products: [
                 :contact_intervals,
                 :mission_timeline,
                 :source_health_transitions,
                 :source_watermark_events,
                 :source_capability_postures,
                 :telemetry_backfill_lifecycle,
                 :telemetry_revision_decisions
               ],
               overlays: [],
               target_points: nil,
               time_axis: :occurred_at,
               data_source_id: "managed_events_projection",
               source_binding_id: "default_flight_events"
             }
           ]

    result =
      Engine.resolve(
        request,
        time_series_source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: time_series_source_opts()
        )
      )

    assert result.plan_metadata.executed_source_request_count == 4
    assert result.plan_metadata.returned_frame_count == 13

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :capability_fallback,
             :physical_aggregate_semantics
           ]

    assert %{
             "placement_power_trend" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :telemetry, shape: :wide} = voltage_frame,
                   %Frame{source: :telemetry, shape: :wide} = current_frame
                 ],
                 overlays: %{limits: limit_frames, events: event_frames},
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert placement_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :capability_fallback,
             :physical_aggregate_semantics
           ]

    assert voltage_frame.meta.sampling == :decimated_envelope
    assert voltage_frame.meta.decimation == :native_min_max_envelope
    assert voltage_frame.meta.target_points == 640
    assert voltage_frame.meta.data_source_id == "native-decimating-questdb"
    assert voltage_frame.meta.source_binding_id == "default_flight_telemetry"
    assert field_values(voltage_frame, "bucket_start") == [~U[2026-06-16 00:00:00Z]]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_min") == [11.5]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_max") == [12.75]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert source_watermark_confidences(voltage_frame) == [:best_effort]
    assert source_watermark_freshness_states(voltage_frame) == [:fresh]
    assert link_targets(voltage_frame) == [:telemetry_point]

    voltage_link = link_by_target(voltage_frame, :telemetry_point)

    assert_link_runtime_context(voltage_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "archive",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry",
      source_request_id: voltage_frame.meta.source_request_id
    )

    assert DataLinkSelection.selected_ref(voltage_link, %{
             "placement-id" => "placement_power_trend",
             "timestamp-ms" => "1781568000000",
             "series-role" => "primary"
           }) == %{
             "link_id" => voltage_link.link_id,
             "target" => "telemetry_point",
             "target_id" => "tlm.hk.battery_voltage",
             "target_text" => "telemetry point",
             "timestamp_ms" => 1_781_568_000_000,
             "placement_id" => "placement_power_trend",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc_001",
             "spacecraft_id" => "sc_001",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "series_role" => "primary",
             "data_source_id" => "native-decimating-questdb",
             "source_binding_id" => "default_flight_telemetry",
             "limit_mode" => "observed",
             "observable_id" => "tlm.hk.battery_voltage"
           }

    assert current_frame.meta.observable_id == "tlm.hk.bus_current"
    assert field_values(current_frame, "tlm.hk.bus_current_value") == [4.5]

    assert Enum.any?(limit_frames, &match?(%Frame{source: :limits, shape: :events}, &1))
    assert Enum.any?(limit_frames, &match?(%Frame{source: :limits, shape: :intervals}, &1))
    assert Enum.any?(event_frames, &match?(%Frame{source: :events, shape: :events}, &1))

    limit_markers = WidgetPresentation.limit_markers(placement_frames, render_widget(document))
    event_markers = WidgetPresentation.event_markers(placement_frames, render_widget(document))

    assert Enum.any?(limit_markers, fn marker ->
             Map.get(marker, :limit_event_id) ==
               "limit-event-golden-tlm-hk-battery-voltage"
           end)

    assert Enum.any?(limit_markers, fn marker ->
             Map.get(marker, :marker_type) == "limit_definition_interval" and
               marker.limit_definition_id == "limit-def-golden-tlm-hk-battery-voltage"
           end)

    assert Enum.any?(event_markers, fn marker ->
             marker.marker_type == "mission_event" and
               marker.target_id == "mission-event-golden-1" and
               marker.event_kind == "limit_violation"
           end)

    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 label: "tlm.hk.battery_voltage",
                 observable_id: "tlm.hk.battery_voltage",
                 unit: "V",
                 source: :telemetry,
                 field: "tlm.hk.battery_voltage_value",
                 time_axis: :generation_time,
                 sampling: :decimated_envelope,
                 decimation: :native_min_max_envelope,
                 data_source_id: "native-decimating-questdb",
                 source_binding_id: "default_flight_telemetry",
                 envelope: %{
                   kind: :min_max,
                   lower_field: "tlm.hk.battery_voltage_min",
                   upper_field: "tlm.hk.battery_voltage_max",
                   sample_count_field: "tlm.hk.battery_voltage_sample_count",
                   points: [[1_781_568_000_000, 11.5, 12.75, %{sample_count: 120}]]
                 },
                 points: [[1_781_568_000_000, 12.25]]
               },
               %{
                 id: "tlm.hk.bus_current",
                 label: "tlm.hk.bus_current",
                 observable_id: "tlm.hk.bus_current",
                 unit: "A",
                 source: :telemetry,
                 field: "tlm.hk.bus_current_value",
                 time_axis: :generation_time,
                 sampling: :decimated_envelope,
                 decimation: :native_min_max_envelope,
                 data_source_id: "native-decimating-questdb",
                 source_binding_id: "default_flight_telemetry",
                 envelope: %{
                   kind: :min_max,
                   lower_field: "tlm.hk.bus_current_min",
                   upper_field: "tlm.hk.bus_current_max",
                   sample_count_field: "tlm.hk.bus_current_sample_count",
                   points: [[1_781_568_000_000, 4.0, 4.8, %{sample_count: 120}]]
                 },
                 points: [[1_781_568_000_000, 4.5]]
               }
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             sample: %{
               sample_id: nil,
               raw_value: 12.25,
               engineering_value: 12.25,
               receipt_time: ~U[2026-06-16 00:00:00Z],
               generation_time: ~U[2026-06-16 00:00:00Z],
               quality_state: :good
             }
           } = WidgetPresentation.data(nil, placement_frames, render_widget(document))
  end

  test "golden operational RF metric time-series fixture preserves link-scoped chart DataLinks" do
    document = load_fixture!("operational_rf_metric_time_series.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_link_snr_history" => %{width_px: 640, height_px: 256}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.snr_db"],
               sampling_mode: :raw_series,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_metric_history_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :rf_metric_history_transports_called
    assert_received :link_rf_metric_history_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_link_snr_history" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :wide,
                     time_axis: :occurred_at,
                     meta: %{
                       supported_capability: :link_rf_metric_history,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :link_rf,
                       observable_id: "link.snr_db",
                       observable_ids: ["link.snr_db"],
                       resource_id: "link-golden-alpha",
                       scope_kind: :link,
                       transport_id: "transport-golden-alpha",
                       source_endpoint_id: "source-endpoint-golden-1",
                       ground_station_id: "dss-14",
                       link_id: "link-golden-alpha",
                       adapter_key: :rf_adapter,
                       unit: "dB",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "time") == [
             ~U[2026-06-17 12:01:00Z],
             ~U[2026-06-17 12:02:00Z]
           ]

    assert field_values(frame, "link.snr_db") == [10.5, 12.75]
    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    metric_field = Enum.find(frame.fields, &(&1.name == "link.snr_db"))

    assert metric_field.metadata == %{
             observable_id: "link.snr_db",
             label: "RF SNR / link-golden-alpha",
             unit: "dB",
             resource_id: "link-golden-alpha",
             scope_kind: :link,
             transport_id: "transport-golden-alpha",
             source_endpoint_id: "source-endpoint-golden-1",
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             adapter_key: :rf_adapter,
             resource_link_id: frame.meta.resource_link_id,
             links: frame.meta.links
           }

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")
    source_endpoint_link = link_by_target(frame, :source_endpoint, "source-endpoint-golden-1")
    ground_station_link = link_by_target(frame, :ground_station, "dss-14")
    link_link = link_by_target(frame, :link, "link-golden-alpha")

    for link <- [transport_link, source_endpoint_link, ground_station_link, link_link] do
      assert_link_runtime_context(link,
        logical_source: "operational_observables",
        observable_id: "link.snr_db",
        scope_kind: "link",
        scope_id: "link-golden-alpha",
        time_mode: "archive",
        time_axis: "generation_time",
        realm: "flight",
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        source_request_id: frame.meta.source_request_id
      )

      assert context_value(link.context, [:operational_resource]) == %{
               adapter_key: :rf_adapter,
               ground_station_id: "dss-14",
               link_id: "link-golden-alpha",
               resource_id: "link-golden-alpha",
               scope_kind: :link,
               source_endpoint_id: "source-endpoint-golden-1",
               transport_id: "transport-golden-alpha"
             }
    end

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_link_snr_history",
             "timestamp-ms" => "1781697660000",
             "series-role" => "primary"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "timestamp_ms" => 1_781_697_660_000,
             "placement_id" => "placement_link_snr_history",
             "source" => "frame",
             "scope_kind" => "link",
             "scope_id" => "link-golden-alpha",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "series_role" => "primary",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "link.snr_db"
           }

    assert %{
             version: 1,
             series: [
               %{
                 id: "link.snr_db",
                 label: "RF SNR / link-golden-alpha",
                 observable_id: "link.snr_db",
                 unit: "dB",
                 source: :operational_observables,
                 frame_id: _frame_id,
                 field: "link.snr_db",
                 time_axis: :occurred_at,
                 sampling: :raw_series,
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 links: [
                   %{
                     target: :link,
                     target_id: "link-golden-alpha"
                   },
                   %{
                     target: :transport,
                     target_id: "transport-golden-alpha"
                   },
                   %{
                     target: :source_endpoint,
                     target_id: "source-endpoint-golden-1"
                   },
                   %{
                     target: :ground_station,
                     target_id: "dss-14"
                   }
                 ],
                 points: [
                   [
                     1_781_697_660_000,
                     10.5,
                     %{
                       link_id: _first_point_link_id,
                       target: "transport",
                       target_id: "transport-golden-alpha"
                     }
                   ],
                   [
                     1_781_697_720_000,
                     12.75,
                     %{
                       link_id: _second_point_link_id,
                       target: "transport",
                       target_id: "transport-golden-alpha"
                     }
                   ]
                 ]
               }
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             source_status: %{
               state: :fresh,
               severity: :ok,
               logical_sources: [:operational_observables],
               scope_kinds: ["link"],
               scope_ids: ["link-golden-alpha"],
               time_modes: ["archive"],
               time_axes: ["generation_time"]
             },
             sample: %{
               sample_id: nil,
               raw_value: 12.75,
               engineering_value: 12.75,
               receipt_time: ~U[2026-06-17 12:02:00Z],
               generation_time: ~U[2026-06-17 12:02:00Z],
               quality_state: nil
             }
           } = WidgetPresentation.data(nil, placement_frames, render_widget(document))
  end

  test "golden operational ingress latency time-series fixture preserves source-endpoint chart DataLinks" do
    document = load_fixture!("operational_ingress_latency_time_series.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_ingress_latency_history" => %{width_px: 640, height_px: 256}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["ingress.processing_latency_ms"],
               sampling_mode: :raw_series,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_ingress_latency_history_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :ingress_latency_history_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_ingress_latency_history" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :wide,
                     time_axis: :occurred_at,
                     meta: %{
                       supported_capability: :ingress_processing_latency_history,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :runtime_ingress,
                       observable_id: "ingress.processing_latency_ms",
                       observable_ids: ["ingress.processing_latency_ms"],
                       resource_id: "source-endpoint-golden-1",
                       scope_kind: :source_endpoint,
                       transport_id: "transport-golden-alpha",
                       source_endpoint_id: "source-endpoint-golden-1",
                       ground_station_id: "dss-14",
                       link_id: "link-golden-alpha",
                       adapter_key: :tcp_socket,
                       unit: "ms",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "time") == [
             ~U[2026-06-17 12:01:00Z],
             ~U[2026-06-17 12:02:00Z]
           ]

    assert field_values(frame, "ingress.processing_latency_ms") == [4.5, 5.25]
    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    metric_field = Enum.find(frame.fields, &(&1.name == "ingress.processing_latency_ms"))

    assert metric_field.metadata == %{
             observable_id: "ingress.processing_latency_ms",
             label: "Ingress latency / source-endpoint-golden-1",
             unit: "ms",
             resource_id: "source-endpoint-golden-1",
             scope_kind: :source_endpoint,
             transport_id: "transport-golden-alpha",
             source_endpoint_id: "source-endpoint-golden-1",
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             adapter_key: :tcp_socket,
             resource_link_id: frame.meta.resource_link_id,
             links: frame.meta.links
           }

    source_endpoint_link = link_by_target(frame, :source_endpoint, "source-endpoint-golden-1")

    assert_link_runtime_context(source_endpoint_link,
      logical_source: "operational_observables",
      observable_id: "ingress.processing_latency_ms",
      scope_kind: "source_endpoint",
      scope_id: "source-endpoint-golden-1",
      time_mode: "archive",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: frame.meta.source_request_id
    )

    assert context_value(source_endpoint_link.context, [:operational_resource]) == %{
             adapter_key: :tcp_socket,
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             resource_id: "source-endpoint-golden-1",
             scope_kind: :source_endpoint,
             source_endpoint_id: "source-endpoint-golden-1",
             transport_id: "transport-golden-alpha"
           }

    assert DataLinkSelection.selected_ref(source_endpoint_link, %{
             "placement-id" => "placement_ingress_latency_history",
             "timestamp-ms" => "1781697660000",
             "series-role" => "primary"
           }) == %{
             "link_id" => source_endpoint_link.link_id,
             "target" => "source_endpoint",
             "target_id" => "source-endpoint-golden-1",
             "target_text" => "source endpoint",
             "timestamp_ms" => 1_781_697_660_000,
             "placement_id" => "placement_ingress_latency_history",
             "source" => "frame",
             "scope_kind" => "source_endpoint",
             "scope_id" => "source-endpoint-golden-1",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "series_role" => "primary",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "transport_id" => "transport-golden-alpha",
             "observable_id" => "ingress.processing_latency_ms"
           }

    assert %{
             version: 1,
             series: [
               %{
                 id: "ingress.processing_latency_ms",
                 label: "Ingress latency / source-endpoint-golden-1",
                 observable_id: "ingress.processing_latency_ms",
                 unit: "ms",
                 source: :operational_observables,
                 frame_id: _frame_id,
                 field: "ingress.processing_latency_ms",
                 time_axis: :occurred_at,
                 sampling: :raw_series,
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 links: [
                   %{target: :link, target_id: "link-golden-alpha"},
                   %{target: :transport, target_id: "transport-golden-alpha"},
                   %{target: :source_endpoint, target_id: "source-endpoint-golden-1"},
                   %{target: :ground_station, target_id: "dss-14"}
                 ],
                 points: [
                   [
                     1_781_697_660_000,
                     4.5,
                     %{
                       link_id: _first_point_link_id,
                       target: "transport",
                       target_id: "transport-golden-alpha"
                     }
                   ],
                   [
                     1_781_697_720_000,
                     5.25,
                     %{
                       link_id: _second_point_link_id,
                       target: "transport",
                       target_id: "transport-golden-alpha"
                     }
                   ]
                 ]
               }
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))
  end

  test "golden operational RF metric no-data time-series fixture remains chartable" do
    document = load_fixture!("operational_rf_metric_no_data_time_series.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_link_snr_history_no_data" => %{width_px: 640, height_px: 256}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.snr_db"],
               sampling_mode: :raw_series,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_metric_history_no_data_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :rf_metric_history_transports_called
    assert_received :link_rf_metric_history_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_link_snr_history_no_data" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :wide,
                     time_axis: :occurred_at,
                     meta: %{
                       supported_capability: :link_rf_metric_history,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :link_rf,
                       observable_id: "link.snr_db",
                       observable_ids: ["link.snr_db"],
                       resource_id: "link-golden-alpha",
                       scope_kind: :link,
                       transport_id: "transport-golden-alpha",
                       source_endpoint_id: "source-endpoint-golden-1",
                       ground_station_id: "dss-14",
                       link_id: "link-golden-alpha",
                       adapter_key: :rf_adapter,
                       returned_points: 0,
                       unit: "dB",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "time") == []
    assert field_values(frame, "link.snr_db") == []
    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")

    assert_link_runtime_context(transport_link,
      logical_source: "operational_observables",
      observable_id: "link.snr_db",
      scope_kind: "link",
      scope_id: "link-golden-alpha",
      time_mode: "archive",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: frame.meta.source_request_id
    )

    assert context_value(transport_link.context, [:operational_resource]) == %{
             adapter_key: :rf_adapter,
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             resource_id: "link-golden-alpha",
             scope_kind: :link,
             source_endpoint_id: "source-endpoint-golden-1",
             transport_id: "transport-golden-alpha"
           }

    assert WidgetPresentation.backfill(nil, placement_frames, render_widget(document)) == nil

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, warning_codes: []},
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               warning_codes: [],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               scope_kinds: ["link"],
               scope_ids: ["link-golden-alpha"],
               time_modes: ["archive"],
               time_axes: ["generation_time"],
               empty_reason: :scope_no_data
             }
           } = WidgetPresentation.data(nil, placement_frames, render_widget(document))
  end

  test "golden no-data time-series fixture carries healthy empty range contract into presenter lifecycle" do
    document = load_fixture!("no_data_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_no_data" => %{width_px: 640, height_px: 256}
      })

    registry_opts = time_series_source_registry_opts(validate_dashboard_contract?: true)
    plan = Engine.plan(request, registry_opts)

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :decimated_envelope,
               products: [],
               overlays: [],
               target_points: 640,
               time_axis: "receipt_time",
               data_source_id: "native-decimating-questdb",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        time_series_source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: no_data_time_series_source_opts()
        )
      )

    refute result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert [%ResolveWarning{code: :physical_aggregate_semantics, severity: :info}] =
             result.dashboard_warnings

    assert %{
             "placement_power_trend_no_data" =>
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
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_min") == []
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_max") == []
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_sample_count") == []
    assert voltage_meta.returned_points == 0
    assert voltage_meta.data_source_id == "native-decimating-questdb"
    assert voltage_meta.source_binding_id == "default_flight_telemetry"
    assert voltage_meta.warning_codes == [:physical_aggregate_semantics]
    assert source_watermark_confidences(voltage_frame) == [:best_effort]
    assert source_watermark_freshness_states(voltage_frame) == [:fresh]
    assert link_targets(voltage_frame) == [:telemetry_point]

    assert field_values(current_frame, "bucket_start") == []
    assert field_values(current_frame, "tlm.hk.bus_current_value") == []
    assert current_meta.returned_points == 0
    assert current_meta.warning_codes == [:physical_aggregate_semantics]

    voltage_link = link_by_target(voltage_frame, :telemetry_point)

    assert_link_runtime_context(voltage_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
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
               scope_kinds: ["spacecraft"],
               scope_ids: ["sc_001"],
               empty_reason: :scope_no_data
             }
           } = data

    assert :flight in data.source_status.realms
    assert "flight" in data.source_status.realms

    assert data.source_status.watermarks
           |> Enum.map(&{&1.confidence, &1.freshness_state})
           |> Enum.uniq() == [{:best_effort, :fresh}]
  end

  test "golden contact-scoped no-data time-series fixture explains source endpoint filtering" do
    document = load_fixture!("contact_no_data_time_series.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_power_trend_contact_no_data" => %{width_px: 640, height_px: 256}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "contact", mode: "one", ids: ["scheduled-contact-golden-1"]}
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
          source_opts: contact_no_data_time_series_source_opts(parent)
        )
      )

    assert_receive {:contact_decimated_history_opts, "tlm.hk.battery_voltage", voltage_opts}
    assert_receive {:contact_decimated_history_opts, "tlm.hk.bus_current", current_opts}
    assert voltage_opts[:source_endpoint_ids] == ["source-endpoint-golden-1"]
    assert current_opts[:source_endpoint_ids] == ["source-endpoint-golden-1"]
    refute Keyword.has_key?(voltage_opts, :spacecraft_id)

    refute result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert [%ResolveWarning{code: :physical_aggregate_semantics, severity: :info}] =
             result.dashboard_warnings

    assert %{
             "placement_power_trend_contact_no_data" =>
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
      scope_kind: "contact",
      scope_id: "scheduled-contact-golden-1",
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
               scope_kinds: ["contact"],
               scope_ids: ["scheduled-contact-golden-1"],
               contact_ids: ["scheduled-contact-golden-1"],
               source_endpoint_ids: ["source-endpoint-golden-1"],
               empty_reason: :contact_scope_no_data
             }
           } = data

    assert data.source_status.watermarks
           |> Enum.map(&{&1.confidence, &1.freshness_state})
           |> Enum.uniq() == [{:best_effort, :fresh}]
  end

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

  test "golden partial time-series fixture carries mixed range coverage into presenter lifecycle" do
    document = load_fixture!("partial_data_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_partial" => %{width_px: 640, height_px: 256}
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
          source_opts: partial_time_series_source_opts()
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :partial_data,
             :physical_aggregate_semantics
           ]

    assert [%ResolveWarning{code: :partial_data, severity: :warning} = partial_warning] =
             Enum.filter(result.dashboard_warnings, &(&1.code == :partial_data))

    assert partial_warning.details.requested_observables == [
             "tlm.hk.battery_voltage",
             "tlm.hk.bus_current"
           ]

    assert partial_warning.details.returned_observables == ["tlm.hk.battery_voltage"]
    assert partial_warning.details.empty_observables == ["tlm.hk.bus_current"]
    assert partial_warning.details.data_source_id == "native-decimating-questdb"
    assert partial_warning.details.source_binding_id == "default_flight_telemetry"

    assert %{
             "placement_power_trend_partial" =>
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
             :partial_data,
             :physical_aggregate_semantics
           ]

    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert voltage_meta.returned_points == 1
    assert voltage_meta.warning_codes == [:physical_aggregate_semantics]

    assert field_values(current_frame, "tlm.hk.bus_current_value") == []
    assert current_meta.returned_points == 0
    assert current_meta.warning_codes == [:physical_aggregate_semantics]

    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 points: [[1_781_568_000_000, 12.25]],
                 envelope: %{
                   points: [[1_781_568_000_000, 11.5, 12.75, %{sample_count: 120}]]
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
             lifecycle_state: :partial,
             lifecycle: %{
               state: :partial,
               severity: :warning,
               warning_codes: lifecycle_warnings
             },
             source_status: %{
               state: :partial,
               severity: :warning,
               data_state: :ready,
               warning_codes: source_warning_codes,
               logical_sources: [:telemetry],
               data_source_ids: ["native-decimating-questdb"],
               source_binding_ids: ["default_flight_telemetry"]
             }
           } = data

    assert Enum.sort(lifecycle_warnings) == [
             :partial_data,
             :physical_aggregate_semantics
           ]

    assert Enum.sort(source_warning_codes) == [
             :partial_data,
             :physical_aggregate_semantics
           ]
  end

  test "golden source-unavailable time-series fixture carries failed range query into presenter lifecycle" do
    document = load_fixture!("source_unavailable_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_unavailable" => %{width_px: 640, height_px: 256}
      })

    registry_opts = time_series_source_registry_opts(validate_dashboard_contract?: true)
    plan = Engine.plan(request, registry_opts)

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :decimated_envelope,
               products: [],
               overlays: [],
               target_points: 640,
               time_axis: "receipt_time",
               data_source_id: "native-decimating-questdb",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        time_series_source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_unavailable_time_series_source_opts()
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 0

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert [%ResolveWarning{code: :source_unavailable, severity: :error} = warning] =
             Enum.filter(result.dashboard_warnings, &(&1.code == :source_unavailable))

    assert warning.message == "Telemetry data source cannot execute native decimated history"
    assert warning.details.reason == ":test_decimated_history_failure"
    assert warning.details.source_empty_reason == :source_query_failed
    assert warning.details.source_query_kind == :native_decimated_history
    assert warning.details.unresolved_capability == :native_decimation
    assert warning.details.observable_id == "tlm.hk.battery_voltage"
    assert warning.details.requested_sampling == :decimated_envelope
    assert warning.details.data_source_id == "native-decimating-questdb"
    assert warning.details.source_binding_id == "default_flight_telemetry"

    assert Enum.map(warning.details.actions, & &1.target) == [
             :source_health,
             :source_inventory,
             :telemetry_explore
           ]

    assert link_targets(warning) == [:telemetry_point]

    assert_link_runtime_context(link_by_target(warning, :telemetry_point),
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "archive",
      time_axis: "receipt_time",
      realm: "flight",
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry"
    )

    assert %{
             "placement_power_trend_unavailable" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert placement_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert WidgetPresentation.backfill(nil, placement_frames, render_widget(document)) == nil

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :error,
             lifecycle: %{
               state: :error,
               severity: :error,
               warning_codes: lifecycle_warnings
             },
             source_status: %{
               state: :unavailable,
               severity: :error,
               data_state: :no_data,
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
             :source_unavailable
           ]

    assert Enum.sort(source_warning_codes) == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert :flight in data.source_status.realms
    refute Map.has_key?(data.source_status, :empty_reason)
  end

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

  test "golden retention-gap time-series fixture renders data while carrying retention boundary lifecycle" do
    document = load_fixture!("retention_gap_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_retention_gap" => %{width_px: 640, height_px: 256}
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
          source_opts: retention_gap_time_series_source_opts(),
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
             :retention_gap
           ]

    assert [%ResolveWarning{code: :retention_gap, severity: :warning} = warning] =
             Enum.filter(result.dashboard_warnings, &(&1.code == :retention_gap))

    assert warning.message == "Requested time range begins before source retention"
    assert warning.details.confidence == :best_effort
    assert warning.details.freshness_state == :retention_gap
    assert warning.details.complete_through == ~U[2026-06-16 00:30:00Z]
    assert warning.details.latest_receipt_time == ~U[2026-06-16 00:30:00Z]
    assert warning.details.retention_starts_at == ~U[2026-06-16 00:10:00Z]
    assert warning.details.data_source_id == "native-decimating-questdb"
    assert warning.details.source_binding_id == "default_flight_telemetry"
    assert warning.details.time_mode == "archive"
    assert warning.details.time_axis == "receipt_time"

    assert Enum.map(warning.details.actions, & &1.target) == [
             :source_health,
             :source_inventory
           ]

    assert %{
             "placement_power_trend_retention_gap" =>
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
             :retention_gap
           ]

    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert field_values(current_frame, "tlm.hk.bus_current_value") == [4.5]
    assert voltage_meta.returned_points == 1
    assert current_meta.returned_points == 1
    assert source_watermark_confidences(voltage_frame) == [:best_effort]
    assert source_watermark_freshness_states(voltage_frame) == [:retention_gap]

    assert %{
             version: 1,
             series: [
               %{id: "tlm.hk.battery_voltage", points: [[1_781_568_000_000, 12.25]]},
               %{id: "tlm.hk.bus_current", points: [[1_781_568_000_000, 4.5]]}
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))

    assert [
             %{
               marker_type: "retention_gap",
               starts_at_ms: 1_781_568_000_000,
               ends_at_ms: 1_781_568_600_000,
               timestamp_ms: 1_781_568_600_000,
               target: "source_watermark",
               logical_source: "telemetry",
               source_binding_id: "default_flight_telemetry",
               data_source_id: "native-decimating-questdb",
               realm: "flight",
               time_mode: "archive",
               time_axis: "receipt_time",
               confidence: "best_effort",
               freshness_state: "retention_gap",
               complete_through_ms: 1_781_569_800_000,
               latest_receipt_time_ms: 1_781_569_800_000,
               retention_starts_at_ms: 1_781_568_600_000,
               label: "Retention gap / default_flight_telemetry / native-decimating-questdb"
             }
           ] =
             placement_frames
             |> WidgetPresentation.event_markers(render_widget(document))
             |> Enum.filter(&(&1.marker_type == "retention_gap"))

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: %{
               raw_value: 12.25,
               engineering_value: 12.25
             },
             lifecycle_state: :retention_gap,
             lifecycle: %{
               state: :retention_gap,
               severity: :error,
               warning_codes: lifecycle_warnings
             },
             source_status: %{
               state: :retention_gap,
               severity: :error,
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
             :retention_gap
           ]

    assert Enum.sort(source_warning_codes) == [
             :physical_aggregate_semantics,
             :retention_gap
           ]

    assert data.source_status.watermarks
           |> Enum.map(&{&1.confidence, &1.freshness_state, &1.retention_starts_at})
           |> Enum.uniq() == [{:best_effort, :retention_gap, ~U[2026-06-16 00:10:00Z]}]
  end

  test "golden unknown-watermark time-series fixture renders data while carrying unknown source freshness" do
    document = load_fixture!("unknown_watermark_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_unknown_watermark" => %{width_px: 640, height_px: 256}
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
          source_opts: unknown_watermark_time_series_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z]
        )
      )

    refute result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :watermark_unknown
           ]

    assert [%ResolveWarning{code: :watermark_unknown, severity: :info} = warning] =
             Enum.filter(result.dashboard_warnings, &(&1.code == :watermark_unknown))

    assert warning.message == "Telemetry source watermark confidence is unknown"
    assert warning.details.unresolved_capability == :source_watermark
    assert warning.details.observable_id == "tlm.hk.battery_voltage"
    assert warning.details.source_query_kind == :watermark
    assert warning.details.reason == ":test_watermark_failure"
    assert warning.details.data_source_id == "native-decimating-questdb"
    assert warning.details.source_binding_id == "default_flight_telemetry"

    assert %{
             "placement_power_trend_unknown_watermark" =>
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
             :watermark_unknown
           ]

    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert field_values(current_frame, "tlm.hk.bus_current_value") == [4.5]
    assert voltage_meta.returned_points == 1
    assert current_meta.returned_points == 1

    assert Enum.sort(voltage_meta.warning_codes) == [
             :physical_aggregate_semantics,
             :watermark_unknown
           ]

    assert source_watermark_confidences(voltage_frame) == [:unknown]
    assert source_watermark_freshness_states(voltage_frame) == [:unknown]

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
             stale?: true,
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
               state: :unknown,
               severity: :warning,
               data_state: :ready,
               stale?: true,
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
             :watermark_unknown
           ]

    assert Enum.sort(source_warning_codes) == [
             :physical_aggregate_semantics,
             :watermark_unknown
           ]

    assert data.source_status.watermarks
           |> Enum.map(&{&1.confidence, &1.freshness_state})
           |> Enum.uniq() == [{:unknown, :unknown}]
  end

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

  test "golden replay fixture preserves snapshot-scoped source context" do
    document = load_fixture!("replay_context.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    plan = Engine.plan(resolve_request(document), replay_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.snapshot?
    refute plan.plan_metadata.live_append_eligible?

    telemetry_request = request_by_source(plan.planned_source_requests, :telemetry)

    assert telemetry_request.time_context.mode == "replay_run"
    assert telemetry_request.time_context.replay_run_id == "replay_run_001"
    assert telemetry_request.data_context.realm == "replay"
    assert telemetry_request.data_context.replay_run_id == "replay_run_001"
    assert telemetry_request.metadata.capability_provenance.data_source_id == "replay-questdb"

    assert telemetry_request.metadata.capability_provenance.binding_id ==
             "replay_flight_telemetry"

    assert telemetry_request.metadata.capability_provenance.dataset == "replay_run_001"

    assert Enum.all?(plan.planned_source_requests, fn request ->
             request.time_context.mode == "replay_run" and
               request.time_context.replay_run_id == "replay_run_001" and
               request.data_context.realm == "replay"
           end)

    result =
      Engine.resolve(
        resolve_request(document, %{
          "placement_replay_counter" => %{width_px: 640, height_px: 256}
        }),
        replay_source_registry_opts(
          source_opts: replay_source_opts(),
          validate_dashboard_contract?: true
        )
      )

    assert result.dashboard_warnings == []

    assert %{
             "placement_replay_counter" => %PlacementFrames{
               primary: [%Frame{source: :telemetry} = replay_frame],
               overlays: %{limits: replay_limit_frames}
             }
           } = result.frames_by_placement

    replay_sample_link = link_by_target(replay_frame, :telemetry_sample)

    assert_link_runtime_context(replay_sample_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.counter",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "replay_run",
      time_axis: "generation_time",
      replay_run_id: "replay_run_001",
      realm: "replay",
      data_source_id: "replay-questdb",
      source_binding_id: "replay_flight_telemetry",
      dataset: "replay_run_001",
      source_request_id: replay_frame.meta.source_request_id
    )

    assert DataLinkSelection.selected_ref(replay_sample_link, %{
             "placement-id" => "placement_replay_counter",
             "timestamp-ms" => "1781568000000"
           }) == %{
             "link_id" => replay_sample_link.link_id,
             "target" => "telemetry_sample",
             "target_id" => "sample-replay-1",
             "target_text" => "telemetry sample",
             "timestamp_ms" => 1_781_568_000_000,
             "placement_id" => "placement_replay_counter",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc_001",
             "spacecraft_id" => "sc_001",
             "realm" => "replay",
             "time_mode" => "replay_run",
             "time_axis" => "generation_time",
             "replay_run_id" => "replay_run_001",
             "data_source_id" => "replay-questdb",
             "source_binding_id" => "replay_flight_telemetry",
             "limit_mode" => "observed",
             "observable_id" => "tlm.hk.counter"
           }

    assert Enum.all?(replay_limit_frames, fn frame ->
             frame.meta.realm == :replay and frame.meta.replay_run_id == "replay_run_001"
           end)
  end

  test "golden unknown widget fixture is retained as placement warning" do
    document = load_fixture!("unknown_widget_retained.v1.json")

    result = Engine.plan(resolve_request(document), source_registry_opts([]))

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?

    assert [
             %ResolveWarning{code: :unknown_widget_type, scope: :dashboard},
             %ResolveWarning{code: :unknown_widget_type, scope: :placement}
           ] = result.dashboard_warnings

    assert %{"placement_legacy" => %PlacementFrames{primary: [], overlays: %{}} = frames} =
             result.frames_by_placement

    assert [%ResolveWarning{code: :unknown_widget_type, placement_id: "placement_legacy"}] =
             frames.warnings
  end

  test "golden unsupported source pairing fixture fails closed as unsupported lifecycle" do
    document = load_fixture!("unsupported_operational_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: false, errors: validation_errors} =
             Dashboards.validate_document(document)

    assert [
             %{
               code: :unsupported_widget_frame_contract,
               details: validation_details
             }
           ] = validation_errors

    assert validation_details.placement_id == "placement_operational_series_unsupported"
    assert validation_details.widget_type_id == "cadence.time_series"
    assert validation_details.requested_source == :operational_observables
    assert validation_details.contract_source == :telemetry

    assert validation_details.supported_products == [
             :transport_bitrate,
             :link_rf,
             :runtime_ingress
           ]

    assert validation_details.supported_value_kinds == [:metric]
    assert validation_details.requested_products == [:contacts_phase]
    assert validation_details.requested_value_kinds == [:state]
    assert validation_details.unsupported_observables == ["contacts.phase"]

    result =
      Engine.plan(
        resolve_request(document, %{
          "placement_operational_series_unsupported" => %{width_px: 640, height_px: 256}
        }),
        operational_source_registry_opts(validate_dashboard_contract?: true)
      )

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?
    assert result.plan_metadata.source_request_count == 0

    assert [
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               severity: :error,
               scope: :dashboard,
               details: dashboard_details
             },
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               severity: :warning,
               scope: :placement,
               placement_id: "placement_operational_series_unsupported",
               details: placement_details
             }
           ] = result.dashboard_warnings

    assert dashboard_details.placement_id == "placement_operational_series_unsupported"
    assert placement_details.widget_type_id == "cadence.time_series"
    assert placement_details.requested_source == :operational_observables
    assert placement_details.contract_source == :telemetry

    assert placement_details.supported_products == [
             :transport_bitrate,
             :link_rf,
             :runtime_ingress
           ]

    assert placement_details.supported_value_kinds == [:metric]
    assert placement_details.requested_products == [:contacts_phase]
    assert placement_details.requested_value_kinds == [:state]
    assert placement_details.unsupported_observables == ["contacts.phase"]
    assert placement_details.fallback == :none

    assert %{
             "placement_operational_series_unsupported" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :unsupported_widget_frame_contract,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_operational_series_unsupported"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.unresolved? == false
    assert data.engine_backed?
    assert data.kind == :point
    assert data.sample == nil
    assert data.lifecycle_state == :unsupported
    assert data.lifecycle.warning_codes == [:unsupported_widget_frame_contract]

    assert %{
             state: :no_data,
             severity: :info,
             data_state: :no_data,
             warning_codes: [:unsupported_widget_frame_contract]
           } = data.source_status
  end

  test "golden operational fixture resolves source override through operational frames" do
    document = load_fixture!("operational_status_matrix.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_operational_status" => %{width_px: 480}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["contacts.phase", "ground.station.connection_state"],
               sampling_mode: :latest,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_bitrate,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 480,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :scheduled_contacts_called
    assert_received :realized_contacts_called
    assert_received :transports_called
    assert_received :source_endpoints_called
    assert_received :connection_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert %{
             "placement_operational_status" => %PlacementFrames{
               primary: [
                 %Frame{source: :operational_observables} = contact_frame,
                 %Frame{source: :operational_observables} = connection_frame
               ],
               overlays: %{},
               warnings: []
             }
           } = result.frames_by_placement

    assert contact_frame.meta.supported_capability == :contacts_phase
    assert contact_frame.meta.source_binding_id == "default_flight_operational_observables"
    assert contact_frame.meta.data_source_id == "managed_operational_observables"
    assert field_values(contact_frame, "observable_id") == ["contacts.phase"]
    assert field_values(contact_frame, "phase") == [:scheduled]

    contact_link = link_by_target(contact_frame, :contact)

    assert_link_runtime_context(contact_link,
      logical_source: "operational_observables",
      observable_id: "scheduled-contact-golden-1",
      scope_kind: "source_endpoint",
      scope_id: "source-endpoint-golden-1",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: contact_frame.meta.source_request_id
    )

    assert connection_frame.meta.supported_capability == :connection_state
    assert connection_frame.meta.source_binding_id == "default_flight_operational_observables"
    assert connection_frame.meta.data_source_id == "managed_operational_observables"
    assert field_values(connection_frame, "observable_id") == ["ground.station.connection_state"]
    assert field_values(connection_frame, "connection_state") == [:connected]

    placement_frames = result.frames_by_placement["placement_operational_status"]
    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             stale?: false,
             source_status: source_status,
             rows: [contact_row, connection_row]
           } = data

    assert %{
             state: :fresh,
             severity: :ok,
             data_state: :ready,
             stale?: false,
             warning_codes: [],
             logical_sources: [:operational_observables],
             data_source_ids: ["managed_operational_observables"],
             source_binding_ids: ["default_flight_operational_observables"],
             time_modes: ["live"],
             time_axes: ["generation_time"]
           } = source_status

    assert %{
             observable_id: "contacts.phase:scheduled-contact-golden-1",
             frame_observable_id: "contacts.phase",
             label: "contacts.phase / scheduled / scheduled-contact-golden-1",
             source: :operational_observables,
             status_policy: :contact_phase,
             product_family: :contacts_phase,
             source_request_id: contact_source_request_id,
             logical_source: :operational_observables,
             realm: "flight",
             data_source_id: "managed_operational_observables",
             source_binding_id: "default_flight_operational_observables",
             contact_id: "scheduled-contact-golden-1",
             contact_kind: :scheduled,
             value: :scheduled,
             normalized_state: :scheduled,
             links: contact_links,
             stale?: false
           } = contact_row

    assert %{
             observable_id: "ground.station.connection_state:dss-14",
             frame_observable_id: "ground.station.connection_state",
             label: "Goldstone DSS-14",
             source: :operational_observables,
             status_policy: :connection_state,
             product_family: :connection_state,
             source_request_id: connection_source_request_id,
             logical_source: :operational_observables,
             realm: "flight",
             data_source_id: "managed_operational_observables",
             source_binding_id: "default_flight_operational_observables",
             resource_id: "dss-14",
             scope_kind: :ground_station,
             source_endpoint_id: "source-endpoint-golden-1",
             ground_station_id: "dss-14",
             value: :connected,
             normalized_state: :connected,
             links: connection_links,
             stale?: false
           } = connection_row

    assert contact_source_request_id == contact_frame.meta.source_request_id
    assert connection_source_request_id == connection_frame.meta.source_request_id

    assert Enum.any?(
             contact_links,
             &(&1.target == :contact and &1.target_id == "scheduled-contact-golden-1")
           )

    assert Enum.any?(
             connection_links,
             &(&1.target == :source_endpoint and &1.target_id == "source-endpoint-golden-1")
           )

    assert Enum.any?(
             connection_links,
             &(&1.target == :ground_station and &1.target_id == "dss-14")
           )

    assert "source_endpoint" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "source-endpoint-golden-1" in data.source_status.scope_ids
  end

  test "golden operational data table fixture preserves projected row source context" do
    document = load_fixture!("operational_data_table.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_operational_data_table" => %{width_px: 640}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["contacts.phase", "ground.station.connection_state"],
               sampling_mode: :latest,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_bitrate,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :scheduled_contacts_called
    assert_received :realized_contacts_called
    assert_received :transports_called
    assert_received :source_endpoints_called
    assert_received :connection_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert %{
             "placement_operational_data_table" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :operational_observables} = contact_frame,
                   %Frame{source: :operational_observables} = connection_frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             stale?: false,
             source_status: %{
               state: :fresh,
               severity: :ok,
               data_state: :ready,
               warning_codes: [],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               time_modes: ["live"],
               time_axes: ["generation_time"]
             },
             rows: [contact_row, connection_row]
           } = data

    assert %{
             observable_id: "contacts.phase:scheduled-contact-golden-1",
             frame_observable_id: "contacts.phase",
             label: "contacts.phase / scheduled / scheduled-contact-golden-1",
             source: :operational_observables,
             status_policy: :contact_phase,
             product_family: :contacts_phase,
             source_request_id: contact_source_request_id,
             logical_source: :operational_observables,
             realm: "flight",
             data_source_id: "managed_operational_observables",
             source_binding_id: "default_flight_operational_observables",
             value: :scheduled,
             normalized_state: :scheduled,
             links: contact_links,
             data_management: nil,
             stale?: false
           } = contact_row

    assert %{
             observable_id: "ground.station.connection_state:dss-14",
             frame_observable_id: "ground.station.connection_state",
             label: "Goldstone DSS-14",
             source: :operational_observables,
             status_policy: :connection_state,
             product_family: :connection_state,
             source_request_id: connection_source_request_id,
             logical_source: :operational_observables,
             realm: "flight",
             data_source_id: "managed_operational_observables",
             source_binding_id: "default_flight_operational_observables",
             resource_id: "dss-14",
             scope_kind: :ground_station,
             value: :connected,
             normalized_state: :connected,
             links: connection_links,
             data_management: nil,
             stale?: false
           } = connection_row

    refute Map.has_key?(contact_row, :contact_kind)
    refute Map.has_key?(connection_row, :connection_state)
    assert contact_source_request_id == contact_frame.meta.source_request_id
    assert connection_source_request_id == connection_frame.meta.source_request_id

    assert Enum.any?(
             contact_links,
             &(&1.target == :contact and &1.target_id == "scheduled-contact-golden-1")
           )

    assert Enum.any?(
             connection_links,
             &(&1.target == :source_endpoint and &1.target_id == "source-endpoint-golden-1")
           )

    assert Enum.any?(
             connection_links,
             &(&1.target == :ground_station and &1.target_id == "dss-14")
           )

    assert "source_endpoint" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "source-endpoint-golden-1" in data.source_status.scope_ids
  end

  test "golden operational RF state timeline fixture resolves event histories into timeline lanes" do
    document = load_fixture!("operational_rf_state_timeline.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_link_rf_state_timeline" => %{width_px: 720}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.rf_lock_state", "link.frame_sync_state"],
               sampling_mode: :event_history,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_execution_state
               ],
               overlays: [],
               target_points: 720,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_state_timeline_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received {:rf_state_transports_opts, transport_opts}
    assert_received {:rf_state_lock_snapshots_opts, lock_opts}
    assert_received {:rf_state_frame_sync_snapshots_opts, frame_sync_opts}

    assert Keyword.fetch!(transport_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(transport_opts, :to) == ~U[2026-06-17 12:03:00Z]
    assert Keyword.fetch!(lock_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(lock_opts, :to) == ~U[2026-06-17 12:03:00Z]
    assert Keyword.fetch!(frame_sync_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(frame_sync_opts, :to) == ~U[2026-06-17 12:03:00Z]

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert %{
             "placement_link_rf_state_timeline" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :operational_observables, shape: :events} = lock_frame,
                   %Frame{source: :operational_observables, shape: :events} = frame_sync_frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert lock_frame.meta.supported_capability == :link_rf_lock_state_history
    assert lock_frame.meta.source_binding_id == "default_flight_operational_observables"
    assert lock_frame.meta.data_source_id == "managed_operational_observables"

    assert field_values(lock_frame, "time") == [
             ~U[2026-06-17 12:00:30Z],
             ~U[2026-06-17 12:01:30Z]
           ]

    assert field_values(lock_frame, "resource_id") == [
             "link-golden-alpha",
             "link-golden-alpha"
           ]

    assert field_values(lock_frame, "state") == [:acquiring, :locked]
    assert field_values(lock_frame, "normalized_state") == [:blue, :green]
    assert link_by_target(lock_frame, :transport, "transport-golden-alpha")
    assert link_by_target(lock_frame, :source_endpoint, "source-endpoint-golden-1")
    assert link_by_target(lock_frame, :ground_station, "dss-14")

    assert frame_sync_frame.meta.supported_capability == :link_rf_frame_sync_state_history

    assert field_values(frame_sync_frame, "time") == [
             ~U[2026-06-17 12:00:45Z],
             ~U[2026-06-17 12:02:00Z]
           ]

    assert field_values(frame_sync_frame, "resource_id") == [
             "link-golden-alpha",
             "link-golden-alpha"
           ]

    assert field_values(frame_sync_frame, "state") == [:acquiring, :synchronized]
    assert field_values(frame_sync_frame, "normalized_state") == [:blue, :green]
    assert link_by_target(frame_sync_frame, :transport, "transport-golden-alpha")

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             lanes: lanes,
             rows: rows
           } = data

    assert Enum.map(lanes, & &1.lane_key) == [
             "operational_observables:link.rf_lock_state:link-golden-alpha",
             "operational_observables:link.frame_sync_state:link-golden-alpha"
           ]

    assert Enum.map(rows, & &1.normalized_state) == [:blue, :green, :blue, :green]

    assert Enum.map(rows, & &1.resource_id) == [
             "link-golden-alpha",
             "link-golden-alpha",
             "link-golden-alpha",
             "link-golden-alpha"
           ]

    assert Enum.all?(rows, fn row ->
             Enum.any?(
               row.links,
               &(&1.target == :transport and &1.target_id == "transport-golden-alpha")
             )
           end)
  end

  test "golden operational transport execution timeline fixture resolves interval history into lanes" do
    document = load_fixture!("operational_transport_execution_state_timeline.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_transport_execution_state_timeline" => %{width_px: 720}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "transport", mode: "one", ids: ["transport-golden-alpha"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["comms.transport.execution_state"],
               sampling_mode: :event_history,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_execution_state
               ],
               overlays: [],
               target_points: 720,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_transport_execution_timeline_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received {:transport_execution_intervals_opts, interval_opts}
    assert Keyword.fetch!(interval_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(interval_opts, :to) == ~U[2026-06-17 12:04:00Z]

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_transport_execution_state_timeline" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :operational_observables, shape: :events} = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert frame.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.source_binding_id == "default_flight_operational_observables"
    assert frame.meta.data_source_id == "managed_operational_observables"
    assert frame.meta.observable_id == "comms.transport.execution_state"
    assert frame.meta.returned_points == 2

    assert field_values(frame, "time") == [
             ~U[2026-06-17 12:00:10Z],
             ~U[2026-06-17 12:01:30Z]
           ]

    assert field_values(frame, "ends_at") == [
             ~U[2026-06-17 12:01:30Z],
             ~U[2026-06-17 12:03:30Z]
           ]

    assert field_values(frame, "resource_id") == [
             "transport-golden-alpha",
             "transport-golden-alpha"
           ]

    assert field_values(frame, "contact_id") == [
             "contact-golden-alpha",
             "contact-golden-alpha"
           ]

    assert field_values(frame, "path_id") == ["uplink-golden-alpha", "uplink-golden-alpha"]
    assert field_values(frame, "state") == [:initialized, :transport_event_handled]
    assert field_values(frame, "normalized_state") == [:initialized, :transport_event_handled]

    assert Enum.map(frame.meta.evidence_refs, &{&1.kind, &1.id, &1.confidence}) == [
             {:transport_execution_interval, "transport-execution-interval-golden-alpha-1",
              :projected},
             {:operational_interval, "transport-execution-event-golden-alpha-1", :direct},
             {:transport_execution_interval, "transport-execution-interval-golden-alpha-2",
              :projected},
             {:operational_interval, "transport-execution-event-golden-alpha-2", :direct}
           ]

    assert link_by_target(frame, :transport, "transport-golden-alpha")

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             lanes: lanes,
             rows: rows
           } = data

    assert Enum.map(lanes, & &1.lane_key) == [
             "operational_observables:comms.transport.execution_state:transport-golden-alpha"
           ]

    assert Enum.map(rows, & &1.normalized_state) == [
             :initialized,
             :transport_event_handled
           ]

    assert Enum.map(rows, & &1.ends_at) == [
             ~U[2026-06-17 12:01:30Z],
             ~U[2026-06-17 12:03:30Z]
           ]

    assert Enum.all?(rows, fn row ->
             Enum.any?(
               row.links,
               &(&1.target == :transport and &1.target_id == "transport-golden-alpha")
             )
           end)
  end

  test "golden operational metric value-tile fixture preserves resource DataLinks through presenter data" do
    document = load_fixture!("operational_metric_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_downlink_bitrate" => %{width_px: 320}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "transport", mode: "one", ids: ["transport-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["comms.transport.downlink_bitrate"],
               sampling_mode: :latest,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_metric_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :metric_transports_called
    assert_received :transport_metric_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_downlink_bitrate" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :transport_bitrate,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       observable_id: "comms.transport.downlink_bitrate",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["comms.transport.downlink_bitrate"]
    assert field_values(frame, "resource_id") == ["transport-golden-alpha"]
    assert field_values(frame, "label") == ["Golden Alpha TCP"]
    assert field_values(frame, "scope_kind") == [:transport]
    assert field_values(frame, "transport_id") == ["transport-golden-alpha"]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "ground_station_id") == ["dss-14"]
    assert field_values(frame, "link_id") == ["link-golden-alpha"]
    assert field_values(frame, "adapter_key") == [:tcp_socket]
    assert field_values(frame, "value") == [12_500.5]
    assert field_values(frame, "unit") == ["bit/s"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:04:00Z]]
    assert field_values(frame, "freshness_state") == [:fresh]

    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")
    source_endpoint_link = link_by_target(frame, :source_endpoint, "source-endpoint-golden-1")
    ground_station_link = link_by_target(frame, :ground_station, "dss-14")

    for link <- [transport_link, source_endpoint_link, ground_station_link] do
      assert_link_runtime_context(link,
        logical_source: "operational_observables",
        observable_id: "comms.transport.downlink_bitrate",
        scope_kind: "transport",
        scope_id: "transport-golden-alpha",
        time_mode: "live",
        time_axis: "generation_time",
        realm: "flight",
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        source_request_id: frame.meta.source_request_id
      )

      assert context_value(link.context, [:operational_resource]) == %{
               adapter_key: :tcp_socket,
               ground_station_id: "dss-14",
               link_id: "link-golden-alpha",
               resource_id: "transport-golden-alpha",
               scope_kind: :transport,
               source_endpoint_id: "source-endpoint-golden-1",
               transport_id: "transport-golden-alpha"
             }
    end

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_downlink_bitrate"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "placement_id" => "placement_downlink_bitrate",
             "source" => "frame",
             "scope_kind" => "transport",
             "scope_id" => "transport-golden-alpha",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "comms.transport.downlink_bitrate"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             unit: "bit/s",
             label: "Golden Alpha TCP",
             sample: %{
               sample_id: "transport-golden-alpha",
               raw_value: 12_500.5,
               engineering_value: 12_500.5,
               receipt_time: ~U[2026-06-17 12:04:00Z],
               generation_time: ~U[2026-06-17 12:04:00Z],
               quality_state: :observed
             }
           } = data

    assert Enum.map(data.links, &{&1.target, &1.target_id}) == [
             {:link, "link-golden-alpha"},
             {:transport, "transport-golden-alpha"},
             {:source_endpoint, "source-endpoint-golden-1"},
             {:ground_station, "dss-14"}
           ]
  end

  test "golden operational uplink metric value-tile fixture preserves directional resource DataLinks" do
    document = load_fixture!("operational_uplink_metric_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_uplink_bitrate" => %{width_px: 320}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "transport", mode: "one", ids: ["transport-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["comms.transport.uplink_bitrate"],
               sampling_mode: :latest,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_metric_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :metric_transports_called
    assert_received :transport_metric_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_uplink_bitrate" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :transport_bitrate,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       observable_id: "comms.transport.uplink_bitrate",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["comms.transport.uplink_bitrate"]
    assert field_values(frame, "resource_id") == ["transport-golden-alpha"]
    assert field_values(frame, "label") == ["Golden Alpha TCP"]
    assert field_values(frame, "scope_kind") == [:transport]
    assert field_values(frame, "transport_id") == ["transport-golden-alpha"]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "ground_station_id") == ["dss-14"]
    assert field_values(frame, "link_id") == ["link-golden-alpha"]
    assert field_values(frame, "adapter_key") == [:tcp_socket]
    assert field_values(frame, "value") == [4_800.0]
    assert field_values(frame, "unit") == ["bit/s"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:04:00Z]]
    assert field_values(frame, "freshness_state") == [:fresh]

    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")

    assert_link_runtime_context(transport_link,
      logical_source: "operational_observables",
      observable_id: "comms.transport.uplink_bitrate",
      scope_kind: "transport",
      scope_id: "transport-golden-alpha",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: frame.meta.source_request_id
    )

    assert context_value(transport_link.context, [:operational_resource]) == %{
             adapter_key: :tcp_socket,
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             resource_id: "transport-golden-alpha",
             scope_kind: :transport,
             source_endpoint_id: "source-endpoint-golden-1",
             transport_id: "transport-golden-alpha"
           }

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_uplink_bitrate"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "placement_id" => "placement_uplink_bitrate",
             "source" => "frame",
             "scope_kind" => "transport",
             "scope_id" => "transport-golden-alpha",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "comms.transport.uplink_bitrate"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             unit: "bit/s",
             label: "Golden Alpha TCP",
             sample: %{
               sample_id: "transport-golden-alpha",
               raw_value: 4_800.0,
               engineering_value: 4_800.0,
               receipt_time: ~U[2026-06-17 12:04:00Z],
               generation_time: ~U[2026-06-17 12:04:00Z],
               quality_state: :observed
             }
           } = data

    assert Enum.map(data.links, &{&1.target, &1.target_id}) == [
             {:link, "link-golden-alpha"},
             {:transport, "transport-golden-alpha"},
             {:source_endpoint, "source-endpoint-golden-1"},
             {:ground_station, "dss-14"}
           ]
  end

  test "golden operational RF metric value-tile fixture preserves link-scoped DataLinks through presenter data" do
    document = load_fixture!("operational_rf_metric_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_link_snr" => %{width_px: 320}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.snr_db"],
               sampling_mode: :latest,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_metric_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :rf_metric_transports_called
    assert_received :link_rf_metric_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_link_snr" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :link_rf_metric,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :link_rf,
                       observable_ids: ["link.snr_db"],
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["link.snr_db"]
    assert field_values(frame, "resource_id") == ["link-golden-alpha"]
    assert field_values(frame, "label") == ["RF SNR / link-golden-alpha"]
    assert field_values(frame, "scope_kind") == [:link]
    assert field_values(frame, "transport_id") == ["transport-golden-alpha"]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "ground_station_id") == ["dss-14"]
    assert field_values(frame, "link_id") == ["link-golden-alpha"]
    assert field_values(frame, "adapter_key") == [:rf_adapter]
    assert field_values(frame, "value") == [12.75]
    assert field_values(frame, "unit") == ["dB"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:06:00Z]]
    assert field_values(frame, "freshness_state") == [:fresh]

    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")
    source_endpoint_link = link_by_target(frame, :source_endpoint, "source-endpoint-golden-1")
    ground_station_link = link_by_target(frame, :ground_station, "dss-14")
    link_link = link_by_target(frame, :link, "link-golden-alpha")

    for link <- [transport_link, source_endpoint_link, ground_station_link, link_link] do
      assert_link_runtime_context(link,
        logical_source: "operational_observables",
        observable_id: "link.snr_db",
        scope_kind: "link",
        scope_id: "link-golden-alpha",
        time_mode: "live",
        time_axis: "generation_time",
        realm: "flight",
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        source_request_id: frame.meta.source_request_id
      )

      assert context_value(link.context, [:operational_resource]) == %{
               adapter_key: :rf_adapter,
               ground_station_id: "dss-14",
               link_id: "link-golden-alpha",
               resource_id: "link-golden-alpha",
               scope_kind: :link,
               source_endpoint_id: "source-endpoint-golden-1",
               transport_id: "transport-golden-alpha"
             }
    end

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_link_snr"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "placement_id" => "placement_link_snr",
             "source" => "frame",
             "scope_kind" => "link",
             "scope_id" => "link-golden-alpha",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "link.snr_db"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             unit: "dB",
             label: "RF SNR / link-golden-alpha",
             sample: %{
               sample_id: "link-golden-alpha",
               raw_value: 12.75,
               engineering_value: 12.75,
               receipt_time: ~U[2026-06-17 12:06:00Z],
               generation_time: ~U[2026-06-17 12:06:00Z],
               quality_state: :observed
             }
           } = data

    assert Enum.map(data.links, &{&1.target, &1.target_id}) == [
             {:link, "link-golden-alpha"},
             {:transport, "transport-golden-alpha"},
             {:source_endpoint, "source-endpoint-golden-1"},
             {:ground_station, "dss-14"}
           ]
  end

  test "golden operational Eb/N0 metric value-tile fixture preserves link-scoped DataLinks through presenter data" do
    document = load_fixture!("operational_eb_n0_metric_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_link_eb_n0" => %{width_px: 320}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.eb_n0_db"],
               sampling_mode: :latest,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_metric_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :rf_metric_transports_called
    assert_received :link_rf_metric_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_link_eb_n0" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :link_rf_metric,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :link_rf,
                       observable_ids: ["link.eb_n0_db"],
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["link.eb_n0_db"]
    assert field_values(frame, "resource_id") == ["link-golden-alpha"]
    assert field_values(frame, "label") == ["RF Eb/N0 / link-golden-alpha"]
    assert field_values(frame, "scope_kind") == [:link]
    assert field_values(frame, "transport_id") == ["transport-golden-alpha"]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "ground_station_id") == ["dss-14"]
    assert field_values(frame, "link_id") == ["link-golden-alpha"]
    assert field_values(frame, "adapter_key") == [:rf_adapter]
    assert field_values(frame, "value") == [9.25]
    assert field_values(frame, "unit") == ["dB"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:06:30Z]]
    assert field_values(frame, "freshness_state") == [:fresh]

    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")
    source_endpoint_link = link_by_target(frame, :source_endpoint, "source-endpoint-golden-1")
    ground_station_link = link_by_target(frame, :ground_station, "dss-14")
    link_link = link_by_target(frame, :link, "link-golden-alpha")

    for link <- [transport_link, source_endpoint_link, ground_station_link, link_link] do
      assert_link_runtime_context(link,
        logical_source: "operational_observables",
        observable_id: "link.eb_n0_db",
        scope_kind: "link",
        scope_id: "link-golden-alpha",
        time_mode: "live",
        time_axis: "generation_time",
        realm: "flight",
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        source_request_id: frame.meta.source_request_id
      )

      assert context_value(link.context, [:operational_resource]) == %{
               adapter_key: :rf_adapter,
               ground_station_id: "dss-14",
               link_id: "link-golden-alpha",
               resource_id: "link-golden-alpha",
               scope_kind: :link,
               source_endpoint_id: "source-endpoint-golden-1",
               transport_id: "transport-golden-alpha"
             }
    end

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_link_eb_n0"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "placement_id" => "placement_link_eb_n0",
             "source" => "frame",
             "scope_kind" => "link",
             "scope_id" => "link-golden-alpha",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "link.eb_n0_db"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             unit: "dB",
             label: "RF Eb/N0 / link-golden-alpha",
             sample: %{
               sample_id: "link-golden-alpha",
               raw_value: 9.25,
               engineering_value: 9.25,
               receipt_time: ~U[2026-06-17 12:06:30Z],
               generation_time: ~U[2026-06-17 12:06:30Z],
               quality_state: :observed
             }
           } = data

    assert Enum.map(data.links, &{&1.target, &1.target_id}) == [
             {:link, "link-golden-alpha"},
             {:transport, "transport-golden-alpha"},
             {:source_endpoint, "source-endpoint-golden-1"},
             {:ground_station, "dss-14"}
           ]
  end

  test "golden operational metric value-tile fixture degrades when a configured resource has no snapshot" do
    document = load_fixture!("operational_metric_missing_snapshot_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_downlink_bitrate_missing_snapshot" => %{width_px: 320}})
      |> Map.put(:scope_context, %{
        primary: %{
          kind: "transport",
          mode: "many",
          ids: ["transport-golden-alpha", "transport-golden-beta"]
        }
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["comms.transport.downlink_bitrate"],
               sampling_mode: :latest,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_metric_source_opts(parent, missing_snapshot?: true),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :metric_transports_called
    assert_received :transport_metric_snapshots_called

    assert [
             %ResolveWarning{
               code: :missing_snapshot,
               severity: :warning,
               message: "Operational observable snapshot is missing",
               scope: :dashboard
             } = dashboard_warning
           ] = result.dashboard_warnings

    assert dashboard_warning.details.supported_capability == :transport_bitrate
    assert dashboard_warning.details.observable_ids == ["comms.transport.downlink_bitrate"]

    assert Enum.map(dashboard_warning.details.actions, & &1.target) == [
             :source_health,
             :source_inventory
           ]

    assert link_targets(dashboard_warning) == [:telemetry_point]

    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_downlink_bitrate_missing_snapshot" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :transport_bitrate,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       observable_id: "comms.transport.downlink_bitrate",
                       warning_codes: [:missing_snapshot]
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :missing_snapshot,
                     severity: :warning,
                     message: "Operational observable snapshot is missing"
                   } = warning
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert warning.details.supported_capability == :transport_bitrate
    assert warning.details.observable_ids == ["comms.transport.downlink_bitrate"]
    assert warning.details.frame_ids == [frame.frame_id]

    assert field_values(frame, "observable_id") == [
             "comms.transport.downlink_bitrate",
             "comms.transport.downlink_bitrate"
           ]

    assert field_values(frame, "resource_id") == [
             "transport-golden-alpha",
             "transport-golden-beta"
           ]

    assert field_values(frame, "label") == ["Golden Alpha TCP", "Golden Beta TCP"]
    assert field_values(frame, "scope_kind") == [:transport, :transport]

    assert field_values(frame, "transport_id") == [
             "transport-golden-alpha",
             "transport-golden-beta"
           ]

    assert field_values(frame, "source_endpoint_id") == [
             "source-endpoint-golden-1",
             "source-endpoint-golden-2"
           ]

    assert field_values(frame, "ground_station_id") == ["dss-14", "dss-63"]
    assert field_values(frame, "link_id") == ["link-golden-alpha", "link-golden-beta"]
    assert field_values(frame, "adapter_key") == [:tcp_socket, :tcp_socket]
    assert field_values(frame, "value") == [12_500.5, nil]
    assert field_values(frame, "unit") == ["bit/s", "bit/s"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:04:00Z], nil]
    assert field_values(frame, "freshness_state") == [:fresh, :missing]

    assert link_targets(frame) == [
             :transport,
             :source_endpoint,
             :ground_station,
             :link,
             :transport,
             :source_endpoint,
             :ground_station,
             :link
           ]

    beta_transport_link = link_by_target(frame, :transport, "transport-golden-beta")

    beta_source_endpoint_link =
      link_by_target(frame, :source_endpoint, "source-endpoint-golden-2")

    beta_ground_station_link = link_by_target(frame, :ground_station, "dss-63")
    beta_link_link = link_by_target(frame, :link, "link-golden-beta")

    for link <- [
          beta_transport_link,
          beta_source_endpoint_link,
          beta_ground_station_link,
          beta_link_link
        ] do
      assert_link_runtime_context(link,
        logical_source: "operational_observables",
        observable_id: "comms.transport.downlink_bitrate",
        scope_kind: "transport",
        time_mode: "live",
        time_axis: "generation_time",
        realm: "flight",
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        source_request_id: frame.meta.source_request_id
      )

      assert context_value(link.context, [:scope, :primary, :ids]) == [
               "transport-golden-alpha",
               "transport-golden-beta"
             ]

      assert context_value(link.context, [:operational_resource]) == %{
               adapter_key: :tcp_socket,
               ground_station_id: "dss-63",
               link_id: "link-golden-beta",
               resource_id: "transport-golden-beta",
               scope_kind: :transport,
               source_endpoint_id: "source-endpoint-golden-2",
               transport_id: "transport-golden-beta"
             }
    end

    assert DataLinkSelection.selected_ref(beta_transport_link, %{
             "placement-id" => "placement_downlink_bitrate_missing_snapshot"
           }) == %{
             "link_id" => beta_transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-beta",
             "target_text" => "transport",
             "placement_id" => "placement_downlink_bitrate_missing_snapshot",
             "source" => "frame",
             "scope_kind" => "transport",
             "scope_id" => "transport-golden-beta",
             "scope_ids" => "transport-golden-alpha,transport-golden-beta",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-beta",
             "source_endpoint_id" => "source-endpoint-golden-2",
             "ground_station_id" => "dss-63",
             "scope_link_id" => "link-golden-beta",
             "observable_id" => "comms.transport.downlink_bitrate"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: true,
             lifecycle: %{state: :stale, severity: :warning, warning_codes: [:missing_snapshot]},
             source_status: %{
               state: :unknown,
               severity: :warning,
               warning_codes: [:missing_snapshot],
               stale?: true
             },
             unit: "bit/s",
             label: "Golden Alpha TCP",
             sample: %{
               sample_id: "transport-golden-alpha",
               raw_value: 12_500.5,
               engineering_value: 12_500.5,
               receipt_time: ~U[2026-06-17 12:04:00Z],
               generation_time: ~U[2026-06-17 12:04:00Z],
               quality_state: :observed
             }
           } = data

    assert data.source_status.scope_ids == ["transport-golden-alpha", "transport-golden-beta"]

    assert Enum.map(data.links, &{&1.target, &1.target_id}) == [
             {:link, "link-golden-alpha"},
             {:link, "link-golden-beta"},
             {:transport, "transport-golden-alpha"},
             {:transport, "transport-golden-beta"},
             {:source_endpoint, "source-endpoint-golden-1"},
             {:source_endpoint, "source-endpoint-golden-2"},
             {:ground_station, "dss-14"},
             {:ground_station, "dss-63"}
           ]
  end

  test "golden event timeline fixture resolves telemetry backfill lifecycle evidence" do
    document = load_fixture!("event_timeline_backfill_lifecycle.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request = resolve_request(document, %{"placement_event_timeline" => %{width_px: 720}})
    plan = Engine.plan(request, event_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    [event_request] = plan.planned_source_requests

    assert %{
             logical_source: :events,
             observables: [],
             sampling_mode: :event_history,
             products: [
               :contact_intervals,
               :mission_timeline,
               :source_health_transitions,
               :source_watermark_events,
               :source_capability_postures,
               :telemetry_backfill_lifecycle,
               :telemetry_revision_decisions
             ],
             overlays: [],
             target_points: 720,
             time_axis: :occurred_at,
             data_source_id: "managed_events_projection",
             source_binding_id: "default_flight_events"
           } = request_summary(event_request)

    assert Map.fetch!(event_request.sampling, :families) == [
             :contacts,
             :mission_timeline,
             :source_health,
             :source_watermarks,
             :source_capabilities,
             :telemetry_backfills,
             :telemetry_revisions
           ]

    result =
      Engine.resolve(
        request,
        event_source_registry_opts(
          validate_dashboard_contract?: true,
          source_result_cache?: false,
          source_opts: event_timeline_source_opts(parent)
        )
      )

    assert_received {:backfill_lifecycle_events_called, "org_dashboards", "mission_dashboards",
                     backfill_opts}

    assert Keyword.fetch!(backfill_opts, :realm) == "flight"
    assert Keyword.fetch!(backfill_opts, :spacecraft_id) == "sc_001"
    assert Keyword.fetch!(backfill_opts, :limit) == 500
    assert Keyword.fetch!(backfill_opts, :order) == :asc

    assert_received {:source_capability_posture_events_called, "org_dashboards",
                     "mission_dashboards", source_capability_opts}

    assert Keyword.fetch!(source_capability_opts, :limit) == 500
    assert Keyword.fetch!(source_capability_opts, :order) == :asc

    assert_received {:backfill_workflow_job_called, "backfill-run-golden-started"}

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 7

    assert %{
             "placement_event_timeline" =>
               %PlacementFrames{
                 primary: primary_frames,
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert Enum.map(primary_frames, & &1.meta.product) == [
             :contact_intervals,
             :mission_timeline,
             :source_health_transitions,
             :source_watermark_events,
             :source_capability_postures,
             :telemetry_backfill_lifecycle,
             :telemetry_revision_decisions
           ]

    source_capability_frame =
      Enum.find(primary_frames, &(&1.meta.product == :source_capability_postures))

    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} =
             source_capability_frame

    assert source_capability_frame.meta.family == :source_capability
    assert source_capability_frame.meta.source_binding_id == "default_flight_events"
    assert source_capability_frame.meta.data_source_id == "managed_events_projection"
    assert source_capability_frame.meta.returned_events == 1

    assert field_values(source_capability_frame, "source_record_id") == [
             "dashboard-golden:resolve-golden:events-request-1"
           ]

    assert field_values(source_capability_frame, "operational_event_id") == [
             "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1"
           ]

    assert field_values(source_capability_frame, "kind") == [:source_capability_fallback]
    assert field_values(source_capability_frame, "severity") == [:warning]
    assert field_values(source_capability_frame, "capability_status") == [:fallback]
    assert field_values(source_capability_frame, "requested_time_axis") == [:generation_time]
    assert field_values(source_capability_frame, "executed_time_axis") == [:occurred_at]

    assert field_values(source_capability_frame, "requested_products") == [
             "source_capability_postures"
           ]

    assert field_values(source_capability_frame, "supported_products") == [
             "source_capability_postures"
           ]

    assert field_values(source_capability_frame, "source_execution_status") == [:resolved]
    assert field_values(source_capability_frame, "source_execution_cache_status") == [:miss]

    assert link_targets(source_capability_frame) == [:operational_event]

    assert_link_runtime_context(
      link_by_target(
        source_capability_frame,
        :operational_event,
        "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1"
      ),
      logical_source: "events",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "occurred_at",
      realm: "flight",
      data_source_id: "managed_events_projection",
      source_binding_id: "default_flight_events",
      source_request_id: source_capability_frame.meta.source_request_id
    )

    backfill_frame =
      Enum.find(primary_frames, &(&1.meta.product == :telemetry_backfill_lifecycle))

    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = backfill_frame
    assert backfill_frame.meta.family == :telemetry_backfill
    assert backfill_frame.meta.source_binding_id == "default_flight_events"
    assert backfill_frame.meta.data_source_id == "managed_events_projection"
    assert backfill_frame.meta.returned_events == 1

    assert field_values(backfill_frame, "source_record_id") == [
             "backfill-event-golden-started-dispatch-failed"
           ]

    assert field_values(backfill_frame, "kind") == [:backfill_started]
    assert field_values(backfill_frame, "workflow_run_id") == ["backfill-run-golden-started"]
    assert field_values(backfill_frame, "workflow_job_id") == ["job-golden-started"]
    assert field_values(backfill_frame, "workflow_job_status") == [:failed]
    assert field_values(backfill_frame, "workflow_job_failure") == [:source_window_failed]

    assert link_targets(backfill_frame) == [
             :telemetry_backfill_lifecycle_event,
             :operational_event
           ]

    assert_link_runtime_context(
      link_by_target(
        backfill_frame,
        :telemetry_backfill_lifecycle_event,
        "backfill-event-golden-started-dispatch-failed"
      ),
      logical_source: "events",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "occurred_at",
      realm: "flight",
      data_source_id: "managed_events_projection",
      source_binding_id: "default_flight_events",
      source_request_id: backfill_frame.meta.source_request_id
    )

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :event_timeline,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             rows: [
               %{
                 category: :telemetry_backfill,
                 kind: :backfill_started,
                 severity: :info,
                 source_record_id: "backfill-event-golden-started-dispatch-failed",
                 backfill_run_id: "backfill-run-golden-started",
                 workflow_run_id: "backfill-run-golden-started",
                 workflow_job_id: "job-golden-started",
                 workflow_job_status: :failed,
                 workflow_job_failure: :source_window_failed,
                 target: :telemetry_backfill_lifecycle_event,
                 data_management: %{
                   badges: [
                     %{
                       kind: :historical_workflow,
                       value: "backfill_started_dispatch_degraded",
                       label: "Backfill dispatch failed",
                       status: :warning,
                       code: "backfill_started_dispatch_degraded",
                       data_link_target: :telemetry_backfill_lifecycle_event,
                       data_link_id: "backfill-event-golden-started-dispatch-failed",
                       workflow_job_id: "job-golden-started",
                       workflow_job_status: "failed",
                       workflow_job_failure: "source_window_failed"
                     }
                   ]
                 }
               },
               %{
                 category: :source_capability,
                 kind: :source_capability_fallback,
                 severity: :warning,
                 source_record_id: "dashboard-golden:resolve-golden:events-request-1",
                 target: :operational_event,
                 target_id:
                   "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1",
                 logical_source: :events,
                 data_source_id: "managed_events_projection",
                 source_binding_id: "default_flight_events",
                 realm: :flight,
                 dataset: "mission_events",
                 capability_status: :fallback,
                 requested_time_axis: :generation_time,
                 executed_time_axis: :occurred_at,
                 source_execution_status: :resolved,
                 source_execution_cache_status: :miss
               }
             ]
           } = data

    source_capability_row =
      Enum.find(data.rows, &(&1.category == :source_capability))

    assert Enum.any?(
             source_capability_row.links,
             &(&1.target == :operational_event and
                 &1.target_id ==
                   "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1")
           )

    assert data.data_management.badges == [
             hd(hd(data.rows).data_management.badges)
           ]
  end

  test "golden repeated fixture expands into scoped placement instances" do
    document = load_fixture!("repeated_spacecraft_status.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_status_repeat" => %{width_px: 480, height_px: 192}})
      |> Map.put(:scope_context, %{})

    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 6

    telemetry_requests =
      Enum.filter(plan.planned_source_requests, &(&1.logical_source == :telemetry))

    limit_requests =
      Enum.filter(plan.planned_source_requests, &(&1.logical_source == :limits))

    assert telemetry_requests
           |> Enum.map(& &1.scope_context.primary.ids)
           |> Enum.sort() == [
             ["sc_001"],
             ["sc_002"],
             ["sc_003"]
           ]

    assert Enum.all?(telemetry_requests, fn request ->
             request.scope_context.primary.mode == "one" and
               request.observables == ["tlm.hk.battery_voltage", "tlm.hk.bus_current"] and
               request.sampling.mode == :latest and
               request.sampling.target_points == 480 and
               request.overlays == [:quality]
           end)

    assert limit_requests
           |> Enum.map(& &1.scope_context.primary.ids)
           |> Enum.sort() == [
             ["sc_001"],
             ["sc_002"],
             ["sc_003"]
           ]

    assert Enum.all?(limit_requests, fn request ->
             request.scope_context.primary.mode == "one" and
               request.observables == ["tlm.hk.battery_voltage", "tlm.hk.bus_current"] and
               request.sampling.mode == :latest_state and
               request.sampling.products == [:latest_state]
           end)

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_opts()
        )
      )

    assert Enum.map(result.dashboard_warnings, & &1.code) == [
             :capability_fallback,
             :capability_fallback,
             :capability_fallback
           ]

    assert result.plan_metadata.executed_source_request_count == 6
    assert result.plan_metadata.returned_frame_count == 12

    assert result.frames_by_placement
           |> Map.keys()
           |> Enum.sort() == [
             "placement_status_repeat__repeat__spacecraft__sc_001",
             "placement_status_repeat__repeat__spacecraft__sc_002",
             "placement_status_repeat__repeat__spacecraft__sc_003"
           ]

    assert %{
             "placement_status_repeat__repeat__spacecraft__sc_001" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :telemetry, shape: :scalar} = voltage_frame,
                   %Frame{source: :telemetry, shape: :scalar} = current_frame
                 ],
                 overlays: %{limits: limit_frames},
                 warnings: [%ResolveWarning{code: :capability_fallback}]
               } = placement_frames
           } = result.frames_by_placement

    assert length(limit_frames) == 2
    assert voltage_frame.scope.primary.ids == ["sc_001"]
    assert voltage_frame.scope.primary.mode == "one"
    assert current_frame.scope.primary.ids == ["sc_001"]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage") == [12.25]
    assert field_values(current_frame, "tlm.hk.bus_current") == [12.25]

    telemetry_link = link_by_target(voltage_frame, :telemetry_point, "tlm.hk.battery_voltage")

    assert context_value(telemetry_link.context, [:scope, :primary, :ids]) == ["sc_001"]

    assert context_text(context_value(telemetry_link.context, [:scope, :primary, :mode])) ==
             "one"

    [render_item, _second_item, _third_item] = RenderItem.from_document(document)
    assert render_item.placement_id == "placement_status_repeat__repeat__spacecraft__sc_001"

    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.kind == :status_matrix
    assert data.lifecycle_state == :ready

    assert Enum.map(data.rows, & &1.observable_id) == [
             "tlm.hk.battery_voltage",
             "tlm.hk.bus_current"
           ]
  end

  test "golden stale operational fixture carries warning through presenter lifecycle" do
    document = load_fixture!("stale_operational_warning.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    result =
      Engine.resolve(
        resolve_request(document, %{"placement_command_queue" => %{width_px: 320}}),
        operational_source_registry_opts(
          source_opts: stale_operational_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard} = warning] =
             result.dashboard_warnings

    assert warning.details.supported_capability == :command_queue_depth
    assert warning.details.observable_ids == ["commanding.queue_depth"]
    assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
    assert link_targets(warning) == [:telemetry_point]

    assert %{
             "placement_command_queue" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :command_queue_depth,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z]
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_command_queue"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["commanding.queue_depth"]
    assert field_values(frame, "value") == [0]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    assert_link_runtime_context(link_by_target(warning, :telemetry_point),
      logical_source: "operational_observables",
      observable_id: "commanding.queue_depth",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables"
    )

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.lifecycle_state == :stale
    assert data.lifecycle.state == :stale
    assert data.lifecycle.warning_codes == [:stale_data]
    assert data.sample.engineering_value == 0
  end

  test "golden stale operational status matrix fixture carries stale row source status" do
    document = load_fixture!("stale_operational_status_matrix.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_command_queue_status" => %{width_px: 480}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "mission", mode: "one", ids: ["mission_dashboards"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["commanding.queue_depth"],
               sampling_mode: :latest,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_bitrate,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 480,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: stale_operational_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard}] =
             result.dashboard_warnings

    assert %{
             "placement_command_queue_status" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :command_queue_depth,
                       product_family: :commanding,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z],
                       data_source_id: "managed_operational_observables",
                       source_binding_id: "default_flight_operational_observables"
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_command_queue_status"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["commanding.queue_depth"]
    assert field_values(frame, "resource_id") == ["mission_dashboards"]
    assert field_values(frame, "label") == ["Pending commands"]
    assert field_values(frame, "scope_kind") == [:mission]
    assert field_values(frame, "value") == [0]
    assert field_values(frame, "unit") == ["commands"]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :stale,
             stale?: true,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data],
               reason_codes: [:stale, :stale_data]
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               time_modes: ["live"],
               time_axes: ["generation_time"]
             },
             data_management: %{
               warning_codes: ["stale_data"],
               badges: [],
               data_views: []
             },
             rows: [
               %{
                 observable_id: "commanding.queue_depth:mission_dashboards",
                 frame_observable_id: "commanding.queue_depth",
                 label: "Pending commands",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 product_family: :commanding,
                 source_request_id: source_request_id,
                 logical_source: :operational_observables,
                 realm: "flight",
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 resource_id: "mission_dashboards",
                 scope_kind: :mission,
                 unit: "commands",
                 value: 0,
                 normalized_state: :observed,
                 freshness_state: :stale,
                 age_ms: 2_000,
                 links: [],
                 stale?: true
               }
             ]
           } = data

    assert source_request_id == frame.meta.source_request_id
    assert "mission" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "mission_dashboards" in data.source_status.scope_ids
  end

  test "golden stale operational data table fixture carries stale public row projection" do
    document = load_fixture!("stale_operational_data_table.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_command_queue_data_table" => %{width_px: 640}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "mission", mode: "one", ids: ["mission_dashboards"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["commanding.queue_depth"],
               sampling_mode: :latest,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_bitrate,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: stale_operational_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard}] =
             result.dashboard_warnings

    assert %{
             "placement_command_queue_data_table" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :command_queue_depth,
                       product_family: :commanding,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z],
                       data_source_id: "managed_operational_observables",
                       source_binding_id: "default_flight_operational_observables"
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_command_queue_data_table"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["commanding.queue_depth"]
    assert field_values(frame, "resource_id") == ["mission_dashboards"]
    assert field_values(frame, "label") == ["Pending commands"]
    assert field_values(frame, "scope_kind") == [:mission]
    assert field_values(frame, "value") == [0]
    assert field_values(frame, "unit") == ["commands"]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :stale,
             stale?: true,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data],
               reason_codes: [:stale, :stale_data]
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               time_modes: ["live"],
               time_axes: ["generation_time"]
             },
             data_management: %{
               warning_codes: ["stale_data"],
               badges: [],
               data_views: []
             },
             rows: [
               %{
                 observable_id: "commanding.queue_depth:mission_dashboards",
                 frame_observable_id: "commanding.queue_depth",
                 label: "Pending commands",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 product_family: :commanding,
                 source_request_id: source_request_id,
                 logical_source: :operational_observables,
                 realm: "flight",
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 resource_id: "mission_dashboards",
                 scope_kind: :mission,
                 unit: "commands",
                 value: 0,
                 normalized_state: :observed,
                 links: [],
                 data_management: %{
                   warning_codes: ["stale_data"],
                   badges: [],
                   data_view: nil
                 },
                 stale?: true
               }
             ]
           } = data

    assert source_request_id == frame.meta.source_request_id
    assert "mission" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "mission_dashboards" in data.source_status.scope_ids
  end

  test "golden stale source-endpoint command queue data table preserves scoped row link" do
    document = load_fixture!("stale_operational_data_table.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_command_queue_data_table" => %{width_px: 640}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: stale_source_endpoint_command_queue_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard}] =
             result.dashboard_warnings

    assert %{
             "placement_command_queue_data_table" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :command_queue_depth,
                       product_family: :commanding,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z],
                       data_source_id: "managed_operational_observables",
                       source_binding_id: "default_flight_operational_observables"
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_command_queue_data_table"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["commanding.queue_depth"]
    assert field_values(frame, "resource_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "label") == ["source endpoint / source-endpoint-golden-1"]
    assert field_values(frame, "scope_kind") == [:source_endpoint]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "value") == [1]
    assert field_values(frame, "unit") == ["commands"]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             lifecycle_state: :stale,
             stale?: true,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data]
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"]
             },
             rows: [
               %{
                 observable_id: "commanding.queue_depth:source-endpoint-golden-1",
                 frame_observable_id: "commanding.queue_depth",
                 label: "source endpoint / source-endpoint-golden-1",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 product_family: :commanding,
                 logical_source: :operational_observables,
                 realm: "flight",
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 resource_id: "source-endpoint-golden-1",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "source-endpoint-golden-1",
                 unit: "commands",
                 value: 1,
                 normalized_state: :observed,
                 data_management: %{
                   warning_codes: ["stale_data"],
                   badges: [],
                   data_view: nil
                 },
                 stale?: true
               } = row
             ]
           } = data

    assert Enum.any?(
             row.links,
             &(&1.target == :source_endpoint and &1.target_id == "source-endpoint-golden-1")
           )

    assert "source_endpoint" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "source-endpoint-golden-1" in data.source_status.scope_ids
  end

  test "golden operational data table fixture fails closed when command queue reader fails" do
    document = load_fixture!("stale_operational_data_table.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_command_queue_data_table" => %{width_px: 640}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "mission", mode: "one", ids: ["mission_dashboards"]}
      })

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_result_cache?: false,
          source_opts: failing_command_queue_source_opts(),
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.returned_frame_count == 0

    assert [%ResolveWarning{code: :source_unavailable, severity: :error} = warning] =
             result.dashboard_warnings

    assert warning.details.logical_source == :operational_observables
    assert warning.details.data_source_id == "managed_operational_observables"
    assert warning.details.source_binding_id == "default_flight_operational_observables"
    assert warning.details.reason =~ "test command queue failure"
    assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
    assert link_targets(warning) == [:telemetry_point]

    assert %{
             "placement_command_queue_data_table" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :source_unavailable,
                     severity: :error,
                     scope: :placement,
                     placement_id: "placement_command_queue_data_table"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :error,
             lifecycle: %{
               state: :error,
               severity: :error,
               warning_codes: [:source_unavailable]
             },
             source_status: %{
               state: :unavailable,
               severity: :error,
               data_state: :no_data,
               warning_codes: [:source_unavailable],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"]
             },
             rows: []
           } = data
  end

  test "golden stale operational ingress latency data table preserves source endpoint projection" do
    document = load_fixture!("stale_operational_ingress_latency_data_table.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_ingress_latency_data_table" => %{width_px: 640}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["ingress.processing_latency_ms"],
               sampling_mode: :latest,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_bitrate,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: stale_operational_ingress_latency_source_opts(parent),
          source_result_cache?: false,
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert_received {:ingress_latency_snapshots_opts, snapshot_opts}

    assert Keyword.fetch!(snapshot_opts, :data_source_id) == "managed_operational_observables"

    assert Keyword.fetch!(snapshot_opts, :source_binding_id) ==
             "default_flight_operational_observables"

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard}] =
             result.dashboard_warnings

    assert %{
             "placement_ingress_latency_data_table" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :ingress_processing_latency,
                       product_family: :runtime_ingress,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z],
                       data_source_id: "managed_operational_observables",
                       source_binding_id: "default_flight_operational_observables"
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_ingress_latency_data_table"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["ingress.processing_latency_ms"]
    assert field_values(frame, "resource_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "label") == ["Ingress latency / source-endpoint-golden-1"]
    assert field_values(frame, "scope_kind") == [:source_endpoint]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "spacecraft_id") == ["sc-golden-alpha"]
    assert field_values(frame, "value") == [42.25]
    assert field_values(frame, "unit") == ["ms"]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :stale,
             stale?: true,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data],
               reason_codes: [:stale, :stale_data]
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               time_modes: ["live"],
               time_axes: ["generation_time"]
             },
             data_management: %{
               warning_codes: ["stale_data"],
               badges: [],
               data_views: []
             },
             rows: [
               %{
                 observable_id: "ingress.processing_latency_ms:source-endpoint-golden-1",
                 frame_observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / source-endpoint-golden-1",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 product_family: :runtime_ingress,
                 source_request_id: source_request_id,
                 logical_source: :operational_observables,
                 realm: "flight",
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 resource_id: "source-endpoint-golden-1",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "source-endpoint-golden-1",
                 spacecraft_id: "sc-golden-alpha",
                 unit: "ms",
                 value: 42.25,
                 normalized_state: :observed,
                 links: [
                   %{
                     target: :source_endpoint,
                     target_id: "source-endpoint-golden-1"
                   }
                 ],
                 data_management: %{
                   warning_codes: ["stale_data"],
                   badges: [],
                   data_view: nil
                 },
                 stale?: true
               }
             ]
           } = data

    assert source_request_id == frame.meta.source_request_id
    assert "source_endpoint" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "source-endpoint-golden-1" in data.source_status.scope_ids
  end

  test "golden source unavailable fixture carries degraded source contract into presenter lifecycle" do
    document = load_fixture!("source_unavailable_value_tile.v1.json")
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_battery_voltage_unavailable" => %{width_px: 320, height_px: 128}
      })

    plan = Engine.plan(request, failing_telemetry_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest,
               products: [],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        failing_telemetry_source_registry_opts(
          source_circuit_breaker: breaker,
          source_circuit_failure_threshold: 2,
          source_opts: %{telemetry: [test_pid: self(), mode: :raise]},
          validate_dashboard_contract?: true
        )
      )

    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 0

    assert %{status_counts: %{source_unavailable: 1}, outcomes: [outcome], degraded?: true} =
             SourceExecutionSemantics.summarize(result)

    assert outcome.actionable?
    assert outcome.retryable?
    assert outcome.operator_action == :inspect_source_health
    assert outcome.runtime_action == :wait_for_source_health
    assert outcome.warning_codes == [:source_unavailable]

    assert [%ResolveWarning{code: :source_unavailable, severity: :error} = warning] =
             result.dashboard_warnings

    assert warning.details.reason == "test source failure"
    assert warning.details.logical_source == :telemetry
    assert warning.details.data_source_id == "flight-questdb"
    assert warning.details.source_binding_id == "flight-telemetry"
    assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
    assert link_targets(warning) == [:telemetry_point]

    assert_link_runtime_context(link_by_target(warning, :telemetry_point),
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "flight-questdb",
      source_binding_id: "flight-telemetry"
    )

    assert %{
             "placement_battery_voltage_unavailable" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :source_unavailable,
                     severity: :error,
                     scope: :placement,
                     placement_id: "placement_battery_voltage_unavailable"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.unresolved? == false
    assert data.engine_backed?
    assert data.lifecycle_state == :error
    assert data.lifecycle.warning_codes == [:source_unavailable]

    assert %{
             state: :unavailable,
             severity: :error,
             data_state: :no_data,
             warning_codes: [:source_unavailable],
             logical_sources: [:telemetry],
             data_source_ids: ["flight-questdb"],
             source_binding_ids: ["flight-telemetry"],
             realms: [:flight],
             time_modes: ["live"],
             time_axes: ["generation_time"]
           } = data.source_status
  end

  test "golden no-data fixture carries healthy empty source contract into presenter lifecycle" do
    document = load_fixture!("no_data_value_tile.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_battery_voltage_no_data" => %{width_px: 320, height_px: 128}
      })

    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest,
               products: [],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: no_data_source_opts()
        )
      )

    refute result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1
    assert result.dashboard_warnings == []

    assert %{
             "placement_battery_voltage_no_data" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :telemetry, shape: :scalar, meta: meta} = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "tlm.hk.battery_voltage") == []
    assert field_values(frame, "time") == []
    assert meta.returned_points == 0
    assert meta.data_source_id == "managed_questdb_primary"
    assert meta.source_binding_id == "default_flight_telemetry"
    assert meta.warning_codes == []
    assert source_watermark_confidences(frame) == [:best_effort]
    assert source_watermark_freshness_states(frame) == [:fresh]
    assert link_targets(frame) == [:telemetry_point]

    telemetry_point_link = link_by_target(frame, :telemetry_point)

    assert_link_runtime_context(telemetry_point_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry",
      source_request_id: frame.meta.source_request_id
    )

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, warning_codes: []},
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               warning_codes: [],
               logical_sources: [:telemetry],
               data_source_ids: ["managed_questdb_primary"],
               source_binding_ids: ["default_flight_telemetry"],
               time_modes: ["live"],
               time_axes: ["generation_time"],
               scope_kinds: ["spacecraft"],
               scope_ids: ["sc_001"],
               empty_reason: :scope_no_data
             }
           } = data

    assert :flight in data.source_status.realms
    assert "flight" in data.source_status.realms
    assert [%{confidence: :best_effort, freshness_state: :fresh}] = data.source_status.watermarks
  end

  test "golden data-management fixture carries revision view into presenter lifecycle" do
    document = load_fixture!("data_management_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_revision_counter" => %{width_px: 320, height_px: 128}})
      |> Map.put(:data_context, %{realm: :flight, view: :all_revisions})

    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.revision_counter"],
               sampling_mode: :latest,
               products: [],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: data_management_source_opts(parent)
        )
      )

    assert_received {:golden_identity_states, ["identity-golden-revision"], lookup_opts}
    assert lookup_opts[:organization_id] == "org_dashboards"
    assert lookup_opts[:mission_id] == "mission_dashboards"
    assert lookup_opts[:realm] == :flight
    assert lookup_opts[:data_source_id] == "managed_questdb_primary"

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert %{
             "placement_revision_counter" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :telemetry,
                     shape: :scalar,
                     meta: %{
                       data_view: :all_revisions,
                       warning_codes: warning_codes,
                       revision_state: revision_state,
                       telemetry_revision_dependency: dependency
                     }
                   } = frame
                 ],
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert Enum.sort(warning_codes) == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert revision_state.identity_count == 1
    assert revision_state.superseded_count == 1
    assert revision_state.advisory_count == 1
    assert revision_state.has_superseded?
    assert revision_state.has_advisory?
    assert dependency.observation_identity_ids == ["identity-golden-revision"]

    assert Enum.map(placement_warnings, & &1.code) |> Enum.sort() == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert field_values(frame, "tlm.hk.revision_counter") == [7]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :partial,
             lifecycle: %{
               state: :partial,
               severity: :warning,
               warning_codes: lifecycle_warnings
             },
             data_management: %{
               data_view: "all_revisions",
               warning_codes: data_management_warning_codes,
               badges: badges
             },
             sample: %{
               sample_id: "sample-golden-revision",
               engineering_value: 7
             }
           } = data

    assert Enum.sort(lifecycle_warnings) == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert Enum.sort(data_management_warning_codes) == [
             "advisory_backfill",
             "all_revisions_view",
             "corrected_range",
             "mixed_revisions"
           ]

    assert Enum.map(badges, &{&1.kind, &1.value, &1.code}) == [
             {:data_view, "all_revisions", "all_revisions_view"},
             {:revision_state, "corrected", "corrected_range"},
             {:revision_state, "backfill", "advisory_backfill"},
             {:revision_state, "mixed", "mixed_revisions"}
           ]
  end

  test "golden data-management fixture carries data-view comparison into render model" do
    document = load_fixture!("data_management_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    primary_request =
      document
      |> resolve_request(%{"placement_revision_counter" => %{width_px: 320, height_px: 128}})
      |> Map.put(:data_context, %{realm: :flight, view: :all_revisions})

    compare_request = %{
      primary_request
      | data_context: %{realm: :flight, view: :canonical}
    }

    primary_result =
      Engine.resolve(
        primary_request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: data_management_source_opts(parent)
        )
      )

    compare_result =
      Engine.resolve(
        compare_request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: comparison_source_opts()
        )
      )

    assert_received {:golden_identity_states, ["identity-golden-revision"], _lookup_opts}

    assert primary_result.plan_metadata.degraded?
    refute compare_result.plan_metadata.degraded?
    assert compare_result.dashboard_warnings == []

    assert %{
             "placement_revision_counter" => %PlacementFrames{primary: [%Frame{} = primary_frame]}
           } = primary_result.frames_by_placement

    assert %{
             "placement_revision_counter" => %PlacementFrames{primary: [%Frame{} = compare_frame]}
           } = compare_result.frames_by_placement

    assert primary_frame.meta.data_view == :all_revisions
    assert compare_frame.meta.data_view == :canonical
    assert field_values(primary_frame, "tlm.hk.revision_counter") == [7]
    assert field_values(compare_frame, "tlm.hk.revision_counter") == [5]

    model =
      document
      |> comparison_render_assigns(primary_result, compare_result)
      |> RenderPageModel.build()

    assert [widget_item] = model.widget_items
    assert widget_item.item.placement_id == "placement_revision_counter"
    assert widget_item.props.data.sample.sample_id == "sample-golden-revision"
    assert widget_item.props.data.sample.engineering_value == 7
    assert widget_item.props.compare_data.sample.sample_id == "sample-golden-canonical"
    assert widget_item.props.compare_data.sample.engineering_value == 5

    assert %{
             state: "increased",
             label: "Canonical +2",
             title: "All revisions compared with Canonical: +2 from 5",
             primary_view: "all_revisions",
             compare_view: "canonical",
             primary_count: 1,
             compare_count: 1,
             delta: "+2",
             primary_sample_id: "sample-golden-revision",
             compare_sample_id: "sample-golden-canonical",
             primary_data_link: primary_link,
             compare_data_link: compare_link
           } = widget_item.props.comparison_summary

    assert primary_link.target == :telemetry_sample
    assert primary_link.target_id == "sample-golden-revision"
    assert compare_link.target == :telemetry_sample
    assert compare_link.target_id == "sample-golden-canonical"

    assert model.root_attrs["data-dashboard-comparison-widgets"] == 1
    assert model.root_attrs["data-dashboard-comparison-deltas"] == 1
    assert model.root_attrs["data-dashboard-comparison-missing"] == 0
    assert model.root_attrs["data-dashboard-comparison-states"] == "increased"

    assert model.root_attrs["data-dashboard-comparison-delta-placements"] ==
             "placement_revision_counter"

    assert model.comparison_rollup.visible?
    assert model.comparison_rollup.delta_count == 1
    assert model.comparison_rollup.missing_count == 0

    assert [
             %{
               key: "deltas",
               placement_ids: "placement_revision_counter",
               items: [
                 %{
                   placement_id: "placement_revision_counter",
                   title: "Revision Counter",
                   state: "increased",
                   label: "Canonical +2",
                   delta: "+2",
                   primary_sample_id: "sample-golden-revision",
                   compare_sample_id: "sample-golden-canonical"
                 }
               ]
             }
           ] = model.comparison_rollup.groups

    assert model.comparison_preset["schema"] == "dashboard_comparison_investigation_preset.v1"
    assert model.comparison_preset["dashboard_id"] == "dashboard_data_management_value_tile"
    assert model.comparison_preset["mission_id"] == "mission_dashboards"

    assert model.comparison_preset["runtime_query"] == %{
             "compare_data_view" => "canonical",
             "data_source_id" => "managed_questdb_primary",
             "data_view" => "all_revisions",
             "source_binding_id" => "default_flight_telemetry",
             "spacecraft_id" => "sc_001"
           }

    assert model.comparison_preset["comparison"] == %{
             "primary_data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "widget_count" => 1,
             "delta_count" => 1,
             "unchanged_count" => 0,
             "coverage_count" => 0,
             "missing_count" => 0,
             "handled_count" => 0,
             "open_count" => 1,
             "unhandled_count" => 1,
             "states" => "increased"
           }

    assert [
             %{
               "key" => "deltas",
               "placement_ids" => ["placement_revision_counter"],
               "items" => [
                 %{
                   "placement_id" => "placement_revision_counter",
                   "state" => "increased",
                   "label" => "Canonical +2",
                   "delta" => "+2",
                   "primary_sample_id" => "sample-golden-revision",
                   "compare_sample_id" => "sample-golden-canonical",
                   "primary_data_link" => %{
                     "target" => "telemetry_sample",
                     "target_id" => "sample-golden-revision"
                   },
                   "compare_data_link" => %{
                     "target" => "telemetry_sample",
                     "target_id" => "sample-golden-canonical"
                   }
                 }
               ]
             }
           ] = model.comparison_preset["groups"]
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes \\ nil) do
    placement_sizes =
      placement_sizes ||
        %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}

    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp comparison_render_assigns(%Document{} = document, primary_result, compare_result) do
    %{
      current_scope: %{organization_id: document.organization_id},
      current_mission: %{mission_id: document.mission_id},
      dashboard_document: document,
      dashboard_data_realms: ["flight"],
      dashboard_data_bindings: [
        DataSources.default_flight_telemetry_binding()
      ],
      dashboard_render_items: RenderItem.from_document(document),
      dashboard_engine_result: primary_result,
      dashboard_compare_engine_result: compare_result,
      dashboard_engine_frames_by_placement: primary_result.frames_by_placement,
      dashboard_compare_engine_frames_by_placement: compare_result.frames_by_placement,
      dashboard_selected_data_ref: nil,
      dashboard_selection_query: nil,
      dashboard_evidence_query: nil,
      dashboard_compare_data_view: "canonical",
      dashboard_time_mode: "live",
      dashboard_time_from: nil,
      dashboard_time_to: nil,
      dashboard_replay_run_id: nil,
      dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
      dashboard_data_realm: "flight",
      dashboard_data_view: "all_revisions",
      dashboard_data_source_id: "managed_questdb_primary",
      dashboard_source_binding_id: "default_flight_telemetry",
      dashboard_limit_mode: "observed",
      dashboard_limit_mode_fallback: nil,
      dashboard_selection_state: "none",
      dashboard_time_validation: "ok",
      dashboard_runtime_resolved?: true,
      dashboard_runtime_coordinator: nil,
      dashboard_runtime_decisions: [],
      dashboard_last_runtime_invalidation: nil,
      dashboard_document_mode: "published",
      dashboard_lifecycle_status: nil,
      dashboard_summary: nil,
      dashboard_versions: [],
      dashboard_lifecycle_events: [],
      dashboard_investigation_presets: [],
      dashboard_publish_validation: nil,
      dashboard_comparison_decision_events: [],
      panel: nil,
      context_scope_kind: "spacecraft",
      context_scope_id: "sc_001",
      context_spacecraft_id: "sc_001",
      points: [],
      points_by_id: %{},
      operational_observables: [],
      selected_point_id: nil,
      selected_point_ids: [],
      widget_data: %{},
      backfills: %{},
      widget_error: nil,
      widget_form: nil,
      historical_workflow_request_form: nil,
      spacecraft: [],
      context_query: ""
    }
  end

  defp source_registry_opts(opts) do
    Keyword.merge(
      [
        data_sources: [
          DataSources.default_managed_data_source(),
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_telemetry_binding(),
          DataSources.default_flight_limits_binding()
        ]
      ],
      opts
    )
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

  defp event_source_registry_opts(opts) do
    Keyword.merge(
      [
        data_sources: [
          DataSources.default_events_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_events_binding()
        ]
      ],
      opts
    )
  end

  defp replay_source_registry_opts(opts \\ []) do
    replay_telemetry_source = %DataSource{
      DataSources.default_managed_data_source()
      | data_source_id: "replay-questdb",
        capabilities:
          DataSources.default_managed_data_source().capabilities
          |> Map.put(:range_scan?, true)
    }

    replay_telemetry_binding = %DataBinding{
      DataSources.default_flight_telemetry_binding()
      | binding_id: "replay_flight_telemetry",
        realm: :replay,
        data_source_id: "replay-questdb",
        dataset: "replay_run_001"
    }

    replay_limits_binding = %DataBinding{
      DataSources.default_flight_limits_binding()
      | binding_id: "replay_limits",
        realm: :replay
    }

    Keyword.merge(
      [
        data_sources: [
          replay_telemetry_source,
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          replay_telemetry_binding,
          replay_limits_binding
        ]
      ],
      opts
    )
  end

  defp operational_source_registry_opts(opts \\ []) do
    Keyword.merge(
      [
        source_health_events?: false,
        source_watermark_events?: false,
        data_sources: [
          DataSources.default_operational_observables_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_operational_observables_binding()
        ]
      ],
      opts
    )
  end

  defp failing_telemetry_source_registry_opts(opts \\ []) do
    Keyword.merge(
      [
        source_result_cache?: false,
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [test_telemetry_binding("flight-questdb")]
      ],
      opts
    )
  end

  defp source_opts do
    %{
      telemetry: [
        latest_fun: &telemetry_sample/4,
        watermark_fun: &best_effort_watermark/4
      ],
      limits: [
        latest_fun: &limit_event/4,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp no_data_source_opts do
    %{
      telemetry: [
        latest_fun: fn _organization_id, _mission_id, _point_id, _opts -> nil end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp event_timeline_source_opts(parent) do
    %{
      events: [
        scheduled_contacts_fun: &empty_events/3,
        realized_contacts_fun: &empty_events/3,
        mission_events_fun: &empty_events/3,
        source_health_events_fun: &empty_events/3,
        source_watermark_events_fun: &empty_events/3,
        source_capability_posture_events_fun: fn organization_id, mission_id, opts ->
          send(
            parent,
            {:source_capability_posture_events_called, organization_id, mission_id, opts}
          )

          [
            Cadence.OperationalEvents.Event.from_source_capability_posture(%{
              organization_id: organization_id,
              mission_id: mission_id,
              source_capability_posture_id: "dashboard-golden:resolve-golden:events-request-1",
              dashboard_id: "dashboard-golden",
              dashboard_version: 7,
              resolve_id: "resolve-golden",
              source_request_id: "events-request-1",
              logical_source: :events,
              data_source_id: "managed_events_projection",
              source_binding_id: "default_flight_events",
              realm: :flight,
              dataset: "mission_events",
              status: :fallback,
              requested_sampling: :event_history,
              supported_sampling: [:event_history],
              requested_products: [:source_capability_postures],
              supported_products: [:source_capability_postures],
              requested_time_axis: :generation_time,
              executed_time_axis: :occurred_at,
              supported_time_axes: [:occurred_at],
              fallbacks: [:occurred_at_axis],
              unsupported: [:generation_time_axis],
              source_execution_status: :resolved,
              source_execution_cache_status: :miss,
              source_execution_operator_action: :inspect_source_capability,
              source_execution_runtime_action: :use_occurred_at_axis,
              source_execution_warning_codes: [:unsupported_source_capability],
              observed_at: ~U[2026-06-17 12:01:00Z]
            })
          ]
        end,
        telemetry_backfill_lifecycle_events_fun: fn organization_id, mission_id, opts ->
          send(parent, {:backfill_lifecycle_events_called, organization_id, mission_id, opts})

          [
            BackfillLifecycleEvent.new(%{
              backfill_lifecycle_event_id: "backfill-event-golden-started-dispatch-failed",
              backfill_run_id: "backfill-run-golden-started",
              organization_id: organization_id,
              mission_id: mission_id,
              realm: :flight,
              data_source_id: "managed_questdb_primary",
              binding_id: "default_flight_telemetry",
              observable_id: "tlm.hk.battery_voltage",
              point_id: "tlm.hk.battery_voltage",
              spacecraft_id: "sc_001",
              event_type: :backfill_started,
              source_from: ~U[2026-06-17 11:00:00Z],
              source_to: ~U[2026-06-17 11:30:00Z],
              receipt_from: ~U[2026-06-17 11:00:00Z],
              receipt_to: ~U[2026-06-17 11:30:00Z],
              sample_count: 42,
              authority: :authoritative,
              reason: :operator_requested,
              actor_id: "user-golden-1",
              actor_kind: :user,
              occurred_at: ~U[2026-06-17 12:00:00Z],
              payload: %{
                "run_id" => "backfill-run-golden-started",
                "selected_sample_count" => 42,
                "projection_effect" => "latest_value_refresh",
                "write_validity_state" => "canonical",
                "record_current_values" => true,
                "refresh_latest_value" => true
              }
            })
          ]
        end,
        telemetry_backfill_workflow_job_fun: fn event ->
          send(parent, {:backfill_workflow_job_called, event.backfill_run_id})

          Job.new(%{
            job_id: "job-golden-started",
            mission_id: event.mission_id,
            job_type: :telemetry_historical_data_workflow,
            run_id: event.backfill_run_id,
            status: :failed,
            payload: %{"attrs" => %{"backfill_run_id" => event.backfill_run_id}},
            attempt_count: 1,
            failure_reason: :source_window_failed,
            started_at: ~U[2026-06-17 12:00:00Z],
            completed_at: ~U[2026-06-17 12:00:02Z]
          })
        end,
        telemetry_revision_decision_events_fun: &empty_events/3
      ]
    }
  end

  defp data_management_source_opts(parent) do
    %{
      telemetry: [
        latest_fun: &revision_telemetry_sample/4,
        identity_states_fun: fn identity_ids, lookup_opts ->
          send(parent, {:golden_identity_states, identity_ids, lookup_opts})

          [
            identity_state("identity-golden-revision",
              observable_id: "tlm.hk.revision_counter",
              point_id: "tlm.hk.revision_counter",
              superseded_count: 1,
              advisory_count: 1
            )
          ]
        end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp comparison_source_opts do
    %{
      telemetry: [
        latest_fun: &comparison_telemetry_sample/4,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp operational_source_opts(parent) do
    %{
      operational_observables: [
        contact_phase_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :contact_phase_revision_called)
          "contact-phase-golden-revision"
        end,
        connection_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :connection_state_revision_called)
          "connection-state-golden-revision"
        end,
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :scheduled_contacts_called)

          [
            %{
              scheduled_contact_id: "scheduled-contact-golden-1",
              realized_contact_id: nil,
              lifecycle_state: :scheduled,
              starts_at: ~U[2026-06-17 12:00:00Z],
              source_endpoint_refs: ["source-endpoint-golden-1"]
            }
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :realized_contacts_called)
          []
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transports_called)
          []
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :source_endpoints_called)

          [
            %{
              source_endpoint_id: "source-endpoint-golden-1",
              display_name: "Goldstone DSS-14",
              metadata: %{ground_station_id: "dss-14"}
            }
          ]
        end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :connection_snapshots_called)

          [
            %{
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:00:00Z]
            }
          ]
        end
      ]
    }
  end

  defp operational_metric_source_opts(parent, opts \\ []) do
    include_beta_snapshot? = not Keyword.get(opts, :missing_snapshot?, false)

    %{
      operational_observables: [
        transport_bitrate_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transport_bitrate_revision_called)
          "transport-bitrate-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :metric_transports_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha TCP",
              adapter_key: :tcp_socket,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta TCP",
              adapter_key: :tcp_socket,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transport_metric_snapshots_called)

          snapshots = [
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              downlink_bitrate: 12_500.5,
              uplink_bitrate: 4_800.0,
              unit: "bit/s",
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]

          if include_beta_snapshot? do
            snapshots ++
              [
                %{
                  transport_id: "transport-golden-beta",
                  source_endpoint_id: "source-endpoint-golden-2",
                  ground_station_id: "dss-63",
                  link_assignment_id: "link-golden-beta",
                  downlink_bitrate: 8_500.0,
                  unit: "bit/s",
                  observed_at: ~U[2026-06-17 12:04:00Z]
                }
              ]
          else
            snapshots
          end
        end
      ]
    }
  end

  defp operational_rf_metric_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_metric_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_revision_called)
          "link-rf-metric-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_metric_transports_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_snapshots_called)

          [
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:06:00Z]
            },
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              value: 9.25,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:06:30Z]
            }
          ]
        end
      ]
    }
  end

  defp operational_rf_metric_history_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_metric_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_history_revision_called)
          "link-rf-metric-history-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_metric_history_transports_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_history_snapshots_called)

          [
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              snr_db: 10.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-golden-beta",
              link_assignment_id: "link-golden-beta",
              adapter_key: :rf_adapter,
              snr_db: 7.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-golden-alpha",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              snr_db: 15.0,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end
      ]
    }
  end

  defp operational_ingress_latency_history_source_opts(parent) do
    %{
      operational_observables: [
        ingress_processing_latency_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :ingress_latency_history_revision_called)
          "ingress-latency-history-golden-revision"
        end,
        ingress_processing_latency_history_snapshots_fun: fn _organization_id,
                                                             _mission_id,
                                                             _opts ->
          send(parent, :ingress_latency_history_snapshots_called)

          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission_dashboards",
              source_endpoint_id: "source-endpoint-golden-1",
              spacecraft_id: "sc-golden-alpha",
              transport_id: "transport-golden-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :tcp_socket,
              value: 4.5,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission_dashboards",
              source_endpoint_id: "source-endpoint-golden-1",
              spacecraft_id: "sc-golden-alpha",
              transport_id: "transport-golden-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :tcp_socket,
              value: 5.25,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission_dashboards",
              source_endpoint_id: "source-endpoint-golden-2",
              spacecraft_id: "sc-golden-beta",
              value: 9.0,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission_dashboards",
              source_endpoint_id: "source-endpoint-golden-1",
              spacecraft_id: "sc-golden-alpha",
              value: 6.75,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end
      ]
    }
  end

  defp operational_rf_metric_history_no_data_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_metric_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_history_revision_called)
          "link-rf-metric-history-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_metric_history_transports_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_history_snapshots_called)
          []
        end
      ]
    }
  end

  defp operational_transport_execution_timeline_source_opts(parent) do
    %{
      operational_observables: [
        transport_execution_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transport_execution_revision_called)
          "transport-execution-golden-revision"
        end,
        transport_execution_intervals_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:transport_execution_intervals_opts, opts})

          [
            transport_execution_interval(
              "transport-execution-interval-golden-alpha-1",
              "transport-golden-alpha",
              :initialized,
              ~U[2026-06-17 12:00:10Z],
              ~U[2026-06-17 12:01:30Z],
              source_event_id: "transport-execution-event-golden-alpha-1"
            ),
            transport_execution_interval(
              "transport-execution-interval-golden-alpha-2",
              "transport-golden-alpha",
              :transport_event_handled,
              ~U[2026-06-17 12:01:30Z],
              ~U[2026-06-17 12:03:30Z],
              source_event_id: "transport-execution-event-golden-alpha-2",
              transport_record_id: "transport-record-golden-alpha-2"
            ),
            transport_execution_interval(
              "transport-execution-interval-golden-beta-1",
              "transport-golden-beta",
              :timer_handled,
              ~U[2026-06-17 12:02:00Z],
              ~U[2026-06-17 12:03:00Z],
              contact_id: "contact-golden-beta",
              path_id: "uplink-golden-beta",
              source_event_id: "transport-execution-event-golden-beta-1"
            )
          ]
        end
      ]
    }
  end

  defp transport_execution_interval(
         interval_id,
         transport_id,
         event_kind,
         starts_at,
         ends_at,
         opts
       ) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: transport_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: Keyword.fetch!(opts, :source_event_id),
      payload: %{
        "capability_instance_id" => transport_id,
        "transport_record_id" =>
          Keyword.get(opts, :transport_record_id, "transport-record-#{interval_id}"),
        "contact_id" => Keyword.get(opts, :contact_id, "contact-golden-alpha"),
        "path_id" => Keyword.get(opts, :path_id, "uplink-golden-alpha"),
        "event_kind" => Atom.to_string(event_kind)
      }
    }
  end

  defp operational_rf_state_timeline_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_lock_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_state_lock_revision_called)
          "link-rf-lock-state-golden-revision"
        end,
        link_rf_frame_sync_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_state_frame_sync_revision_called)
          "link-rf-frame-sync-state-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:rf_state_transports_opts, opts})

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:rf_state_lock_snapshots_opts, opts})

          [
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              lock_state: :acquiring,
              observed_at: ~U[2026-06-17 12:00:30Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              transport_id: "transport-golden-beta",
              source_endpoint_id: "source-endpoint-golden-2",
              ground_station_id: "dss-63",
              link_assignment_id: "link-golden-beta",
              adapter_key: :rf_adapter,
              lock_state: :unlocked,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              lock_state: :degraded,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:rf_state_frame_sync_snapshots_opts, opts})

          [
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :acquiring,
              observed_at: ~U[2026-06-17 12:00:45Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-golden-beta",
              source_endpoint_id: "source-endpoint-golden-2",
              ground_station_id: "dss-63",
              link_assignment_id: "link-golden-beta",
              adapter_key: :rf_adapter,
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]
        end
      ]
    }
  end

  defp stale_operational_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
        read_time: ~U[2026-06-17 12:05:00Z]
      ]
    }
  end

  defp stale_source_endpoint_command_queue_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              command_queue_entry_id: "queue-golden-alpha",
              source_endpoint_ref: "source-endpoint-golden-1",
              queue_lane_key: "source-endpoint-golden-1",
              lifecycle_state: :pending
            },
            %{
              command_queue_entry_id: "queue-golden-beta",
              source_endpoint_ref: "source-endpoint-golden-2",
              queue_lane_key: "source-endpoint-golden-2",
              lifecycle_state: :pending
            }
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z]
      ]
    }
  end

  defp failing_command_queue_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          raise "test command queue failure"
        end
      ]
    }
  end

  defp stale_operational_ingress_latency_source_opts(parent) do
    %{
      operational_observables: [
        ingress_processing_latency_revision_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:ingress_latency_revision_opts, opts})
          "ingress-latency-golden-revision"
        end,
        ingress_processing_latency_snapshots_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:ingress_latency_snapshots_opts, opts})

          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission_dashboards",
              source_endpoint_id: "source-endpoint-golden-1",
              spacecraft_id: "sc-golden-alpha",
              value: 42.25,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:05:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission_dashboards",
              source_endpoint_id: "source-endpoint-golden-2",
              spacecraft_id: "sc-golden-beta",
              value: 11.0,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end
      ]
    }
  end

  defp time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: &best_effort_watermark/4
      ],
      limits: [
        history_fun: &limit_history_events/4,
        interval_fun: &limit_definition_intervals/4,
        watermark_fun: &best_effort_watermark/4
      ],
      events: [
        scheduled_contacts_fun: &empty_events/3,
        realized_contacts_fun: &empty_events/3,
        mission_events_fun: &mission_events/3,
        source_health_events_fun: &empty_events/3,
        source_watermark_events_fun: &empty_events/3,
        source_capability_posture_events_fun: &empty_events/3,
        telemetry_backfill_lifecycle_events_fun: &empty_events/3,
        telemetry_revision_decision_events_fun: &empty_events/3
      ]
    }
  end

  defp no_data_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: fn _organization_id, _mission_id, _point_id, _opts -> [] end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp contact_no_data_time_series_source_opts(parent) do
    %{
      telemetry: [
        decimated_history_fun: fn _organization_id, _mission_id, point_id, opts ->
          send(parent, {:contact_decimated_history_opts, point_id, opts})
          []
        end,
        watermark_fun: &best_effort_watermark/4,
        fetch_scheduled_contact: fn "org_dashboards",
                                    "mission_dashboards",
                                    "scheduled-contact-golden-1" ->
          {:ok,
           %{
             scheduled_contact_id: "scheduled-contact-golden-1",
             source_endpoint_refs: ["source-endpoint-golden-1"]
           }}
        end
      ]
    }
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

  defp partial_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: fn
          _organization_id, _mission_id, "tlm.hk.bus_current", _opts ->
            []

          organization_id, mission_id, point_id, opts ->
            decimated_history_buckets(organization_id, mission_id, point_id, opts)
        end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp source_unavailable_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: fn _organization_id, _mission_id, _point_id, _opts ->
          {:error, :test_decimated_history_failure}
        end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp stale_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: &stale_best_effort_watermark/4
      ]
    }
  end

  defp retention_gap_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: &retention_gap_best_effort_watermark/4
      ]
    }
  end

  defp unknown_watermark_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: fn _organization_id, _mission_id, _point_id, _opts ->
          {:error, :test_watermark_failure}
        end
      ]
    }
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

  defp replay_source_opts do
    %{
      telemetry: [
        history_fun: &replay_history_samples/4,
        watermark_fun: &best_effort_watermark/4
      ],
      limits: [
        history_fun: &limit_history_events/4,
        interval_fun: &limit_definition_intervals/4,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  defp test_telemetry_binding(data_source_id) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: "flight"
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

  defp limit_history_events(_organization_id, mission_id, point_id, _opts) do
    [limit_event(mission_id, point_id)]
  end

  defp limit_definition_intervals(_organization_id, mission_id, point_id, _opts) do
    [limit_definition_interval(mission_id, point_id)]
  end

  defp empty_events(_organization_id, _mission_id, _opts), do: []

  defp mission_events(_organization_id, mission_id, _opts) do
    [
      Entry.new(%{
        mission_event_id: "mission-event-golden-1",
        mission_id: mission_id,
        occurred_at: ~U[2026-06-16 00:03:00Z],
        category: :health,
        kind: :limit_violation,
        severity: :warning,
        title: "Battery voltage yellow high",
        source_record_kind: :limit_event,
        source_record_id: "limit-event-golden-tlm-hk-battery-voltage",
        subject_kind: :telemetry_point,
        subject_id: "tlm.hk.battery_voltage",
        spacecraft_id: "sc_001"
      })
    ]
  end

  defp telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-golden-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-golden-1",
      raw_value: 12.25,
      engineering_value: 12.25,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp revision_telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-golden-revision",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-golden-revision",
      raw_value: 7,
      engineering_value: 7,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: storage_provenance("identity-golden-revision")
    }
  end

  defp comparison_telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-golden-canonical",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-golden-canonical",
      raw_value: 5,
      engineering_value: 5,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp replay_history_samples(_organization_id, mission_id, point_id, _opts) do
    [
      %Sample{
        sample_id: "sample-replay-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        packet_definition_id: "packet-def-1",
        packet_definition_version: 1,
        packet_id: "packet-1",
        evidence_id: "evidence-replay-1",
        raw_value: 7,
        engineering_value: 7,
        quality_state: :good,
        generation_time: ~U[2026-06-16 00:00:00Z],
        receipt_time: ~U[2026-06-16 00:00:00Z],
        provenance: %{}
      }
    ]
  end

  defp limit_event(_organization_id, mission_id, point_id, _opts) do
    limit_event(mission_id, point_id)
  end

  defp limit_event(mission_id, point_id) do
    stable_point_id = stable_point_id(point_id)

    %Event{
      limit_event_id: "limit-event-golden-#{stable_point_id}",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-golden-1",
      limit_definition_id: "limit-def-golden-#{stable_point_id}",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 12.25,
      limit_state: :yellow_high,
      normalized_state: :yellow,
      violation: true,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp limit_definition_interval(mission_id, point_id) do
    stable_point_id = stable_point_id(point_id)

    %DefinitionInterval{
      definition_activation_key: "limit-activation-golden-#{stable_point_id}",
      limit_definition_lifecycle_event_id: "limit-lifecycle-golden-#{stable_point_id}",
      organization_id: "org_dashboards",
      mission_id: mission_id,
      point_id: point_id,
      limit_set_name: "ops",
      event_type: :registered,
      limit_definition_id: "limit-def-golden-#{stable_point_id}",
      limit_definition_version: 3,
      active_from: ~U[2026-06-16 00:00:00Z],
      active_to: ~U[2026-06-16 00:30:00Z],
      observed_at: ~U[2026-06-16 00:00:00Z],
      thresholds: %{"yellow_high" => 15, "red_high" => 25},
      metadata: %{},
      complete?: true
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

  defp retention_gap_best_effort_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:30:00Z],
       latest_receipt_time: ~U[2026-06-16 00:30:00Z],
       retention_starts_at: ~U[2026-06-16 00:10:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  defp storage_provenance(observation_identity_id) do
    %{
      "storage" => %{
        "observation_identity_id" => observation_identity_id,
        "observation_id" => "observation-#{observation_identity_id}",
        "validity_state" => "canonical"
      }
    }
  end

  defp identity_state(observation_identity_id, overrides) do
    attrs =
      [
        observation_identity_id: observation_identity_id,
        organization_id: "org_dashboards",
        mission_id: "mission_dashboards",
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        observable_id: "tlm.hk.revision_counter",
        point_id: "tlm.hk.revision_counter",
        spacecraft_id: "sc_001",
        canonical_observation_id: "observation-#{observation_identity_id}",
        canonical_sample_id: "sample-#{observation_identity_id}",
        canonical_revision: 1,
        latest_observation_id: "observation-#{observation_identity_id}",
        latest_sample_id: "sample-#{observation_identity_id}",
        latest_revision: 2,
        validity_state: :canonical,
        canonical_count: 1,
        duplicate_count: 0,
        conflict_count: 0,
        superseded_count: 0,
        advisory_count: 0,
        first_seen_at: ~U[2026-06-17 12:00:00Z],
        last_seen_at: ~U[2026-06-17 12:00:00Z],
        payload: %{}
      ]
      |> Keyword.merge(overrides)

    struct!(ObservationIdentityState, attrs)
  end

  defp request_summary(request) do
    %{
      logical_source: request.logical_source,
      observables: request.observables,
      sampling_mode: request.sampling.mode,
      products: Map.get(request.sampling, :products, []),
      overlays: request.overlays,
      target_points: Map.get(request.sampling, :target_points),
      time_axis: request.time_context.axis,
      data_source_id: request.metadata.capability_provenance.data_source_id,
      source_binding_id: request.metadata.capability_provenance.binding_id
    }
  end

  defp request_by_source(requests, source) do
    Enum.find(requests, &(&1.logical_source == source))
  end

  defp request_sort_key(%{
         logical_source: source,
         sampling_mode: sampling_mode,
         products: products
       }) do
    {source_sort_key(source), sampling_sort_key(sampling_mode), Enum.map(products, &to_string/1)}
  end

  defp source_sort_key(:telemetry), do: 0
  defp source_sort_key(:limits), do: 1
  defp source_sort_key(:events), do: 2
  defp source_sort_key(source), do: to_string(source)

  defp sampling_sort_key(:latest), do: 0
  defp sampling_sort_key(:decimated_envelope), do: 1
  defp sampling_sort_key(:latest_state), do: 2
  defp sampling_sort_key(:event_history), do: 3
  defp sampling_sort_key(:definition_intervals), do: 4
  defp sampling_sort_key(sampling_mode), do: to_string(sampling_mode)

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
  end

  defp stable_point_id(point_id) do
    point_id
    |> String.replace(".", "-")
    |> String.replace("_", "-")
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_targets(%Frame{meta: meta}) do
    meta
    |> Map.get(:links, [])
    |> Enum.map(& &1.target)
  end

  defp link_targets(%ResolveWarning{links: links}) do
    Enum.map(links, & &1.target)
  end

  defp link_by_target(container, target, target_id \\ nil)

  defp link_by_target(%Frame{meta: meta}, target, target_id) do
    find_link_by_target(Map.get(meta, :links, []), target, target_id)
  end

  defp link_by_target(%ResolveWarning{links: links}, target, target_id) do
    find_link_by_target(links, target, target_id)
  end

  defp find_link_by_target(links, target, nil) do
    Enum.find(links, &(&1.target == target))
  end

  defp find_link_by_target(links, target, target_id) do
    Enum.find(links, &(&1.target == target and &1.target_id == target_id))
  end

  defp assert_link_runtime_context(link, opts) do
    refute is_nil(link)

    assert_context_texts(link, [
      {[:organization_id], "org_dashboards"},
      {[:mission_id], "mission_dashboards"}
    ])

    assert_context_texts(link, optional_context_texts(opts))
    assert_scope_id(link, Keyword.get(opts, :scope_id))
    assert_replay_context(link, Keyword.get(opts, :replay_run_id))
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

  defp assert_replay_context(_link, nil), do: :ok

  defp assert_replay_context(link, expected) do
    assert context_text(context_value(link.context, [:time, :replay_run_id])) == expected
    assert context_text(context_value(link.context, [:data, :replay_run_id])) == expected
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
