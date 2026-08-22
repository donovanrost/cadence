defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineRowComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.{
    ActivityEventSummary,
    ActivityTimelineRowComponents,
    ActivityViewModel
  }

  test "activity_row renders selected readiness row actions and badges" do
    previous_event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness-previous",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-27 12:00:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 3
        }
      )

    readiness_event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        dashboard_version: 2,
        occurred_at: ~U[2026-06-27 12:05:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 1,
          "remediation_targets" => [
            %{
              "label" => "Use a compatible source",
              "target" => "data_sources",
              "message" => "Open Data Sources and choose a compatible source.",
              "params" => %{
                "data_source_id" => "rehearsal-source",
                "source_binding_id" => "rehearsal-binding",
                "source_empty_reason" => "unsupported_source_capability"
              }
            }
          ]
        }
      )

    events = [previous_event, readiness_event]
    activity = ActivityViewModel.build(events, :publish_readiness)

    rows =
      ActivityEventSummary.rows(
        activity.visible_events,
        "dashboard-lifecycle-event-readiness",
        []
      )

    row = Enum.find(rows, &(&1.event_id == "dashboard-lifecycle-event-readiness"))

    html =
      render_component(&ActivityTimelineRowComponents.activity_row/1,
        row: row,
        activity: activity,
        dashboard_lifecycle_events: events,
        dashboard_review_placement_id: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["publish_readiness_checked"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-readiness")
             |> LazyHTML.attribute("data-lifecycle-event-type")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-readiness")
             |> LazyHTML.attribute("data-dashboard-activity-selected")

    assert ["improved"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-readiness-trend]")
             |> LazyHTML.attribute("data-dashboard-activity-readiness-trend")

    assert ["dashboard-lifecycle-event-readiness-previous"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-readiness-trend]")
             |> LazyHTML.attribute("data-dashboard-activity-readiness-previous")

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-remediation-count]")
             |> LazyHTML.attribute("data-dashboard-activity-remediation-count")

    assert ["Use a compatible source"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-remediation-action]")
             |> LazyHTML.attribute("data-dashboard-activity-remediation-action")

    assert ["data_sources"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-remediation-action]")
             |> LazyHTML.attribute("data-dashboard-activity-remediation-target")

    assert ["select_activity_event"] =
             document
             |> LazyHTML.query("#dashboard-activity-select-dashboard-lifecycle-event-readiness")
             |> LazyHTML.attribute("phx-click")

    assert ["ClipboardButton"] =
             document
             |> LazyHTML.query(
               "#dashboard-activity-link-copy-dashboard-lifecycle-event-readiness"
             )
             |> LazyHTML.attribute("phx-hook")

    assert [href] =
             document
             |> LazyHTML.query(
               "#dashboard-activity-link-copy-dashboard-lifecycle-event-readiness"
             )
             |> LazyHTML.attribute("data-clipboard-text")

    assert URI.decode_query(URI.parse(href).query) == %{
             "panel" => "versions",
             "activity_filter" => "publish_readiness",
             "activity_event" => "dashboard-lifecycle-event-readiness"
           }
  end
end
