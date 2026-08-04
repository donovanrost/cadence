defmodule Cadence.Dashboards.SourceRegistryTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    SourceCircuitBreaker,
    SourceExecutionPolicy,
    SourceFacts,
    SourceRegistry
  }

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.DataSource

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
end
