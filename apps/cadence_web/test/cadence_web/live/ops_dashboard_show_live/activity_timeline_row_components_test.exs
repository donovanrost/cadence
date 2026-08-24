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

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-activity-row-dashboard-lifecycle-event-readiness-component"
      )

    assert vue.component == "ActivityTimelineRow"
    assert vue.id == "dashboard-activity-row-dashboard-lifecycle-event-readiness-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert Map.keys(vue.props) == ["presentation"]

    presentation = vue.props["presentation"]
    root = presentation["root"]

    assert root["id"] == "dashboard-activity-dashboard-lifecycle-event-readiness"

    assert root["class"] == [
             "border-l-2 bg-base-100/40 px-2 py-2",
             "border-info bg-info/10"
           ]

    assert root["attrs"]["data-lifecycle-event-type"] == "publish_readiness_checked"
    assert root["attrs"]["data-dashboard-activity-selected"] == "true"

    readiness_badge = presentation["header"]["readiness_badge"]

    assert readiness_badge["attrs"]["data-dashboard-activity-readiness-trend"] == "improved"

    assert readiness_badge["attrs"]["data-dashboard-activity-readiness-previous"] ==
             "dashboard-lifecycle-event-readiness-previous"

    remediation_badge = presentation["header"]["remediation_badge"]
    assert remediation_badge["attrs"]["data-dashboard-activity-remediation-count"] == "1"

    assert [remediation_action] = presentation["header"]["remediation_actions"]

    assert remediation_action["attrs"]["data-dashboard-activity-remediation-action"] ==
             "Use a compatible source"

    assert remediation_action["attrs"]["data-dashboard-activity-remediation-target"] ==
             "data_sources"

    select = presentation["actions"]["select"]
    assert select["attrs"]["phx-click"] == "select_activity_event"
    assert select["attrs"]["phx-value-event-id"] == "dashboard-lifecycle-event-readiness"
    assert select["text"] == "Select"

    copy_host = presentation["actions"]["copy_host"]
    copy = presentation["actions"]["copy_props"]

    assert copy_host == %{
             "attrs" => %{"data-name" => "ClipboardButton"},
             "class" => "contents",
             "id" => "dashboard-activity-link-copy-dashboard-lifecycle-event-readiness-component"
           }

    assert copy["button_id"] ==
             "dashboard-activity-link-copy-dashboard-lifecycle-event-readiness"

    assert copy["button_class"] == "btn btn-ghost btn-xs"
    assert copy["icon"] == "hero-link"
    assert copy["icon_class"] == "h-3.5 w-3.5"
    assert copy["label"] == "Copy link"

    assert copy["data_attrs"] == %{
             "data-dashboard-activity-link-copy" => "dashboard-lifecycle-event-readiness"
           }

    href = copy["clipboard_text"]

    assert URI.decode_query(URI.parse(href).query) == %{
             "panel" => "versions",
             "activity_filter" => "publish_readiness",
             "activity_event" => "dashboard-lifecycle-event-readiness"
           }

    assert presentation["comparison_review"] == %{"request" => nil, "resolution" => nil}
    assert presentation["health_snapshot"] == nil
  end

  test "activity row DTO preserves raw attribute and body rendering semantics" do
    event = lifecycle_event("dashboard-lifecycle-event-attributes", :published)
    activity = ActivityViewModel.build([event], nil)
    [row] = ActivityEventSummary.rows(activity.visible_events, nil, [])

    row = %{
      row
      | event_id: "attribute-semantics",
        event_type: true,
        source_version_text: nil,
        reverted_version_text: false,
        runtime_impact: %{
          row.runtime_impact
          | state: true,
            invalidation_id: nil,
            context_match: false,
            refresh_allowed: 7
        },
        fields: [
          %{label: nil, value: nil, class: "value-nil"},
          %{label: false, value: false, class: "value-false"},
          %{label: true, value: true, class: "value-true"},
          %{label: "", value: "", class: "value-empty"},
          %{label: 7, value: 7, class: "value-number"}
        ]
    }

    presentation =
      ActivityTimelineRowComponents.presentation(
        row,
        activity,
        [event],
        nil,
        "/missions/mission-1/ops/dashboards/dashboard-1"
      )
      |> Jason.encode!()
      |> Jason.decode!()

    attrs = presentation["root"]["attrs"]

    assert attrs["data-lifecycle-event-type"] == ""
    refute Map.has_key?(attrs, "data-lifecycle-source-version")
    refute Map.has_key?(attrs, "data-lifecycle-reverted-version")
    assert attrs["data-dashboard-activity-runtime-impact-state"] == ""
    refute Map.has_key?(attrs, "data-dashboard-activity-runtime-impact-invalidation")
    refute Map.has_key?(attrs, "data-dashboard-activity-runtime-impact-context")
    assert attrs["data-dashboard-activity-runtime-impact-refresh"] == "7"

    fields = presentation["fields"]["rows"]

    assert Enum.map(fields, & &1["value"]["attrs"]) == [
             %{},
             %{},
             %{"data-activity-field" => ""},
             %{"data-activity-field" => ""},
             %{"data-activity-field" => "7"}
           ]

    assert Enum.map(fields, & &1["value"]["text"]) == ["", "false", "true", "", "7"]

    assert ActivityTimelineRowComponents.component_id(row) ==
             "dashboard-activity-row-attribute-semantics-component"
  end
end
