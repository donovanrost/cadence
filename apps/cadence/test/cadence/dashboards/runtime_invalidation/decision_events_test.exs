defmodule Cadence.Dashboards.RuntimeInvalidation.DecisionEventsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, RuntimeInvalidation}
  alias Cadence.Dashboards.RuntimeInvalidation.Event

  test "records and lists durable dashboard runtime invalidation decisions" do
    persist_mission_scope("org-runtime-decision-events", "mission-runtime-decision-events")

    dashboard =
      persist_dashboard!(
        "org-runtime-decision-events",
        "mission-runtime-decision-events",
        "dashboard-runtime-decision-events"
      )

    invalidation =
      invalidation_event(
        dashboard,
        %{source_results: 1, frames: 2, total: 3},
        ~U[2026-06-24 12:00:00Z]
      )

    decision = %{
      dashboard_id: dashboard.dashboard_id,
      organization_id: dashboard.organization_id,
      mission_id: dashboard.mission_id,
      matches?: false,
      dashboard_matches?: true,
      context_matches?: false,
      context_reason: :replay_run_mismatch,
      refresh_allowed?: false,
      refresh_reason: :stale_for_context,
      affected_placement_count: 2,
      affected_placement_ids: ["placement-counter", "placement-trend"],
      affected_widget_type_ids: ["cadence.value_tile", "cadence.trend_chart"],
      affected_impact_reasons: [:primary_source, :secondary_source],
      selection_state: :active,
      selected_link_id: "telemetry-sample-link",
      selected_target: :telemetry_sample,
      selected_target_id: "sample-1",
      selected_placement_id: "placement-counter",
      selected_observable_id: "HK.counter",
      selected_data_view: :all_revisions,
      selection_affected?: true,
      selection_impact_reason: :affected_placement,
      source_cache_evidence_state_summary: %{total: 3, resolved: 1, context_only: 1, missing: 1},
      source_cache_evidence_target_ids: ["source_health_event:source-health-event-1"],
      source_cache_evidence_request_ids: ["req-telemetry", "req-limits"],
      source_execution_retryable_count: 3,
      source_execution_actionable_count: 2,
      source_execution_degraded_count: 2,
      source_execution_status_summary: %{
        cache_stale: 1,
        source_unavailable: 1,
        source_degraded: 1
      },
      source_execution_severity_summary: %{warning: 2, error: 1},
      source_execution_runtime_action_summary: %{
        refresh_source_result: 1,
        wait_for_source_health: 2
      },
      source_execution_operator_action_summary: %{
        wait_for_refresh: 1,
        inspect_source_health: 2
      },
      source_execution_degraded_identities: [
        "telemetry:req-circuit:source_degraded",
        "telemetry:req-unavailable:source_unavailable"
      ],
      source_execution_degraded_actions: [
        "telemetry:req-circuit:wait_for_source_health:inspect_source_health",
        "telemetry:req-unavailable:wait_for_source_health:inspect_source_health"
      ],
      source_dependency_degraded_count: 1,
      source_dependency_evidence: [
        "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
      ],
      decision_status: :filtered
    }

    assert {:ok, event} =
             Cadence.record_dashboard_runtime_invalidation_decision(
               invalidation,
               decision,
               invalidation_event_id: Event.id(invalidation),
               decision_observed_at: ~U[2026-06-24 12:00:05Z]
             )

    assert event.dashboard_id == dashboard.dashboard_id
    assert event.context_reason == :replay_run_mismatch
    assert event.affected_placement_ids == ["placement-counter", "placement-trend"]

    assert [row] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id,
               decision_status: :filtered,
               refresh_allowed?: false
             )

    assert row.dashboard_runtime_invalidation_decision_event_id ==
             event.dashboard_runtime_invalidation_decision_event_id

    assert row.invalidation_event_id == Event.id(invalidation)
    assert row.dashboard_id == dashboard.dashboard_id
    assert row.organization_id == dashboard.organization_id
    assert row.mission_id == dashboard.mission_id
    assert row.boundary == :source_watermark_changed
    assert row.domain_fact == :source_watermark_changed
    assert row.decision_status == :filtered
    assert row.matches? == false
    assert row.context_reason == :replay_run_mismatch
    assert row.refresh_allowed? == false
    assert row.refresh_reason == :stale_for_context
    assert row.affected_placement_count == 2
    assert row.affected_placement_ids == ["placement-counter", "placement-trend"]
    assert row.affected_widget_type_ids == ["cadence.value_tile", "cadence.trend_chart"]
    assert row.affected_impact_reasons == [:primary_source, :secondary_source]
    assert row.selection_state == :active
    assert row.selected_link_id == "telemetry-sample-link"
    assert row.selected_target == :telemetry_sample
    assert row.selected_target_id == "sample-1"
    assert row.selected_placement_id == "placement-counter"
    assert row.selected_observable_id == "HK.counter"
    assert row.selected_data_view == :all_revisions
    assert row.selection_affected? == true
    assert row.selection_impact_reason == :affected_placement

    assert row.source_cache_evidence_state_summary == %{
             total: 3,
             resolved: 1,
             context_only: 1,
             missing: 1
           }

    assert row.source_cache_evidence_target_ids == [
             "source_health_event:source-health-event-1"
           ]

    assert row.source_cache_evidence_request_ids == ["req-telemetry", "req-limits"]
    assert row.source_execution_retryable_count == 3
    assert row.source_execution_actionable_count == 2
    assert row.source_execution_degraded_count == 2

    assert row.source_execution_status_summary == %{
             cache_stale: 1,
             source_unavailable: 1,
             source_degraded: 1
           }

    assert row.source_execution_severity_summary == %{warning: 2, error: 1}

    assert row.source_execution_runtime_action_summary == %{
             refresh_source_result: 1,
             wait_for_source_health: 2
           }

    assert row.source_execution_operator_action_summary == %{
             wait_for_refresh: 1,
             inspect_source_health: 2
           }

    assert row.source_execution_degraded_identities == [
             "telemetry:req-circuit:source_degraded",
             "telemetry:req-unavailable:source_unavailable"
           ]

    assert row.source_execution_degraded_actions == [
             "telemetry:req-circuit:wait_for_source_health:inspect_source_health",
             "telemetry:req-unavailable:wait_for_source_health:inspect_source_health"
           ]

    assert row.source_dependency_degraded_count == 1

    assert row.source_dependency_evidence == [
             "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
           ]

    assert row.invalidated_artifacts == 3
    assert DateTime.compare(row.invalidation_occurred_at, ~U[2026-06-24 12:00:00Z]) == :eq
    assert DateTime.compare(row.decision_observed_at, ~U[2026-06-24 12:00:05Z]) == :eq
    assert row.filters.logical_source == :telemetry
    assert row.measurements.total == 3
    assert row.decision.context_reason == :replay_run_mismatch
    assert row.source_event_present?

    assert [^row] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id,
               affected_placement_id: "placement-counter"
             )

    assert [^row] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               dashboard_runtime_invalidation_decision_event_id:
                 event.dashboard_runtime_invalidation_decision_event_id
             )

    assert [^row] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               decision_event_id: event.dashboard_runtime_invalidation_decision_event_id
             )

    assert [] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               decision_event_id: "missing-dashboard-runtime-decision"
             )

    assert [] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id,
               affected_placement_id: "placement-missing"
             )

    assert [^row] =
             Cadence.dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id
             )
  end

  test "lists durable source decisions by replay run filter" do
    persist_mission_scope("org-runtime-decision-replay", "mission-runtime-decision-replay")

    dashboard =
      persist_dashboard!(
        "org-runtime-decision-replay",
        "mission-runtime-decision-replay",
        "dashboard-runtime-decision-replay"
      )

    watermark_invalidation =
      invalidation_event(
        dashboard,
        %{source_results: 1, frames: 1, total: 2},
        ~U[2026-06-24 12:00:00Z],
        boundary: :source_watermark_changed,
        replay_run_id: "replay-run-1"
      )

    health_invalidation =
      invalidation_event(
        dashboard,
        %{source_results: 1, frames: 1, total: 2},
        ~U[2026-06-24 12:01:00Z],
        boundary: :source_health_changed,
        replay_run_id: "replay-run-1"
      )

    other_invalidation =
      invalidation_event(
        dashboard,
        %{source_results: 1, frames: 1, total: 2},
        ~U[2026-06-24 12:02:00Z],
        boundary: :source_watermark_changed,
        replay_run_id: "replay-run-2"
      )

    for invalidation <- [watermark_invalidation, health_invalidation, other_invalidation] do
      assert {:ok, _event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 invalidation,
                 %{
                   dashboard_id: dashboard.dashboard_id,
                   organization_id: dashboard.organization_id,
                   mission_id: dashboard.mission_id,
                   matches?: true,
                   dashboard_matches?: true,
                   context_matches?: true,
                   context_reason: :matched,
                   refresh_allowed?: true,
                   refresh_reason: :allowed,
                   decision_status: :refresh_allowed
                 },
                 invalidation_event_id: Event.id(invalidation),
                 decision_observed_at: DateTime.add(invalidation.occurred_at, 5, :second)
               )
    end

    assert [newer, older] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id,
               replay_run_id: "replay-run-1"
             )

    assert newer.boundary == :source_health_changed
    assert newer.filters.replay_run_id == "replay-run-1"
    assert older.boundary == :source_watermark_changed
    assert older.filters.replay_run_id == "replay-run-1"

    assert [watermark] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id,
               replay_run_id: "replay-run-1",
               boundary: :source_watermark_changed
             )

    assert watermark.boundary == :source_watermark_changed

    assert [] =
             Cadence.durable_dashboard_runtime_invalidation_decisions(
               organization_id: dashboard.organization_id,
               mission_id: dashboard.mission_id,
               dashboard_id: dashboard.dashboard_id,
               replay_run_id: "missing-replay-run"
             )
  end

  test "public decision read falls back to runtime-health memory when no durable row exists" do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)

    invalidation =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{
          organization_id: "org-runtime-fallback",
          mission_id: "mission-runtime-fallback",
          logical_source: :telemetry,
          observable: "HK.counter"
        },
        %{},
        %{source_results: 1, frames: 1, total: 2},
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    RuntimeInvalidation.emit_decision(
      invalidation,
      %{
        dashboard_id: "dashboard-runtime-fallback",
        organization_id: "org-runtime-fallback",
        mission_id: "mission-runtime-fallback",
        matches?: false,
        dashboard_matches?: true,
        context_matches?: false,
        context_reason: :replay_run_mismatch,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        decision_status: :filtered
      },
      invalidation_event_id: Event.id(invalidation)
    )

    Cadence.runtime_health_snapshot()

    assert [row] =
             Cadence.dashboard_runtime_invalidation_decisions(
               organization_id: "org-runtime-fallback",
               mission_id: "mission-runtime-fallback",
               dashboard_id: "dashboard-runtime-fallback"
             )

    assert row.invalidation_event_id == Event.id(invalidation)
    assert row.source_event_present? == false
  end

  defp persist_dashboard!(organization_id, mission_id, dashboard_id) do
    document = %Document{
      dashboard_id: dashboard_id,
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Runtime Decision Audit"
    }

    assert {:ok, %Document{} = persisted} = Dashboards.persist_document(organization_id, document)
    persisted
  end

  defp invalidation_event(%Document{} = dashboard, measurements, occurred_at, opts \\ []) do
    Event.new(
      Keyword.get(opts, :boundary, :source_watermark_changed),
      [:source_result, :frame],
      %{
        organization_id: dashboard.organization_id,
        mission_id: dashboard.mission_id,
        logical_source: :telemetry,
        observable: "HK.counter"
      }
      |> maybe_put(:replay_run_id, Keyword.get(opts, :replay_run_id)),
      %{},
      measurements,
      occurred_at: occurred_at
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
