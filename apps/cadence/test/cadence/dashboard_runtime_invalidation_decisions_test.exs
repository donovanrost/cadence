defmodule Cadence.DashboardRuntimeInvalidationDecisionsTest do
  use ExUnit.Case, async: false

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.Event

  setup do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)

    :ok
  end

  test "projects dashboard runtime invalidation decisions from runtime health" do
    invalidation =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{
          organization_id: "org-health",
          mission_id: "mission-health",
          logical_source: :telemetry,
          observable: "HK.counter",
          replay_run_id: "replay-health-1"
        },
        %{},
        %{source_results: 1, frames: 1, total: 2},
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    RuntimeInvalidation.emit_decision(
      invalidation,
      %{
        dashboard_id: "dashboard-health",
        organization_id: "org-health",
        mission_id: "mission-health",
        matches?: false,
        dashboard_matches?: true,
        context_matches?: false,
        context_reason: :replay_run_mismatch,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        affected_placement_count: 1,
        affected_placement_ids: ["placement-health"],
        affected_widget_type_ids: ["cadence.value_tile"],
        affected_impact_reasons: [:primary_source],
        decision_status: :filtered
      },
      invalidation_event_id: Event.id(invalidation)
    )

    assert_eventually(fn ->
      assert [decision] =
               Cadence.dashboard_runtime_invalidation_decisions(
                 organization_id: "org-health",
                 mission_id: "mission-health",
                 dashboard_id: "dashboard-health",
                 decision_status: :filtered,
                 replay_run_id: "replay-health-1"
               )

      assert decision.invalidation_event_id == Event.id(invalidation)
      assert decision.boundary == :source_watermark_changed
      assert decision.filters.replay_run_id == "replay-health-1"
      assert decision.context_reason == :replay_run_mismatch
      assert decision.refresh_allowed? == false
      assert decision.affected_placement_count == 1
      assert decision.affected_placement_ids == ["placement-health"]
      assert decision.affected_widget_type_ids == ["cadence.value_tile"]
      assert decision.affected_impact_reasons == [:primary_source]
    end)

    assert [] =
             Cadence.dashboard_runtime_invalidation_decisions(
               organization_id: "org-health",
               mission_id: "mission-health",
               dashboard_id: "dashboard-health",
               decision_status: :filtered,
               replay_run_id: "replay-health-missing"
             )
  end

  defp assert_eventually(assertion, attempts_left \\ 20)

  defp assert_eventually(assertion, attempts_left) when attempts_left > 0 do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      assert_eventually(assertion, attempts_left - 1)
  end

  defp assert_eventually(assertion, 0), do: assertion.()
end
