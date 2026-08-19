defmodule Cadence.Dashboards.ResolutionContextTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{ResolutionContext, RuntimeCache}

  test "converts typed resolution policy to explicit engine options" do
    context =
      ResolutionContext.new!(
        persisted?: true,
        validate_dashboard_contract?: true,
        persist_limit_selected_clock_audit_events?: true,
        runtime_cache: RuntimeCache.client(:cache, call_timeout_ms: 250),
        plan_cache?: true,
        source_result_cache?: true,
        frame_cache?: false,
        source_execution_opts: [source_execution_timeout_ms: 500, now: ~U[2026-08-17 12:00:00Z]]
      )

    assert ResolutionContext.to_engine_opts(context) == [
             frame_cache?: false,
             source_result_cache?: true,
             plan_cache?: true,
             runtime_cache: %RuntimeCache{server: :cache, call_timeout_ms: 250},
             persist_limit_selected_clock_audit_events?: true,
             validate_dashboard_contract?: true,
             persisted?: true,
             source_execution_timeout_ms: 500,
             now: ~U[2026-08-17 12:00:00Z]
           ]
  end

  test "rejects source execution options that override owned resolution policy" do
    assert_raise ArgumentError, ~r/cannot override resolution context keys/, fn ->
      ResolutionContext.new!(source_execution_opts: [persisted?: true])
    end
  end
end
