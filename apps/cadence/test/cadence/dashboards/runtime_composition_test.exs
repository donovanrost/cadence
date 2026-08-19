defmodule Cadence.Dashboards.RuntimeCompositionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    ResolutionContext,
    RuntimeCache,
    RuntimeComposition,
    SourceExecutionPolicy
  }

  test "carries cache, source, readiness, circuit, and telemetry policies into engine options" do
    execution_defaults = %SourceExecutionPolicy{
      max_concurrency: 2,
      timeout_ms: 750,
      circuit_failure_threshold: 4,
      circuit_backoff_ms: 12_000,
      provenance: %{captured?: true}
    }

    composition =
      RuntimeComposition.new!(
        runtime_cache: RuntimeCache.client(:cache, call_timeout_ms: 125),
        runtime_invalidation?: false,
        source_execution_defaults: execution_defaults,
        source_readiness_policy: [policy_id: :strict, block_source_health: [:degraded]],
        source_circuit_breaker: :breaker,
        source_health_events?: false,
        record_source_health_events?: true,
        source_health_freshness: [default_max_age_ms: 5_000],
        source_watermark_events?: false,
        data_sources_persisted?: true
      )

    context = ResolutionContext.from_composition!(composition)

    assert context.runtime_cache == %RuntimeCache{server: :cache, call_timeout_ms: 125}
    refute context.runtime_invalidation?
    assert context.persisted?

    opts = ResolutionContext.to_engine_opts(context)
    assert opts[:source_execution_defaults] == execution_defaults
    assert opts[:source_readiness_policy].policy_id == :strict
    assert opts[:source_circuit_breaker?]
    assert opts[:source_circuit_breaker] == :breaker
    refute opts[:source_health_events?]
    assert opts[:record_source_health_events?]
    assert opts[:source_health_freshness] == [default_max_age_ms: 5_000]
    refute opts[:source_watermark_events?]

    telemetry_opts = get_in(opts, [:source_opts, :telemetry])
    assert is_map(telemetry_opts[:current_value_store_policy])
    assert is_map(telemetry_opts[:history_store_policy])
  end

  test "captured execution defaults avoid compatibility config reads during resolve" do
    defaults = %SourceExecutionPolicy{
      max_concurrency: 1,
      timeout_ms: :infinity,
      circuit_failure_threshold: 7,
      circuit_backoff_ms: 900,
      provenance: %{captured?: true}
    }

    assert %SourceExecutionPolicy{
             max_concurrency: 1,
             timeout_ms: :infinity,
             circuit_failure_threshold: 7,
             circuit_backoff_ms: 900,
             provenance: %{app_defaults?: false, explicit_opts?: false}
           } = SourceExecutionPolicy.resolve(source_execution_defaults: defaults)
  end
end
