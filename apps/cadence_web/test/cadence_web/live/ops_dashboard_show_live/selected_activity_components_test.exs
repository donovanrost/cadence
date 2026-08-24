defmodule CadenceWeb.OpsDashboardShowLive.SelectedActivityComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.{ActivityEventSummary, SelectedActivityComponents}

  test "selected_activity_event_summary offers recovery when selected activity is hidden by filter" do
    selected_event = lifecycle_event("dashboard-lifecycle-event-published", :published)
    visible_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    summary =
      ActivityEventSummary.build(
        [selected_event, visible_event],
        "dashboard-lifecycle-event-published",
        [visible_event],
        %{filter_value: "health_snapshots"}
      )

    html =
      render_component(&SelectedActivityComponents.selected_activity_event_summary/1,
        summary: summary,
        dashboard_document: dashboard_document(),
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1"
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-event-component"
      )

    assert Map.take(vue, [:component, :id, :ssr, :class, :handlers]) == %{
             component: "SelectedActivityEventSummary",
             id: "dashboard-selected-activity-event-component",
             ssr: false,
             class: "contents",
             handlers: %{}
           }

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props["presentation"] ==
             summary
             |> SelectedActivityComponents.presentation(
               dashboard_document(),
               "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1"
             )
             |> Jason.encode!()
             |> Jason.decode!()

    refute Enum.any?(vue.props["presentation"]["root"]["attrs"], fn {_key, value} ->
             is_nil(value)
           end)

    assert %{
             "root" => %{
               "attrs" => %{"data-dashboard-selected-activity-recovery" => "hidden"}
             },
             "message" => %{
               "text" => "This event exists but is hidden by the current activity filter."
             },
             "action" => %{"href" => href}
           } = vue.props["presentation"]["recovery"]

    assert URI.decode_query(URI.parse(href).query) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_event" => "dashboard-lifecycle-event-published"
           }
  end

  test "selected_activity_event_summary renders publish readiness remediation links" do
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
              "label" => "Fix source connection",
              "target" => "data_sources",
              "message" => "Open Data Sources and inspect the failed connection test.",
              "params" => %{
                "data_source_id" => "rehearsal-source",
                "source_binding_id" => "rehearsal-binding",
                "source_empty_reason" => "connection_test_failed",
                "selected_evidence_kind" => "source",
                "selected_source_evidence_mode" => "health"
              }
            }
          ]
        }
      )

    summary =
      ActivityEventSummary.build(
        [readiness_event],
        "dashboard-lifecycle-event-readiness",
        [readiness_event],
        %{filter_value: "publish_readiness"}
      )

    html =
      render_component(&SelectedActivityComponents.selected_activity_event_summary/1,
        summary: summary,
        dashboard_document: dashboard_document(),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1",
        readiness_return_intent: "source_return"
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-event-component"
      )

    assert Map.take(vue, [:component, :id, :ssr, :class, :handlers]) == %{
             component: "SelectedActivityEventSummary",
             id: "dashboard-selected-activity-event-component",
             ssr: false,
             class: "contents",
             handlers: %{}
           }

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props["presentation"] ==
             summary
             |> SelectedActivityComponents.presentation(
               dashboard_document(),
               "/missions/mission-1/ops/dashboards/dashboard-1",
               "source_return"
             )
             |> Jason.encode!()
             |> Jason.decode!()

    refute Enum.any?(vue.props["presentation"]["root"]["attrs"], fn {_key, value} ->
             is_nil(value)
           end)

    presentation = vue.props["presentation"]
    readiness_return = presentation["readiness_return"]
    remediation = presentation["remediation"]

    assert "refresh_publish_readiness" =
             presentation["header"]["refresh"]["attrs"]["phx-click"]

    assert "source_return" =
             readiness_return["root"]["attrs"][
               "data-dashboard-selected-activity-readiness-return"
             ]

    assert {["Fix source connection"], ["data_sources"]} =
             {
               Enum.map(
                 remediation["rows"],
                 & &1["attrs"]["data-dashboard-selected-activity-remediation"]
               ),
               Enum.map(
                 remediation["rows"],
                 & &1["attrs"]["data-dashboard-selected-activity-remediation-target"]
               )
             }

    [row] = remediation["rows"]
    href = row["action"]["href"]

    assert row["action"]["attrs"]["data-dashboard-selected-activity-remediation-href"] == href and
             String.starts_with?(href, "/missions/mission-1/ops/data-sources?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "data_source_id" => "rehearsal-source",
             "selected_evidence_kind" => "source",
             "selected_source_evidence_mode" => "health",
             "source_binding_id" => "rehearsal-binding",
             "source_dashboard_id" => "dashboard-1",
             "source_empty_reason" => "connection_test_failed",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end
end
