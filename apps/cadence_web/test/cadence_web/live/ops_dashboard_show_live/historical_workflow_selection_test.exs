defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelectionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataLink

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowParams,
    HistoricalWorkflowSelection,
    HistoricalWorkflowSelectionResult,
    SelectionQuery
  }

  describe "event_link/2" do
    test "builds a telemetry backfill lifecycle event data link from event fields" do
      event = %{
        backfill_lifecycle_event_id: "event-1",
        observable_id: "obs-1",
        point_id: "point-1",
        realm: "backfill",
        data_source_id: "source-1",
        binding_id: "binding-1"
      }

      assert %DataLink{
               label: "Telemetry backfill lifecycle event",
               target: :telemetry_backfill_lifecycle_event,
               target_id: "event-1",
               context: %{
                 logical_source: :events,
                 observable_id: "obs-1",
                 data: %{
                   realm: "backfill",
                   data_source_id: "source-1",
                   source_binding_id: "binding-1"
                 }
               },
               source: :frame
             } = HistoricalWorkflowSelection.event_link(event, %{})
    end

    test "falls back to submitted params when event context is sparse" do
      event = %{
        backfill_lifecycle_event_id: "event-1",
        observable_id: nil,
        point_id: nil,
        realm: nil,
        data_source_id: nil,
        binding_id: nil
      }

      params = %{
        "point-id" => "point-1",
        "realm" => "backfill",
        "data-source-id" => "source-1",
        "source-binding-id" => "binding-1"
      }

      assert %DataLink{
               context: %{
                 observable_id: "point-1",
                 data: %{
                   realm: "backfill",
                   data_source_id: "source-1",
                   source_binding_id: "binding-1"
                 }
               }
             } = HistoricalWorkflowSelection.event_link(event, params)
    end

    test "falls back to typed submitted params when event context is sparse" do
      event = %{
        backfill_lifecycle_event_id: "event-1",
        observable_id: nil,
        point_id: nil,
        realm: nil,
        data_source_id: nil,
        binding_id: nil
      }

      params =
        HistoricalWorkflowParams.event_params(%{
          "point_id" => "point-1",
          "realm" => "backfill",
          "data_source_id" => "source-1",
          "source_binding_id" => "binding-1"
        })

      assert %DataLink{
               context: %{
                 observable_id: "point-1",
                 data: %{
                   realm: "backfill",
                   data_source_id: "source-1",
                   source_binding_id: "binding-1"
                 }
               }
             } = HistoricalWorkflowSelection.event_link(event, params)
    end

    test "builds query-only event links from event ids" do
      assert %DataLink{
               target: :telemetry_backfill_lifecycle_event,
               target_id: "event-1",
               context: %{logical_source: :events},
               source: :frame
             } = HistoricalWorkflowSelection.event_link("event-1")
    end
  end

  describe "event_query/1" do
    test "builds a data-link query for a lifecycle event" do
      query = HistoricalWorkflowSelection.event_query("event-1")

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "event-1"
             }
    end

    test "preserves replay dashboard context in lifecycle event data-link queries" do
      query =
        HistoricalWorkflowSelection.event_query("event-1", %{
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "compare"
        })

      assert SelectionQuery.to_params(query) == %{
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "event-1",
               "time_mode" => "replay_run",
               "replay_run_id" => "replay-1",
               "selected_data_view" => "all_revisions",
               "limit_mode" => "compare"
             }
    end
  end

  describe "retry_selection/2" do
    test "selects the first retry event when retry events were recorded" do
      event = %{backfill_lifecycle_event_id: "retry-event-1"}

      assert %HistoricalWorkflowSelectionResult{
               event: ^event,
               query: %SelectionQuery{} = query,
               link: %DataLink{target_id: "retry-event-1"}
             } =
               HistoricalWorkflowSelection.retry_selection(%{events: [event]}, "fallback-event")

      assert SelectionQuery.value(query, "selected_id") == "retry-event-1"
    end

    test "preserves replay dashboard context when selecting retry events" do
      event = %{backfill_lifecycle_event_id: "retry-event-1"}

      assert %HistoricalWorkflowSelectionResult{query: %SelectionQuery{} = query} =
               HistoricalWorkflowSelection.retry_selection(
                 %{events: [event]},
                 "fallback-event",
                 %{
                   "dashboard_time_mode" => "replay_run",
                   "dashboard_replay_run_id" => "replay-1",
                   "dashboard_data_view" => "all_revisions",
                   "dashboard_limit_mode" => "compare"
                 }
               )

      assert SelectionQuery.to_params(query) == %{
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "retry-event-1",
               "time_mode" => "replay_run",
               "replay_run_id" => "replay-1",
               "selected_data_view" => "all_revisions",
               "limit_mode" => "compare"
             }
    end

    test "falls back to the original event when no retry event is available" do
      assert %HistoricalWorkflowSelectionResult{
               event: nil,
               query: %SelectionQuery{} = query,
               link: %DataLink{target_id: "fallback-event"}
             } =
               HistoricalWorkflowSelection.retry_selection(%{events: []}, "fallback-event")

      assert SelectionQuery.value(query, "selected_id") == "fallback-event"
    end
  end

  describe "group_transition_selection/3" do
    test "selects the first event with a failed dispatch result" do
      events = [
        %{backfill_lifecycle_event_id: "event-ok-1"},
        %{backfill_lifecycle_event_id: "event-failed", point_id: "HK.failed"},
        %{backfill_lifecycle_event_id: "event-ok-2"}
      ]

      assert %HistoricalWorkflowSelectionResult{
               event: %{backfill_lifecycle_event_id: "event-failed"},
               query: %SelectionQuery{} = query,
               link: %DataLink{target_id: "event-failed", context: %{observable_id: "HK.failed"}}
             } =
               HistoricalWorkflowSelection.group_transition_selection(
                 events,
                 [{:ok, %{job_id: "job-1"}}, {:error, :queue_down}, {:ok, nil}],
                 %{}
               )

      assert SelectionQuery.value(query, "selected_id") == "event-failed"
    end

    test "falls back to the first group transition event when dispatch did not fail" do
      events = [
        %{backfill_lifecycle_event_id: "event-1"},
        %{backfill_lifecycle_event_id: "event-2"}
      ]

      assert %HistoricalWorkflowSelectionResult{
               event: %{backfill_lifecycle_event_id: "event-1"},
               query: %SelectionQuery{} = query,
               link: %DataLink{target_id: "event-1"}
             } =
               HistoricalWorkflowSelection.group_transition_selection(
                 events,
                 [{:ok, %{job_id: "job-1"}}, {:ok, nil}],
                 %{}
               )

      assert SelectionQuery.value(query, "selected_id") == "event-1"
    end
  end
end
