defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyContextTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyContext

  test "build extracts late-data policy source fields from atom-key rows" do
    context =
      LateDataPolicyContext.build(%{
        rows: [
          %{label: "Backfill lifecycle event", value: "event-1"},
          %{label: "Event type", value: "backfill_completed"},
          %{label: "Backfill run", value: "run-1"},
          %{label: "Dashboard context time mode", value: "replay_run"},
          %{label: "Dashboard context replay run", value: "replay-1"},
          %{label: "Dashboard context data view", value: "all_revisions"},
          %{label: "Dashboard context limit mode", value: "compare"},
          %{label: "Realm", value: "flight"},
          %{label: "Data source", value: "questdb-flight"},
          %{label: "Source binding", value: "binding-flight"},
          %{label: "Observable", value: "HK.counter"},
          %{label: "Point", value: "HK.counter"},
          %{label: "Source from", value: "2026-06-22T10:00:00Z"},
          %{label: "Source to", value: "2026-06-22T11:00:00Z"},
          %{label: "Receipt from", value: "2026-06-22T12:00:00Z"},
          %{label: "Receipt to", value: "2026-06-22T12:10:00Z"},
          %{label: "Sample count", value: "3"},
          %{label: "Authority", value: "comparison"},
          %{label: "Reason", value: "late_packet_receipt"}
        ]
      })

    assert context == %{
             source_event_id: "event-1",
             source_event_type: "backfill_completed",
             run_id: "run-1",
             dashboard_time_mode: "replay_run",
             dashboard_replay_run_id: "replay-1",
             dashboard_data_view: "all_revisions",
             dashboard_limit_mode: "compare",
             realm: "flight",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             observable_id: "HK.counter",
             point_id: "HK.counter",
             source_from: "2026-06-22T10:00:00Z",
             source_to: "2026-06-22T11:00:00Z",
             receipt_from: "2026-06-22T12:00:00Z",
             receipt_to: "2026-06-22T12:10:00Z",
             sample_count: "3",
             authority: "comparison",
             reason: "late_packet_receipt"
           }
  end

  test "build supports string-key rows and normalizes blank values" do
    context =
      LateDataPolicyContext.build(%{
        rows: [
          %{"label" => "Backfill lifecycle event", "value" => "event-1"},
          %{"label" => "Event type", "value" => "backfill_completed"},
          %{"label" => "Backfill run", "value" => ""},
          %{"label" => "Authority", "value" => ""},
          %{"label" => "Reason", "value" => nil}
        ]
      })

    assert context.source_event_id == "event-1"
    assert context.source_event_type == "backfill_completed"
    assert context.run_id == nil
    assert context.authority == nil
    assert context.reason == nil
  end

  test "build extracts dashboard runtime context from link context rows for source lifecycle events" do
    context =
      LateDataPolicyContext.build(%{
        rows: [
          %{label: "Backfill lifecycle event", value: "event-1"},
          %{label: "Event type", value: "backfill_completed"},
          %{label: "Backfill run", value: "run-1"}
        ],
        context_rows: [
          %{label: "Time mode", value: "replay_run"},
          %{label: "Replay run", value: "replay-1"},
          %{label: "Data view", value: "all_revisions"},
          %{label: "Limit mode", value: "recomputed"}
        ]
      })

    assert context.dashboard_time_mode == "replay_run"
    assert context.dashboard_replay_run_id == "replay-1"
    assert context.dashboard_data_view == "all_revisions"
    assert context.dashboard_limit_mode == "recomputed"
  end

  test "build returns empty-compatible context when inspector is missing rows" do
    context = LateDataPolicyContext.build(%{})

    assert context.source_event_id == nil
    assert context.source_event_type == nil
    assert context.run_id == nil
    assert context.realm == nil
    assert context.data_source_id == nil
    assert context.source_binding_id == nil
    assert context.dashboard_time_mode == nil
    assert context.dashboard_replay_run_id == nil
    assert context.dashboard_data_view == nil
    assert context.dashboard_limit_mode == nil
  end
end
