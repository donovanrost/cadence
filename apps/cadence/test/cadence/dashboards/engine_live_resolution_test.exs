defmodule Cadence.Dashboards.EngineLiveResolutionTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.EngineFixtures

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSource,
    Document,
    Engine,
    Frame,
    ResolveWarning,
    RuntimeCacheKey
  }

  alias Cadence.Limits.Event
  alias Cadence.Telemetry.Sample

  test "live tick resolves poll-latest source requests" do
    document = mixed_latest_and_history_document()
    parent = self()

    telemetry_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_latest, organization_id, mission_id, point_id, opts})

      %Sample{
        sample_id: "sample-live-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        packet_definition_id: "packet-def-1",
        packet_definition_version: 1,
        packet_id: "packet-1",
        evidence_id: "evidence-1",
        raw_value: 12.5,
        engineering_value: 12.5,
        quality_state: :good,
        generation_time: ~U[2026-06-17 12:01:00Z],
        receipt_time: ~U[2026-06-17 12:01:01Z],
        provenance: %{}
      }
    end

    telemetry_watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok,
       %{
         complete_through: ~U[2026-06-17 12:01:01Z],
         latest_receipt_time: ~U[2026-06-17 12:01:01Z],
         retention_starts_at: ~U[2026-06-17 12:01:01Z],
         sample_count: 1,
         confidence: :best_effort
       }}
    end

    telemetry_history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("live_tick should not resolve telemetry history requests")
    end

    limits_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_latest, organization_id, mission_id, point_id, opts})

      %Event{
        limit_event_id: "limit-event-live-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        source_sample_type: :telemetry_sample,
        sample_id: "sample-live-1",
        limit_definition_id: "limit-def-1",
        limit_definition_version: 3,
        limit_set_name: "ops",
        evaluated_value: 12.5,
        limit_state: :green,
        normalized_state: :green,
        violation: false,
        generation_time: ~U[2026-06-17 12:01:00Z],
        receipt_time: ~U[2026-06-17 12:01:01Z],
        provenance: %{}
      }
    end

    limits_watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok,
       %{
         complete_through: ~U[2026-06-17 12:01:01Z],
         latest_receipt_time: ~U[2026-06-17 12:01:01Z],
         retention_starts_at: ~U[2026-06-17 12:01:01Z],
         sample_count: 1,
         confidence: :best_effort
       }}
    end

    limits_history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("live_tick should not resolve limit event history requests")
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          resolve_mode: :live_tick,
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        source_opts: %{
          telemetry: [
            latest_fun: telemetry_latest_fun,
            history_fun: telemetry_history_fun,
            watermark_fun: telemetry_watermark_fun
          ],
          limits: [
            latest_fun: limits_latest_fun,
            history_fun: limits_history_fun,
            watermark_fun: limits_watermark_fun
          ]
        }
      )

    assert result.resolve_mode == :live_tick
    assert result.plan_metadata.source_request_count == 5
    assert result.plan_metadata.executed_source_request_count == 4
    assert result.plan_metadata.skipped_source_request_count == 1
    assert result.plan_metadata.returned_frame_count >= 4

    assert %{"placement_battery_voltage" => latest_frames} = result.frames_by_placement
    assert [%Frame{source: :telemetry, shape: :scalar}] = latest_frames.primary
    assert %{limits: [%Frame{source: :limits, shape: :scalar}]} = latest_frames.overlays

    assert %{"placement_power_trend" => history_frames} = result.frames_by_placement

    assert Enum.all?(
             history_frames.primary,
             &match?(%Frame{source: :telemetry, shape: :scalar}, &1)
           )

    assert %{limits: limit_frames} = history_frames.overlays
    assert Enum.all?(limit_frames, &match?(%Frame{source: :limits, shape: :scalar}, &1))
    assert length(result.watermarks) == 4

    assert_receive {:telemetry_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", _opts}

    assert_receive {:limits_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", _opts}
  end

  test "archive live tick is treated as an immutable snapshot" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    document = mixed_latest_and_history_document()

    fail_on_source_read = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("archive live_tick must not execute source requests")
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          resolve_mode: :live_tick,
          time_context: %{mode: :archive, axis: :receipt_time, from: from_time, to: to_time},
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        source_opts: %{
          telemetry: [
            latest_fun: fail_on_source_read,
            history_fun: fail_on_source_read,
            watermark_fun: fail_on_source_read
          ],
          limits: [
            latest_fun: fail_on_source_read,
            history_fun: fail_on_source_read,
            interval_fun: fail_on_source_read,
            watermark_fun: fail_on_source_read
          ]
        }
      )

    assert result.resolve_mode == :live_tick

    assert result.plan_metadata.time == %{
             mode: :archive,
             axis: :receipt_time,
             from: from_time,
             to: to_time
           }

    assert result.plan_metadata.snapshot?
    refute result.plan_metadata.live_append_eligible?
    assert result.plan_metadata.source_request_count == 6
    assert result.plan_metadata.executed_source_request_count == 0
    assert result.plan_metadata.skipped_source_request_count == 6
    assert result.plan_metadata.returned_frame_count == 0
    assert result.watermarks == []

    assert %{"placement_battery_voltage" => latest_frames} = result.frames_by_placement
    assert latest_frames.primary == []
    assert latest_frames.overlays == %{}

    assert %{"placement_power_trend" => history_frames} = result.frames_by_placement
    assert history_frames.primary == []
    assert history_frames.overlays == %{}
  end

  test "range time context is planned as a snapshot" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
      })

    assert result.plan_metadata.time == %{
             mode: :range,
             axis: :receipt_time,
             from: from_time,
             to: to_time
           }

    assert result.plan_metadata.snapshot?
    refute result.plan_metadata.live_append_eligible?
  end

  test "resolves planned telemetry source requests into placement frames" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "layout", "w"], 6)
      |> put_in(["placements", Access.at(0), "layout", "h"], 4)
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "widget_type_id"],
        "cadence.time_series"
      )
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
        "raw_series"
      )
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})

      [
        %Sample{
          sample_id: "sample-1",
          mission_id: mission_id,
          spacecraft_id: "sc_001",
          point_id: point_id,
          point_name: point_id,
          packet_definition_id: "packet-def-1",
          packet_definition_version: 1,
          packet_id: "packet-1",
          evidence_id: "evidence-1",
          raw_value: 12.25,
          engineering_value: 12.25,
          quality_state: :good,
          generation_time: nil,
          receipt_time: ~U[2026-06-17 12:00:00Z],
          provenance: %{}
        }
      ]
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      %{confidence: :unknown}
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          time_context: %{axis: :receipt_time},
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        source_opts: %{telemetry: [history_fun: history_fun, watermark_fun: watermark_fun]}
      )

    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1
    refute result.plan_metadata.degraded?

    assert [
             %Cadence.Dashboards.SourceWatermark{
               confidence: :unknown,
               logical_source: :telemetry
             }
           ] = result.watermarks

    assert Enum.find(
             result.dashboard_warnings,
             &match?(%ResolveWarning{code: :watermark_unknown, severity: :info}, &1)
           )

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement
    assert [%Frame{source: :telemetry, fields: [_time, value]}] = placement_frames.primary
    assert value.name == "tlm.hk.battery_voltage"
    assert value.values == [12.25]

    assert [%ResolveWarning{code: :watermark_unknown, placement_id: "placement_battery_voltage"}] =
             placement_frames.warnings

    assert_receive {:history, "org_dashboards", "mission_dashboards", "tlm.hk.battery_voltage",
                    opts}

    assert opts[:spacecraft_id] == "sc_001"
    assert opts[:data_source_id] == "managed_questdb_primary"
    assert opts[:source_binding_id] == "default_flight_telemetry"
    assert opts[:dataset] == "flight"
    assert opts[:order] == :asc
  end

  test "classifies source watermarks against dashboard freshness policy" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["defaults", "health"], %{
        "freshness_policy" => %{"stale_after_ms" => 5_000}
      })
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    latest_receipt_time = ~U[2026-06-17 12:00:00Z]

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      %Sample{
        sample_id: "sample-stale-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        packet_definition_id: "packet-def-1",
        packet_definition_version: 1,
        packet_id: "packet-1",
        evidence_id: "evidence-1",
        raw_value: 12.25,
        engineering_value: 12.25,
        quality_state: :good,
        generation_time: latest_receipt_time,
        receipt_time: latest_receipt_time,
        provenance: %{}
      }
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok,
       %{
         complete_through: latest_receipt_time,
         latest_receipt_time: latest_receipt_time,
         retention_starts_at: ~U[2026-06-17 11:00:00Z],
         sample_count: 1,
         confidence: :best_effort
       }}
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        freshness_now: ~U[2026-06-17 12:00:06Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert [
             %Cadence.Dashboards.SourceWatermark{
               freshness_state: :stale,
               freshness_policy: %{stale_after_ms: 5_000},
               freshness_checked_at: ~U[2026-06-17 12:00:06Z]
             }
           ] = result.watermarks

    assert [%ResolveWarning{code: :stale_data, severity: :warning} = warning] =
             result.dashboard_warnings

    assert warning.details.source_request_id
    assert warning.details.freshness_state == :stale

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement

    assert [%ResolveWarning{code: :stale_data, placement_id: "placement_battery_voltage"}] =
             placement_frames.warnings

    assert result.plan_metadata.degraded?

    assert %RuntimeCacheKey{layer: :plan} = result.plan_metadata.cache.plan_key

    assert [{source_request_id, %RuntimeCacheKey{layer: :source_result} = source_key}] =
             Map.to_list(result.plan_metadata.cache.source_result_keys_by_request_id)

    assert source_key.parts.freshness_policy == %{stale_after_ms: 5_000}
    assert source_key.parts.source_binding.binding_id == "default_flight_telemetry"
    assert source_key.parts.data_source.data_source_id == "managed_questdb_primary"
    assert source_key.parts.watermark_cursor.freshness_state == :stale
    assert source_key.parts.watermark_cursor.complete_through == latest_receipt_time

    assert %RuntimeCacheKey{layer: :frame} =
             frame_key =
             result.plan_metadata.cache.frame_keys_by_placement["placement_battery_voltage"][
               source_request_id
             ]

    assert frame_key.parts.source_result_fingerprint == source_key.fingerprint
    assert frame_key.parts.placement_size == %{}
  end

  test "classifies source watermarks with retention gaps" do
    from_time = ~U[2026-06-17 10:00:00Z]
    to_time = ~U[2026-06-17 12:00:00Z]

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["defaults", "time"], %{
        "mode" => "archive",
        "axis" => "receipt_time",
        "from" => DateTime.to_iso8601(from_time),
        "to" => DateTime.to_iso8601(to_time)
      })
      |> put_in(["defaults", "health"], %{
        "freshness_policy" => %{"stale_after_ms" => 5_000}
      })
      |> put_in(["placements", Access.at(0), "layout", "w"], 6)
      |> put_in(["placements", Access.at(0), "layout", "h"], 4)
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "widget_type_id"],
        "cadence.time_series"
      )
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
        "raw_series"
      )
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    history_fun = fn _organization_id, mission_id, point_id, _opts ->
      [
        %Sample{
          sample_id: "sample-retention-1",
          mission_id: mission_id,
          spacecraft_id: "sc_001",
          point_id: point_id,
          point_name: point_id,
          packet_definition_id: "packet-def-1",
          packet_definition_version: 1,
          packet_id: "packet-1",
          evidence_id: "evidence-1",
          raw_value: 12.25,
          engineering_value: 12.25,
          quality_state: :good,
          generation_time: to_time,
          receipt_time: to_time,
          provenance: %{}
        }
      ]
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok,
       %{
         complete_through: to_time,
         latest_receipt_time: to_time,
         retention_starts_at: ~U[2026-06-17 11:00:00Z],
         sample_count: 1,
         confidence: :best_effort
       }}
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        freshness_now: ~U[2026-06-17 12:00:01Z],
        source_opts: %{telemetry: [history_fun: history_fun, watermark_fun: watermark_fun]}
      )

    assert [
             %Cadence.Dashboards.SourceWatermark{
               freshness_state: :retention_gap,
               retention_starts_at: ~U[2026-06-17 11:00:00Z]
             }
           ] = result.watermarks

    assert [%ResolveWarning{code: :retention_gap, severity: :warning}] =
             result.dashboard_warnings

    assert result.plan_metadata.degraded?
  end

  test "resolves native decimated telemetry when the data source advertises it" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "layout", "w"], 6)
      |> put_in(["placements", Access.at(0), "layout", "h"], 4)
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "widget_type_id"],
        "cadence.time_series"
      )
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
        "decimated_envelope"
      )
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    decimated_history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:decimated_history, organization_id, mission_id, point_id, opts})

      [
        %{
          bucket_start: from_time,
          bucket_end: to_time,
          min: 11.5,
          max: 12.75,
          mean: 12.25,
          sample_count: 120,
          worst_quality_state: :good
        }
      ]
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
          interaction_context: %{
            placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 240}}
          }
        },
        data_sources: [
          telemetry_data_source("native-decimating-questdb", native_decimation?: true)
        ],
        data_bindings: [
          telemetry_binding("native-decimating-questdb")
        ],
        source_opts: %{telemetry: [decimated_history_fun: decimated_history_fun]}
      )

    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1
    refute result.plan_metadata.degraded?

    assert Enum.find(
             result.dashboard_warnings,
             &match?(%ResolveWarning{code: :watermark_unknown, severity: :info}, &1)
           )

    assert Enum.find(
             result.dashboard_warnings,
             &match?(%ResolveWarning{code: :physical_aggregate_semantics, severity: :info}, &1)
           )

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement

    assert [%Frame{source: :telemetry, shape: :wide, fields: fields} = frame] =
             placement_frames.primary

    assert frame.meta.sampling == :decimated_envelope
    assert frame.meta.decimation == :native_min_max_envelope
    assert frame.meta.canonical_mode == :physical
    assert frame.meta.aggregate_semantics == :physical_as_recorded
    assert frame.meta.target_points == 320
    assert Enum.find(fields, &(&1.name == "tlm.hk.battery_voltage_min")).values == [11.5]
    assert Enum.find(fields, &(&1.name == "tlm.hk.battery_voltage_max")).values == [12.75]
    assert Enum.find(fields, &(&1.name == "tlm.hk.battery_voltage_value")).values == [12.25]

    refute Enum.any?(placement_frames.warnings, &(&1.code == :unsupported_sampling))
    refute Enum.any?(placement_frames.warnings, &(&1.code == :source_unavailable))

    assert_receive {:decimated_history, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", opts}

    assert opts[:spacecraft_id] == "sc_001"
    assert opts[:data_source_id] == "native-decimating-questdb"
    assert opts[:source_binding_id] == "flight-telemetry"
    assert opts[:dataset] == "flight"
    assert opts[:from_receipt_time] == from_time
    assert opts[:to_receipt_time] == to_time
    assert opts[:target_points] == 320
    assert opts[:decimation] == :native_min_max_envelope
  end

  test "resolve cache provenance reflects selected data realm source binding" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      %Sample{
        sample_id: "sample-rehearsal-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        packet_definition_id: "packet-def-1",
        packet_definition_version: 1,
        packet_id: "packet-1",
        evidence_id: "evidence-1",
        raw_value: 12.25,
        engineering_value: 12.25,
        quality_state: :good,
        generation_time: ~U[2026-06-17 12:00:00Z],
        receipt_time: ~U[2026-06-17 12:00:01Z],
        provenance: %{}
      }
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
          data_context: %{realm: :rehearsal}
        },
        data_sources: [
          telemetry_data_source("rehearsal-questdb", latest?: true, watermarks?: false)
        ],
        data_bindings: [
          telemetry_binding("rehearsal-questdb", :rehearsal)
        ],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert [{_source_request_id, %RuntimeCacheKey{layer: :source_result} = source_key}] =
             Map.to_list(result.plan_metadata.cache.source_result_keys_by_request_id)

    assert source_key.parts.source_binding.realm == :rehearsal
    assert source_key.parts.source_binding.data_source_id == "rehearsal-questdb"
    assert source_key.parts.data_source.data_source_id == "rehearsal-questdb"
  end

  test "latest telemetry widgets render values from the selected source binding" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    latest_fun = fn _organization_id, mission_id, point_id, opts ->
      value =
        case opts[:source_binding_id] do
          "default_flight_telemetry" -> 12.25
          "flight-telemetry" -> 99.0
        end

      telemetry_sample(mission_id, point_id, value)
    end

    base_request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
    }

    flight =
      Engine.resolve(base_request,
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    rehearsal =
      Engine.resolve(
        %DashboardResolveRequest{base_request | data_context: %{realm: :rehearsal}},
        data_sources: [
          telemetry_data_source("rehearsal-questdb", latest?: true, watermarks?: false)
        ],
        data_bindings: [
          telemetry_binding("rehearsal-questdb", :rehearsal)
        ],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert telemetry_latest_values(flight) == [12.25]
    assert telemetry_latest_values(rehearsal) == [99.0]
  end

  test "planning reports data source adapter failures through the registry" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        data_sources: [
          %DataSource{
            data_source_id: "managed_questdb_primary",
            adapter: nil
          }
        ]
      )

    assert result.plan_metadata.executed_source_request_count == 0
    assert result.plan_metadata.returned_frame_count == 0
    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :unsupported_source_adapter, severity: :error}] =
             result.dashboard_warnings

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement
    assert placement_frames.primary == []
    assert placement_frames.planned_request_ids == []

    assert [%ResolveWarning{code: :unsupported_source_adapter, scope: :placement}] =
             placement_frames.warnings
  end
end
