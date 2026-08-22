defmodule Cadence.Dashboards.SourceCircuitBreakerTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{PlannedSourceRequest, ResolvedSourceBinding, SourceCircuitBreaker}

  alias Cadence.DataSources.{DataBinding, DataSource}

  test "keys include tenant mission logical source data source realm and dataset" do
    request = source_request(realm: :rehearsal)
    binding = resolved_binding("rehearsal-questdb", :rehearsal)

    assert SourceCircuitBreaker.source_key(request, binding) ==
             {"org-1", "mission-1", :telemetry, "rehearsal-questdb", :rehearsal, "rehearsal"}
  end

  test "opens after the configured threshold and allows one half-open retry after backoff" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    key = {"org-1", "mission-1", :telemetry, "flight-questdb", :flight, "flight"}
    opts = [failure_threshold: 2, backoff_ms: 100, now_ms: 1_000]

    assert {:allow, %{state: :closed, failure_count: 0}} =
             SourceCircuitBreaker.allow?(breaker, key, opts)

    assert %{state: :closed, failure_count: 1} =
             SourceCircuitBreaker.record_failure(breaker, key, :timeout, opts)

    assert %{state: :open, failure_count: 2, retry_after_ms: 1_100} =
             SourceCircuitBreaker.record_failure(breaker, key, :timeout, opts)

    assert {:blocked, %{state: :open, failure_count: 2}} =
             SourceCircuitBreaker.allow?(breaker, key, Keyword.put(opts, :now_ms, 1_050))

    assert {:allow, %{state: :half_open, failure_count: 2}} =
             SourceCircuitBreaker.allow?(breaker, key, Keyword.put(opts, :now_ms, 1_100))

    assert {:blocked, %{state: :half_open, failure_count: 2}} =
             SourceCircuitBreaker.allow?(breaker, key, Keyword.put(opts, :now_ms, 1_100))

    assert :ok = SourceCircuitBreaker.record_success(breaker, key, opts)

    assert %{state: :closed, failure_count: 0} =
             SourceCircuitBreaker.status(breaker, key, opts)
  end

  test "keeps physical sources isolated even when they share a logical source" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    opts = [failure_threshold: 1, backoff_ms: 100, now_ms: 1_000]
    flight_key = {"org-1", "mission-1", :telemetry, "flight-questdb", :flight, "flight"}

    rehearsal_key =
      {"org-1", "mission-1", :telemetry, "rehearsal-questdb", :rehearsal, "rehearsal"}

    assert %{state: :open} =
             SourceCircuitBreaker.record_failure(breaker, flight_key, :timeout, opts)

    assert {:blocked, %{state: :open}} =
             SourceCircuitBreaker.allow?(breaker, flight_key, opts)

    assert {:allow, %{state: :closed}} =
             SourceCircuitBreaker.allow?(breaker, rehearsal_key, opts)
  end

  defp source_request(overrides) do
    attrs = %{
      request_id: "source-request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      data_context: %{realm: Keyword.fetch!(overrides, :realm)}
    }

    struct!(PlannedSourceRequest, attrs)
  end

  defp resolved_binding(data_source_id, realm) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "#{realm}-telemetry",
        realm: realm,
        logical_source: :telemetry,
        data_source_id: data_source_id,
        dataset: Atom.to_string(realm)
      },
      data_source: %DataSource{
        data_source_id: data_source_id,
        adapter: Cadence.Support.DashboardSourceTestAdapter
      },
      realm: realm,
      dataset: Atom.to_string(realm)
    }
  end
end
