defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPublishReadinessFreshnessComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{Document, ValidationResult}
  alias CadenceWeb.OpsDashboardShowLive.{PublishReadinessModel, VersionHistoryPanelComponents}

  test "versions_panel renders stale publish validation state" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(%ValidationResult{}, %{
            evaluated_at: "2026-06-27T12:00:00Z",
            draft_version: "1",
            summary_draft_version: "2",
            latest_version: "2",
            published_version: "-",
            state: "stale",
            state_label: "stale draft",
            reason: "draft_version_changed",
            reason_label: "draft changed",
            message: "The dashboard draft changed after this publish readiness check."
          }),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-status")

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-state")

    assert ["draft_version_changed"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-reason")

    assert ["needs_recheck"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-result")
             |> LazyHTML.attribute("data-publish-validation-result-state")

    assert document
           |> LazyHTML.query("[data-publish-validation-freshness-message]")
           |> selected_text() =~ "dashboard draft changed"

    assert document
           |> LazyHTML.query("#dashboard-publish-validation")
           |> selected_text() =~ "Re-check readiness before publishing"
  end

  test "versions_panel renders source evidence stale publish validation reason" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(
            %ValidationResult{
              warnings: [%{code: :stale_data, details: %{data_source_id: "source-1"}}]
            },
            %{
              evaluated_at: "2026-06-27T12:10:00Z",
              draft_version: "2",
              summary_draft_version: "2",
              latest_version: "2",
              published_version: "1",
              state: "stale",
              state_label: "source evidence stale",
              reason: "source_watermark_stale",
              reason_label: "source stale",
              message:
                "Source watermark evidence is stale; re-check readiness after source data advances."
            }
          ),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-status")

    assert ["source_watermark_stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-reason")

    assert document
           |> LazyHTML.query("[data-publish-validation-freshness-message]")
           |> selected_text() =~ "Source watermark evidence is stale"

    assert document
           |> LazyHTML.query("#dashboard-publish-validation-result")
           |> selected_text() =~ "Source watermark evidence is stale"
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp publish_readiness(validation, freshness) do
    PublishReadinessModel.build(validation, freshness)
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
