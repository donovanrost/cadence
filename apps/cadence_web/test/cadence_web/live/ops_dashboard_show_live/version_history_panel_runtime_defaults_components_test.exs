defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelRuntimeDefaultsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{
    DashboardSummary,
    Document,
    Version
  }

  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel renders published and draft runtime default context" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: %DashboardSummary{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          latest_version: 2,
          draft_version: 2,
          published_version: 1
        },
        dashboard_versions: [
          runtime_default_version(1, "flight", "canonical", "questdb-flight", "flight-binding"),
          runtime_default_version(
            2,
            "rehearsal",
            "as_recorded",
            "questdb-rehearsal",
            "rehearsal-binding"
          )
        ],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-differ")

    assert ["flight"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-published-realm")

    assert ["rehearsal-binding"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-draft-source-binding")

    assert ["as_recorded"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-draft-data-view")

    assert "rehearsal-binding" =
             document
             |> LazyHTML.query(
               ~s([data-dashboard-runtime-default-context="Draft"] [data-runtime-default-field="Source"])
             )
             |> selected_text()

    assert ["runtime_context_change"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-state")

    assert ["warning"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-severity")

    assert ["flight"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-from-realm")

    assert ["rehearsal-binding"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-to-source-binding")

    assert "Publishing will move operators from flight / flight-binding / canonical to rehearsal / rehearsal-binding / as_recorded." =
             document
             |> LazyHTML.query("[data-dashboard-publish-impact-message]")
             |> selected_text()
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp runtime_default_version(version, realm, data_view, data_source_id, source_binding_id) do
    %Version{
      dashboard_version_id: "version-#{version}",
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      version: version,
      document: %Document{
        dashboard_id: "dashboard-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        name: "Dashboard",
        defaults: %{
          "data" => %{
            "realm" => realm,
            "view" => data_view,
            "source_contexts" => %{
              "telemetry" => %{
                "data_source_id" => data_source_id,
                "source_binding_id" => source_binding_id
              }
            }
          }
        },
        metadata: %{version: version}
      },
      snapshot_kind: :draft_save,
      inserted_at: ~U[2026-06-24 12:00:00Z]
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
