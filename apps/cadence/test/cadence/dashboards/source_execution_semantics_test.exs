defmodule Cadence.Dashboards.SourceExecutionSemanticsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    Engine,
    PlannedSourceRequest,
    RuntimeCache,
    SourceCircuitBreaker,
    SourceExecutionSemantics
  }

  alias Cadence.Management.DataSources

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Limits.Event
  alias Cadence.Telemetry.Sample

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "summarizes source-result cache miss and hit semantics" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: source_opts()
      )

    assert %{
             source_request_count: 2,
             executed_source_request_count: 2,
             skipped_source_request_count: 0,
             actionable_source_request_count: 0,
             retryable_source_request_count: 0,
             severity_counts: %{info: 2},
             status_counts: %{cache_miss: 2}
           } = first_summary = SourceExecutionSemantics.summarize(first)

    assert Enum.all?(first_summary.outcomes, &(&1.operator_action == :none))

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: source_opts()
      )

    assert %{
             source_request_count: 2,
             executed_source_request_count: 2,
             skipped_source_request_count: 0,
             status_counts: %{cache_hit: 2}
           } = Dashboards.summarize_dashboard_source_execution(second)
  end

  test "summarizes stale source-result cache preflight semantics" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = telemetry_only_value_tile_document()
    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun(), watermark_fun: watermark_fun()]
        }
      )

    assert %{status_counts: %{cache_miss: 1}} = SourceExecutionSemantics.summarize(first)

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [
            latest_fun: telemetry_latest_fun(),
            watermark_fun: watermark_fun(),
            source_health: :degraded
          ]
        }
      )

    assert %{status_counts: %{cache_stale: 1}, outcomes: [outcome]} =
             SourceExecutionSemantics.summarize(second)

    assert outcome.metadata.cache_reasons == [:source_degraded]
    assert outcome.severity == :warning
    assert outcome.operator_action == :wait_for_refresh
    assert outcome.runtime_action == :refresh_source_result
    assert outcome.retryable?
    refute outcome.actionable?
    refute outcome.dashboard_degraded?
  end

  test "source-health degradation stales cached source results across logical sources" do
    cache = start_supervised!({RuntimeCache, name: nil})

    requests = [
      resolve_request(live_time_series_with_limits_document()),
      operational_resolve_request()
    ]

    healthy_outcomes =
      requests
      |> Enum.map(
        &Engine.resolve(
          &1,
          source_contract_opts(:empty_result,
            runtime_cache: cache,
            source_result_cache?: true,
            source_opts: source_contract_source_opts(:empty_result, source_health: :healthy)
          )
        )
      )
      |> Enum.flat_map(&source_summary_outcomes/1)

    assert Enum.frequencies_by(healthy_outcomes, & &1.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    assert Enum.all?(healthy_outcomes, &(&1.status == :cache_miss))

    degraded_outcomes =
      requests
      |> Enum.map(
        &Engine.resolve(
          &1,
          source_contract_opts(:empty_result,
            runtime_cache: cache,
            source_result_cache?: true,
            source_opts: source_contract_source_opts(:empty_result, source_health: :degraded)
          )
        )
      )
      |> Enum.flat_map(&source_summary_outcomes/1)

    assert Enum.frequencies_by(degraded_outcomes, & &1.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    for outcome <- degraded_outcomes do
      assert outcome.status == :cache_stale
      assert outcome.executed?
      refute outcome.degraded?
      refute outcome.dashboard_degraded?
      refute outcome.actionable?
      assert outcome.retryable?
      assert outcome.severity == :warning
      assert outcome.operator_action == :wait_for_refresh
      assert outcome.runtime_action == :refresh_source_result
      assert outcome.warning_codes == []
      assert :source_degraded in outcome.metadata.cache_reasons
    end
  end

  test "freshness facts drive source-result cache identity across logical sources" do
    cache = start_supervised!({RuntimeCache, name: nil})

    requests = [
      resolve_request(live_time_series_with_limits_document()),
      operational_resolve_request()
    ]

    first_outcomes =
      requests
      |> Enum.map(
        &Engine.resolve(
          &1,
          source_contract_opts(:empty_result,
            runtime_cache: cache,
            source_result_cache?: true,
            source_opts:
              freshness_contract_source_opts(
                watermark_complete_through: ~U[2026-06-17 12:00:00Z],
                data_revision: "source-revision-1"
              )
          )
        )
      )
      |> Enum.flat_map(&source_summary_outcomes/1)

    assert_contract_source_frequencies(first_outcomes)
    assert Enum.all?(first_outcomes, &(&1.status == :cache_miss))

    second_outcomes =
      requests
      |> Enum.map(
        &Engine.resolve(
          &1,
          source_contract_opts(:empty_result,
            runtime_cache: cache,
            source_result_cache?: true,
            source_opts:
              freshness_contract_source_opts(
                watermark_complete_through: ~U[2026-06-17 12:00:00Z],
                data_revision: "source-revision-1"
              )
          )
        )
      )
      |> Enum.flat_map(&source_summary_outcomes/1)

    assert_contract_source_frequencies(second_outcomes)
    assert Enum.all?(second_outcomes, &(&1.status == :cache_hit))

    changed_outcomes =
      requests
      |> Enum.map(
        &Engine.resolve(
          &1,
          source_contract_opts(:empty_result,
            runtime_cache: cache,
            source_result_cache?: true,
            source_opts:
              freshness_contract_source_opts(
                watermark_complete_through: ~U[2026-06-17 12:05:00Z],
                data_revision: "source-revision-2"
              )
          )
        )
      )
      |> Enum.flat_map(&source_summary_outcomes/1)

    assert_contract_source_frequencies(changed_outcomes)
    assert Enum.all?(changed_outcomes, &(&1.status == :cache_miss))
  end

  test "summarizes timeout as source execution failure while preserving partial success" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    result =
      Engine.resolve(resolve_request(mixed_telemetry_execution_document()),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{
          telemetry: [
            sleep_ms_by_sampling: %{latest: 200}
          ]
        },
        source_execution_timeout_ms: 50,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_circuit_failure_threshold: 1
      )

    assert %{degraded?: true, status_counts: status_counts, outcomes: outcomes} =
             SourceExecutionSemantics.summarize(result)

    assert status_counts.source_execution_failed == 1
    assert status_counts.cache_disabled == 1

    assert Enum.any?(outcomes, fn outcome ->
             outcome.status == :source_execution_failed and
               outcome.degraded? and
               outcome.actionable? and
               outcome.retryable? and
               outcome.operator_action == :inspect_source_failure and
               outcome.warning_codes == [:source_unavailable]
           end)
  end

  test "summarizes circuit-open requests as degraded without executing adapter" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    document = telemetry_only_value_tile_document()
    request = resolve_request(document)

    first =
      Engine.resolve(request,
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{telemetry: [mode: :error_result]},
        source_execution_max_concurrency: 1,
        source_circuit_breaker: breaker,
        source_circuit_failure_threshold: 1,
        source_circuit_backoff_ms: 60_000
      )

    assert %{status_counts: %{source_unavailable: 1}} =
             SourceExecutionSemantics.summarize(first)

    second =
      Engine.resolve(request,
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{telemetry: [test_pid: self()]},
        source_execution_max_concurrency: 1,
        source_circuit_breaker: breaker,
        source_circuit_failure_threshold: 1,
        source_circuit_backoff_ms: 60_000
      )

    assert %{status_counts: %{source_degraded: 1}, outcomes: [outcome]} =
             SourceExecutionSemantics.summarize(second)

    assert outcome.warning_codes == [:source_degraded]
    assert outcome.metadata.data_source_id == "flight-questdb"
    refute_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}
  end

  test "summarizes unsupported capability as a skipped no-fallback outcome" do
    result =
      Engine.plan(resolve_request(unsupported_time_series_document()),
        data_sources: [
          %DataSource{
            data_source_id: "flight-questdb",
            adapter: Cadence.Support.DashboardSourceTestAdapter,
            capabilities: %{range_scan?: true}
          }
        ],
        data_bindings: [telemetry_binding("flight-questdb")]
      )

    assert %{status_counts: %{unsupported_capability: 1}, outcomes: [outcome]} =
             SourceExecutionSemantics.summarize(result)

    refute outcome.executed?
    assert outcome.degraded?
    assert outcome.severity == :error
    assert outcome.actionable?
    refute outcome.retryable?
    assert outcome.operator_action == :inspect_source_capability
    assert outcome.runtime_action == :requires_configuration_change
    assert outcome.warning_codes == [:unsupported_source_capability]
    assert outcome.metadata.fallback == :none
  end

  test "summarizes request-local capability posture metadata" do
    posture = %{
      status: :fallback,
      requested_sampling: :latest,
      supported_sampling: [:latest],
      requested_products: [:link_rf_metric_history],
      supported_products: [:transport_bitrate_history],
      requested_time_axis: :generation_time,
      executed_time_axis: :receipt_time,
      supported_time_axes: [:receipt_time],
      fallbacks: [
        %{
          capability: :time_axis,
          requested: :generation_time,
          executed: :receipt_time,
          reason: :unsupported_time_axis
        }
      ]
    }

    result = %DashboardResolveResult{
      dashboard_id: "dashboard-1",
      resolve_mode: :live_tick,
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          organization_id: "org-1",
          mission_id: "mission-1",
          logical_source: :telemetry,
          observables: ["HK.counter"],
          sampling: %{mode: :latest},
          metadata: %{
            capability_provenance: %{
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              realm: :flight,
              capability_posture: posture
            }
          }
        }
      ],
      plan_metadata: %{
        source_request_count: 1,
        executed_source_request_count: 1,
        skipped_source_request_count: 0,
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :miss}
          }
        }
      }
    }

    assert %{outcomes: [outcome]} = SourceExecutionSemantics.summarize(result)

    assert outcome.metadata.capability_status == :fallback
    assert outcome.metadata.capability_posture == posture

    assert [event] =
             SourceExecutionSemantics.source_capability_posture_events(result,
               observed_at: ~U[2026-06-26 12:00:00Z],
               resolve_id: "resolve-1"
             )

    assert event.kind == :source_capability_fallback
    assert event.severity == :warning
    assert event.subject == %{kind: :data_source, id: "flight-questdb"}
    assert event.scope.source_binding_id == "flight-telemetry"
    assert event.payload.dashboard_id == "dashboard-1"
    assert event.payload.source_request_id == "req-telemetry"
    assert event.payload.source_execution_status == :cache_miss
    assert event.payload.requested_products == [:link_rf_metric_history]
    assert event.current.supported_products == [:transport_bitrate_history]
    assert event.payload.requested_time_axis == :generation_time
    assert event.current.executed_time_axis == :receipt_time
  end

  test "source adapter failures share one degraded action contract across logical sources" do
    outcomes =
      [
        resolve_request(load_fixture!("time_series_with_limits.v1.json")),
        operational_resolve_request()
      ]
      |> Enum.map(&Engine.resolve(&1, source_contract_opts(:raise)))
      |> Enum.flat_map(&source_execution_outcomes/1)

    assert Enum.frequencies_by(outcomes, & &1.outcome.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    for %{outcome: outcome, warning: warning} <- outcomes do
      assert outcome.status == :source_unavailable
      assert outcome.executed?
      assert outcome.degraded?
      assert outcome.dashboard_degraded?
      assert outcome.actionable?
      assert outcome.retryable?
      assert outcome.severity == :error
      assert outcome.operator_action == :inspect_source_health
      assert outcome.runtime_action == :wait_for_source_health
      assert outcome.warning_codes == [:source_unavailable]

      assert warning.severity == :error
      assert warning.scope == :dashboard
      assert warning.details.source_request_id == outcome.request_id
      assert warning.details.logical_source == outcome.logical_source
      assert warning.details.data_source_id == outcome.metadata.data_source_id
      assert warning.details.source_binding_id == warning.details.binding_id
      assert warning.details.realm == outcome.metadata.realm
      assert warning.details.reason =~ "contract adapter failure"
      assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
      assert Enum.map(warning.details.actions, & &1.source) == [:warning, :warning]
      assert_source_action_runtime_contexts(warning)
    end
  end

  test "fans adapter annotations out to placement composition independently of frames" do
    hidden_result =
      Engine.resolve(
        resolve_request(live_time_series_with_limits_document()),
        source_contract_opts(:annotation_result)
      )

    assert %{"placement_power_trend" => hidden_placement_frames} =
             hidden_result.frames_by_placement

    assert hidden_placement_frames.annotations == []

    result =
      Engine.resolve(
        resolve_request(live_time_series_with_limits_document(["test.annotations"])),
        source_contract_opts(:annotation_result)
      )

    assert %{"placement_power_trend" => placement_frames} = result.frames_by_placement
    assert placement_frames.primary == []
    assert Enum.all?(placement_frames.overlays, fn {_role, frames} -> frames == [] end)

    assert Enum.sort(Enum.map(placement_frames.annotations, & &1.annotation_id)) ==
             result.planned_source_requests
             |> Enum.map(&"test.provider:#{&1.request_id}")
             |> Enum.sort()

    assert Enum.all?(placement_frames.annotations, fn annotation ->
             annotation.provenance.source_request_context.source_request_id in placement_frames.planned_request_ids
           end)
  end

  test "source adapter timeouts share one retryable execution-failure contract across logical sources" do
    results =
      [
        resolve_request(load_fixture!("time_series_with_limits.v1.json")),
        operational_resolve_request()
      ]
      |> Enum.map(
        &Engine.resolve(
          &1,
          source_contract_opts(:sleep,
            source_execution_timeout_ms: 10,
            source_execution_max_concurrency: 4,
            source_opts: source_contract_source_opts(:sleep, sleep_ms: 100)
          )
        )
      )

    outcomes = Enum.flat_map(results, &source_summary_outcomes/1)

    assert Enum.frequencies_by(outcomes, & &1.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    for outcome <- outcomes do
      assert outcome.status == :source_execution_failed
      assert outcome.executed?
      assert outcome.degraded?
      assert outcome.dashboard_degraded?
      assert outcome.actionable?
      assert outcome.retryable?
      assert outcome.severity == :error
      assert outcome.operator_action == :inspect_source_failure
      assert outcome.runtime_action == :retry_source_execution
      assert outcome.cache_status == :source_execution_failed
    end

    warnings_by_request_id = source_warnings_by_request_id(results, :source_unavailable)
    warning_outcomes = Enum.filter(outcomes, &Map.has_key?(warnings_by_request_id, &1.request_id))

    assert warning_outcomes != []

    for outcome <- warning_outcomes do
      warning = Map.fetch!(warnings_by_request_id, outcome.request_id)

      assert warning.severity == :error
      assert warning.scope == :dashboard
      assert warning.details.source_request_id == outcome.request_id
      assert warning.details.logical_source == outcome.logical_source
      assert warning.details.data_source_id == outcome.metadata.data_source_id
      assert warning.details.source_binding_id == warning.details.binding_id
      assert warning.details.realm == outcome.metadata.realm
      assert warning.details.reason =~ "timeout after 10ms"
      assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
      assert_source_action_runtime_contexts(warning)
    end
  end

  test "empty source results share non-degraded no-action execution semantics" do
    outcomes =
      [
        resolve_request(load_fixture!("time_series_with_limits.v1.json")),
        operational_resolve_request()
      ]
      |> Enum.map(&Engine.resolve(&1, source_contract_opts(:empty_result)))
      |> Enum.flat_map(fn result ->
        assert result.dashboard_warnings == []
        assert result.plan_metadata.returned_frame_count == 0
        refute result.plan_metadata.degraded?

        result
        |> SourceExecutionSemantics.summarize()
        |> Map.fetch!(:outcomes)
      end)

    assert Enum.frequencies_by(outcomes, & &1.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    for outcome <- outcomes do
      assert outcome.status == :cache_disabled
      assert outcome.executed?
      refute outcome.degraded?
      refute outcome.dashboard_degraded?
      refute outcome.actionable?
      refute outcome.retryable?
      assert outcome.severity == :info
      assert outcome.operator_action == :none
      assert outcome.runtime_action == :none
      assert outcome.warning_codes == []
    end
  end

  test "open source circuits skip adapter execution across logical sources" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    requests = [
      resolve_request(load_fixture!("time_series_with_limits.v1.json")),
      operational_resolve_request()
    ]

    first_results =
      Enum.map(
        requests,
        &Engine.resolve(
          &1,
          source_contract_opts(:raise,
            source_circuit_breaker: breaker,
            source_circuit_failure_threshold: 1,
            source_circuit_backoff_ms: 60_000,
            now_ms: 1_000
          )
        )
      )

    first_outcomes = Enum.flat_map(first_results, &source_summary_outcomes/1)

    assert Enum.frequencies_by(first_outcomes, & &1.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    assert Enum.all?(first_outcomes, &(&1.status in [:source_unavailable, :source_degraded]))

    assert first_outcomes
           |> Enum.filter(&(&1.status == :source_unavailable))
           |> MapSet.new(& &1.logical_source) ==
             MapSet.new([:telemetry, :limits, :events, :operational_observables])

    flush_contract_adapter_messages()

    second_results =
      Enum.map(
        requests,
        &Engine.resolve(
          &1,
          source_contract_opts(:empty_result,
            source_circuit_breaker: breaker,
            source_circuit_failure_threshold: 1,
            source_circuit_backoff_ms: 60_000,
            now_ms: 1_001
          )
        )
      )

    outcomes =
      second_results
      |> Enum.flat_map(&source_degraded_outcomes/1)

    assert Enum.frequencies_by(outcomes, & &1.outcome.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }

    for %{outcome: outcome, warning: warning} <- outcomes do
      assert outcome.status == :source_degraded
      assert outcome.degraded?
      assert outcome.dashboard_degraded?
      assert outcome.actionable?
      assert outcome.retryable?
      assert outcome.severity == :warning
      assert outcome.operator_action == :inspect_source_health
      assert outcome.runtime_action == :wait_for_source_health
      assert outcome.warning_codes == [:source_degraded]

      assert warning.details.source_request_id == outcome.request_id
      assert warning.details.logical_source == outcome.logical_source
      assert warning.details.circuit_state == :open
      assert warning.details.failure_count >= 1
      assert warning.details.failure_threshold == 1
      assert warning.details.retry_after_ms == 61_000
      assert warning.details.last_failure_reason == :source_unavailable
      assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
      assert_source_action_runtime_contexts(warning)
    end

    refute_received {:dashboard_source_contract_adapter_resolve, _logical_source}
  end

  test "BYO source timeout opens only that physical source circuit while managed source still executes" do
    persist_mission_scope("org_dashboards", "mission_dashboards")

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "secret://org_dashboards/dashboard/customer-byo-questdb",
               organization_id: "org_dashboards",
               mission_id: "mission_dashboards",
               data_source_id: "customer-byo-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/byo-questdb"}
             })

    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    document = byo_managed_telemetry_execution_document()
    request = resolve_request(document)

    source_opts = %{
      telemetry: [
        test_pid: self(),
        sleep_ms_by_sampling: %{latest: 200}
      ]
    }

    first =
      Engine.resolve(request,
        data_sources: [byo_test_adapter_data_source(), managed_test_adapter_data_source()],
        data_bindings: [byo_telemetry_binding(), managed_telemetry_binding()],
        source_opts: source_opts,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_health_events?: false,
        record_source_health_events?: false,
        source_watermark_events?: false,
        now_ms: 10_000
      )

    first_outcomes =
      first
      |> SourceExecutionSemantics.summarize()
      |> Map.fetch!(:outcomes)

    assert Enum.frequencies_by(first_outcomes, & &1.metadata.data_source_id) == %{
             "customer-byo-questdb" => 1,
             "managed-questdb" => 1
           }

    assert Enum.any?(first_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "customer-byo-questdb" and
               outcome.status == :source_execution_failed and
               outcome.warning_codes == [:source_unavailable] and
               outcome.operator_action == :inspect_source_failure and
               outcome.runtime_action == :retry_source_execution and
               outcome.actionable? and
               outcome.retryable?
           end)

    assert Enum.any?(first_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "managed-questdb" and
               outcome.status == :cache_disabled and
               outcome.warning_codes == []
           end)

    first_byo_warning =
      Enum.find(first.dashboard_warnings, fn warning ->
        warning.code == :source_unavailable and
          warning.details.data_source_id == "customer-byo-questdb"
      end)

    assert first_byo_warning.details.reason =~ "timeout after 50ms"

    flush_test_adapter_messages()

    second =
      Engine.resolve(request,
        data_sources: [byo_test_adapter_data_source(), managed_test_adapter_data_source()],
        data_bindings: [byo_telemetry_binding(), managed_telemetry_binding()],
        source_opts: source_opts,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_health_events?: false,
        record_source_health_events?: false,
        source_watermark_events?: false,
        now_ms: 10_001
      )

    second_outcomes =
      second
      |> SourceExecutionSemantics.summarize()
      |> Map.fetch!(:outcomes)

    assert Enum.any?(second_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "customer-byo-questdb" and
               outcome.status == :source_degraded and
               outcome.warning_codes == [:source_degraded] and
               outcome.operator_action == :inspect_source_health and
               outcome.runtime_action == :wait_for_source_health
           end)

    assert Enum.any?(second_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "managed-questdb" and
               outcome.status == :cache_disabled and
               outcome.warning_codes == []
           end)

    byo_warning =
      Enum.find(second.dashboard_warnings, fn warning ->
        warning.code == :source_degraded and
          warning.details.data_source_id == "customer-byo-questdb"
      end)

    assert byo_warning.details.circuit_state == :open
    assert byo_warning.details.failure_count == 1
    assert byo_warning.details.failure_threshold == 1
    assert byo_warning.details.retry_after_ms == 70_000
    assert byo_warning.details.last_failure_reason == :source_unavailable

    assert_received {:dashboard_source_test_adapter_request, "managed-questdb", :raw_series}
    refute_received {:dashboard_source_test_adapter_request, "customer-byo-questdb", :latest}
  end

  test "defines runtime and operator policy for every source execution status" do
    assert %{
             severity: :ok,
             actionable?: false,
             retryable?: false,
             dashboard_degraded?: false,
             operator_action: :none,
             runtime_action: :none
           } = SourceExecutionSemantics.status_policy(:cache_hit)

    assert %{
             severity: :warning,
             actionable?: false,
             retryable?: true,
             dashboard_degraded?: false,
             operator_action: :wait_for_refresh,
             runtime_action: :refresh_source_result
           } = SourceExecutionSemantics.status_policy(:cache_stale)

    assert %{
             severity: :error,
             actionable?: true,
             retryable?: true,
             dashboard_degraded?: true,
             operator_action: :inspect_source_failure,
             runtime_action: :retry_source_execution
           } = SourceExecutionSemantics.status_policy(:source_execution_failed)

    assert %{
             severity: :error,
             actionable?: true,
             retryable?: true,
             dashboard_degraded?: true,
             operator_action: :inspect_source_health,
             runtime_action: :wait_for_source_health
           } = SourceExecutionSemantics.status_policy(:source_unavailable)

    assert %{
             severity: :error,
             actionable?: true,
             retryable?: false,
             dashboard_degraded?: true,
             operator_action: :inspect_source_capability,
             runtime_action: :requires_configuration_change
           } = SourceExecutionSemantics.status_policy(:unsupported_capability)
  end

  defp source_opts do
    %{
      telemetry: [latest_fun: telemetry_latest_fun(), watermark_fun: watermark_fun()],
      limits: [latest_fun: limits_latest_fun(), watermark_fun: watermark_fun()]
    }
  end

  defp telemetry_latest_fun do
    fn _organization_id, mission_id, point_id, _opts ->
      telemetry_sample(mission_id, point_id)
    end
  end

  defp limits_latest_fun do
    fn _organization_id, mission_id, point_id, _opts ->
      limit_event(mission_id, point_id)
    end
  end

  defp watermark_fun do
    fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok,
       %{
         complete_through: ~U[2026-06-17 12:00:01Z],
         latest_receipt_time: ~U[2026-06-17 12:00:01Z],
         retention_starts_at: ~U[2026-06-17 11:00:00Z],
         sample_count: 1,
         confidence: :best_effort
       }}
    end
  end

  defp resolve_request(%Document{} = document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
    }
  end

  defp operational_resolve_request do
    "operational_status_matrix.v1.json"
    |> load_fixture!()
    |> resolve_request()
    |> Map.put(:scope_context, %{
      primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-contract-1"]}
    })
  end

  defp live_time_series_with_limits_document(annotation_layers \\ []) do
    attrs = load_fixture_map!("time_series_with_limits.v1.json")
    [placement] = attrs["placements"]

    placement =
      put_in(
        placement,
        ["content", "widget_def", "options", "annotation_layers"],
        annotation_layers
      )

    attrs
    |> put_in(["defaults", "time", "mode"], "live")
    |> Map.put("placements", [placement])
    |> Document.from_map()
  end

  defp telemetry_only_value_tile_document do
    attrs = load_fixture_map!("value_tile_latest.v1.json")
    [placement] = attrs["placements"]

    placement =
      put_in(placement, ["content", "widget_def", "binding", "overlays"], [])

    attrs
    |> put_in(["defaults", "overlays", "limits"], false)
    |> Map.put("placements", [placement])
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
    |> put_in(["defaults", "overlays", "limits"], false)
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  defp byo_managed_telemetry_execution_document do
    latest_attrs = load_fixture_map!("value_tile_latest.v1.json")
    [latest_placement] = latest_attrs["placements"]
    [history_placement] = load_fixture_map!("time_series_with_limits.v1.json")["placements"]

    latest_placement =
      latest_placement
      |> put_in(["content", "widget_def", "binding", "overlays"], [])
      |> Map.put("data_override", %{
        "realm" => "flight",
        "source_contexts" => %{
          "telemetry" => %{
            "data_source_id" => "customer-byo-questdb",
            "source_binding_id" => "customer-byo-telemetry",
            "dataset" => "customer-flight"
          }
        }
      })

    history_placement =
      history_placement
      |> put_in(["content", "widget_def", "binding", "sampling"], "raw_series")
      |> put_in(["content", "widget_def", "binding", "overlays"], [])
      |> Map.put("data_override", %{
        "realm" => "flight",
        "source_contexts" => %{
          "telemetry" => %{
            "data_source_id" => "managed-questdb",
            "source_binding_id" => "managed-telemetry",
            "dataset" => "flight"
          }
        }
      })

    latest_attrs
    |> put_in(["defaults", "overlays", "limits"], false)
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  defp unsupported_time_series_document do
    attrs = load_fixture_map!("time_series_with_limits.v1.json")
    [placement] = attrs["placements"]

    placement =
      put_in(placement, ["content", "widget_def", "binding", "overlays"], [])

    attrs
    |> put_in(["defaults", "overlays", "limits"], false)
    |> put_in(["defaults", "overlays", "events"], false)
    |> Map.put("placements", [placement])
    |> Document.from_map()
  end

  defp test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  defp byo_test_adapter_data_source do
    %DataSource{
      data_source_id: "customer-byo-questdb",
      owner: :customer,
      kind: :byo_tsdb,
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      isolation_level: :customer_owned,
      credentials_ref: "secret://org_dashboards/dashboard/customer-byo-questdb",
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true},
      metadata: %{
        dashboard_policy: %{
          execution: %{timeout_ms: 50},
          circuit_breaker: %{failure_threshold: 1, backoff_ms: 60_000}
        }
      }
    }
  end

  defp managed_test_adapter_data_source do
    %DataSource{
      data_source_id: "managed-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      isolation_level: :shared,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  defp source_contract_opts(mode, overrides \\ []) do
    Keyword.merge(
      [
        adapters: %{
          telemetry: Cadence.Support.DashboardSourceContractAdapter,
          limits: Cadence.Support.DashboardSourceContractAdapter,
          events: Cadence.Support.DashboardSourceContractAdapter,
          operational_observables: Cadence.Support.DashboardSourceContractAdapter
        },
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
        source_opts: %{
          telemetry: [mode: mode, test_pid: self()],
          limits: [mode: mode, test_pid: self()],
          events: [mode: mode, test_pid: self()],
          operational_observables: [mode: mode, test_pid: self()]
        },
        source_result_cache?: false,
        validate_dashboard_contract?: true
      ],
      overrides
    )
  end

  defp source_contract_source_opts(mode, extra_opts) do
    %{
      telemetry: Keyword.merge([mode: mode, test_pid: self()], extra_opts),
      limits: Keyword.merge([mode: mode, test_pid: self()], extra_opts),
      events: Keyword.merge([mode: mode, test_pid: self()], extra_opts),
      operational_observables: Keyword.merge([mode: mode, test_pid: self()], extra_opts)
    }
  end

  defp freshness_contract_source_opts(extra_opts) do
    source_contract_source_opts(:empty_result, extra_opts)
  end

  defp assert_contract_source_frequencies(outcomes) do
    assert Enum.frequencies_by(outcomes, & &1.logical_source) == %{
             telemetry: 1,
             limits: 2,
             events: 1,
             operational_observables: 1
           }
  end

  defp source_execution_outcomes(result) do
    result
    |> source_outcomes_by_warning_code(:source_unavailable)
  end

  defp source_summary_outcomes(result) do
    result
    |> SourceExecutionSemantics.summarize()
    |> Map.fetch!(:outcomes)
  end

  defp source_degraded_outcomes(result) do
    result
    |> source_outcomes_by_warning_code(:source_degraded)
  end

  defp source_outcomes_by_warning_code(result, warning_code) do
    warnings_by_request_id =
      result.dashboard_warnings
      |> Enum.filter(&(&1.code == warning_code))
      |> Map.new(fn warning -> {warning.details.source_request_id, warning} end)

    result
    |> SourceExecutionSemantics.summarize()
    |> Map.fetch!(:outcomes)
    |> Enum.map(fn outcome ->
      %{outcome: outcome, warning: Map.fetch!(warnings_by_request_id, outcome.request_id)}
    end)
  end

  defp source_warnings_by_request_id(results, warning_code) do
    results
    |> Enum.flat_map(& &1.dashboard_warnings)
    |> Enum.filter(&(&1.code == warning_code))
    |> Map.new(fn warning -> {warning.details.source_request_id, warning} end)
  end

  defp flush_contract_adapter_messages do
    receive do
      {:dashboard_source_contract_adapter_resolve, _logical_source} ->
        flush_contract_adapter_messages()
    after
      0 -> :ok
    end
  end

  defp flush_test_adapter_messages do
    receive do
      {:dashboard_source_test_adapter_request, _data_source_id, _sampling} ->
        flush_test_adapter_messages()
    after
      0 -> :ok
    end
  end

  defp assert_source_action_runtime_contexts(warning) do
    for action <- warning.details.actions do
      assert action.route == nil
      assert action.kind == :invoke
      assert action.context.source_request_id == warning.details.source_request_id
      assert action.context.logical_source == warning.details.logical_source
      assert action.context.data_source_id == warning.details.data_source_id
      assert action.context.source_binding_id == warning.details.source_binding_id
      assert action.context.realm == warning.details.realm
      assert action.context.dataset == warning.details.dataset
      assert action.context.time_mode == warning.details.time_mode
      assert action.context.time_axis == warning.details.time_axis
      assert action.context.requested_realm == warning.details.requested_realm

      assert action.query["data_source_id"] == warning.details.data_source_id
      assert action.query["source_binding_id"] == warning.details.source_binding_id
      assert action.query["logical_source"] == Atom.to_string(warning.details.logical_source)
      assert action.query["realm"] == Atom.to_string(warning.details.realm)
      refute Map.has_key?(action.query, "source_request_id")
    end
  end

  defp telemetry_binding(data_source_id) do
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

  defp byo_telemetry_binding do
    %DataBinding{
      telemetry_binding("customer-byo-questdb")
      | binding_id: "customer-byo-telemetry",
        dataset: "customer-flight"
    }
  end

  defp managed_telemetry_binding do
    %DataBinding{
      telemetry_binding("managed-questdb")
      | binding_id: "managed-telemetry",
        dataset: "flight"
    }
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp telemetry_sample(mission_id, point_id) do
    %Sample{
      sample_id: "semantic-sample-1",
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

  defp limit_event(mission_id, point_id) do
    %Event{
      limit_event_id: "semantic-limit-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "semantic-sample-1",
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
end
