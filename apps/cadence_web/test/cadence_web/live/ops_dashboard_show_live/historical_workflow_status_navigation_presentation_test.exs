defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  @current_path "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link&selected_placement=old-placement&activity_filter=open_comparison_reviews&activity_event=old-event"

  test "comparison_review_links builds review and placement links" do
    links =
      HistoricalWorkflowStatusNavigationPresentation.comparison_review_links(
        %{
          comparison_review_request_event_id: "review-request-1",
          comparison_review_open_placement_ids: "placement-1, placement-2 placement-1"
        },
        @current_path
      )

    assert review_href_query(links.review_href) == %{
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1"
           }

    assert Enum.map(links.placement_links, & &1.placement_id) == ["placement-1", "placement-2"]

    assert links.placement_links
           |> Enum.map(&review_href_query(&1.href)) == [
             %{
               "panel" => "versions",
               "activity_filter" => "open_comparison_reviews",
               "activity_event" => "review-request-1",
               "selected_placement" => "placement-1"
             },
             %{
               "panel" => "versions",
               "activity_filter" => "open_comparison_reviews",
               "activity_event" => "review-request-1",
               "selected_placement" => "placement-2"
             }
           ]
  end

  test "latest_action_handoffs builds selected and result lifecycle links" do
    handoffs =
      HistoricalWorkflowStatusNavigationPresentation.latest_action_handoffs(
        %{
          target_event_id: "target-event",
          result_event_ids: "target-event result-event result-event"
        },
        @current_path
      )

    assert Enum.map(handoffs, &Map.take(&1, [:event_id, :role, :label])) == [
             %{event_id: "target-event", role: "target_result", label: "Selected result"},
             %{event_id: "result-event", role: "result", label: "Result 1"}
           ]

    assert HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id(handoffs) ==
             "target-event"

    assert handoffs
           |> Enum.map(&lifecycle_href_query(&1.href)) == [
             %{
               "panel" => "data_link",
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "target-event"
             },
             %{
               "panel" => "data_link",
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "result-event"
             }
           ]
  end

  test "latest_action_handoffs numbers only result handoffs" do
    handoffs =
      HistoricalWorkflowStatusNavigationPresentation.latest_action_handoffs(
        %{
          target_event_id: "target-event",
          result_event_ids: "result-event-1 result-event-2"
        },
        @current_path
      )

    assert Enum.map(handoffs, &Map.take(&1, [:event_id, :role, :label])) == [
             %{event_id: "target-event", role: "target", label: "Selected event"},
             %{event_id: "result-event-1", role: "result", label: "Result 1"},
             %{event_id: "result-event-2", role: "result", label: "Result 2"}
           ]
  end

  test "group_failed_item_handoffs parses failed item events and lifecycle links" do
    handoffs =
      HistoricalWorkflowStatusNavigationPresentation.group_failed_item_handoffs(
        %{
          request_group_failed_item_events:
            "label=HK.voltage run=run-002 event=failed-event-2 recovery=retry_job retryable=true; " <>
              "label=HK.current run=run-003 event=failed-event-3 recovery=correct_workflow_request retryable=false; " <>
              "label=missing-event run=run-004"
        },
        @current_path
      )

    assert Enum.map(handoffs, &Map.drop(&1, [:href])) == [
             %{
               label: "HK.voltage",
               run_id: "run-002",
               event_id: "failed-event-2",
               recovery_action: "retry_job",
               retryable: "true"
             },
             %{
               label: "HK.current",
               run_id: "run-003",
               event_id: "failed-event-3",
               recovery_action: "correct_workflow_request",
               retryable: "false"
             }
           ]

    assert handoffs
           |> Enum.map(&lifecycle_href_query(&1.href)) == [
             %{
               "panel" => "data_link",
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "failed-event-2"
             },
             %{
               "panel" => "data_link",
               "selected_target" => "telemetry_backfill_lifecycle_event",
               "selected_id" => "failed-event-3"
             }
           ]
  end

  test "builders return empty navigation packages without required context" do
    assert HistoricalWorkflowStatusNavigationPresentation.comparison_review_links(nil, nil) ==
             %{review_href: nil, placement_links: []}

    assert HistoricalWorkflowStatusNavigationPresentation.latest_action_handoffs(nil, nil) == []
    assert HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id([]) == nil

    assert HistoricalWorkflowStatusNavigationPresentation.group_failed_item_handoffs(nil, nil) ==
             []
  end

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  defp lifecycle_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.take(["panel", "selected_target", "selected_id"])
  end
end
