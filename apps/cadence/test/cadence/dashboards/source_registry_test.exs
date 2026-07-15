defmodule Cadence.Dashboards.SourceRegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    EvidenceRef,
    Field,
    Frame,
    PlannedSourceRequest,
    SourceCapabilities,
    SourceCircuitBreaker,
    SourceExecutionPolicy,
    SourceFacts,
    SourceHealthEvent,
    SourceHealthStatus,
    SourceRegistry
  }

  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Telemetry.Sample

  test "returns telemetry adapter capabilities" do
    assert %SourceCapabilities{} = capabilities = SourceRegistry.capabilities(:telemetry)

    assert capabilities.logical_source == :telemetry

    assert capabilities.supported_sampling == [
             :latest,
             :raw_series,
             :bounded_history,
             :bounded_raw_series
           ]

    assert SourceCapabilities.supports_sampling?(capabilities, :latest)
    refute SourceCapabilities.supports_sampling?(capabilities, :decimated_envelope)
  end

  test "returns limits adapter capabilities" do
    assert %SourceCapabilities{} = capabilities = SourceRegistry.capabilities(:limits)

    assert capabilities.logical_source == :limits

    assert capabilities.supported_sampling == [
             :latest_state,
             :latest,
             :event_history,
             :definition_intervals,
             :analysis_buckets
           ]

    assert capabilities.supported_products == [
             :latest_state,
             :event_history,
             :definition_intervals,
             :analysis_buckets
           ]
  end

  test "returns operational observables adapter capabilities" do
    assert %SourceCapabilities{} =
             capabilities =
             SourceRegistry.capabilities(:operational_observables)

    assert capabilities.logical_source == :operational_observables

    assert capabilities.supported_sampling == [
             :constellation_health,
             :latest,
             :event_history,
             :raw_series
           ]

    assert capabilities.supported_products == [
             :constellation_health,
             :contacts_phase,
             :contacts_phase_history,
             :connection_state,
             :connection_state_history,
             :ground_station_antenna_pointing_state,
             :ground_station_antenna_pointing_state_history,
             :link_rf_lock_state,
             :link_rf_lock_state_history,
             :link_rf_frame_sync_state,
             :link_rf_frame_sync_state_history,
             :link_rf_metric,
             :link_rf_metric_history,
             :transport_bitrate,
             :transport_bitrate_history,
             :transport_execution_state_history,
             :managed_runtime_activity_history,
             :transport_runtime_activity_history,
             :ingress_processing_latency_history,
             :operational_metric_history,
             :operational_latest,
             :operational_state_history,
             :command_queue_depth,
             :ingress_processing_latency
           ]

    assert capabilities.supported_shapes == [:matrix, :events, :wide]
    assert "contacts.phase" in capabilities.metadata.observable_ids
    assert "comms.transport.downlink_bitrate" in capabilities.metadata.backed_observable_ids
    assert "comms.transport.connection_state" in capabilities.metadata.backed_observable_ids
    assert "ground.station.connection_state" in capabilities.metadata.backed_observable_ids
    assert "ground.station.antenna_pointing_state" in capabilities.metadata.backed_observable_ids
    assert "link.rf_lock_state" in capabilities.metadata.backed_observable_ids
    assert "link.frame_sync_state" in capabilities.metadata.backed_observable_ids
    assert "link.snr_db" in capabilities.metadata.backed_observable_ids
    assert "link.symbol_rate_sps" in capabilities.metadata.backed_observable_ids
    assert "link.doppler_hz" in capabilities.metadata.backed_observable_ids
    assert "commanding.queue_depth" in capabilities.metadata.backed_observable_ids
    assert "runtime.managed_activity" in capabilities.metadata.backed_observable_ids
    assert "runtime.transport_activity" in capabilities.metadata.backed_observable_ids
    assert "ingress.processing_latency_ms" in capabilities.metadata.backed_observable_ids

    assert capabilities.metadata.metric_history_contracts == [
             %{
               observables: [
                 "link.snr_db",
                 "link.eb_n0_db",
                 "link.symbol_rate_sps",
                 "link.doppler_hz"
               ],
               product: :link_rf_metric_history,
               product_family: :link_rf
             },
             %{
               observables: [
                 "comms.transport.downlink_bitrate",
                 "comms.transport.uplink_bitrate"
               ],
               product: :transport_bitrate_history,
               product_family: :transport_bitrate
             },
             %{
               observables: ["ingress.processing_latency_ms"],
               product: :ingress_processing_latency_history,
               product_family: :runtime_ingress
             }
           ]
  end

  test "returns events adapter capabilities" do
    assert %SourceCapabilities{} = capabilities = SourceRegistry.capabilities(:events)

    assert capabilities.logical_source == :events
    assert capabilities.supported_sampling == [:event_history]

    assert capabilities.supported_products == [
             :contact_intervals,
             :mission_timeline,
             :source_health_transitions,
             :source_watermark_events,
             :source_capability_postures,
             :telemetry_backfill_lifecycle,
             :telemetry_revision_decisions
           ]

    assert capabilities.supported_shapes == [:intervals, :events]
    assert capabilities.completeness == :partial
  end

  test "returns nil for unknown logical sources" do
    assert SourceRegistry.capabilities(:commands) == nil
  end

  test "merges request data source capabilities into adapter capabilities" do
    assert {:ok, %SourceCapabilities{} = capabilities} =
             SourceRegistry.capabilities(source_request(sampling: %{mode: :decimated_envelope}),
               data_sources: [
                 data_source("native-decimating-questdb",
                   native_decimation?: true,
                   watermarks?: true
                 )
               ],
               data_bindings: [data_binding("native-decimating-questdb")]
             )

    assert SourceCapabilities.supports_sampling?(capabilities, :decimated_envelope)
    assert capabilities.supports_watermarks?

    assert capabilities.metadata.data_source_capabilities == %{
             native_decimation?: true,
             watermarks?: true
           }
  end

  test "data source capabilities can narrow supported time axes" do
    assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
             SourceRegistry.capability_context(
               source_request(time_context: %{axis: :generation_time}),
               data_sources: [
                 data_source("receipt-only-questdb",
                   supported_time_axes: [:receipt_time],
                   range_scan?: true
                 )
               ],
               data_bindings: [data_binding("receipt-only-questdb")]
             )

    assert capabilities.supported_time_axes == [:receipt_time]
    assert provenance.supported_time_axes == [:receipt_time]
    assert provenance.capability_posture.status == :fallback
    assert provenance.capability_posture.requested_time_axis == :generation_time
    assert provenance.capability_posture.executed_time_axis == :receipt_time
    assert provenance.capability_posture.supported_time_axes == [:receipt_time]

    assert [
             %{
               capability: :time_axis,
               requested: :generation_time,
               executed: :receipt_time,
               reason: :unsupported_time_axis
             }
           ] = provenance.capability_posture.fallbacks

    assert capabilities.metadata.data_source_capabilities == %{
             range_scan?: true,
             supported_time_axes: [:receipt_time]
           }
  end

  test "data source capabilities can narrow supported products" do
    assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
             SourceRegistry.capability_context(
               source_request(),
               data_sources: [
                 data_source("latest-value-only-questdb",
                   supported_products: [:latest_value],
                   range_scan?: true
                 )
               ],
               data_bindings: [data_binding("latest-value-only-questdb")]
             )

    assert capabilities.supported_products == [:latest_value]
    assert provenance.supported_products == [:latest_value]

    assert capabilities.metadata.data_source_capabilities == %{
             range_scan?: true,
             supported_products: [:latest_value]
           }
  end

  test "capability posture reports unsupported requested products" do
    assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
             SourceRegistry.capability_context(
               source_request(
                 sampling: %{
                   mode: :raw_series,
                   products: [:bounded_generation_time_history]
                 }
               ),
               data_sources: [
                 data_source("latest-value-only-questdb",
                   supported_products: [:latest_value],
                   range_scan?: true
                 )
               ],
               data_bindings: [data_binding("latest-value-only-questdb")]
             )

    assert capabilities.supported_sampling == [
             :latest,
             :raw_series,
             :bounded_history,
             :bounded_raw_series
           ]

    assert provenance.supported_products == [:latest_value]
    assert provenance.capability_posture.status == :unsupported
    assert provenance.capability_posture.requested_products == [:bounded_generation_time_history]
    assert provenance.capability_posture.supported_products == [:latest_value]

    assert [
             %{
               capability: :products,
               requested: [:bounded_generation_time_history],
               supported: [:latest_value],
               missing: [:bounded_generation_time_history],
               fallback: :none
             }
           ] = provenance.capability_posture.unsupported
  end

  test "operational capability posture uses source backing contracts for latest products" do
    request =
      source_request(
        logical_source: :operational_observables,
        observables: ["link.snr_db"],
        sampling: %{mode: :latest, products: [:link_rf]}
      )

    operational_source = %{
      DataSources.default_operational_observables_data_source()
      | capabilities: %{supported_products: [:operational_latest]}
    }

    assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
             SourceRegistry.capability_context(request,
               data_sources: [operational_source],
               data_bindings: [DataSources.default_flight_operational_observables_binding()]
             )

    assert capabilities.supported_products == [:operational_latest]
    assert provenance.capability_posture.status == :native
    assert provenance.capability_posture.requested_products == [:link_rf_metric]
    assert provenance.capability_posture.supported_products == [:operational_latest]
    refute Map.has_key?(provenance.capability_posture, :unsupported)
  end

  test "operational capability posture reports aggregate state-history source products" do
    request =
      source_request(
        logical_source: :operational_observables,
        observables: [
          "comms.transport.connection_state",
          "ground.station.antenna_pointing_state"
        ],
        sampling: %{mode: :event_history, products: [:event_history]}
      )

    operational_source = %{
      DataSources.default_operational_observables_data_source()
      | capabilities: %{supported_products: [:connection_state_history]}
    }

    assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
             SourceRegistry.capability_context(request,
               data_sources: [operational_source],
               data_bindings: [DataSources.default_flight_operational_observables_binding()]
             )

    assert capabilities.supported_products == [:connection_state_history]
    assert provenance.capability_posture.status == :unsupported
    assert provenance.capability_posture.requested_products == [:operational_state_history]
    assert provenance.capability_posture.supported_products == [:connection_state_history]

    assert [
             %{
               capability: :products,
               requested: [:operational_state_history],
               supported: [:connection_state_history],
               missing: [:operational_state_history],
               fallback: :none
             }
           ] = provenance.capability_posture.unsupported
  end

  test "source facts carry request-local capability posture" do
    request = source_request(time_context: %{axis: :generation_time})

    assert {:ok, %SourceFacts{} = facts} =
             SourceRegistry.facts(request,
               data_sources: [
                 data_source("receipt-only-questdb",
                   supported_time_axes: [:receipt_time],
                   range_scan?: true
                 )
               ],
               data_bindings: [data_binding("receipt-only-questdb")]
             )

    assert facts.meta.capability_posture.status == :fallback
    assert facts.meta.capability_posture.requested_time_axis == :generation_time
    assert facts.meta.capability_posture.executed_time_axis == :receipt_time
    assert facts.meta.capability_posture.supported_time_axes == [:receipt_time]
    assert facts.meta.capability_provenance.capability_posture == facts.meta.capability_posture
  end

  test "returns capability provenance for request-aware planning" do
    assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
             SourceRegistry.capability_context(
               source_request(sampling: %{mode: :decimated_envelope}),
               data_sources: [
                 data_source("native-decimating-questdb",
                   native_decimation?: true,
                   watermarks?: true
                 )
               ],
               data_bindings: [data_binding("native-decimating-questdb")]
             )

    assert SourceCapabilities.supports_sampling?(capabilities, :decimated_envelope)
    assert provenance.logical_source == :telemetry
    assert provenance.binding_id == "flight-telemetry"
    assert provenance.data_source_id == "native-decimating-questdb"
    assert provenance.realm == :flight
    assert provenance.dataset == "flight"
    assert Map.get(provenance, :supports_watermarks?)
    assert :decimated_envelope in provenance.supported_sampling
    assert provenance.data_source_capabilities == %{native_decimation?: true, watermarks?: true}
    assert is_binary(provenance.capability_fingerprint)
  end

  test "request-aware capability context is normalized for every production source adapter" do
    opts = production_source_registry_opts()

    for contract <- production_source_contracts() do
      request =
        production_source_request(contract.logical_source, contract.sampling_mode)

      assert %SourceCapabilities{} =
               adapter_capabilities =
               SourceRegistry.capabilities(contract.logical_source,
                 validate_dashboard_contract?: true
               )

      assert {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} =
               SourceRegistry.capability_context(request, opts)

      assert adapter_capabilities.logical_source == contract.logical_source
      assert adapter_capabilities.supported_products == contract.adapter_supported_products
      assert adapter_capabilities.supported_time_axes == contract.supported_time_axes
      assert adapter_capabilities.supported_value_types == contract.supported_value_types
      assert adapter_capabilities.supported_shapes == contract.supported_shapes
      assert adapter_capabilities.completeness == contract.completeness

      assert capabilities.logical_source == contract.logical_source
      assert SourceCapabilities.supports_sampling?(capabilities, contract.sampling_mode)
      assert capabilities.supports_watermarks? == contract.supports_watermarks?
      assert capabilities.supported_products == contract.adapter_supported_products
      assert capabilities.supported_time_axes == contract.supported_time_axes
      assert capabilities.supported_value_types == contract.supported_value_types
      assert capabilities.supported_shapes == contract.supported_shapes
      assert capabilities.completeness == contract.completeness
      assert is_map(capabilities.metadata.data_source_capabilities)

      assert provenance.logical_source == contract.logical_source
      assert provenance.binding_id == contract.binding_id
      assert provenance.data_source_id == contract.data_source_id
      assert provenance.realm == :flight
      assert provenance.dataset == contract.dataset
      assert provenance.supports_watermarks? == contract.supports_watermarks?
      assert contract.sampling_mode in provenance.supported_sampling
      assert provenance.supported_products == contract.adapter_supported_products
      assert provenance.supported_time_axes == contract.supported_time_axes
      assert provenance.supported_value_types == contract.supported_value_types
      assert provenance.supported_shapes == contract.supported_shapes
      assert provenance.completeness == contract.completeness
      assert provenance.data_source_capabilities == capabilities.metadata.data_source_capabilities
      assert is_binary(provenance.capability_fingerprint)
    end
  end

  test "request-aware capability fingerprints are stable and data-source sensitive" do
    opts = production_source_registry_opts()

    for contract <- production_source_contracts() do
      request = production_source_request(contract.logical_source, contract.sampling_mode)

      assert {:ok, %{provenance: first_provenance}} =
               SourceRegistry.capability_context(request, opts)

      assert {:ok, %{provenance: second_provenance}} =
               SourceRegistry.capability_context(request, opts)

      changed_opts =
        opts
        |> Keyword.replace!(:data_sources, [
          capability_variant_data_source(contract.logical_source)
          | opts
            |> Keyword.fetch!(:data_sources)
            |> Enum.reject(&(&1.data_source_id == contract.data_source_id))
        ])

      assert {:ok, %{provenance: changed_provenance}} =
               SourceRegistry.capability_context(request, changed_opts)

      assert first_provenance.capability_fingerprint == second_provenance.capability_fingerprint
      refute first_provenance.capability_fingerprint == changed_provenance.capability_fingerprint

      assert first_provenance.data_source_capabilities !=
               changed_provenance.data_source_capabilities
    end
  end

  test "returns binding warnings for request-aware capability lookup" do
    assert {:error, warning} =
             SourceRegistry.capabilities(source_request(),
               data_sources: [],
               data_bindings: []
             )

    assert warning.code == :missing_source_binding
    assert warning.details.logical_source == :telemetry
  end

  test "binding warnings carry replay request context into actions" do
    assert {:error, warning} =
             SourceRegistry.capabilities(replay_source_request(),
               data_sources: [],
               data_bindings: []
             )

    assert warning.code == :missing_replay_source_binding
    assert warning.details.time_mode == :replay_run
    assert warning.details.time_axis == :receipt_time
    assert warning.details.replay_run_id == "replay-run-1"
    assert warning.details.requested_realm == :replay

    assert Enum.any?(warning.details.actions, fn action ->
             action.target == :source_inventory and
               action.context.replay_run_id == "replay-run-1" and
               action.context.time_mode == :replay_run
           end)
  end

  test "strict validation rejects malformed planned source requests before registry lookup" do
    request = %PlannedSourceRequest{
      request_id: "",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :bad_source,
      observables: ["HK.counter"],
      sampling: %{mode: :raw_series}
    }

    assert_raise ArgumentError, ~r/dashboard planned_source_request contract violated/, fn ->
      SourceRegistry.resolve(request, validate_dashboard_contract?: true)
    end
  end

  test "strict validation rejects malformed adapter capabilities" do
    assert_raise ArgumentError, ~r/dashboard source_capabilities contract violated/, fn ->
      SourceRegistry.capabilities(:telemetry,
        adapters: %{telemetry: Cadence.Support.DashboardInvalidCapabilitiesAdapter},
        validate_dashboard_contract?: true
      )
    end
  end

  test "strict validation rejects malformed adapter facts" do
    assert_raise ArgumentError, ~r/dashboard source_facts contract violated/, fn ->
      SourceRegistry.facts(source_request(),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [data_binding("flight-questdb")],
        source_opts: %{telemetry: [facts_mode: :invalid]},
        validate_dashboard_contract?: true
      )
    end
  end

  test "strict validation rejects malformed adapter source results" do
    assert_raise ArgumentError, ~r/dashboard source_result contract violated/, fn ->
      SourceRegistry.resolve(source_request(),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [data_binding("flight-questdb")],
        source_opts: %{telemetry: [mode: :invalid_result]},
        validate_dashboard_contract?: true
      )
    end
  end

  test "enriches telemetry frames with selected operational interval evidence" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})
      [sample(point_id, "sample-1", 42, selected_at, "evidence-1")]
    end

    result =
      SourceRegistry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "source_endpoint", mode: "one", ids: ["endpoint-alpha"]}
          },
          sampling: %{mode: :raw_series, max_raw_points: 25}
        ),
        data_sources: [data_source("flight-questdb", range_scan?: true)],
        data_bindings: [data_binding("flight-questdb")],
        source_opts: %{telemetry: [history_fun: history_fun]},
        persisted?: true,
        source_binding_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          [effective_interval(:binding_set, "binding-set-interval-1", "runtime-apps")]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "application-binding-interval-1",
              "runtime-apps-packet-counter-rule"
            )
          ]
        end,
        catalog_revision_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:catalog_revision_intervals, organization_id, mission_id, opts})
          [effective_interval(:catalog_revision, "catalog-revision-interval-1", "catalog-rev-a")]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "binding-set-interval-1", kind: :binding_set},
             %{interval_id: "application-binding-interval-1", kind: :application_binding},
             %{interval_id: "catalog-revision-interval-1", kind: :catalog_revision}
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(frame.meta.evidence, :binding_set_interval, "binding-set-interval-1")

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "application-binding-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :catalog_revision_interval,
             "catalog-revision-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :operational_interval,
             "source-event-binding-set-interval-1"
           )

    assert evidence_ref(frame.meta.evidence, :source_binding, "flight-telemetry")

    assert [%Field{name: "time"}, %Field{name: "HK.counter"} = value_field] = frame.fields

    assert value_field.metadata.links
           |> hd()
           |> Map.fetch!(:context)
           |> get_in([:data, :source_binding_id]) == "flight-telemetry"

    assert_receive {:history, "org-1", "mission-1", "HK.counter", history_opts}
    assert history_opts[:from_receipt_time] == from_time
    assert history_opts[:to_receipt_time] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"

    assert_receive {:catalog_revision_intervals, "org-1", "mission-1", catalog_opts}
    assert catalog_opts[:at] == selected_at
    assert catalog_opts[:catalog_family] == :telemetry
  end

  test "enriches limits frames with selected catalog revision interval evidence" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_latest, organization_id, mission_id, point_id, opts})

      limit_event(point_id,
        receipt_time: selected_at,
        generation_time: selected_at,
        normalized_state: :yellow,
        limit_state: :yellow_high,
        violation: true
      )
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_intervals, organization_id, mission_id, point_id, opts})

      [
        limit_definition_interval(point_id,
          active_from: ~U[2026-06-21 20:00:00Z],
          active_to: nil
        )
      ]
    end

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :limits,
          observables: ["HK.counter"],
          sampling: %{mode: :latest_state},
          time_context: %{axis: :receipt_time, to: selected_at},
          scope_context: %{
            organization_id: "org-1",
            mission_id: "mission-1",
            primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
          }
        ),
        source_opts: %{limits: [latest_fun: latest_fun, interval_fun: interval_fun]},
        data_sources: [capability_variant_data_source(:limits)],
        data_bindings: [DataSources.default_flight_limits_binding()],
        persisted?: true,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          []
        end,
        catalog_revision_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:catalog_revision_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :catalog_revision,
              "limits-catalog-revision-interval-1",
              "catalog-rev-limits"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.source == :limits
    assert frame.meta.logical_source == :limits
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "limits-catalog-revision-interval-1", kind: :catalog_revision}
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :catalog_revision_interval,
             "limits-catalog-revision-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :operational_interval,
             "source-event-limits-catalog-revision-interval-1"
           )

    assert evidence_ref(frame.meta.evidence, :source_binding, "default_flight_limits")
    assert evidence_ref(frame.meta.evidence, :limit_event, "limit-event-1")

    assert_receive {:limits_latest, "org-1", "mission-1", "HK.counter", latest_opts}
    assert latest_opts[:data_source_id] == "managed_limits_projection"
    assert latest_opts[:dataset] == "telemetry_latest_limit_states"

    assert_receive {:limits_intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:data_source_id] == "managed_limits_projection"

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:catalog_revision_intervals, "org-1", "mission-1", catalog_opts}
    assert catalog_opts[:at] == selected_at
    assert catalog_opts[:catalog_family] == :telemetry
  end

  test "enriches operational metric-history frames with selected operational interval evidence" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["link.snr_db"],
          sampling: %{mode: :raw_series, max_raw_points: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "link", mode: "one", ids: ["link-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            transports_fun: fn organization_id, mission_id, opts ->
              send(parent, {:metric_history_transports, organization_id, mission_id, opts})

              [
                %{
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  ground_station_id: "dss-14",
                  link_assignment_id: "link-alpha",
                  display_name: "Transport Alpha"
                }
              ]
            end,
            link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:link_rf_metric_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "link.snr_db",
                  resource_id: "link-alpha",
                  link_id: "link-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  value: 12.5,
                  snr_db: 12.5,
                  unit: "dB",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:snr-sample-1"
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          [effective_interval(:binding_set, "metric-binding-set-interval-1", "runtime-apps")]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "metric-application-binding-interval-1",
              "runtime-apps-link-rule"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.logical_source == :operational_observables
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "metric-binding-set-interval-1", kind: :binding_set},
             %{interval_id: "metric-application-binding-interval-1", kind: :application_binding}
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :binding_set_interval,
             "metric-binding-set-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "metric-application-binding-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :operational_interval,
             "source-event-metric-binding-set-interval-1"
           )

    assert_receive {:metric_history_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:from] == from_time
    assert transport_opts[:to] == to_time

    assert_receive {:link_rf_metric_snapshots, "org-1", "mission-1", snapshot_opts}
    assert snapshot_opts[:from] == from_time
    assert snapshot_opts[:to] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"
  end

  test "enriches operational observable frames with source-health interval evidence" do
    parent = self()
    observed_at = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
    source_health_event_id = "source-health-operational-observables-1"
    operational_event_id = "operational_event:source_health_event:#{source_health_event_id}"

    status =
      source_health_status(%{
        source_health_event_id: source_health_event_id,
        source_health: :degraded,
        reason: :source_probe_failed,
        observed_at: observed_at,
        last_seen_at: observed_at
      })

    source_health_interval = %EffectiveInterval{
      interval_id: "effective_interval:source_health:#{operational_event_id}",
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: :source_health,
      subject_kind: :data_source,
      subject_id: "managed_operational_observables",
      starts_at: observed_at,
      source_event_id: operational_event_id,
      payload: %{
        "source_health_event_id" => source_health_event_id,
        "source_health" => "degraded",
        "reason" => "source_probe_failed"
      }
    }

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["comms.transport.connection_state"],
          sampling: %{mode: :latest}
        ),
        source_opts: %{
          operational_observables: [
            transports_fun: fn organization_id, mission_id, opts ->
              send(parent, {:source_health_transports, organization_id, mission_id, opts})

              [
                %{
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  ground_station_id: "dss-14",
                  display_name: "Transport Alpha"
                }
              ]
            end,
            source_endpoints_fun: fn organization_id, mission_id, opts ->
              send(parent, {:source_health_source_endpoints, organization_id, mission_id, opts})
              []
            end,
            connection_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:source_health_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "comms.transport.connection_state",
                  transport_id: "transport-alpha",
                  connection_state: :degraded,
                  observed_at: observed_at
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        source_health_events?: true,
        record_source_health_events?: false,
        source_health_statuses: [status],
        source_health_freshness: %{default_max_age_ms: 2_000_000_000},
        source_health_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:source_health_intervals, organization_id, mission_id, opts})
          [source_health_interval]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert result.meta.source_health == :degraded
    assert result.meta.source_health_event_id == source_health_event_id
    assert result.meta.source_health_interval_id == source_health_interval.interval_id
    assert result.meta.source_health_interval_source_event_id == operational_event_id
    assert result.meta.degraded?

    assert frame.meta.source_health == :degraded
    assert frame.meta.source_health_event_id == source_health_event_id
    assert frame.meta.source_health_interval_id == source_health_interval.interval_id
    assert frame.meta.source_health_interval.source_event_id == operational_event_id
    assert frame.meta.source_health_interval.kind == :source_health
    assert frame.meta.degraded?

    assert evidence_ref(
             frame.meta.evidence,
             :source_health_interval,
             source_health_interval.interval_id
           )

    assert evidence_ref(frame.meta.evidence, :operational_interval, operational_event_id)
    assert evidence_ref(frame.meta.evidence, :source_health_event, source_health_event_id)

    assert_received {:source_health_intervals, "org-1", "mission-1", interval_opts}
    assert interval_opts[:at] == observed_at
    assert interval_opts[:logical_source] == :operational_observables
    assert interval_opts[:data_source_id] == "managed_operational_observables"
    assert interval_opts[:source_binding_id] == "default_flight_operational_observables"
    assert interval_opts[:realm] == :flight
    assert interval_opts[:dataset] == "operational_observables"

    assert_received {:source_health_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:data_source_id] == "managed_operational_observables"

    assert_received {:source_health_source_endpoints, "org-1", "mission-1", endpoint_opts}
    assert endpoint_opts[:dataset] == "operational_observables"

    assert_received {:source_health_snapshots, "org-1", "mission-1", snapshot_opts}
    assert snapshot_opts[:source_binding_id] == "default_flight_operational_observables"
  end

  test "enriches all operational metric-history product frames with selected intervals" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: [
            "link.snr_db",
            "comms.transport.downlink_bitrate",
            "ingress.processing_latency_ms"
          ],
          sampling: %{mode: :raw_series, max_raw_points: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "link", mode: "one", ids: ["link-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            transports_fun: fn organization_id, mission_id, opts ->
              send(parent, {:metric_history_transports, organization_id, mission_id, opts})

              [
                %{
                  transport_id: "transport-alpha",
                  display_name: "Transport Alpha",
                  metadata: %{
                    source_endpoint_id: "endpoint-alpha",
                    ground_station_id: "dss-14",
                    link_assignment_id: "link-alpha"
                  }
                }
              ]
            end,
            link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:link_rf_metric_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "link.snr_db",
                  resource_id: "link-alpha",
                  link_id: "link-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  value: 12.5,
                  snr_db: 12.5,
                  unit: "dB",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:snr-sample-1"
                }
              ]
            end,
            transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:transport_bitrate_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "comms.transport.downlink_bitrate",
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  link_id: "link-alpha",
                  value: 96_000,
                  unit: "bit/s",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:bitrate-sample-1"
                }
              ]
            end,
            ingress_processing_latency_history_snapshots_fun: fn organization_id,
                                                                 mission_id,
                                                                 opts ->
              send(
                parent,
                {:ingress_latency_history_snapshots, organization_id, mission_id, opts}
              )

              [
                %{
                  observable_id: "ingress.processing_latency_ms",
                  mission_id: mission_id,
                  source_endpoint_id: "endpoint-alpha",
                  spacecraft_id: "spacecraft-alpha",
                  transport_id: "transport-alpha",
                  ground_station_id: "dss-14",
                  link_id: "link-alpha",
                  adapter_key: :tcp_socket,
                  value: 4.5,
                  unit: "ms",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:ingress-sample-1"
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :binding_set,
              "metric-history-binding-set-interval-1",
              "runtime-apps"
            )
          ]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "metric-history-application-binding-interval-1",
              "runtime-apps-link-rule"
            )
          ]
        end
      )

    assert %{frames: frames} = result
    assert length(frames) == 3

    expected_frames = %{
      "link.snr_db" => {:link_rf_metric_history, :link_rf, :link, "link-alpha"},
      "comms.transport.downlink_bitrate" =>
        {:transport_bitrate_history, :transport_bitrate, :transport, "transport-alpha"},
      "ingress.processing_latency_ms" =>
        {:ingress_processing_latency_history, :runtime_ingress, :source_endpoint,
         "endpoint-alpha"}
    }

    for {observable_id, {capability, product_family, scope_kind, resource_id}} <- expected_frames do
      frame = Enum.find(frames, &(&1.meta.observable_id == observable_id))
      assert %Frame{} = frame
      assert frame.meta.logical_source == :operational_observables
      assert frame.meta.supported_capability == capability
      assert frame.meta.product_family == product_family
      assert frame.meta.scope_kind == scope_kind
      assert frame.meta.resource_id == resource_id
      assert frame.meta.source_endpoint_id == "endpoint-alpha"
      assert frame.meta.selected_operational_interval_at == selected_at

      assert [
               %{interval_id: "metric-history-binding-set-interval-1", kind: :binding_set},
               %{
                 interval_id: "metric-history-application-binding-interval-1",
                 kind: :application_binding
               }
             ] = frame.meta.selected_operational_intervals

      assert evidence_ref(
               frame.meta.evidence,
               :binding_set_interval,
               "metric-history-binding-set-interval-1"
             )

      assert evidence_ref(
               frame.meta.evidence,
               :application_binding_interval,
               "metric-history-application-binding-interval-1"
             )
    end

    assert_receive {:metric_history_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:from] == from_time
    assert transport_opts[:to] == to_time

    assert_receive {:link_rf_metric_snapshots, "org-1", "mission-1", link_rf_opts}
    assert link_rf_opts[:from] == from_time
    assert link_rf_opts[:to] == to_time

    assert_receive {:transport_bitrate_snapshots, "org-1", "mission-1", bitrate_opts}
    assert bitrate_opts[:from] == from_time
    assert bitrate_opts[:to] == to_time

    assert_receive {:ingress_latency_history_snapshots, "org-1", "mission-1", ingress_opts}
    assert ingress_opts[:from] == from_time
    assert ingress_opts[:to] == to_time
  end

  test "enriches runtime ingress metric-history frames with selected intervals from frame source-endpoint fields" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["ingress.processing_latency_ms"],
          sampling: %{mode: :raw_series, max_raw_points: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "source_endpoint", mode: "one", ids: ["endpoint-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            ingress_processing_latency_history_snapshots_fun: fn organization_id,
                                                                 mission_id,
                                                                 opts ->
              send(
                parent,
                {:ingress_latency_history_snapshots, organization_id, mission_id, opts}
              )

              [
                %{
                  observable_id: "ingress.processing_latency_ms",
                  mission_id: mission_id,
                  source_endpoint_id: "endpoint-alpha",
                  spacecraft_id: "spacecraft-alpha",
                  transport_id: "transport-alpha",
                  ground_station_id: "dss-14",
                  link_id: "link-alpha",
                  adapter_key: :tcp_socket,
                  value: 4.5,
                  unit: "ms",
                  observed_at: selected_at
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :binding_set,
              "ingress-binding-set-interval-1",
              "runtime-apps"
            )
          ]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "ingress-application-binding-interval-1",
              "runtime-apps-ingress-rule"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.logical_source == :operational_observables
    assert frame.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "ingress-binding-set-interval-1", kind: :binding_set},
             %{
               interval_id: "ingress-application-binding-interval-1",
               kind: :application_binding
             }
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :binding_set_interval,
             "ingress-binding-set-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "ingress-application-binding-interval-1"
           )

    assert %Field{metadata: %{source_endpoint_id: "endpoint-alpha"}} =
             Enum.find(frame.fields, &(&1.name == "ingress.processing_latency_ms"))

    assert_receive {:ingress_latency_history_snapshots, "org-1", "mission-1", snapshot_opts}
    assert snapshot_opts[:from] == from_time
    assert snapshot_opts[:to] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"
  end

  test "enriches transport execution frames with selected intervals from frame source-endpoint fields" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["comms.transport.execution_state"],
          sampling: %{mode: :event_history, limit: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "transport", mode: "one", ids: ["transport-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            transport_execution_intervals_fun: fn organization_id, mission_id, opts ->
              send(parent, {:transport_execution_intervals, organization_id, mission_id, opts})

              [
                %EffectiveInterval{
                  interval_id: "transport-execution-interval-1",
                  organization_id: organization_id,
                  mission_id: mission_id,
                  kind: :transport_execution,
                  subject_kind: :transport,
                  subject_id: "transport-alpha",
                  starts_at: selected_at,
                  ends_at: ~U[2026-06-21 20:45:00Z],
                  source_event_id: "transport-execution-event-1",
                  payload: %{
                    "capability_instance_id" => "transport-alpha",
                    "source_endpoint_id" => "endpoint-alpha",
                    "ground_station_id" => "dss-14",
                    "link_assignment_id" => "link-alpha",
                    "event_kind" => "initialized"
                  }
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          [effective_interval(:binding_set, "transport-binding-set-interval-1", "runtime-apps")]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "transport-application-binding-interval-1",
              "runtime-apps-transport-rule"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.logical_source == :operational_observables
    assert frame.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "transport-binding-set-interval-1", kind: :binding_set},
             %{
               interval_id: "transport-application-binding-interval-1",
               kind: :application_binding
             }
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :binding_set_interval,
             "transport-binding-set-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "transport-application-binding-interval-1"
           )

    assert %Field{values: ["endpoint-alpha"]} =
             Enum.find(frame.fields, &(&1.name == "source_endpoint_id"))

    assert_receive {:transport_execution_intervals, "org-1", "mission-1", interval_opts}
    assert interval_opts[:from] == from_time
    assert interval_opts[:to] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"
  end

  test "resolves source execution policy from source and binding metadata with explicit overrides" do
    data_source_policy = %{
      dashboard_policy: %{
        execution: %{timeout_ms: 80},
        circuit_breaker: %{failure_threshold: 4, backoff_ms: 8_000}
      }
    }

    binding_policy = %{
      "dashboard_policy" => %{
        "execution" => %{"timeout_ms" => 30},
        "circuit_breaker" => %{"failure_threshold" => 1}
      }
    }

    assert %SourceExecutionPolicy{} =
             policy =
             SourceRegistry.execution_policy(source_request(),
               data_sources: [
                 data_source("flight-questdb", [watermarks?: true], data_source_policy)
               ],
               data_bindings: [data_binding("flight-questdb", :flight, binding_policy)],
               source_circuit_backoff_ms: 1_234
             )

    assert policy.timeout_ms == 30
    assert policy.circuit_failure_threshold == 1
    assert policy.circuit_backoff_ms == 1_234
    assert policy.provenance.data_source_policy?
    assert policy.provenance.binding_policy?
    assert policy.provenance.explicit_opts?
    assert policy.provenance.data_source_id == "flight-questdb"
    assert policy.provenance.source_binding_id == "flight-telemetry"
  end

  test "opens a source circuit after repeated adapter errors and skips the adapter during backoff" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    opts = source_circuit_opts(breaker, mode: :error_result, now_ms: 1_000)

    first = SourceRegistry.resolve(source_request(), opts)
    second = SourceRegistry.resolve(source_request(), opts)
    third = SourceRegistry.resolve(source_request(), opts)

    assert [%{code: :source_unavailable, severity: :error}] = first.warnings
    assert [%{code: :source_unavailable, severity: :error}] = second.warnings
    assert [%{code: :source_degraded, severity: :error} = warning] = third.warnings
    assert warning.details.circuit_state == :open
    assert warning.details.failure_count == 2
    assert warning.details.data_source_id == "flight-questdb"
    assert warning.details.realm == :flight

    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    refute_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
  end

  test "keeps source circuit failures isolated by concrete data source and realm" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    failing_opts = source_circuit_opts(breaker, mode: :error_result, now_ms: 1_000)
    rehearsal_opts = source_circuit_opts(breaker, mode: :ok, realm: :rehearsal, now_ms: 1_000)

    _first = SourceRegistry.resolve(source_request(), failing_opts)
    _second = SourceRegistry.resolve(source_request(), failing_opts)

    result =
      SourceRegistry.resolve(
        source_request(data_context: %{realm: :rehearsal}),
        rehearsal_opts
      )

    assert result.warnings == []
    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    assert_received {:dashboard_source_test_adapter_resolve, "rehearsal-questdb"}
  end

  test "source circuit thresholds are isolated by concrete source policy" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    opts = [
      source_circuit_breaker: breaker,
      now_ms: 1_000,
      data_sources: [
        %DataSource{
          data_source_id: "flight-questdb",
          adapter: Cadence.Support.DashboardSourceTestAdapter
        },
        %DataSource{
          data_source_id: "rehearsal-questdb",
          adapter: Cadence.Support.DashboardSourceTestAdapter
        }
      ],
      data_bindings: [
        data_binding("flight-questdb", :flight, %{
          dashboard_policy: %{circuit_breaker: %{failure_threshold: 1, backoff_ms: 5_000}}
        }),
        data_binding("rehearsal-questdb", :rehearsal, %{
          dashboard_policy: %{circuit_breaker: %{failure_threshold: 2, backoff_ms: 60_000}}
        })
      ],
      source_opts: %{
        telemetry: [
          test_pid: self(),
          mode: :error_result
        ]
      }
    ]

    flight_first = SourceRegistry.resolve(source_request(), opts)
    flight_second = SourceRegistry.resolve(source_request(), opts)

    rehearsal_first =
      SourceRegistry.resolve(
        source_request(data_context: %{realm: :rehearsal}),
        opts
      )

    assert [%{code: :source_unavailable}] = flight_first.warnings
    assert [%{code: :source_degraded} = flight_warning] = flight_second.warnings
    assert flight_warning.details.failure_threshold == 1
    assert flight_warning.details.backoff_ms == 5_000

    assert [%{code: :source_unavailable}] = rehearsal_first.warnings

    assert %{state: :open, failure_count: 1, failure_threshold: 1, backoff_ms: 5_000} =
             SourceCircuitBreaker.status(
               breaker,
               {"org-1", "mission-1", :telemetry, "flight-questdb", :flight, "flight"},
               failure_threshold: 1,
               backoff_ms: 5_000
             )

    assert %{state: :closed, failure_count: 1, failure_threshold: 2, backoff_ms: 60_000} =
             SourceCircuitBreaker.status(
               breaker,
               {"org-1", "mission-1", :telemetry, "rehearsal-questdb", :rehearsal, "rehearsal"},
               failure_threshold: 2,
               backoff_ms: 60_000
             )
  end

  test "adapter exceptions become source-unavailable warnings and feed the circuit" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    opts =
      breaker
      |> source_circuit_opts(mode: :raise, now_ms: 1_000)
      |> Keyword.put(:source_circuit_failure_threshold, 1)

    first = SourceRegistry.resolve(source_request(), opts)
    second = SourceRegistry.resolve(source_request(), opts)

    assert [%{code: :source_unavailable, severity: :error} = warning] = first.warnings
    assert warning.details.reason == "test source failure"
    assert [%{code: :source_degraded, severity: :error}] = second.warnings

    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    refute_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
  end

  test "command queue depth reader exceptions become source-unavailable warnings" do
    request =
      source_request(
        logical_source: :operational_observables,
        observables: ["commanding.queue_depth"],
        sampling: %{mode: :latest}
      )

    result =
      SourceRegistry.resolve(request,
        source_opts: %{
          operational_observables: [
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
              raise "command queue read failed"
            end
          ]
        }
      )

    assert result.frames == []
    assert [%{code: :source_unavailable, severity: :error} = warning] = result.warnings
    assert warning.details.logical_source == :operational_observables
    assert warning.details.data_source_id == "managed_operational_observables"
    assert warning.details.reason =~ "command queue read failed"
  end

  test "contact phase reader exceptions become source-unavailable warnings" do
    request =
      source_request(
        logical_source: :operational_observables,
        observables: ["contacts.phase"],
        sampling: %{mode: :latest}
      )

    result =
      SourceRegistry.resolve(request,
        source_opts: %{
          operational_observables: [
            scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
              raise "scheduled contact read failed"
            end,
            realized_contacts_fun: fn _organization_id, _mission_id, _opts -> [] end
          ]
        }
      )

    assert result.frames == []
    assert [%{code: :source_unavailable, severity: :error} = warning] = result.warnings
    assert warning.details.logical_source == :operational_observables
    assert warning.details.data_source_id == "managed_operational_observables"
    assert warning.details.reason =~ "scheduled contact read failed"
  end

  test "operational metric history reader exceptions become source-unavailable warnings" do
    request =
      source_request(
        logical_source: :operational_observables,
        observables: ["link.snr_db"],
        sampling: %{mode: :raw_series, limit: 10},
        time_context: %{from: ~U[2026-06-17 12:01:00Z], to: ~U[2026-06-17 12:03:00Z]}
      )

    result =
      SourceRegistry.resolve(request,
        source_opts: %{
          operational_observables: [
            transports_fun: fn _organization_id, _mission_id, _opts -> [] end,
            link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
              raise "RF metric history read failed"
            end
          ]
        }
      )

    assert result.frames == []
    assert [%{code: :source_unavailable, severity: :error} = warning] = result.warnings
    assert warning.details.logical_source == :operational_observables
    assert warning.details.data_source_id == "managed_operational_observables"
    assert warning.details.reason =~ "RF metric history read failed"
  end

  test "source execution warnings carry replay request context into actions" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    opts = source_circuit_opts(breaker, mode: :error_result, realm: :replay, now_ms: 1_000)

    result = SourceRegistry.resolve(replay_source_request(), opts)

    assert [%{code: :source_unavailable, severity: :error} = warning] = result.warnings
    assert warning.details.realm == :replay
    assert warning.details.time_mode == :replay_run
    assert warning.details.time_axis == :receipt_time
    assert warning.details.replay_run_id == "replay-run-1"
    assert warning.details.requested_realm == :replay
    assert warning.details.data_source_id == "replay-questdb"

    assert Enum.any?(warning.details.actions, fn action ->
             action.target == :source_health and
               action.context.replay_run_id == "replay-run-1" and
               action.context.realm == :replay and
               action.context.time_mode == :replay_run
           end)
  end

  defp source_request(overrides \\ []) do
    attrs = %{
      request_id: "source-request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{realm: :flight},
      sampling: %{mode: :raw_series}
    }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp production_source_request(logical_source, sampling_mode) do
    source_request(
      request_id: "source-request-#{logical_source}",
      logical_source: logical_source,
      sampling: %{mode: sampling_mode}
    )
  end

  defp replay_source_request(overrides \\ []) do
    source_request(
      Keyword.merge(
        [
          time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"},
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"}
        ],
        overrides
      )
    )
  end

  defp source_health_status(overrides) do
    attrs =
      %{
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        realm: :flight,
        dataset: "operational_observables",
        replay_run_id: nil,
        source_health_event_id: "source-health-operational-observables-1",
        event_type: :degraded,
        source_health: :degraded,
        previous_source_health: :healthy,
        reason: :source_probe_failed,
        observed_at: ~U[2026-06-21 20:30:00Z],
        last_seen_at: ~U[2026-06-21 20:30:00Z],
        transition_count: 1,
        payload: %{}
      }
      |> Map.merge(overrides)

    struct!(
      SourceHealthStatus,
      Map.put(attrs, :source_health_key, SourceHealthEvent.source_health_key(attrs))
    )
  end

  defp data_binding(data_source_id) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org-1",
      mission_id: "mission-1",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: "flight"
    }
  end

  defp data_binding(data_source_id, realm, metadata \\ %{}) do
    %DataBinding{
      binding_id: "#{realm}-telemetry",
      organization_id: "org-1",
      mission_id: "mission-1",
      realm: realm,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm),
      metadata: metadata
    }
  end

  defp data_source(data_source_id, capabilities, metadata \\ %{}) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: Map.new(capabilities),
      metadata: metadata
    }
  end

  defp test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter
    }
  end

  defp production_source_registry_opts do
    [
      data_sources: [
        DataSources.default_managed_data_source(),
        DataSources.default_limits_data_source(),
        DataSources.default_events_data_source(),
        DataSources.default_operational_observables_data_source()
      ],
      data_bindings: [
        DataSources.default_flight_telemetry_binding(),
        DataSources.default_flight_limits_binding(),
        DataSources.default_flight_events_binding(),
        DataSources.default_flight_operational_observables_binding()
      ],
      validate_dashboard_contract?: true
    ]
  end

  defp production_source_contracts do
    [
      %{
        logical_source: :telemetry,
        sampling_mode: :raw_series,
        binding_id: "default_flight_telemetry",
        data_source_id: "managed_questdb_primary",
        dataset: "flight",
        adapter_supported_products: [
          :latest_value,
          :bounded_receipt_time_history,
          :bounded_generation_time_history
        ],
        supported_time_axes: [:generation_time, :receipt_time],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:scalar, :wide],
        supports_watermarks?: true,
        completeness: :unknown
      },
      %{
        logical_source: :limits,
        sampling_mode: :latest_state,
        binding_id: "default_flight_limits",
        data_source_id: "managed_limits_projection",
        dataset: "telemetry_latest_limit_states",
        adapter_supported_products: [
          :latest_state,
          :event_history,
          :definition_intervals,
          :analysis_buckets
        ],
        supported_time_axes: [:receipt_time],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:scalar, :events, :intervals],
        supports_watermarks?: true,
        completeness: :unknown
      },
      %{
        logical_source: :events,
        sampling_mode: :event_history,
        binding_id: "default_flight_events",
        data_source_id: "managed_events_projection",
        dataset: "mission_events",
        adapter_supported_products: [
          :contact_intervals,
          :mission_timeline,
          :source_health_transitions,
          :source_watermark_events,
          :source_capability_postures,
          :telemetry_backfill_lifecycle,
          :telemetry_revision_decisions
        ],
        supported_time_axes: [:occurred_at],
        supported_value_types: [],
        supported_shapes: [:intervals, :events],
        supports_watermarks?: false,
        completeness: :partial
      },
      %{
        logical_source: :operational_observables,
        sampling_mode: :latest,
        binding_id: "default_flight_operational_observables",
        data_source_id: "managed_operational_observables",
        dataset: "operational_observables",
        adapter_supported_products: [
          :constellation_health,
          :contacts_phase,
          :contacts_phase_history,
          :connection_state,
          :connection_state_history,
          :ground_station_antenna_pointing_state,
          :ground_station_antenna_pointing_state_history,
          :link_rf_lock_state,
          :link_rf_lock_state_history,
          :link_rf_frame_sync_state,
          :link_rf_frame_sync_state_history,
          :link_rf_metric,
          :link_rf_metric_history,
          :transport_bitrate,
          :transport_bitrate_history,
          :transport_execution_state_history,
          :managed_runtime_activity_history,
          :transport_runtime_activity_history,
          :ingress_processing_latency_history,
          :operational_metric_history,
          :operational_latest,
          :operational_state_history,
          :command_queue_depth,
          :ingress_processing_latency
        ],
        supported_time_axes: [:occurred_at],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:matrix, :events, :wide],
        supports_watermarks?: false,
        completeness: :known
      }
    ]
  end

  defp capability_variant_data_source(:telemetry) do
    %{
      DataSources.default_managed_data_source()
      | capabilities: %{
          range_scan?: true,
          bounded_history?: true,
          latest?: true,
          watermarks?: true,
          native_decimation?: true
        }
    }
  end

  defp capability_variant_data_source(:limits) do
    %{
      DataSources.default_limits_data_source()
      | capabilities: %{
          latest_state?: true,
          event_history?: true,
          definition_intervals?: false,
          watermarks?: false
        }
    }
  end

  defp capability_variant_data_source(:events) do
    %{
      DataSources.default_events_data_source()
      | capabilities: %{
          contact_intervals?: true,
          mission_timeline?: true,
          source_health_transitions?: true,
          source_watermark_events?: true,
          source_capability_postures?: true,
          telemetry_backfill_lifecycle?: true,
          telemetry_revision_decisions?: true,
          watermarks?: true,
          external_projection?: true
        }
    }
  end

  defp capability_variant_data_source(:operational_observables) do
    %{
      DataSources.default_operational_observables_data_source()
      | capabilities: %{
          constellation_health?: true,
          watermarks?: true,
          projected_snapshot_revision?: true
        }
    }
  end

  defp sample(point_id, sample_id, value, receipt_time, evidence_id) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-1",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      evidence_id: evidence_id,
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      receipt_time: receipt_time
    }
  end

  defp limit_event(point_id, overrides) do
    %Event{
      limit_event_id: "limit-event-1",
      mission_id: "mission-1",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-1",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 42,
      limit_state: :green,
      normalized_state: :green,
      violation: false,
      generation_time: nil,
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
    |> struct!(overrides)
  end

  defp limit_definition_interval(point_id, overrides) do
    %DefinitionInterval{
      definition_activation_key: "limit-activation-1",
      limit_definition_lifecycle_event_id: "limit-lifecycle-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      point_id: point_id,
      limit_set_name: "ops",
      scope_type: nil,
      scope_ref: nil,
      realm: nil,
      event_type: :registered,
      limit_definition_id: "limit-def-1",
      limit_definition_version: 1,
      active_from: ~U[2026-06-17 12:00:00Z],
      active_to: nil,
      observed_at: ~U[2026-06-17 12:00:00Z],
      thresholds: %{},
      metadata: %{},
      complete?: true
    }
    |> struct!(overrides)
  end

  defp effective_interval(kind, interval_id, subject_id) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: kind,
      subject_kind: kind,
      subject_id: subject_id,
      starts_at: ~U[2026-06-21 20:00:00Z],
      source_event_id: "source-event-#{interval_id}",
      payload: %{subject_id: subject_id}
    }
  end

  defp evidence_ref(evidence, kind, id) do
    Enum.find(evidence, fn
      %EvidenceRef{kind: ^kind, id: ^id} -> true
      _other -> false
    end)
  end

  defp source_circuit_opts(breaker, opts) do
    realm = Keyword.get(opts, :realm, :flight)
    data_source_id = "#{realm}-questdb"

    [
      source_circuit_breaker: breaker,
      source_circuit_failure_threshold: 2,
      source_circuit_backoff_ms: 60_000,
      now_ms: Keyword.fetch!(opts, :now_ms),
      data_sources: [
        %DataSource{
          data_source_id: data_source_id,
          adapter: Cadence.Support.DashboardSourceTestAdapter
        }
      ],
      data_bindings: [data_binding(data_source_id, realm)],
      source_opts: %{
        telemetry: [
          test_pid: self(),
          mode: Keyword.fetch!(opts, :mode)
        ]
      }
    ]
  end
end
