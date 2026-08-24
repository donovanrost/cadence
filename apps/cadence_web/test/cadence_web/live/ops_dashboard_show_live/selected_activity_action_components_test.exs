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

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-recovery-component"
      )

    assert vue.component == "SelectedActivityActions"
    assert vue.id == "dashboard-selected-activity-recovery-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["kind"] == "recovery"
    assert presentation["visible"] == true

    assert presentation["root"] == %{
             "id" => "dashboard-selected-activity-recovery",
             "class" =>
               "mt-2 flex flex-wrap items-center gap-2 border-l-2 border-warning/70 pl-2 text-base-content/70",
             "attrs" => %{
               "data-dashboard-selected-activity-recovery" => "hidden",
               "data-dashboard-selected-activity-recovery-href" => presentation["action"]["href"]
             }
           }

    assert presentation["message"] == %{
             "class" => "min-w-0 flex-1",
             "text" => "This event exists but is hidden by the current activity filter."
           }

    action = presentation["action"]
    href = action["href"]

    assert action == %{
             "id" => "dashboard-selected-activity-recovery-link",
             "href" => href,
             "navigation_kind" => "navigate",
             "class" =>
               "inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus",
             "text" => "Show all activity",
             "icon" => %{"name" => "hero-list-bullet", "class" => "h-3 w-3"},
             "attrs" => %{
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push"
             }
           }

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

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-readiness-return-component"
      )

    assert vue.component == "SelectedActivityActions"
    assert vue.id == "dashboard-selected-activity-readiness-return-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["kind"] == "readiness_return"
    assert presentation["visible"] == true

    assert presentation["root"] == %{
             "id" => "dashboard-selected-activity-readiness-return",
             "class" =>
               "mt-2 flex flex-wrap items-center gap-2 border-l-2 border-primary/70 pl-2 text-base-content/70",
             "attrs" => %{
               "data-dashboard-selected-activity-readiness-return" => "source_return",
               "data-dashboard-selected-activity-readiness-return-event" =>
                 "dashboard-lifecycle-event-readiness"
             }
           }

    assert presentation["message"] == %{
             "class" => "min-w-0 flex-1",
             "text" =>
               "Source evidence changed or was reviewed. Re-check publish readiness before publishing this draft."
           }

    assert presentation["action"] == %{
             "type" => "button",
             "class" =>
               "inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
             "text" => "Re-check readiness",
             "icon" => %{"name" => "hero-arrow-path", "class" => "h-3 w-3"},
             "attrs" => %{
               "phx-click" => "refresh_publish_readiness",
               "data-dashboard-selected-activity-readiness-return-refresh" =>
                 "dashboard-lifecycle-event-readiness"
             }
           }

    nil_event =
      render_component(&SelectedActivityActionComponents.readiness_return_prompt/1,
        summary: %{
          found?: true,
          event_type_text: "publish_readiness_checked",
          event_id: nil
        },
        readiness_return_intent: "source_return"
      )
      |> LiveVue.Test.get_vue(id: "dashboard-selected-activity-readiness-return-component")
      |> then(& &1.props["presentation"])

    assert nil_event["root"]["attrs"][
             "data-dashboard-selected-activity-readiness-return-event"
           ] == nil

    assert nil_event["action"]["attrs"][
             "data-dashboard-selected-activity-readiness-return-refresh"
           ] == nil
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
              },
              %{
                kind: "source_refreshed",
                occurred_at: "2026-06-27T11:55:00Z",
                source: "",
                message: "Source evidence refreshed"
              }
            ]
          }
        }
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-source-actions-component"
      )

    assert vue.component == "SelectedActivityActions"
    assert vue.id == "dashboard-selected-activity-source-actions-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["kind"] == "source_actions"
    assert presentation["visible"] == true

    assert presentation["root"] == %{
             "id" => "dashboard-selected-activity-source-actions",
             "class" => "mt-2 space-y-1 border-l-2 border-success/70 pl-2 text-base-content/70",
             "attrs" => %{
               "data-dashboard-selected-activity-source-actions" => "2",
               "data-dashboard-selected-activity-source-action-latest-kind" => "source_reviewed",
               "data-dashboard-selected-activity-source-action-latest-at" =>
                 "2026-06-27T12:00:00Z"
             }
           }

    assert presentation["latest"] == %{
             "class" => "font-semibold",
             "text" => "Source evidence reviewed"
           }

    assert Enum.map(presentation["rows"], & &1["key"]) == [
             "source-action-0",
             "source-action-1"
           ]

    assert Enum.map(
             presentation["rows"],
             & &1["attrs"]["data-dashboard-selected-activity-source-action"]
           ) == ["source_reviewed", "source_refreshed"]

    [reviewed, refreshed] = presentation["rows"]

    assert reviewed == %{
             "key" => "source-action-0",
             "class" => "flex flex-wrap items-center gap-x-2 gap-y-0.5",
             "attrs" => %{
               "data-dashboard-selected-activity-source-action" => "source_reviewed",
               "data-dashboard-selected-activity-source-action-at" => "2026-06-27T12:00:00Z",
               "data-dashboard-selected-activity-source-action-source" => "rehearsal-source"
             },
             "message" => %{"text" => "Source evidence reviewed"},
             "occurred_at" => %{
               "class" => "font-mono text-base-content/60",
               "text" => "2026-06-27T12:00:00Z"
             },
             "source" => %{
               "visible" => true,
               "class" => "font-mono text-base-content/60",
               "text" => "rehearsal-source"
             }
           }

    assert refreshed == %{
             "key" => "source-action-1",
             "class" => "flex flex-wrap items-center gap-x-2 gap-y-0.5",
             "attrs" => %{
               "data-dashboard-selected-activity-source-action" => "source_refreshed",
               "data-dashboard-selected-activity-source-action-at" => "2026-06-27T11:55:00Z",
               "data-dashboard-selected-activity-source-action-source" => ""
             },
             "message" => %{"text" => "Source evidence refreshed"},
             "occurred_at" => %{
               "class" => "font-mono text-base-content/60",
               "text" => "2026-06-27T11:55:00Z"
             },
             "source" => %{
               "visible" => false,
               "class" => "font-mono text-base-content/60",
               "text" => ""
             }
           }
  end

  test "source_actions preserves nil source truthiness while omitting the nil DOM attr" do
    html =
      render_component(&SelectedActivityActionComponents.source_actions/1,
        summary: %{
          source_actions: %{
            present?: true,
            count_text: "1",
            latest: %{
              kind: "source_reviewed",
              occurred_at: "2026-06-27T12:00:00Z",
              message: "Source evidence reviewed"
            },
            rows: [
              %{
                kind: "source_reviewed",
                occurred_at: "2026-06-27T12:00:00Z",
                source: nil,
                message: "Source evidence reviewed"
              }
            ]
          }
        }
      )

    presentation =
      html
      |> LiveVue.Test.get_vue(id: "dashboard-selected-activity-source-actions-component")
      |> then(& &1.props["presentation"])

    assert presentation == Jason.decode!(Jason.encode!(presentation))

    [row] = presentation["rows"]

    assert row["source"] == %{
             "visible" => true,
             "class" => "font-mono text-base-content/60",
             "text" => ""
           }

    assert row["attrs"]["data-dashboard-selected-activity-source-action-source"] == nil
  end

  test "remediation_actions routes data source remediation back through dashboard context" do
    selected_issue_id = "issue-widget-context"

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
            },
            %{
              issue_id: selected_issue_id,
              label: "Change widget context",
              target: "dashboard_editor",
              message: nil,
              params: %{
                "placement_id" => "placement-ground-state",
                "source_empty_reason" => "unsupported_observable_scope",
                "unsupported_observables" => "ground.station.connection_state"
              }
            }
          ]
        },
        dashboard_document: dashboard_document()
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-remediation-component"
      )

    assert vue.component == "SelectedActivityActions"
    assert vue.id == "dashboard-selected-activity-remediation-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["kind"] == "remediation"
    assert presentation["visible"] == true
    assert presentation["root"] == %{"class" => "mt-3 space-y-2"}
    assert presentation["heading"] == %{"class" => "hud-label", "text" => "Remediation"}

    assert Enum.map(presentation["rows"], & &1["key"]) == [
             "remediation-action-0",
             "remediation-action-1"
           ]

    assert Enum.map(
             presentation["rows"],
             & &1["attrs"]["data-dashboard-selected-activity-remediation"]
           ) == ["Fix source connection", "Change widget context"]

    assert Enum.map(
             presentation["rows"],
             & &1["attrs"]["data-dashboard-selected-activity-remediation-target"]
           ) == ["data_sources", "dashboard_editor"]

    [source_row, editor_row] = presentation["rows"]

    assert source_row["class"] == "border-l-2 border-info/70 pl-2"
    assert source_row["label"] == %{"class" => "font-semibold", "text" => "Fix source connection"}
    assert source_row["attrs"]["data-dashboard-selected-activity-remediation-issue"] == ""

    assert source_row["message"] == %{
             "visible" => true,
             "class" => "mt-0.5 text-base-content/70",
             "text" => "Inspect the failed connection test."
           }

    source_action = source_row["action"]
    source_href = source_action["href"]

    assert source_action["navigation_kind"] == "navigate"

    assert source_action["class"] ==
             "mt-1 inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus"

    assert source_action["text"] == "Open Data Sources"

    assert source_action["icon"] == %{
             "name" => "hero-arrow-top-right-on-square",
             "class" => "h-3 w-3"
           }

    assert source_action["attrs"] == %{
             "data-dashboard-selected-activity-remediation-link" => "Fix source connection",
             "data-dashboard-selected-activity-remediation-href" => source_href,
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push"
           }

    assert String.starts_with?(source_href, "/missions/mission-1/ops/data-sources?")

    assert URI.decode_query(URI.parse(source_href).query) == %{
             "data_source_id" => "rehearsal-source",
             "selected_evidence_kind" => "source",
             "source_dashboard_id" => "dashboard-1",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }

    assert editor_row["attrs"]["data-dashboard-selected-activity-remediation-issue"] ==
             selected_issue_id

    assert editor_row["class"] == "border-l-2 border-info/70 pl-2"
    assert editor_row["label"] == %{"class" => "font-semibold", "text" => "Change widget context"}

    assert editor_row["message"] == %{
             "visible" => false,
             "class" => "mt-0.5 text-base-content/70",
             "text" => ""
           }

    editor_action = editor_row["action"]
    editor_href = editor_action["href"]

    assert editor_action["navigation_kind"] == "patch"

    assert editor_action["class"] ==
             "mt-1 inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus"

    assert editor_action["text"] == "Open Widget Editor"
    assert editor_action["icon"] == %{"name" => "hero-pencil-square", "class" => "h-3 w-3"}

    assert editor_action["attrs"] == %{
             "data-dashboard-selected-activity-remediation-link" => "Change widget context",
             "data-dashboard-selected-activity-remediation-href" => editor_href,
             "data-phx-link" => "patch",
             "data-phx-link-state" => "push"
           }

    assert String.starts_with?(
             editor_href,
             "/missions/mission-1/ops/dashboards/dashboard-1?"
           )

    assert URI.decode_query(URI.parse(editor_href).query) == %{
             "panel" => "dashboard_editor",
             "selected_placement" => "placement-ground-state",
             "selected_publish_issue" => selected_issue_id,
             "source_empty_reason" => "unsupported_observable_scope",
             "unsupported_observables" => "ground.station.connection_state"
           }
  end

  test "does not render an island when the original action renderer is empty" do
    readiness =
      render_component(&SelectedActivityActionComponents.readiness_return_prompt/1,
        summary: %{found?: false},
        readiness_return_intent: nil
      )

    source_actions =
      render_component(&SelectedActivityActionComponents.source_actions/1,
        summary: %{source_actions: %{present?: false}}
      )

    recovery =
      render_component(&SelectedActivityActionComponents.recovery_banner/1,
        summary: %{filter_state: :visible},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    remediation =
      render_component(&SelectedActivityActionComponents.remediation_actions/1,
        summary: %{remediation_actions: []},
        dashboard_document: dashboard_document()
      )

    assert [] =
             readiness
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-selected-activity-readiness-return-component")
             |> LazyHTML.attribute("id")

    assert [] =
             source_actions
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-selected-activity-source-actions-component")
             |> LazyHTML.attribute("id")

    assert [] =
             recovery
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-selected-activity-recovery-component")
             |> LazyHTML.attribute("id")

    assert [] =
             remediation
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-selected-activity-remediation-component")
             |> LazyHTML.attribute("id")
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
