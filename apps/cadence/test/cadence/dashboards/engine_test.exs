defmodule Cadence.Dashboards.EngineTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataContext,
    DataSource,
    DataSources,
    Document,
    Engine,
    Frame,
    LimitContext,
    Placement,
    ResolveWarning,
    RuntimeCache,
    RuntimeCacheKey,
    SourceCircuitBreaker,
    WidgetDef
  }

  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Telemetry.Sample

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "plans Tier 0 value tile source requests without reading telemetry stores" do
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        resolve_mode: :initial,
        scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
        interaction_context: %{
          placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}
        }
      })

    assert result.dashboard_id == "dashboard_value_tile_latest"
    assert result.resolve_mode == :initial
    assert result.dashboard_warnings == []
    assert %RuntimeCacheKey{layer: :plan} = result.plan_metadata.cache.plan_key

    assert result.plan_metadata.cache.plan_key.parts.document.dashboard_id ==
             document.dashboard_id

    assert result.plan_metadata.source_request_count == 2
    assert result.plan_metadata.batched_consumer_count == 2

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)
    limits_request = request_by_source(result.planned_source_requests, :limits)
    telemetry_provenance = telemetry_request.metadata.capability_provenance
    limits_provenance = limits_request.metadata.capability_provenance

    assert telemetry_request.organization_id == document.organization_id
    assert telemetry_request.mission_id == document.mission_id
    assert telemetry_request.observables == ["tlm.hk.battery_voltage"]
    assert telemetry_request.value_type == :engineering
    assert telemetry_request.sampling.mode == :latest
    assert telemetry_request.sampling.target_points == 320
    assert telemetry_request.overlays == [:quality]
    assert telemetry_request.scope_context.primary.ids == ["sc_001"]
    assert telemetry_request.data_context.realm == "flight"
    assert %LimitContext{semantics_mode: "observed"} = telemetry_request.limit_context
    assert telemetry_provenance.logical_source == :telemetry
    assert telemetry_provenance.binding_id == "default_flight_telemetry"
    assert telemetry_provenance.data_source_id == "managed_questdb_primary"
    assert telemetry_provenance.realm == :flight
    assert telemetry_provenance.dataset == "flight"
    assert :latest in telemetry_provenance.supported_sampling
    assert is_binary(telemetry_provenance.capability_fingerprint)

    assert limits_request.organization_id == document.organization_id
    assert limits_request.mission_id == document.mission_id
    assert limits_request.observables == ["tlm.hk.battery_voltage"]
    assert limits_request.sampling.mode == :latest_state
    assert limits_request.sampling.products == [:latest_state]
    assert limits_request.overlays == []
    assert %LimitContext{semantics_mode: "observed"} = limits_request.limit_context
    assert limits_provenance.logical_source == :limits
    assert limits_provenance.binding_id == "default_flight_limits"
    assert limits_provenance.data_source_id == "managed_limits_projection"
    assert limits_provenance.dataset == "telemetry_latest_limit_states"

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement

    assert Enum.sort(placement_frames.planned_request_ids) ==
             result.planned_source_requests |> Enum.map(& &1.request_id) |> Enum.sort()
  end

  test "plans source capability posture for data-source time-axis fallback" do
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          resolve_mode: :initial,
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
        },
        data_sources: [
          telemetry_data_source("receipt-only-questdb",
            latest?: true,
            supported_time_axes: [:receipt_time]
          ),
          limits_data_source()
        ],
        data_bindings: [
          telemetry_binding("receipt-only-questdb"),
          limits_binding()
        ]
      )

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)
    posture = telemetry_request.metadata.capability_provenance.capability_posture

    assert result.dashboard_warnings == []
    assert posture.status == :fallback
    assert posture.requested_time_axis == :generation_time
    assert posture.executed_time_axis == :receipt_time
    assert posture.supported_time_axes == [:receipt_time]

    assert [
             %{
               capability: :time_axis,
               requested: :generation_time,
               executed: :receipt_time,
               reason: :unsupported_time_axis
             }
           ] = posture.fallbacks
  end

  test "normalizes dashboard defaults into typed runtime contexts" do
    document = load_fixture!("value_tile_latest.v1.json")

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document
      })

    request = request_by_source(result.planned_source_requests, :telemetry)

    assert %Cadence.Dashboards.TimeContext{mode: "live", axis: "generation_time"} =
             request.time_context

    assert request.time_context.range == %{kind: "relative", duration_ms: 1_800_000}

    assert %Cadence.Dashboards.ScopeContext{
             primary: %{kind: "spacecraft", mode: "context", ids: []}
           } = request.scope_context

    assert %DataContext{realm: "flight", source_mode: "primary"} = request.data_context
    assert request.data_context.allowed_realms == ["flight"]
    assert %LimitContext{semantics_mode: "observed"} = request.limit_context
  end

  test "plans backed operational observable status matrix requests" do
    document = %Document{
      dashboard_id: "dashboard_contact_phase",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Contact Phase",
      placements: [
        %Placement{
          placement_id: "placement_contact_phase",
          layout: %{x: nil, y: nil, w: 4, h: 3},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.status_matrix",
            widget_type_version: 1,
            title: "Contact Phase",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0, window_seconds: 300}
          }
        }
      ]
    }

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document
      })

    request = request_by_source(result.planned_source_requests, :operational_observables)

    assert request.observables == ["contacts.phase"]
    assert request.sampling.mode == :latest
    assert request.overlays == []
    assert request.metadata.capability_provenance.logical_source == :operational_observables
    refute request_by_source(result.planned_source_requests, :telemetry)
    refute request_by_source(result.planned_source_requests, :limits)
  end

  test "plans value tile requests through declared operational metric contract override" do
    document = %Document{
      dashboard_id: "dashboard_downlink_bitrate",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Downlink Bitrate",
      placements: [
        %Placement{
          placement_id: "placement_downlink_bitrate",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document
      })

    request = request_by_source(result.planned_source_requests, :operational_observables)

    assert result.dashboard_warnings == []
    assert request.observables == ["comms.transport.downlink_bitrate"]
    assert request.sampling.mode == :latest
    assert request.overlays == []
    assert request.metadata.capability_provenance.logical_source == :operational_observables
    refute request_by_source(result.planned_source_requests, :telemetry)
    refute request_by_source(result.planned_source_requests, :limits)
  end

  test "resolves stale operational observable warnings into dashboard and placement warnings" do
    document = %Document{
      dashboard_id: "dashboard_command_queue",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Command Queue",
      placements: [
        %Placement{
          placement_id: "placement_command_queue",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
            read_time: ~U[2026-06-17 12:05:00Z]
          ]
        }
      )

    assert result.plan_metadata.degraded?

    assert [
             %ResolveWarning{
               code: :stale_data,
               severity: :warning,
               scope: :dashboard
             } = dashboard_warning
           ] = result.dashboard_warnings

    assert dashboard_warning.details.supported_capability == :command_queue_depth
    assert dashboard_warning.details.observable_ids == ["commanding.queue_depth"]
    assert dashboard_warning.details.frame_ids != []

    assert %{"placement_command_queue" => placement_frames} = result.frames_by_placement

    assert [
             %ResolveWarning{
               code: :stale_data,
               severity: :warning,
               scope: :placement,
               placement_id: "placement_command_queue"
             } = placement_warning
           ] = placement_frames.warnings

    assert placement_warning.details == dashboard_warning.details

    assert [
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
           ] = placement_frames.primary

    assert [
             %Cadence.Dashboards.Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Cadence.Dashboards.Field{name: "resource_id", values: ["mission_engine"]},
             %Cadence.Dashboards.Field{name: "label", values: ["Pending commands"]},
             %Cadence.Dashboards.Field{name: "scope_kind", values: [:mission]},
             %Cadence.Dashboards.Field{name: "source_endpoint_id", values: [nil]},
             %Cadence.Dashboards.Field{name: "value", values: [0]},
             %Cadence.Dashboards.Field{name: "unit", values: ["commands"]},
             %Cadence.Dashboards.Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Cadence.Dashboards.Field{name: "freshness_state", values: [:stale]},
             %Cadence.Dashboards.Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "command queue reader failures fail closed as source unavailable" do
    document = %Document{
      dashboard_id: "dashboard_command_queue_failure",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Command Queue Failure",
      placements: [
        %Placement{
          placement_id: "placement_command_queue",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        source_result_cache?: false,
        source_opts: %{
          operational_observables: [
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
              raise "test command queue failure"
            end
          ]
        }
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.returned_frame_count == 0

    assert [
             %ResolveWarning{
               code: :source_unavailable,
               severity: :error,
               scope: :dashboard
             } = dashboard_warning
           ] = result.dashboard_warnings

    assert dashboard_warning.details.logical_source == :operational_observables
    assert dashboard_warning.details.data_source_id == "managed_operational_observables"
    assert dashboard_warning.details.source_binding_id == "default_flight_operational_observables"
    assert dashboard_warning.details.reason =~ "test command queue failure"

    assert %{"placement_command_queue" => placement_frames} = result.frames_by_placement
    assert placement_frames.primary == []

    assert [
             %ResolveWarning{
               code: :source_unavailable,
               severity: :error,
               scope: :placement,
               placement_id: "placement_command_queue"
             } = placement_warning
           ] = placement_frames.warnings

    assert placement_warning.details == dashboard_warning.details
  end

  test "operational observable source-result cache key uses source facts and freshness policy" do
    cache = start_supervised!({RuntimeCache, name: nil})
    parent = self()

    document = %Document{
      dashboard_id: "dashboard_command_queue_cache",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Command Queue Cache",
      placements: [
        %Placement{
          placement_id: "placement_command_queue",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }

    request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document
    }

    result =
      Engine.resolve(
        request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            command_queue_revision_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_command_queue_revision)
              "ops-rev-1"
            end,
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_command_queue_entries)
              []
            end,
            read_time: ~U[2026-06-17 12:05:00Z]
          ]
        }
      )

    entry = source_cache_entry_by_source(result, :operational_observables)

    assert entry.status == :miss
    assert entry.key.parts.freshness_policy == %{stale_after_ms: 1_000}
    assert entry.key.parts.source_binding.binding_id == "default_flight_operational_observables"
    assert entry.key.parts.data_source.data_source_id == "managed_operational_observables"
    assert entry.key.parts.data_revision == "ops-rev-1"

    assert_received :first_command_queue_revision
    assert_received :first_command_queue_entries

    cached =
      Engine.resolve(
        request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            command_queue_revision_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_command_queue_revision)
              "ops-rev-1"
            end,
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_command_queue_entries)
              []
            end,
            read_time: ~U[2026-06-17 12:05:00Z]
          ]
        }
      )

    cached_entry = source_cache_entry_by_source(cached, :operational_observables)

    assert cached_entry.status == :hit
    assert cached_entry.key.fingerprint == entry.key.fingerprint
    assert_received :second_command_queue_revision
    refute_received :second_command_queue_entries
  end

  test "transport bitrate source-result cache uses source-owned revision before frame reads" do
    cache = start_supervised!({RuntimeCache, name: nil})
    parent = self()

    document = %Document{
      dashboard_id: "dashboard_bitrate_cache",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Bitrate Cache",
      placements: [
        %Placement{
          placement_id: "placement_downlink_bitrate",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }

    request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document
    }

    result =
      Engine.resolve(
        request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            transport_bitrate_revision_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_transport_bitrate_revision)
              "bitrate-rev-1"
            end,
            transports_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_transports)
              []
            end,
            transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_transport_metric_snapshots)
              []
            end
          ]
        }
      )

    entry = source_cache_entry_by_source(result, :operational_observables)

    assert entry.status == :miss
    assert entry.key.parts.data_revision == "bitrate-rev-1"
    assert_received :first_transport_bitrate_revision
    assert_received :first_transports
    assert_received :first_transport_metric_snapshots

    cached =
      Engine.resolve(
        request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            transport_bitrate_revision_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_transport_bitrate_revision)
              "bitrate-rev-1"
            end,
            transports_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_transports)
              []
            end,
            transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_transport_metric_snapshots)
              []
            end
          ]
        }
      )

    cached_entry = source_cache_entry_by_source(cached, :operational_observables)

    assert cached_entry.status == :hit
    assert cached_entry.key.fingerprint == entry.key.fingerprint
    assert_received :second_transport_bitrate_revision
    refute_received :second_transports
    refute_received :second_transport_metric_snapshots
  end

  test "ingress latency source-result cache uses runtime metric revision before frame reads" do
    cache = start_supervised!({RuntimeCache, name: nil})
    parent = self()

    document = %Document{
      dashboard_id: "dashboard_ingress_latency_cache",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Ingress Latency Cache",
      placements: [
        %Placement{
          placement_id: "placement_ingress_latency",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }

    request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document
    }

    result =
      Engine.resolve(
        request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            ingress_processing_latency_revision_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_ingress_revision)
              "ingress-rev-1"
            end,
            runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :first_runtime_metric_snapshots)
              []
            end
          ]
        }
      )

    entry = source_cache_entry_by_source(result, :operational_observables)

    assert entry.status == :miss
    assert entry.key.parts.data_revision == "ingress-rev-1"
    assert_received :first_ingress_revision
    assert_received :first_runtime_metric_snapshots

    cached =
      Engine.resolve(
        request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            ingress_processing_latency_revision_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_ingress_revision)
              "ingress-rev-1"
            end,
            runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
              send(parent, :second_runtime_metric_snapshots)
              []
            end
          ]
        }
      )

    cached_entry = source_cache_entry_by_source(cached, :operational_observables)

    assert cached_entry.status == :hit
    assert cached_entry.key.fingerprint == entry.key.fingerprint
    assert_received :second_ingress_revision
    refute_received :second_runtime_metric_snapshots
  end

  test "warns when a time series requests nonmetric operational observables" do
    document = %Document{
      dashboard_id: "dashboard_operational_series",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Operational Series",
      placements: [
        %Placement{
          placement_id: "placement_operational_series",
          layout: %{x: nil, y: nil, w: 6, h: 4},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Operational Series",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :decimated_envelope,
              overlays: []
            },
            options: %{}
          }
        }
      ]
    }

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
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               scope: :dashboard,
               details: validation_details
             },
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               scope: :placement,
               placement_id: "placement_operational_series",
               details: details
             }
           ] = result.dashboard_warnings

    assert validation_details.placement_id == "placement_operational_series"
    assert details.widget_type_id == "cadence.time_series"
    assert details.requested_source == :operational_observables
    assert details.contract_source == :telemetry
    assert details.supported_products == [:transport_bitrate, :link_rf, :runtime_ingress]
    assert details.supported_value_kinds == [:metric]
    assert details.requested_products == [:contacts_phase]
    assert details.requested_value_kinds == [:state]
    assert details.unsupported_observables == ["contacts.phase"]
    assert details.fallback == :none

    assert %{"placement_operational_series" => placement_frames} = result.frames_by_placement

    assert [
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               placement_id: "placement_operational_series"
             }
           ] = placement_frames.warnings
  end

  test "resolves operational metric time series into wide primary frames" do
    document = %Document{
      dashboard_id: "dashboard_operational_metric_series",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Operational Metric Series",
      placements: [
        %Placement{
          placement_id: "placement_rf_snr_series",
          layout: %{x: nil, y: nil, w: 6, h: 4},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :raw_series,
              overlays: []
            },
            options: %{}
          }
        }
      ]
    }

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          scope_context: %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}}
        },
        source_opts: %{
          operational_observables: [
            transports_fun: fn _organization_id, _mission_id, _opts ->
              [
                %{
                  transport_id: "transport-alpha",
                  display_name: "Lab TCP",
                  adapter_key: :tcp_socket,
                  metadata: %{
                    source_endpoint_id: "endpoint-alpha",
                    ground_station_id: "dss-14",
                    link_assignment_id: "link-alpha"
                  }
                }
              ]
            end,
            link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
              [
                %{
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  ground_station_id: "dss-14",
                  link_assignment_id: "link-alpha",
                  adapter_key: :rf_adapter,
                  snr_db: 10.5,
                  observed_at: ~U[2026-06-17 12:01:00Z]
                },
                %{
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  ground_station_id: "dss-14",
                  link_assignment_id: "link-alpha",
                  adapter_key: :rf_adapter,
                  snr_db: 12.75,
                  observed_at: ~U[2026-06-17 12:02:00Z]
                }
              ]
            end
          ]
        }
      )

    assert result.dashboard_warnings == []
    assert [request] = result.planned_source_requests
    assert request.logical_source == :operational_observables
    assert request.observables == ["link.snr_db"]
    assert request.sampling.mode == :raw_series

    assert %{"placement_rf_snr_series" => placement_frames} = result.frames_by_placement

    assert [
             %Frame{
               source: :operational_observables,
               shape: :wide,
               time_axis: :occurred_at,
               meta: %{
                 supported_capability: :link_rf_metric_history,
                 observable_id: "link.snr_db",
                 resource_id: "link-alpha",
                 returned_points: 2
               }
             } = frame
           ] = placement_frames.primary

    assert [
             %Cadence.Dashboards.Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Cadence.Dashboards.Field{name: "link.snr_db", values: [10.5, 12.75]}
           ] = frame.fields
  end

  test "warns instead of planning operational observable requests for unsupported runtime scopes" do
    document = %Document{
      dashboard_id: "dashboard_transport_bitrate",
      organization_id: "org_engine",
      mission_id: "mission_engine",
      name: "Transport Bitrate",
      placements: [
        %Placement{
          placement_id: "placement_transport_bitrate",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{}
          }
        }
      ]
    }

    result =
      Engine.plan(%DashboardResolveRequest{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        scope_context: %{primary: %{kind: :mission, mode: :one, ids: ["mission_engine"]}}
      })

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?

    assert [
             %ResolveWarning{
               code: :unsupported_observable_scope,
               scope: :placement,
               placement_id: "placement_transport_bitrate",
               details: details
             }
           ] = result.dashboard_warnings

    assert details.logical_source == :operational_observables
    assert details.requested_scope_kind == :mission
    assert details.requested_scope_ids == ["mission_engine"]
    assert details.unsupported_observables == ["comms.transport.downlink_bitrate"]

    assert details.supported_scopes == %{
             "comms.transport.downlink_bitrate" => [
               :transport,
               :spacecraft,
               :contact,
               :ground_station,
               :source_endpoint,
               :link
             ]
           }

    assert details.fallback == :none

    assert %{"placement_transport_bitrate" => placement_frames} = result.frames_by_placement

    assert [
             %ResolveWarning{
               code: :unsupported_observable_scope,
               placement_id: "placement_transport_bitrate"
             }
           ] = placement_frames.warnings
  end

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

    selected_telemetry_source = %DataSource{
      DataSources.default_managed_data_source()
      | data_source_id: "selected_questdb",
        capabilities: %{latest?: true}
    }

    selected_telemetry_binding = %DataBinding{
      DataSources.default_flight_telemetry_binding()
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

  test "source result cache opt-in reuses cached adapter results" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    parent = self()

    telemetry_latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:telemetry_latest, point_id})
      telemetry_sample(mission_id, point_id)
    end

    limits_latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:limits_latest, point_id})
      limit_event(mission_id, point_id)
    end

    telemetry_watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:telemetry_watermark, point_id})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    limits_watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:limits_watermark, point_id})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun, watermark_fun: telemetry_watermark_fun],
          limits: [latest_fun: limits_latest_fun, watermark_fun: limits_watermark_fun]
        }
      )

    assert source_cache_statuses(first) == [:miss, :miss]
    telemetry_request = request_by_source(first.planned_source_requests, :telemetry)
    limits_request = request_by_source(first.planned_source_requests, :limits)
    telemetry_provenance = telemetry_request.metadata.capability_provenance
    limits_provenance = limits_request.metadata.capability_provenance

    assert source_cache_entry_by_source(first, :telemetry).capability_provenance ==
             telemetry_provenance

    assert source_cache_entry_by_source(first, :limits).capability_provenance ==
             limits_provenance

    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}
    assert_receive {:limits_latest, "tlm.hk.battery_voltage"}

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun, watermark_fun: telemetry_watermark_fun],
          limits: [latest_fun: limits_latest_fun, watermark_fun: limits_watermark_fun]
        }
      )

    assert source_cache_statuses(second) == [:hit, :hit]

    assert source_cache_entry_by_source(second, :telemetry).capability_provenance ==
             telemetry_provenance

    assert source_cache_entry_by_source(second, :limits).capability_provenance ==
             limits_provenance

    refute_receive {:telemetry_latest, _point_id}, 20
    refute_receive {:limits_latest, _point_id}, 20

    assert %{"placement_battery_voltage" => placement_frames} = second.frames_by_placement

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^telemetry_provenance}
             }
           ] = placement_frames.primary

    assert %{
             limits: [
               %Frame{
                 source: :limits,
                 meta: %{capability_provenance: ^limits_provenance}
               }
             ]
           } = placement_frames.overlays
  end

  test "source result cache preflight rejects cached result when source is degraded" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:telemetry_latest, point_id})
      telemetry_sample(mission_id, point_id)
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:telemetry_watermark, point_id})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(first) == [:miss]
    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [
            latest_fun: latest_fun,
            watermark_fun: watermark_fun,
            source_health: :degraded
          ]
        }
      )

    assert source_cache_statuses(second) == [:stale]
    assert [%{reasons: [:source_degraded]}] = source_cache_entries(second)
    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}
  end

  test "frame cache refreshes when source result preflight rejects cached result" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    counter = start_supervised!({Agent, fn -> 0 end})

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      value =
        Agent.get_and_update(counter, fn count ->
          {if(count == 0, do: 12.25, else: 99.0), count + 1}
        end)

      telemetry_sample(mission_id, point_id, value)
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(first) == [:miss]
    assert frame_cache_statuses(first) == [:miss]
    assert telemetry_latest_values(first) == [12.25]

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [
            latest_fun: latest_fun,
            watermark_fun: watermark_fun,
            source_health: :degraded
          ]
        }
      )

    assert source_cache_statuses(second) == [:stale]
    assert frame_cache_statuses(second) == [:refresh]
    assert telemetry_latest_values(second) == [99.0]
    assert Agent.get(counter, & &1) == 2
  end

  test "snapshot source and frame caches ignore moved watermark and source health" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    sample_counter =
      start_supervised!(%{id: :sample_counter, start: {Agent, :start_link, [fn -> 0 end]}})

    watermark_counter =
      start_supervised!(%{id: :watermark_counter, start: {Agent, :start_link, [fn -> 0 end]}})

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:telemetry_latest, point_id})

      value =
        Agent.get_and_update(sample_counter, fn count ->
          {if(count == 0, do: 12.25, else: 99.0), count + 1}
        end)

      telemetry_sample(mission_id, point_id, value)
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:telemetry_watermark, point_id})

      cursor =
        Agent.get_and_update(watermark_counter, fn count ->
          cursor =
            if count == 0 do
              ~U[2026-06-17 12:05:00Z]
            else
              ~U[2026-06-17 12:10:00Z]
            end

          {cursor, count + 1}
        end)

      best_effort_watermark(cursor)
    end

    request =
      resolve_request(document,
        time_context: %{
          mode: :archive,
          axis: :receipt_time,
          from: ~U[2026-06-17 12:00:00Z],
          to: ~U[2026-06-17 12:05:00Z]
        }
      )

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:10:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(first) == [:miss]
    assert frame_cache_statuses(first) == [:miss]
    assert telemetry_latest_values(first) == [12.25]
    assert [%{key: first_key}] = source_cache_entries(first)
    assert first_key.parts.cache_policy == :snapshot
    refute Map.has_key?(first_key.parts, :watermark_cursor)
    refute Map.has_key?(first_key.parts, :freshness_policy)
    assert [%{key: first_frame_key}] = frame_cache_entries(first)
    assert first_frame_key.parts.cache_policy == :snapshot
    assert first_frame_key.parts.source_result_fingerprint == first_key.fingerprint
    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}
    assert_receive {:telemetry_watermark, "tlm.hk.battery_voltage"}

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:15:00Z],
        source_opts: %{
          telemetry: [
            latest_fun: latest_fun,
            watermark_fun: watermark_fun,
            source_health: :degraded
          ]
        }
      )

    assert source_cache_statuses(second) == [:hit]
    assert frame_cache_statuses(second) == [:hit]
    assert telemetry_latest_values(second) == [12.25]
    assert [%{key: second_key}] = source_cache_entries(second)
    assert second_key.fingerprint == first_key.fingerprint
    assert [%{key: second_frame_key}] = frame_cache_entries(second)
    assert second_frame_key.fingerprint == first_frame_key.fingerprint
    assert_receive {:telemetry_watermark, "tlm.hk.battery_voltage"}
    refute_receive {:telemetry_latest, _point_id}, 20
    assert Agent.get(sample_counter, & &1) == 1
  end

  test "replay-run source and frame caches are snapshot-scoped and never labeled flight" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    latest_fun = fn _organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_latest, point_id, opts})
      telemetry_sample(mission_id, point_id)
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:telemetry_watermark, point_id, opts})
      best_effort_watermark(~U[2026-06-17 12:05:00Z])
    end

    replay_source = %DataSource{
      DataSources.default_managed_data_source()
      | data_source_id: "replay_questdb",
        capabilities: %{latest?: true, watermarks?: true}
    }

    replay_binding = %DataBinding{
      DataSources.default_flight_telemetry_binding()
      | binding_id: "replay_flight_telemetry",
        data_source_id: "replay_questdb",
        realm: :replay,
        dataset: "replay-run-1"
    }

    request =
      resolve_request(document,
        time_context: %{
          mode: :replay_run,
          axis: :generation_time,
          replay_run_id: "replay-run-1"
        },
        data_context: %{}
      )

    result =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        data_sources: [DataSources.default_managed_data_source(), replay_source],
        data_bindings: [DataSources.default_flight_telemetry_binding(), replay_binding],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(result) == [:miss]
    assert frame_cache_statuses(result) == [:miss]

    assert [%{key: source_key}] = source_cache_entries(result)
    assert source_key.parts.cache_policy == :snapshot
    refute Map.has_key?(source_key.parts, :watermark_cursor)
    refute Map.has_key?(source_key.parts, :freshness_policy)
    assert source_key.parts.source_binding.realm == :replay
    assert source_key.parts.request.time_context.replay_run_id == "replay-run-1"

    assert [%{key: frame_key}] = frame_cache_entries(result)
    assert frame_key.parts.cache_policy == :snapshot
    assert frame_key.parts.source_result_binding.realm == :replay

    assert %Frame{meta: meta} =
             result.frames_by_placement["placement_battery_voltage"].primary |> List.first()

    assert meta.realm == :replay
    assert meta.dataset == "replay-run-1"
    assert meta.replay_run_id == "replay-run-1"
    assert meta.source_request_context.requested_realm == :replay
    assert meta.source_request_context.time_mode == :replay_run
    refute meta.realm == :flight

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)

    assert %{
             requested_realm: :replay,
             requested_time_mode: :replay_run,
             replay_run_id: "replay-run-1",
             selected_source_binding_id: "replay_flight_telemetry",
             selected_data_source_id: "replay_questdb",
             selected_dataset: "replay-run-1"
           } = result.plan_metadata.source_selection_by_request_id[telemetry_request.request_id]

    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage", telemetry_opts}
    assert telemetry_opts[:data_source_id] == "replay_questdb"
    assert telemetry_opts[:dataset] == "replay-run-1"

    assert_receive {:telemetry_watermark, "tlm.hk.battery_voltage", watermark_opts}
    assert watermark_opts[:data_source_id] == "replay_questdb"
    assert watermark_opts[:dataset] == "replay-run-1"
  end

  test "frame cache opt-in reuses materialized frames" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    counter = start_supervised!({Agent, fn -> 0 end})

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      value =
        Agent.get_and_update(counter, fn count ->
          value =
            case count do
              0 -> 12.25
              _count -> 99.0
            end

          {value, count + 1}
        end)

      telemetry_sample(mission_id, point_id, value)
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert frame_cache_statuses(first) == [:miss]
    telemetry_request = request_by_source(first.planned_source_requests, :telemetry)
    telemetry_provenance = telemetry_request.metadata.capability_provenance
    assert [%{capability_provenance: ^telemetry_provenance}] = frame_cache_entries(first)
    assert telemetry_latest_values(first) == [12.25]

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^telemetry_provenance}
             }
           ] = first.frames_by_placement["placement_battery_voltage"].primary

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert frame_cache_statuses(second) == [:hit]
    assert [%{capability_provenance: ^telemetry_provenance}] = frame_cache_entries(second)
    assert telemetry_latest_values(second) == [12.25]

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^telemetry_provenance}
             }
           ] = second.frames_by_placement["placement_battery_voltage"].primary

    assert Agent.get(counter, & &1) == 2
  end

  test "source execution timeouts degrade the timed-out request while other requests complete" do
    document = mixed_telemetry_execution_document()
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    result =
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{
          telemetry: [
            test_pid: self(),
            sleep_ms_by_sampling: %{latest: 75}
          ]
        },
        source_execution_timeout_ms: 20,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_circuit_failure_threshold: 1,
        source_circuit_backoff_ms: 60_000
      )

    assert result.plan_metadata.source_execution_policy == %{
             max_concurrency: 2,
             timeout_ms: 20
           }

    source_policies = Map.values(result.plan_metadata.source_execution_policies_by_request_id)
    assert length(source_policies) == 2
    assert Enum.all?(source_policies, &(&1.timeout_ms == 20))
    assert Enum.all?(source_policies, &(&1.circuit_failure_threshold == 1))
    assert Enum.all?(source_policies, & &1.provenance.explicit_opts?)

    assert result.plan_metadata.executed_source_request_count == 2
    assert result.plan_metadata.degraded?
    assert source_cache_statuses(result) == [:disabled, :source_execution_failed]

    assert Enum.any?(result.dashboard_warnings, fn warning ->
             warning.code == :source_unavailable and
               warning.details.reason == "timeout after 20ms" and
               warning.details.data_source_id == "flight-questdb"
           end)

    assert %{state: :open, failure_count: 1} =
             SourceCircuitBreaker.status(
               breaker,
               {"org_dashboards", "mission_dashboards", :telemetry, "flight-questdb", :flight,
                "flight"},
               []
             )

    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}
    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :raw_series}
  end

  test "source execution uses binding timeout policy before global timeout" do
    document = mixed_telemetry_execution_document()
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    binding = %DataBinding{
      telemetry_binding("flight-questdb")
      | metadata: %{
          dashboard_policy: %{
            execution: %{timeout_ms: 20},
            circuit_breaker: %{failure_threshold: 1, backoff_ms: 15_000}
          }
        }
    }

    result =
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [binding],
        source_opts: %{
          telemetry: [
            test_pid: self(),
            sleep_ms_by_sampling: %{latest: 75}
          ]
        },
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker
      )

    assert result.plan_metadata.source_execution_policy == %{
             max_concurrency: 2,
             timeout_ms: 5_000
           }

    source_policies = Map.values(result.plan_metadata.source_execution_policies_by_request_id)
    assert length(source_policies) == 2
    assert Enum.all?(source_policies, &(&1.timeout_ms == 20))
    assert Enum.all?(source_policies, &(&1.circuit_failure_threshold == 1))
    assert Enum.all?(source_policies, &(&1.circuit_backoff_ms == 15_000))
    assert Enum.all?(source_policies, & &1.provenance.binding_policy?)

    assert result.plan_metadata.degraded?
    assert source_cache_statuses(result) == [:disabled, :source_execution_failed]

    assert Enum.any?(result.dashboard_warnings, fn warning ->
             warning.code == :source_unavailable and
               warning.details.reason == "timeout after 20ms" and
               warning.details.data_source_id == "flight-questdb"
           end)

    assert %{state: :open, failure_count: 1, failure_threshold: 1, backoff_ms: 15_000} =
             SourceCircuitBreaker.status(
               breaker,
               {"org_dashboards", "mission_dashboards", :telemetry, "flight-questdb", :flight,
                "flight"},
               failure_threshold: 1,
               backoff_ms: 15_000
             )
  end

  test "source execution policy caps concurrent adapter resolves" do
    document = mixed_telemetry_execution_document()
    concurrency_agent = start_supervised!({Agent, fn -> %{current: 0, max: 0} end})

    result =
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{
          telemetry: [
            test_pid: self(),
            sleep_ms: 40,
            concurrency_agent: concurrency_agent
          ]
        },
        source_execution_timeout_ms: 500,
        source_execution_max_concurrency: 1
      )

    assert result.plan_metadata.executed_source_request_count == 2
    refute result.plan_metadata.degraded?
    assert Agent.get(concurrency_agent, & &1.max) == 1

    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}
    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :raw_series}
  end

  test "validation mode rejects malformed source results at the adapter boundary" do
    document = mixed_telemetry_execution_document()

    assert_raise ArgumentError, ~r/dashboard source_result contract violated/, fn ->
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{telemetry: [mode: :invalid_result]},
        source_execution_max_concurrency: 1,
        source_execution_timeout_ms: :infinity,
        validate_dashboard_contract?: true
      )
    end
  end

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

  defp resolve_request(%Document{} = document, overrides \\ []) do
    attrs =
      %{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
      }

    struct!(DashboardResolveRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp source_cache_entries(result) do
    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> Map.values()
  end

  defp source_cache_statuses(result) do
    result
    |> source_cache_entries()
    |> Enum.map(& &1.status)
    |> Enum.sort()
  end

  defp source_cache_entry_by_source(result, logical_source) do
    request = request_by_source(result.planned_source_requests, logical_source)

    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> Map.fetch!(request.request_id)
  end

  defp frame_cache_entries(result) do
    result.plan_metadata
    |> get_in([:cache, :frame_cache_by_placement])
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
  end

  defp frame_cache_statuses(result) do
    result
    |> frame_cache_entries()
    |> Enum.map(& &1.status)
    |> Enum.sort()
  end

  defp telemetry_latest_values(result) do
    result.frames_by_placement
    |> Map.fetch!("placement_battery_voltage")
    |> Map.fetch!(:primary)
    |> List.first()
    |> Map.fetch!(:fields)
    |> Enum.find(&(&1.name == "tlm.hk.battery_voltage"))
    |> Map.fetch!(:values)
  end

  defp telemetry_sample(mission_id, point_id, value \\ 12.25) do
    %Sample{
      sample_id: "sample-cache-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp limit_event(mission_id, point_id) do
    %Event{
      limit_event_id: "limit-cache-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-cache-1",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 12.25,
      limit_state: :green,
      normalized_state: :green,
      violation: false,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp limit_definition_interval(mission_id, point_id) do
    %DefinitionInterval{
      definition_activation_key: "limit-activation-cache-1",
      limit_definition_lifecycle_event_id: "limit-lifecycle-cache-1",
      organization_id: "org_dashboards",
      mission_id: mission_id,
      point_id: point_id,
      limit_set_name: "ops",
      event_type: :registered,
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      active_from: ~U[2026-06-17 12:00:00Z],
      active_to: nil,
      observed_at: ~U[2026-06-17 12:00:00Z],
      thresholds: %{"yellow_high" => 15, "red_high" => 25},
      metadata: %{},
      complete?: true
    }
  end

  defp best_effort_watermark(cursor) do
    {:ok,
     %{
       complete_through: cursor,
       latest_receipt_time: cursor,
       retention_starts_at: ~U[2026-06-17 11:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  defp request_by_source(requests, logical_source) do
    Enum.find(requests, &(&1.logical_source == logical_source))
  end

  defp request_by_source_product(requests, logical_source, product) do
    Enum.find(requests, fn request ->
      request.logical_source == logical_source and
        product in Map.get(request.sampling, :products, [])
    end)
  end

  defp telemetry_data_source(data_source_id, capabilities) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: Map.new(capabilities)
    }
  end

  defp test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  defp limits_data_source do
    %DataSource{
      data_source_id: "managed_limits_projection",
      adapter: Cadence.Dashboards.Sources.Limits,
      kind: :projection,
      capabilities: %{latest_state?: true, event_history?: true, definition_intervals?: true}
    }
  end

  defp events_data_source do
    %DataSource{
      data_source_id: "managed_events_projection",
      adapter: Cadence.Dashboards.Sources.Events,
      kind: :projection,
      capabilities: %{
        contact_intervals?: true,
        mission_timeline?: true,
        source_health_transitions?: true
      }
    }
  end

  defp telemetry_binding(data_source_id, realm \\ :flight) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm)
    }
  end

  defp limits_binding(realm \\ :flight) do
    %DataBinding{
      binding_id: "flight-limits",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :limits,
      data_source_id: "managed_limits_projection",
      dataset: "telemetry_latest_limit_states"
    }
  end

  defp events_binding(realm \\ :flight) do
    %DataBinding{
      binding_id: "flight-events",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :events,
      data_source_id: "managed_events_projection",
      dataset: "mission_events"
    }
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp mixed_latest_and_history_document do
    latest_attrs = load_fixture_map!("value_tile_latest.v1.json")
    [latest_placement] = latest_attrs["placements"]
    [history_placement] = load_fixture_map!("time_series_with_limits.v1.json")["placements"]

    history_placement =
      put_in(history_placement, ["content", "widget_def", "binding", "sampling"], "raw_series")

    latest_attrs
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  defp mixed_telemetry_execution_document do
    latest_attrs = load_fixture_map!("value_tile_latest.v1.json")
    [latest_placement] = latest_attrs["placements"]
    [history_placement] = load_fixture_map!("time_series_with_limits.v1.json")["placements"]

    latest_placement =
      put_in(latest_placement, ["content", "widget_def", "binding", "overlays"], [])

    history_placement =
      history_placement
      |> put_in(["content", "widget_def", "binding", "sampling"], "raw_series")
      |> put_in(["content", "widget_def", "binding", "overlays"], [])

    latest_attrs
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  defp load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
