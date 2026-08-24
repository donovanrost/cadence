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

    presentation = version_history_summary_presentation(html)
    runtime_defaults = presentation["runtime_defaults"]
    publish_impact = presentation["publish_impact"]

    assert runtime_defaults["root"]["attrs"] == %{
             "id" => "dashboard-runtime-defaults-summary",
             "class" => "space-y-2 border border-base-300/70 bg-base-100/40 p-2",
             "data-dashboard-runtime-defaults-differ" => "true",
             "data-dashboard-runtime-defaults-published-version" => "v1",
             "data-dashboard-runtime-defaults-draft-version" => "v2",
             "data-dashboard-runtime-defaults-published-realm" => "flight",
             "data-dashboard-runtime-defaults-draft-realm" => "rehearsal",
             "data-dashboard-runtime-defaults-published-source-binding" => "flight-binding",
             "data-dashboard-runtime-defaults-draft-source-binding" => "rehearsal-binding",
             "data-dashboard-runtime-defaults-published-data-source" => "questdb-flight",
             "data-dashboard-runtime-defaults-draft-data-source" => "questdb-rehearsal",
             "data-dashboard-runtime-defaults-published-data-view" => "canonical",
             "data-dashboard-runtime-defaults-draft-data-view" => "as_recorded"
           }

    assert runtime_defaults["header"]["badge"] == %{
             "attrs" => %{
               "class" => "badge badge-xs badge-warning",
               "data-dashboard-runtime-defaults-status" => "draft differs"
             },
             "text" => "draft differs"
           }

    assert Enum.map(runtime_defaults["contexts"]["items"], fn context ->
             {context["order"], context["attrs"]["data-dashboard-runtime-default-context"]}
           end) == [{0, "Published"}, {1, "Draft"}]

    [published, draft] = runtime_defaults["contexts"]["items"]

    assert Enum.map(published["rows"], & &1["value"]["text"]) ==
             ["v1", "flight", "flight-binding", "canonical"]

    assert Enum.map(draft["rows"], fn row ->
             {row["order"], row["label"]["text"], row["value"]["attrs"], row["value"]["text"]}
           end) == [
             {0, "Draft",
              %{
                "class" => "font-mono text-base-content/70",
                "data-runtime-default-field" => "Version"
              }, "v2"},
             {1, "Realm",
              %{
                "class" => "font-mono text-base-content/70",
                "data-runtime-default-field" => "Realm"
              }, "rehearsal"},
             {2, "Source",
              %{
                "class" => "truncate font-mono text-base-content/70",
                "data-runtime-default-field" => "Source"
              }, "rehearsal-binding"},
             {3, "View",
              %{
                "class" => "font-mono text-base-content/70",
                "data-runtime-default-field" => "View"
              }, "as_recorded"}
           ]

    assert publish_impact["root"]["attrs"] == %{
             "id" => "dashboard-publish-impact",
             "class" => "space-y-2 border border-base-300/70 bg-base-100/40 p-2",
             "data-dashboard-publish-impact-state" => "runtime_context_change",
             "data-dashboard-publish-impact-severity" => "warning",
             "data-dashboard-publish-impact-from-version" => "v1",
             "data-dashboard-publish-impact-to-version" => "v2",
             "data-dashboard-publish-impact-from-realm" => "flight",
             "data-dashboard-publish-impact-to-realm" => "rehearsal",
             "data-dashboard-publish-impact-from-source-binding" => "flight-binding",
             "data-dashboard-publish-impact-to-source-binding" => "rehearsal-binding",
             "data-dashboard-publish-impact-from-data-view" => "canonical",
             "data-dashboard-publish-impact-to-data-view" => "as_recorded"
           }

    assert publish_impact["header"]["badge"] == %{
             "attrs" => %{
               "class" => "badge badge-xs badge-warning",
               "data-dashboard-publish-impact-label" => "runtime defaults change"
             },
             "text" => "runtime defaults change"
           }

    assert publish_impact["message"] == %{
             "attrs" => %{
               "class" => "text-xs text-base-content/70",
               "data-dashboard-publish-impact-message" => ""
             },
             "text" =>
               "Publishing will move operators from flight / flight-binding / canonical to rehearsal / rehearsal-binding / as_recorded."
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

  defp version_history_summary_presentation(rendered) do
    vue =
      LiveVue.Test.get_vue(rendered,
        id: "dashboard-version-history-summary-component"
      )

    assert vue.component == "VersionHistorySummary"
    assert vue.id == "dashboard-version-history-summary-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end
end
