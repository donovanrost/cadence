defmodule Cadence.Dashboards.EngineFrameResolutionTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.EngineFixtures

  alias Cadence.Dashboards.{DashboardResolveRequest, Document, Engine, Frame}

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Limits.Event
  alias Cadence.Telemetry.Sample

  test "resolves latest telemetry value tiles into placement frames" do
    document = load_fixture!("value_tile_latest.v1.json")
    parent = self()

    telemetry_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_latest, organization_id, mission_id, point_id, opts})

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
        generation_time: ~U[2026-06-17 12:00:00Z],
        receipt_time: ~U[2026-06-17 12:00:01Z],
        provenance: %{}
      }
    end

    limits_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_latest, organization_id, mission_id, point_id, opts})

      %Event{
        limit_event_id: "limit-event-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        source_sample_type: :telemetry_sample,
        sample_id: "sample-1",
        limit_definition_id: "limit-def-1",
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

    limits_watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_watermark, organization_id, mission_id, point_id, opts})

      {:ok,
       %{
         complete_through: ~U[2026-06-17 12:00:01Z],
         latest_receipt_time: ~U[2026-06-17 12:00:01Z],
         retention_starts_at: ~U[2026-06-17 12:00:01Z],
         sample_count: 1,
         confidence: :best_effort
       }}
    end

    telemetry_watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      %{confidence: :unknown}
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
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun, watermark_fun: telemetry_watermark_fun],
          limits: [latest_fun: limits_latest_fun, watermark_fun: limits_watermark_fun]
        }
      )

    assert result.plan_metadata.executed_source_request_count == 2
    assert result.plan_metadata.returned_frame_count == 2
    refute result.plan_metadata.degraded?

    assert result.dashboard_warnings |> Enum.map(& &1.code) |> Enum.sort() == [
             :capability_fallback,
             :watermark_unknown
           ]

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement

    assert [%Frame{source: :telemetry, shape: :scalar, fields: [_time, value]}] =
             placement_frames.primary

    assert value.name == "tlm.hk.battery_voltage"
    assert value.values == [12.25]

    assert %{limits: [%Frame{source: :limits, shape: :scalar, fields: limits_fields}]} =
             placement_frames.overlays

    assert Enum.find(limits_fields, &(&1.name == "normalized_state")).values == [:yellow]
    assert Enum.find(limits_fields, &(&1.name == "limit_state")).values == [:yellow_high]
    assert Enum.find(limits_fields, &(&1.name == "violation")).values == [true]

    refute Enum.any?(placement_frames.warnings, &(&1.code == :unsupported_sampling))

    assert_receive {:telemetry_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", opts}

    assert opts[:spacecraft_id] == "sc_001"
    assert opts[:data_source_id] == "managed_questdb_primary"
    assert opts[:source_binding_id] == "default_flight_telemetry"
    assert opts[:dataset] == "flight"
    refute Keyword.has_key?(opts, :order)

    assert_receive {:limits_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", limit_opts}

    assert limit_opts[:spacecraft_id] == "sc_001"
    assert limit_opts[:data_source_id] == "managed_limits_projection"
    assert limit_opts[:dataset] == "telemetry_latest_limit_states"
    assert limit_opts[:semantics_mode] == :observed

    assert_receive {:limits_watermark, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", watermark_opts}

    assert watermark_opts[:spacecraft_id] == "sc_001"
    assert watermark_opts[:data_source_id] == "managed_limits_projection"
    assert watermark_opts[:dataset] == "telemetry_latest_limit_states"
    assert watermark_opts[:semantics_mode] == :observed
  end

  test "telemetry source context does not constrain limits overlays" do
    document = load_fixture!("value_tile_latest.v1.json")
    parent = self()

    telemetry_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_latest, organization_id, mission_id, point_id, opts})
      telemetry_sample(mission_id, point_id)
    end

    limits_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_latest, organization_id, mission_id, point_id, opts})
      limit_event(mission_id, point_id)
    end

    limits_watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_watermark, organization_id, mission_id, point_id, opts})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    %DataSource{} = default_managed_source = DataSources.default_managed_data_source()
    %DataBinding{} = default_telemetry_binding = DataSources.default_flight_telemetry_binding()

    selected_telemetry_source = %DataSource{
      default_managed_source
      | data_source_id: "selected_questdb",
        capabilities: %{latest?: true}
    }

    selected_telemetry_binding = %DataBinding{
      default_telemetry_binding
      | binding_id: "selected_flight_telemetry",
        data_source_id: "selected_questdb",
        dataset: "selected-flight",
        priority: 10
    }

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
          data_context: %{
            realm: :flight,
            source_contexts: %{
              telemetry: %{
                source_binding_id: "selected_flight_telemetry",
                data_source_id: "selected_questdb",
                dataset: "selected-flight"
              }
            }
          }
        },
        data_sources: [selected_telemetry_source, DataSources.default_limits_data_source()],
        data_bindings: [selected_telemetry_binding, DataSources.default_flight_limits_binding()],
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun],
          limits: [latest_fun: limits_latest_fun, watermark_fun: limits_watermark_fun]
        }
      )

    refute result.plan_metadata.degraded?

    telemetry_request =
      Enum.find(result.planned_source_requests, &(&1.logical_source == :telemetry))

    assert %{
             selected_source_binding_id: "selected_flight_telemetry",
             selected_data_source_id: "selected_questdb",
             selected_dataset: "selected-flight",
             requested_source_binding_id: "selected_flight_telemetry",
             requested_data_source_id: "selected_questdb",
             requested_dataset: "selected-flight",
             strategy: :current_binding,
             candidates: candidates
           } =
             result.plan_metadata.source_selection_by_request_id[
               telemetry_request.request_id
             ]

    assert Enum.any?(
             candidates,
             &match?(
               %{binding_id: "selected_flight_telemetry", decision: :selected},
               &1
             )
           )

    assert Enum.any?(
             candidates,
             fn candidate ->
               candidate.binding_id == "default_flight_limits" and
                 candidate.decision == :rejected and
                 :logical_source_mismatch in candidate.reasons
             end
           )

    assert_receive {:telemetry_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", telemetry_opts}

    assert telemetry_opts[:data_source_id] == "selected_questdb"
    assert telemetry_opts[:source_binding_id] == "selected_flight_telemetry"
    assert telemetry_opts[:dataset] == "selected-flight"

    assert_receive {:limits_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", limit_opts}

    assert limit_opts[:data_source_id] == "managed_limits_projection"
    assert limit_opts[:dataset] == "telemetry_latest_limit_states"
    refute limit_opts[:source_binding_id] == "selected_flight_telemetry"

    assert_receive {:limits_watermark, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", watermark_opts}

    assert watermark_opts[:data_source_id] == "managed_limits_projection"
    assert watermark_opts[:dataset] == "telemetry_latest_limit_states"
    refute watermark_opts[:source_binding_id] == "selected_flight_telemetry"
  end

  test "resolves temporal limit overlays with events and definition intervals" do
    document =
      "time_series_with_limits.v1.json"
      |> load_fixture_map!()
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
        "raw_series"
      )
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "overlays"],
        ["limits"]
      )
      |> Document.from_map()

    parent = self()

    telemetry_history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_history, organization_id, mission_id, point_id, opts})
      [telemetry_sample(mission_id, point_id)]
    end

    limits_history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_history, organization_id, mission_id, point_id, opts})
      [limit_event(mission_id, point_id)]
    end

    limits_interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_intervals, organization_id, mission_id, point_id, opts})
      [limit_definition_interval(mission_id, point_id)]
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          time_context: %{
            mode: :archive,
            axis: :receipt_time,
            from: ~U[2026-06-17 12:00:00Z],
            to: ~U[2026-06-17 12:10:00Z]
          },
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        source_opts: %{
          telemetry: [history_fun: telemetry_history_fun, watermark_fun: watermark_fun],
          limits: [
            history_fun: limits_history_fun,
            interval_fun: limits_interval_fun,
            watermark_fun: watermark_fun
          ]
        }
      )

    refute result.plan_metadata.degraded?

    assert %{"placement_power_trend" => placement_frames} = result.frames_by_placement

    assert Enum.any?(
             placement_frames.primary,
             &match?(%Frame{source: :telemetry, shape: :wide}, &1)
           )

    assert %{limits: limit_frames} = placement_frames.overlays
    assert Enum.any?(limit_frames, &match?(%Frame{source: :limits, shape: :events}, &1))
    assert Enum.any?(limit_frames, &match?(%Frame{source: :limits, shape: :intervals}, &1))

    assert_receive {:limits_history, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", history_opts}

    assert_receive {:limits_intervals, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", interval_opts}

    assert history_opts[:from_receipt_time] == ~U[2026-06-17 12:00:00Z]
    assert history_opts[:to_receipt_time] == ~U[2026-06-17 12:10:00Z]
    assert interval_opts[:from_receipt_time] == ~U[2026-06-17 12:00:00Z]
    assert interval_opts[:to_receipt_time] == ~U[2026-06-17 12:10:00Z]
  end
end
