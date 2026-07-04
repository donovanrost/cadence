defmodule CadenceWeb.OpsDashboardShowLive.SelectedActivityActionComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.SelectedActivityActionComponents

  test "recovery_banner links hidden activity back to the all-activity view" do
    html =
      render_component(&SelectedActivityActionComponents.recovery_banner/1,
        summary: %{
          filter_state: :hidden,
          filter_state_text: "hidden",
          event_id: "dashboard-lifecycle-event-published"
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["hidden"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> LazyHTML.attribute("data-dashboard-selected-activity-recovery")

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery-link")
             |> LazyHTML.attribute("href")

    assert URI.decode_query(URI.parse(href).query) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_event" => "dashboard-lifecycle-event-published"
           }
  end

  test "readiness_return_prompt renders refresh action for source-return readiness selections" do
    html =
      render_component(&SelectedActivityActionComponents.readiness_return_prompt/1,
        summary: %{
          found?: true,
          event_type_text: "publish_readiness_checked",
          event_id: "dashboard-lifecycle-event-readiness"
        },
        readiness_return_intent: "source_return"
      )

    document = LazyHTML.from_fragment(html)

    assert ["source_return"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-readiness-return")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-return")

    assert ["dashboard-lifecycle-event-readiness"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-readiness-return-refresh]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-return-refresh")
  end

  test "source_actions renders the latest source action and row metadata" do
    html =
      render_component(&SelectedActivityActionComponents.source_actions/1,
        summary: %{
          source_actions: %{
            present?: true,
            count_text: "2",
            latest: %{
              kind: "source_reviewed",
              occurred_at: "2026-06-27T12:00:00Z",
              message: "Source evidence reviewed"
            },
            rows: [
              %{
                kind: "source_reviewed",
                occurred_at: "2026-06-27T12:00:00Z",
                source: "rehearsal-source",
                message: "Source evidence reviewed"
              }
            ]
          }
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-source-actions")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-actions")

    assert ["source_reviewed"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-source-action]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-action")

    assert "Source evidence reviewed" =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-source-action]")
             |> LazyHTML.text()
             |> String.trim()
             |> String.replace("2026-06-27T12:00:00Z", "")
             |> String.replace("rehearsal-source", "")
             |> String.trim()
  end

  test "remediation_actions routes data source remediation back through dashboard context" do
    html =
      render_component(&SelectedActivityActionComponents.remediation_actions/1,
        summary: %{
          event_id: "dashboard-lifecycle-event-readiness",
          remediation_actions: [
            %{
              label: "Fix source connection",
              target: "data_sources",
              message: "Inspect the failed connection test.",
              params: %{
                "data_source_id" => "rehearsal-source",
                "selected_evidence_kind" => "source"
              }
            }
          ]
        },
        dashboard_document: dashboard_document()
      )

    document = LazyHTML.from_fragment(html)

    assert ["Fix source connection"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-remediation")

    assert [href] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation-link]")
             |> LazyHTML.attribute("href")

    assert String.starts_with?(href, "/missions/mission-1/ops/data-sources?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "data_source_id" => "rehearsal-source",
             "selected_evidence_kind" => "source",
             "source_dashboard_id" => "dashboard-1",
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
