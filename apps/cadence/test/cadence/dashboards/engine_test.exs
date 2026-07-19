defmodule Cadence.Dashboards.EngineTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.EngineFixtures

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataContext,
    Document,
    Engine,
    Frame,
    LimitContext,
    Placement,
    ResolveWarning,
    RuntimeCache,
    RuntimeCacheKey,
    WidgetDef
  }

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
end
