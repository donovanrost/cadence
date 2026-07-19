defmodule Cadence.Dashboards.EngineRuntimePlanningTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.EngineFixtures

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataContext,
    DataSources,
    Document,
    Engine,
    LimitContext,
    Placement,
    ResolveWarning
  }

  alias Cadence.Telemetry.Sample

  test "runtime context overrides are typed and participate in batching" do
    document = load_fixture!("value_tile_latest.v1.json")

    observed =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        limit_context: %{semantics_mode: "observed"}
      })

    current =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        limit_context: %{semantics_mode: "current"}
      })

    observed_request = request_by_source(observed.planned_source_requests, :limits)
    current_request = request_by_source(current.planned_source_requests, :limits)

    assert %LimitContext{semantics_mode: "observed"} = observed_request.limit_context
    assert %LimitContext{semantics_mode: "current"} = current_request.limit_context
    assert observed_request.source_dependencies == []

    assert [
             %{
               logical_source: :telemetry,
               reason: :limit_latest_sample_input,
               products: [:latest_sample],
               sampling: %{mode: :latest}
             }
           ] = current_request.source_dependencies

    assert observed_request.request_id != current_request.request_id
  end

  test "placement overrides take precedence over document defaults and runtime context" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> then(fn %Document{placements: [placement | rest]} = document ->
        %Placement{} = placement

        placement = %Placement{
          placement
          | data_override: %{
              realm: :rehearsal,
              source_contexts: %{
                telemetry: %{
                  data_source_id: "placement-rehearsal-questdb",
                  source_binding_id: "flight-telemetry",
                  dataset: "placement-rehearsal"
                }
              }
            },
            limit_override: %{semantics_mode: :current}
        }

        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "flight",
                "source_contexts" => %{
                  "telemetry" => %{
                    "data_source_id" => "document-flight-questdb",
                    "source_binding_id" => "document-flight-binding",
                    "dataset" => "document-flight"
                  }
                }
              },
              "limits" => %{"semantics_mode" => "observed"}
            },
            placements: [placement | rest]
        }
      end)

    result =
      Engine.plan(
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
                data_source_id: "runtime-flight-questdb",
                source_binding_id: "runtime-flight-binding",
                dataset: "runtime-flight"
              }
            }
          },
          limit_context: %{semantics_mode: :observed}
        },
        data_sources: [
          telemetry_data_source("placement-rehearsal-questdb", latest?: true, watermarks?: false),
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          %DataBinding{
            telemetry_binding("placement-rehearsal-questdb", :rehearsal)
            | dataset: "placement-rehearsal"
          },
          limits_binding(:rehearsal)
        ]
      )

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)
    limits_request = request_by_source(result.planned_source_requests, :limits)

    assert %DataContext{} = telemetry_request.data_context
    assert telemetry_request.data_context.realm == :rehearsal

    assert DataContext.source_value(telemetry_request.data_context, :telemetry, :data_source_id) ==
             "placement-rehearsal-questdb"

    assert DataContext.source_value(telemetry_request.data_context, :telemetry, :dataset) ==
             "placement-rehearsal"

    assert %LimitContext{semantics_mode: :current} = telemetry_request.limit_context
    assert %LimitContext{semantics_mode: :current} = limits_request.limit_context

    assert result.dashboard_warnings == []
  end

  test "invalid runtime context values become placement warnings" do
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        scope_context: %{primary: %{kind: "antenna", mode: "one", ids: ["gs-1"]}},
        data_context: %{realm: "customer-prod"},
        limit_context: %{semantics_mode: "hypothetical"}
      })

    assert result.plan_metadata.degraded?

    warnings =
      Enum.filter(result.dashboard_warnings, &(&1.code == :invalid_runtime_context))

    assert Enum.map(warnings, & &1.details.context) |> Enum.sort() == [:data, :limit, :scope]
    assert Enum.any?(warnings, &(:unsupported_scope_kind in &1.details.errors))
    assert Enum.any?(warnings, &(:unsupported_data_realm in &1.details.errors))
    assert Enum.any?(warnings, &(:unsupported_limit_semantics_mode in &1.details.errors))
  end

  test "batches equivalent source requests across placements" do
    attrs = load_fixture_map!("value_tile_latest.v1.json")
    [placement] = attrs["placements"]
    second_placement = put_in(placement, ["placement_id"], "placement_battery_voltage_copy")
    attrs = Map.put(attrs, "placements", [placement, second_placement])
    document = Document.from_map(attrs)

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document
      })

    assert result.plan_metadata.unbatched_source_request_count == 4
    assert result.plan_metadata.source_request_count == 2

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)
    limits_request = request_by_source(result.planned_source_requests, :limits)

    assert Enum.map(telemetry_request.consumers, & &1.placement_id) |> Enum.sort() == [
             "placement_battery_voltage",
             "placement_battery_voltage_copy"
           ]

    assert Enum.map(limits_request.consumers, & &1.placement_id) |> Enum.sort() == [
             "placement_battery_voltage",
             "placement_battery_voltage_copy"
           ]

    planned_ids =
      result.frames_by_placement
      |> Map.values()
      |> Enum.map(&Enum.sort(&1.planned_request_ids))
      |> Enum.uniq()

    assert planned_ids == [
             result.planned_source_requests |> Enum.map(& &1.request_id) |> Enum.sort()
           ]
  end

  test "does not batch equivalent source requests across tenant or mission context" do
    document = load_fixture!("value_tile_latest.v1.json")

    first =
      Engine.plan(%DashboardResolveRequest{
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: document.dashboard_id,
        document: document
      })

    second =
      Engine.plan(%DashboardResolveRequest{
        organization_id: "org-1",
        mission_id: "mission-2",
        dashboard_id: document.dashboard_id,
        document: document
      })

    first_request = request_by_source(first.planned_source_requests, :telemetry)
    second_request = request_by_source(second.planned_source_requests, :telemetry)

    assert first_request.organization_id == "org-1"
    assert first_request.mission_id == "mission-1"
    assert second_request.organization_id == "org-1"
    assert second_request.mission_id == "mission-2"
    assert first_request.request_id != second_request.request_id
  end

  test "preserves DateTime values while normalizing runtime time context keys" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        time_context: %{"axis" => "receipt_time", "from" => from_time, "to" => to_time}
      })

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)

    assert telemetry_request.time_context.axis == "receipt_time"
    assert telemetry_request.time_context.from == from_time
    assert telemetry_request.time_context.to == to_time
  end

  test "returns placement warning instead of source request for unknown widget" do
    document = load_fixture!("unknown_widget_retained.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document
      })

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?

    assert [
             %ResolveWarning{code: :unknown_widget_type, scope: :dashboard},
             %ResolveWarning{code: :unknown_widget_type, scope: :placement}
           ] = result.dashboard_warnings

    assert %{"placement_legacy" => placement_frames} = result.frames_by_placement

    assert [%ResolveWarning{code: :unknown_widget_type, placement_id: "placement_legacy"}] =
             placement_frames.warnings
  end

  test "carries replay context into planned source requests" do
    document = load_fixture!("replay_context.v1.json")

    result =
      Engine.plan(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        data_sources: [
          telemetry_data_source("replay-questdb", range_scan?: true),
          limits_data_source()
        ],
        data_bindings: [
          telemetry_binding("replay-questdb", :replay),
          limits_binding(:replay)
        ]
      )

    request = request_by_source(result.planned_source_requests, :telemetry)
    assert request.time_context.mode == "replay_run"
    assert request.time_context.replay_run_id == "replay_run_001"
    assert request.data_context.realm == "replay"
    assert request.data_context.replay_run_id == "replay_run_001"
    assert result.plan_metadata.snapshot?
    refute result.plan_metadata.live_append_eligible?
  end

  test "carries replay source context into freshness warnings" do
    document =
      "replay_context.v1.json"
      |> load_fixture_map!()
      |> put_in(["defaults", "health"], %{
        "freshness_policy" => %{"stale_after_ms" => 5_000}
      })
      |> put_in(["defaults", "time", "axis"], "receipt_time")
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    history_fun = fn _organization_id, mission_id, point_id, _opts ->
      [
        %Sample{
          sample_id: "sample-replay-stale-1",
          mission_id: mission_id,
          spacecraft_id: "sc_001",
          point_id: point_id,
          point_name: point_id,
          packet_definition_id: "packet-def-1",
          packet_definition_version: 1,
          packet_id: "packet-1",
          evidence_id: "evidence-replay-1",
          raw_value: 12.25,
          engineering_value: 12.25,
          quality_state: :good,
          generation_time: ~U[2026-06-16 00:00:00Z],
          receipt_time: ~U[2026-06-16 00:00:00Z],
          provenance: %{}
        }
      ]
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok,
       %{
         complete_through: ~U[2026-06-16 00:00:00Z],
         latest_receipt_time: ~U[2026-06-16 00:00:00Z],
         retention_starts_at: ~U[2026-06-15 00:00:00Z],
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
          document: document
        },
        data_sources: [
          telemetry_data_source("replay-questdb", range_scan?: true, watermarks?: true),
          limits_data_source()
        ],
        data_bindings: [
          telemetry_binding("replay-questdb", :replay),
          limits_binding(:replay)
        ],
        freshness_now: ~U[2026-06-16 00:00:06Z],
        source_opts: %{telemetry: [history_fun: history_fun, watermark_fun: watermark_fun]}
      )

    assert [%ResolveWarning{code: :stale_data, severity: :warning} = warning] =
             result.dashboard_warnings

    assert warning.details.time_mode == "replay_run"
    assert warning.details.time_axis == "receipt_time"
    assert warning.details.replay_run_id == "replay_run_001"
    assert warning.details.realm == :replay
    assert warning.details.requested_realm == "replay"
    assert warning.details.data_source_id == "replay-questdb"
    assert warning.details.source_binding_id == "flight-telemetry"

    assert Enum.any?(warning.details.actions, fn action ->
             action.target == :source_health and
               action.context.replay_run_id == "replay_run_001" and
               action.context.realm == :replay and
               action.context.data_source_id == "replay-questdb"
           end)

    refute warning.details.realm == :flight
  end

  test "plans temporal limits overlays while warning on unsupported telemetry sampling" do
    document = load_fixture!("time_series_with_limits.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document
      })

    limits_analysis_request =
      request_by_source_product(result.planned_source_requests, :limits, :analysis_buckets)

    limits_interval_request =
      request_by_source_product(result.planned_source_requests, :limits, :definition_intervals)

    events_request = request_by_source(result.planned_source_requests, :events)

    refute request_by_source(result.planned_source_requests, :telemetry)
    assert events_request
    assert limits_analysis_request
    assert limits_interval_request
    assert result.plan_metadata.degraded?

    assert [
             %ResolveWarning{
               code: :unsupported_source_capability,
               scope: :placement,
               placement_id: "placement_power_trend",
               details: details
             }
           ] = result.dashboard_warnings

    assert details.logical_source == :telemetry
    assert details.requested_sampling == :decimated_envelope
    assert details.source_binding_id == "default_flight_telemetry"
    assert details.data_source_id == "managed_questdb_primary"
    assert details.realm == :flight
    assert details.dataset == "flight"
    assert is_binary(details.capability_fingerprint)
    assert details.capability_provenance.capability_fingerprint == details.capability_fingerprint

    assert details.supported_sampling == [
             :latest,
             :raw_series,
             :bounded_history,
             :bounded_raw_series
           ]

    assert details.fallback == :none

    assert limits_analysis_request.sampling.mode == :analysis_buckets
    assert limits_analysis_request.sampling.products == [:analysis_buckets]
    assert limits_analysis_request.sampling.semantics_mode == :observed
    assert limits_analysis_request.sampling.temporal?
    assert limits_analysis_request.sampling.limit == 1_000
    assert limits_analysis_request.source_dependencies == []
    assert limits_analysis_request.time_context.axis == :receipt_time
    assert limits_analysis_request.observables == ["tlm.hk.battery_voltage", "tlm.hk.bus_current"]

    assert limits_interval_request.sampling.mode == :definition_intervals
    assert limits_interval_request.sampling.products == [:definition_intervals]
    assert limits_interval_request.sampling.semantics_mode == :observed
    assert limits_interval_request.sampling.temporal?
    assert limits_interval_request.time_context.axis == :receipt_time

    assert limits_interval_request.observables == [
             "tlm.hk.battery_voltage",
             "tlm.hk.bus_current"
           ]

    assert events_request.sampling.mode == :event_history
    assert events_request.time_context.axis == :occurred_at

    assert events_request.sampling.products == [
             :contact_intervals,
             :mission_timeline,
             :source_health_transitions,
             :source_watermark_events,
             :source_capability_postures,
             :telemetry_backfill_lifecycle,
             :telemetry_revision_decisions
           ]

    assert events_request.sampling.families == [
             :contacts,
             :mission_timeline,
             :source_health,
             :source_watermarks,
             :source_capabilities,
             :telemetry_backfills,
             :telemetry_revisions
           ]

    assert events_request.sampling.temporal?
    assert events_request.sampling.source_watermark == %{logical_source: :telemetry}
    assert events_request.sampling.limit == 500

    assert %{"placement_power_trend" => placement_frames} = result.frames_by_placement

    assert Enum.sort(placement_frames.planned_request_ids) ==
             [
               limits_analysis_request.request_id,
               limits_interval_request.request_id,
               events_request.request_id
             ]
             |> Enum.sort()

    assert [
             %ResolveWarning{
               code: :unsupported_source_capability,
               placement_id: "placement_power_trend"
             }
           ] = placement_frames.warnings
  end

  test "plans source-watermark event overlays with primary telemetry source filters" do
    document =
      "time_series_with_limits.v1.json"
      |> load_fixture_map!()
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
        "raw_series"
      )
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "overlays"],
        ["events"]
      )
      |> Document.from_map()

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        data_context: %{
          realm: :flight,
          source_contexts: %{
            telemetry: %{
              data_source_id: "selected_questdb",
              source_binding_id: "selected_flight_telemetry",
              dataset: "selected-flight"
            }
          }
        }
      })

    events_request = request_by_source(result.planned_source_requests, :events)

    assert events_request.sampling.mode == :event_history
    assert events_request.data_context.data_source_id == nil
    assert events_request.data_context.source_binding_id == nil
    assert events_request.data_context.dataset == nil

    assert events_request.sampling.source_watermark == %{
             logical_source: :telemetry,
             data_source_id: "selected_questdb",
             source_binding_id: "selected_flight_telemetry",
             dataset: "selected-flight"
           }
  end

  test "plans compare temporal limits with explicit telemetry history dependency" do
    document = load_fixture!("time_series_with_limits.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        limit_context: %{semantics_mode: :compare}
      })

    limits_analysis_request =
      request_by_source_product(result.planned_source_requests, :limits, :analysis_buckets)

    assert [
             %{
               logical_source: :telemetry,
               reason: :limit_sample_history_input,
               products: [:sample_history],
               sampling: %{mode: :history}
             }
           ] = limits_analysis_request.source_dependencies
  end

  test "plans decimated telemetry when the resolved data source advertises native decimation" do
    document = load_fixture!("time_series_with_limits.v1.json")

    result =
      Engine.plan(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        data_sources: [
          telemetry_data_source("native-decimating-questdb", native_decimation?: true),
          limits_data_source(),
          events_data_source()
        ],
        data_bindings: [
          telemetry_binding("native-decimating-questdb"),
          limits_binding(),
          events_binding()
        ]
      )

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)

    limits_analysis_request =
      request_by_source_product(result.planned_source_requests, :limits, :analysis_buckets)

    limits_interval_request =
      request_by_source_product(result.planned_source_requests, :limits, :definition_intervals)

    events_request = request_by_source(result.planned_source_requests, :events)
    telemetry_provenance = telemetry_request.metadata.capability_provenance

    assert telemetry_request.sampling.mode == :decimated_envelope
    assert telemetry_request.time_context.axis == "generation_time"
    assert telemetry_provenance.data_source_id == "native-decimating-questdb"
    assert telemetry_provenance.binding_id == "flight-telemetry"
    assert Map.get(telemetry_provenance.data_source_capabilities, :native_decimation?)
    assert :decimated_envelope in telemetry_provenance.supported_sampling
    assert limits_analysis_request.sampling.mode == :analysis_buckets
    assert limits_analysis_request.time_context.axis == :receipt_time
    assert limits_interval_request.sampling.mode == :definition_intervals
    assert limits_interval_request.time_context.axis == :receipt_time
    assert events_request.sampling.mode == :event_history
    assert events_request.time_context.axis == :occurred_at
    refute result.plan_metadata.degraded?
    assert result.dashboard_warnings == []
  end

  test "surfaces missing source bindings during planning" do
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        data_sources: [],
        data_bindings: []
      )

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?

    assert Enum.map(result.dashboard_warnings, & &1.code) == [
             :missing_source_binding,
             :missing_source_binding
           ]

    assert Enum.all?(result.dashboard_warnings, &(&1.scope == :placement))
  end
end
