defmodule CadenceWeb.OpsDashboardShowLive.VersionListComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardSummary, Document, Version}
  alias CadenceWeb.OpsDashboardShowLive.{VersionHistoryPresentation, VersionListComponents}

  test "version_overview renders pointers and version actions" do
    version_history =
      VersionHistoryPresentation.build(
        %DashboardSummary{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          latest_version: 2,
          draft_version: 2,
          published_version: 1
        },
        [
          version(1, :publish, "published save"),
          version(2, :draft_save, "draft save")
        ]
      )

    html =
      render_component(&VersionListComponents.version_overview/1,
        version_history: version_history
      )

    document = LazyHTML.from_fragment(html)

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-version-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-version-", ""))
             |> Enum.take(1)

    assert ["published"] =
             document
             |> LazyHTML.query("#dashboard-version-1 [data-version-pointer]")
             |> LazyHTML.attribute("data-version-pointer")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-publish-available")

    assert ["already_latest"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-restore-reason")

    assert "draft save" =
             document
             |> LazyHTML.query(~s(#dashboard-version-2 [data-version-field="Summary"]))
             |> selected_text()

    assert ["draft_save"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-lineage-kind")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-lineage-source-version")

    assert "Draft saved from v1" =
             document
             |> LazyHTML.query(~s(#dashboard-version-2 [data-version-field="Origin"]))
             |> selected_text()
  end

  test "version_overview renders empty state" do
    version_history = VersionHistoryPresentation.build(nil, [])

    html =
      render_component(&VersionListComponents.version_overview/1,
        version_history: version_history
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-version-list > li")
             |> LazyHTML.attribute("id")

    assert "No saved versions." =
             document
             |> LazyHTML.query("section > p")
             |> selected_text()
  end

  defp version(version, snapshot_kind, change_summary) do
    %Version{
      dashboard_version_id: "version-#{version}",
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      version: version,
      document: dashboard_document(),
      snapshot_kind: snapshot_kind,
      parent_version: previous_version(version),
      based_on_version: previous_version(version),
      change_summary: change_summary,
      created_by: "operator",
      inserted_at: ~U[2026-06-24 12:00:00Z]
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

  defp previous_version(version) when is_integer(version) and version > 1, do: version - 1
  defp previous_version(_version), do: nil

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
