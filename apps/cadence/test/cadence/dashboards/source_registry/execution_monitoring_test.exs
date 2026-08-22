defmodule Cadence.Dashboards.SourceRegistry.ExecutionMonitoringTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.{
    ResolvedSourceBinding,
    ResolveWarning,
    SourceCircuitBreaker,
    SourceExecutionPolicy,
    SourceResult
  }

  alias Cadence.Dashboards.SourceRegistry.ExecutionMonitoring

  test "allows execution when the circuit breaker is explicitly disabled" do
    assert {:allow, %{}} =
             ExecutionMonitoring.allow(
               source_request(),
               resolved_binding(),
               policy(),
               source_circuit_breaker?: false
             )
  end

  test "records adapter failures in the circuit and clears it after success" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    request = source_request()
    resolved_binding = resolved_binding()

    opts = [
      source_circuit_breaker: breaker,
      record_source_health_events?: false,
      now_ms: 1_000
    ]

    assert :ok =
             ExecutionMonitoring.record_result(
               request,
               resolved_binding,
               error_result(),
               policy(),
               opts
             )

    assert {:blocked,
            %{
              state: :open,
              failure_count: 1,
              failure_threshold: 1,
              retry_after_ms: 6_000
            }} = ExecutionMonitoring.allow(request, resolved_binding, policy(), opts)

    assert :ok =
             ExecutionMonitoring.record_result(
               request,
               resolved_binding,
               %SourceResult{},
               policy(),
               opts
             )

    assert {:allow, %{state: :closed, failure_count: 0}} =
             ExecutionMonitoring.allow(request, resolved_binding, policy(), opts)
  end

  test "keeps circuit state isolated by physical source identity" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    request = source_request()
    flight_binding = resolved_binding()
    rehearsal_binding = resolved_binding(:rehearsal)

    opts = [
      source_circuit_breaker: breaker,
      record_source_health_events?: false,
      now_ms: 1_000
    ]

    assert :ok =
             ExecutionMonitoring.record_result(
               request,
               flight_binding,
               error_result(),
               policy(),
               opts
             )

    assert {:blocked, %{state: :open}} =
             ExecutionMonitoring.allow(request, flight_binding, policy(), opts)

    assert {:allow, %{state: :closed}} =
             ExecutionMonitoring.allow(request, rehearsal_binding, policy(), opts)
  end

  test "builds concrete source-health identity attributes" do
    assert ExecutionMonitoring.health_attributes(
             source_request(),
             resolved_binding(),
             :degraded,
             :source_unavailable
           ) == %{
             organization_id: "org-1",
             mission_id: "mission-1",
             logical_source: :telemetry,
             data_source_id: "flight-source",
             source_binding_id: "flight-telemetry",
             realm: :flight,
             dataset: "flight",
             source_health: :degraded,
             reason: :source_unavailable
           }
  end

  defp resolved_binding(realm \\ :flight) do
    data_source_id = "#{realm}-source"

    %ResolvedSourceBinding{
      binding: data_binding(data_source_id, realm),
      data_source: data_source(data_source_id, []),
      realm: realm,
      dataset: Atom.to_string(realm)
    }
  end

  defp policy do
    %SourceExecutionPolicy{
      circuit_failure_threshold: 1,
      circuit_backoff_ms: 5_000
    }
  end

  defp error_result do
    %SourceResult{
      warnings: [
        %ResolveWarning{
          code: :source_unavailable,
          severity: :error
        }
      ]
    }
  end
end
