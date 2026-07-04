defmodule Cadence.Dashboards.RuntimeInvalidation.DecisionProjectionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.DecisionProjection
  alias Cadence.Dashboards.RuntimeInvalidation.Event

  test "projects runtime health decision events with source invalidation details" do
    invalidation =
      invalidation_event(
        :historical_data_changed,
        %{
          organization_id: "org-1",
          mission_id: "mission-1",
          logical_source: :telemetry,
          observable: "HK.counter",
          replay_run_id: "replay-1"
        },
        %{total: 4},
        ~U[2026-06-24 12:00:00Z]
      )

    events = [
      recent_invalidation(invalidation),
      recent_decision(invalidation,
        dashboard_id: "dashboard-1",
        matches?: false,
        context_reason: :replay_run_mismatch,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        affected_placement_count: 2,
        affected_placement_ids: ["placement-counter", "placement-trend"],
        affected_widget_type_ids: ["cadence.value_tile", "cadence.trend_chart"],
        affected_impact_reasons: [:primary_source, :secondary_source],
        decision_status: :filtered,
        observed_at: ~U[2026-06-24 12:00:05Z]
      )
    ]

    assert [row] = DecisionProjection.list(%{recent_events: events})
    assert row.invalidation_event_id == Event.id(invalidation)
    assert row.dashboard_id == "dashboard-1"
    assert row.organization_id == "org-1"
    assert row.mission_id == "mission-1"
    assert row.boundary == :historical_data_changed
    assert row.domain_fact == :historical_data_changed
    assert row.decision_status == :filtered
    assert row.matches? == false
    assert row.context_reason == :replay_run_mismatch
    assert row.refresh_allowed? == false
    assert row.refresh_reason == :stale_for_context
    assert row.affected_placement_count == 2
    assert row.affected_placement_ids == ["placement-counter", "placement-trend"]
    assert row.affected_widget_type_ids == ["cadence.value_tile", "cadence.trend_chart"]
    assert row.affected_impact_reasons == [:primary_source, :secondary_source]
    assert row.invalidated_artifacts == 4
    assert row.invalidation_occurred_at == ~U[2026-06-24 12:00:00Z]
    assert row.decision_observed_at == ~U[2026-06-24 12:00:05Z]
    assert row.filters.replay_run_id == "replay-1"
    assert row.source_event_present?
  end

  test "filters projected decisions and returns newest first" do
    first =
      invalidation_event(
        :source_watermark_changed,
        %{organization_id: "org-1", mission_id: "mission-1", observable: "HK.counter"},
        %{total: 1},
        ~U[2026-06-24 12:00:00Z]
      )

    second =
      invalidation_event(
        :source_watermark_changed,
        %{organization_id: "org-1", mission_id: "mission-2", observable: "HK.counter"},
        %{total: 1},
        ~U[2026-06-24 12:01:00Z]
      )

    events = [
      recent_decision(first,
        dashboard_id: "dashboard-1",
        decision_status: :refresh_suppressed,
        refresh_allowed?: false,
        observed_at: ~U[2026-06-24 12:00:05Z]
      ),
      recent_decision(second,
        dashboard_id: "dashboard-2",
        decision_status: :refresh_allowed,
        refresh_allowed?: true,
        observed_at: ~U[2026-06-24 12:01:05Z]
      )
    ]

    assert [%{dashboard_id: "dashboard-2"}, %{dashboard_id: "dashboard-1"}] =
             DecisionProjection.list(events)

    assert [%{dashboard_id: "dashboard-1"}] =
             DecisionProjection.list(events,
               mission_id: "mission-1",
               dashboard_id: "dashboard-1",
               decision_status: :refresh_suppressed,
               refresh_allowed?: false
             )

    assert [] = DecisionProjection.list(events, mission_id: "mission-missing")
  end

  test "filters projected source decisions by replay run" do
    watermark =
      invalidation_event(
        :source_watermark_changed,
        %{
          organization_id: "org-1",
          mission_id: "mission-1",
          observable: "HK.counter",
          replay_run_id: "replay-run-1"
        },
        %{total: 2},
        ~U[2026-06-24 12:00:00Z]
      )

    health =
      invalidation_event(
        :source_health_changed,
        %{
          organization_id: "org-1",
          mission_id: "mission-1",
          observable: "HK.counter",
          replay_run_id: "replay-run-1"
        },
        %{total: 1},
        ~U[2026-06-24 12:01:00Z]
      )

    other =
      invalidation_event(
        :source_watermark_changed,
        %{
          organization_id: "org-1",
          mission_id: "mission-1",
          observable: "HK.counter",
          replay_run_id: "replay-run-2"
        },
        %{total: 1},
        ~U[2026-06-24 12:02:00Z]
      )

    events = [
      recent_decision(watermark, dashboard_id: "dashboard-1"),
      recent_decision(health, dashboard_id: "dashboard-1"),
      recent_decision(other, dashboard_id: "dashboard-1")
    ]

    assert [%{boundary: :source_health_changed}, %{boundary: :source_watermark_changed}] =
             DecisionProjection.list(events,
               dashboard_id: "dashboard-1",
               replay_run_id: "replay-run-1"
             )

    assert [%{boundary: :source_watermark_changed, filters: %{replay_run_id: "replay-run-1"}}] =
             DecisionProjection.list(events,
               dashboard_id: "dashboard-1",
               replay_run_id: "replay-run-1",
               boundary: :source_watermark_changed
             )

    assert [] =
             DecisionProjection.list(events,
               dashboard_id: "dashboard-1",
               replay_run_id: "missing-replay-run"
             )
  end

  test "uses decision metadata when source invalidation is no longer in recent events" do
    invalidation =
      invalidation_event(
        :source_health_changed,
        %{organization_id: "org-1", mission_id: "mission-1", observable: "HK.counter"},
        %{total: 2},
        ~U[2026-06-24 12:00:00Z]
      )

    assert [row] =
             DecisionProjection.list([
               recent_decision(invalidation,
                 dashboard_id: "dashboard-1",
                 decision_status: :refresh_allowed,
                 refresh_allowed?: true
               )
             ])

    assert row.boundary == :source_health_changed
    assert row.invalidated_artifacts == 2
    assert row.invalidation_occurred_at == ~U[2026-06-24 12:00:00Z]
    refute row.source_event_present?
  end

  defp invalidation_event(boundary, filters, measurements, occurred_at) do
    Event.new(
      boundary,
      [:source_result, :frame],
      filters,
      %{source_result: filters, frame: filters},
      measurements,
      occurred_at: occurred_at
    )
  end

  defp recent_invalidation(%Event{} = event) do
    %{
      source: :dashboards_runtime_invalidation,
      event: :invalidate,
      event_name: RuntimeInvalidation.telemetry_event(),
      observed_at: event.occurred_at,
      metadata: Event.to_telemetry_metadata(event, :runtime_cache),
      measurements: event.measurements,
      runtime_event: event
    }
  end

  defp recent_decision(%Event{} = event, opts) do
    observed_at = Keyword.get(opts, :observed_at, DateTime.add(event.occurred_at, 1, :second))

    decision =
      %{
        dashboard_id: Keyword.get(opts, :dashboard_id, "dashboard-1"),
        organization_id: event.filters.organization_id,
        mission_id: event.filters.mission_id,
        matches?: Keyword.get(opts, :matches?, true),
        dashboard_matches?: Keyword.get(opts, :dashboard_matches?, true),
        context_matches?: Keyword.get(opts, :context_matches?, true),
        context_reason: Keyword.get(opts, :context_reason, :matched),
        refresh_allowed?: Keyword.get(opts, :refresh_allowed?, true),
        refresh_reason: Keyword.get(opts, :refresh_reason, :allowed),
        affected_placement_count: Keyword.get(opts, :affected_placement_count),
        affected_placement_ids: Keyword.get(opts, :affected_placement_ids),
        affected_widget_type_ids: Keyword.get(opts, :affected_widget_type_ids),
        affected_impact_reasons: Keyword.get(opts, :affected_impact_reasons),
        decision_status: Keyword.get(opts, :decision_status, :refresh_allowed)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    metadata =
      event
      |> Event.to_telemetry_metadata(:runtime_cache)
      |> Map.put(:invalidation_event_id, Event.id(event))
      |> Map.put(:decision, decision)
      |> Map.merge(decision)

    %{
      source: :dashboards_runtime_invalidation,
      event: :decision,
      event_name: RuntimeInvalidation.decision_telemetry_event(),
      observed_at: observed_at,
      metadata: metadata,
      measurements: %{total: 1}
    }
  end
end
