defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPublishReadinessActivityTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.SourceHealthEvent
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel links selected publish readiness activity to remediation target" do
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
          "source_evidence_contexts" => [
            %{
              "warning_code" => "unsupported_source_capability",
              "source_request_id" => "request-telemetry-latest",
              "logical_source" => "telemetry",
              "source_binding_id" => "rehearsal-binding",
              "data_source_id" => "rehearsal-source",
              "replay_run_id" => "replay-run-7"
            }
          ],
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

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [previous_event, readiness_event],
        dashboard_source_action_events: [
          SourceHealthEvent.new(%{
            source_health_event_id: "source-health-event-1",
            organization_id: "org-1",
            mission_id: "mission-1",
            logical_source: "telemetry",
            data_source_id: "rehearsal-source",
            source_binding_id: "rehearsal-binding",
            source_health: :healthy,
            observed_at: ~U[2026-06-27 12:35:00Z],
            payload: %{
              "source_dashboard_id" => "dashboard-1",
              "source_return_activity_event" => "dashboard-lifecycle-event-readiness"
            }
          })
        ],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-readiness",
        dashboard_readiness_return_intent: "source_return",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    activity_row = activity_row_presentation(html, readiness_event.dashboard_lifecycle_event_id)

    selected_activity = activity_timeline_presentation(html)["selected_activity"]

    remediation = selected_activity["remediation"]
    source_actions = selected_activity["source_actions"]
    readiness_return = selected_activity["readiness_return"]

    assert [
             "Use a compatible source",
             "Inspect telemetry: rehearsal-binding -> rehearsal-source (replay replay-run-7, request request-telemetry-latest)"
           ] =
             Enum.map(
               remediation["rows"],
               & &1["attrs"]["data-dashboard-selected-activity-remediation"]
             )

    assert ["data_sources", "data_sources"] =
             Enum.map(
               remediation["rows"],
               & &1["attrs"]["data-dashboard-selected-activity-remediation-target"]
             )

    assert Enum.any?(
             remediation["rows"],
             &(&1["message"]["text"] == "Open Data Sources and choose a compatible source.")
           )

    assert "improved" =
             selected_activity["header"]["readiness_comparison"]["attrs"][
               "data-dashboard-selected-activity-readiness-trend"
             ]

    assert "dashboard-lifecycle-event-readiness-previous" =
             selected_activity["header"]["readiness_comparison"]["attrs"][
               "data-dashboard-selected-activity-readiness-previous"
             ]

    assert "Readiness improved: 3 issues -> 1 issue." =
             selected_activity["fields"]
             |> Enum.find(&(&1["label"] == "Readiness trend"))
             |> Map.fetch!("value")

    assert "1" =
             source_actions["root"]["attrs"]["data-dashboard-selected-activity-source-actions"]

    assert "source_health" =
             source_actions["root"]["attrs"][
               "data-dashboard-selected-activity-source-action-latest-kind"
             ]

    assert "2026-06-27 12:35:00 UTC" =
             source_actions["root"]["attrs"][
               "data-dashboard-selected-activity-source-action-latest-at"
             ]

    assert ["source_health"] =
             Enum.map(
               source_actions["rows"],
               & &1["attrs"]["data-dashboard-selected-activity-source-action"]
             )

    assert ["telemetry / rehearsal-binding / rehearsal-source"] =
             Enum.map(
               source_actions["rows"],
               & &1["attrs"]["data-dashboard-selected-activity-source-action-source"]
             )

    assert source_actions["latest"]["text"] =~ "Source probed after this check"

    assert activity_row["header"]["readiness_badge"]["attrs"][
             "data-dashboard-activity-readiness-trend"
           ] == "improved"

    assert activity_row["header"]["readiness_badge"]["attrs"][
             "data-dashboard-activity-readiness-previous"
           ] == "dashboard-lifecycle-event-readiness-previous"

    assert activity_row["header"]["remediation_badge"]["attrs"][
             "data-dashboard-activity-remediation-count"
           ] == "2"

    assert [
             "Use a compatible source",
             "Inspect telemetry: rehearsal-binding -> rehearsal-source (replay replay-run-7, request request-telemetry-latest)"
           ] =
             Enum.map(
               activity_row["header"]["remediation_actions"],
               & &1["attrs"]["data-dashboard-activity-remediation-action"]
             )

    assert ["data_sources", "data_sources"] =
             Enum.map(
               activity_row["header"]["remediation_actions"],
               & &1["attrs"]["data-dashboard-activity-remediation-target"]
             )

    assert "refresh_publish_readiness" =
             selected_activity["header"]["refresh"]["attrs"]["phx-click"]

    assert "source_return" =
             readiness_return["root"]["attrs"][
               "data-dashboard-selected-activity-readiness-return"
             ]

    assert "dashboard-lifecycle-event-readiness" =
             readiness_return["root"]["attrs"][
               "data-dashboard-selected-activity-readiness-return-event"
             ]

    assert "dashboard-lifecycle-event-readiness" =
             readiness_return["action"]["attrs"][
               "data-dashboard-selected-activity-readiness-return-refresh"
             ]

    assert "refresh_publish_readiness" =
             readiness_return["action"]["attrs"]["phx-click"]

    assert "dashboard-lifecycle-event-readiness" =
             selected_activity["header"]["refresh"]["attrs"][
               "data-dashboard-selected-activity-refresh-readiness"
             ]

    assert "improved" =
             selected_activity["header"]["refresh"]["attrs"][
               "data-dashboard-selected-activity-refresh-readiness-state"
             ]

    assert [explicit_href, source_evidence_href] =
             Enum.map(remediation["rows"], & &1["action"]["href"])

    assert String.starts_with?(explicit_href, "/missions/mission-1/ops/data-sources?")
    assert String.starts_with?(source_evidence_href, "/missions/mission-1/ops/data-sources?")

    query =
      explicit_href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "data_source_id" => "rehearsal-source",
             "source_dashboard_id" => "dashboard-1",
             "source_binding_id" => "rehearsal-binding",
             "source_empty_reason" => "unsupported_source_capability",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }

    source_evidence_query =
      source_evidence_href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert source_evidence_query == %{
             "data_source_id" => "rehearsal-source",
             "logical_source" => "telemetry",
             "replay_run_id" => "replay-run-7",
             "selected_evidence_kind" => "source",
             "selected_source_evidence_mode" => "health",
             "source_dashboard_id" => "dashboard-1",
             "source_binding_id" => "rehearsal-binding",
             "source_empty_reason" => "unsupported_source_capability",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }
  end

  test "versions_panel links connection-test publish readiness activity to source evidence" do
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
                "selected_source_evidence_mode" => "health",
                "selected_source_evidence_state" => "connection_test_failed",
                "connection_test_result" => "failed",
                "connection_test_kind" => "adapter_io",
                "connection_test_message" => "Adapter connection test failed."
              }
            }
          ]
        }
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [readiness_event],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-readiness",
        dashboard_readiness_return_intent: "source_return",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    remediation =
      html
      |> activity_timeline_presentation()
      |> get_in(["selected_activity", "remediation"])

    assert ["Fix source connection"] =
             Enum.map(
               remediation["rows"],
               & &1["attrs"]["data-dashboard-selected-activity-remediation"]
             )

    [row] = remediation["rows"]
    href = row["action"]["href"]
    assert row["action"]["attrs"]["data-dashboard-selected-activity-remediation-href"] == href

    assert String.starts_with?(href, "/missions/mission-1/ops/data-sources?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "connection_test_kind" => "adapter_io",
             "connection_test_message" => "Adapter connection test failed.",
             "connection_test_result" => "failed",
             "data_source_id" => "rehearsal-source",
             "selected_evidence_kind" => "source",
             "selected_source_evidence_mode" => "health",
             "selected_source_evidence_state" => "connection_test_failed",
             "source_binding_id" => "rehearsal-binding",
             "source_dashboard_id" => "dashboard-1",
             "source_empty_reason" => "connection_test_failed",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }
  end

  test "versions_panel links selected publish readiness activity to dashboard editor focus" do
    selected_issue_id =
      "error:unready_publish_source_request:placement-ground-state:unsupported_observable_scope:ground.station.connection_state"

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
              "issue_id" => selected_issue_id,
              "label" => "Change widget context",
              "target" => "dashboard_editor",
              "message" =>
                "Open the dashboard editor and choose observables that support this context.",
              "params" => %{
                "placement_id" => "placement-ground-state",
                "selected_publish_issue" => selected_issue_id,
                "source_empty_reason" => "unsupported_observable_scope",
                "unsupported_observables" => "ground.station.connection_state"
              }
            }
          ]
        }
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [readiness_event],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-readiness",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    remediation =
      html
      |> activity_timeline_presentation()
      |> get_in(["selected_activity", "remediation"])

    [row] = remediation["rows"]

    assert row["attrs"]["data-dashboard-selected-activity-remediation-issue"] ==
             selected_issue_id

    assert "dashboard_editor" =
             row["attrs"]["data-dashboard-selected-activity-remediation-target"]

    assert "Open Widget Editor" =
             row["action"]["text"]

    href = row["action"]["href"]
    assert row["action"]["attrs"]["data-dashboard-selected-activity-remediation-href"] == href

    assert String.starts_with?(href, "/missions/mission-1/ops/dashboards/dashboard-1?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "panel" => "dashboard_editor",
             "selected_placement" => "placement-ground-state",
             "selected_publish_issue" => selected_issue_id,
             "source_empty_reason" => "unsupported_observable_scope",
             "unsupported_observables" => "ground.station.connection_state"
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

  defp activity_row_presentation(rendered, event_id) do
    row =
      rendered
      |> activity_timeline_presentation()
      |> get_in(["list", "rows"])
      |> Enum.find(&(&1["key"] == event_id))

    assert row["key"] == event_id
    assert is_integer(row["order"])
    assert row["presentation"]["root"]["id"] == "dashboard-activity-#{event_id}"
    assert row["presentation"] == Jason.decode!(Jason.encode!(row["presentation"]))
    row["presentation"]
  end

  defp activity_timeline_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-activity-timeline-component")

    assert vue.component == "ActivityTimeline"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end
end
