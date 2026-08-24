defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.ComparisonReviewQueue

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents

  test "dashboard_toolbar exposes mission scope alongside spacecraft context search" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          context_scope_kind: "mission",
          context_scope_id: "mission-1",
          query: "lunar"
        )
      )

    document = LazyHTML.from_fragment(html)
    context = context_selector_presentation(html)
    mission = context_node_by_attr(context, "phx-value-scope-kind", "mission")
    input = context_node_by_attr(context, "id", "context-search")

    assert mission["attrs"]["phx-value-scope-kind"] == "mission"
    assert mission["attrs"]["phx-value-scope-id"] == "mission-1"
    assert List.first(mission["children"]) == "Lunar Demo"

    assert input["attrs"]["placeholder"] ==
             "Find mission, spacecraft, contact, source, transport, ground, or link"

    assert ["#"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("href")
  end

  test "dashboard_toolbar exposes scheduled and realized contacts as runtime contexts" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          spacecraft: [],
          scheduled_contacts: [
            %{
              scheduled_contact_id: "contact-scheduled-1",
              source_endpoint_refs: ["gs-alpha"]
            }
          ],
          realized_contacts: [
            %{
              realized_contact_id: "contact-realized-1",
              scheduled_contact_id: "contact-scheduled-1",
              source_endpoint_refs: ["gs-alpha"]
            }
          ],
          context_scope_kind: "contact",
          context_scope_id: "contact-realized-1",
          query: "gs-alpha"
        )
      )

    context = context_selector_presentation(html)
    selected = context_node_by_attr(context, "id", "dashboard-selected-context")

    scheduled =
      context_node_by_attr(
        context,
        "data-dashboard-context-contact-id",
        "contact-scheduled-1"
      )

    realized =
      context_node_by_attr(context, "data-dashboard-context-contact-kind", "realized")

    assert selected["children"] == ["realized / contact-realized-1 / gs-alpha"]
    assert scheduled["attrs"]["phx-value-scope-kind"] == "contact"
    assert scheduled["attrs"]["phx-value-scope-id"] == "contact-scheduled-1"
    assert scheduled["attrs"]["data-dashboard-context-contact-kind"] == "scheduled"
    assert realized["attrs"]["phx-value-scope-id"] == "contact-realized-1"
  end

  test "dashboard_toolbar exposes unsupported limit mode fallback" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          show_context?: false,
          time_mode: "archive",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          limit_mode: "observed",
          limit_mode_fallback: %{
            "requested_mode" => "projected",
            "applied_mode" => "observed",
            "reason" => "unsupported_limit_semantics_mode"
          }
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["projected"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-requested-limit-mode")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-applied-limit-mode")

    assert ["unsupported_limit_semantics_mode"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-limit-mode-fallback-reason")

    assert ["Requested projected limit semantics; using observed."] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("title")
  end

  test "dashboard_toolbar routes lifecycle and data operations out of the viewer" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          edit_mode?: true,
          dashboard_lifecycle_status: %{publish_available?: false, archive_available?: true}
        )
      )

    document = LazyHTML.from_fragment(html)
    presentation = editor_actions_presentation(html)

    assert editor_action(presentation, "edit-paused-note")["text"] ==
             "Live updates paused while editing"

    assert editor_action(presentation, "edit-layout-toggle")["text"] == "Done"

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-lifecycle-action="publish"]))
             |> LazyHTML.attribute("data-dashboard-action-available")

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-lifecycle-action="archive"]))
             |> LazyHTML.attribute("data-dashboard-action-available")

    assert [historical_request_path] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-button")
             |> LazyHTML.attribute("href")

    assert historical_request_path =~ "/missions/mission-1/ops/data-operations?"

    assert ["#"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-button")
             |> LazyHTML.attribute("href")

    assert [] =
             document
             |> LazyHTML.query("#runtime-context-controls")
             |> LazyHTML.attribute("id")
  end

  test "dashboard_toolbar renders publish readiness summary" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          edit_mode?: true,
          dashboard_publish_readiness: %{
            status: "blocked",
            label: "blocked",
            issues: [
              %{severity: :error, code: "invalid_runtime_default_context"},
              %{severity: :error, code: "unready_publish_source_request"}
            ]
          }
        )
      )

    presentation = editor_actions_presentation(html)

    assert Enum.map(presentation["elements"], & &1["key"]) == [
             "dashboard-publish-readiness-summary",
             "edit-paused-note",
             "edit-layout-toggle",
             "add-widget-button",
             "manage-dashboard-sections"
           ]

    assert editor_action(presentation, "dashboard-publish-readiness-summary") == %{
             "key" => "dashboard-publish-readiness-summary",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-publish-readiness-summary",
               "type" => "button",
               "phx-click" => "open_versions",
               "class" =>
                 "inline-flex h-6 items-center gap-1 rounded border px-2 text-[11px] font-medium border-error/40 bg-error/10 text-error",
               "data-dashboard-publish-readiness-status" => "blocked",
               "data-dashboard-publish-readiness-issue-count" => "2"
             },
             "text" => "",
             "children" => [
               %{
                 "key" => "icon",
                 "tag" => "span",
                 "attrs" => %{"class" => "hero-exclamation-triangle h-3 w-3"},
                 "text" => ""
               },
               %{
                 "key" => "label",
                 "tag" => "span",
                 "attrs" => %{},
                 "text" => "Publish blocked"
               },
               %{
                 "key" => "issue-count",
                 "tag" => "span",
                 "attrs" => %{"class" => "font-mono opacity-80"},
                 "text" => "2"
               }
             ]
           }
  end

  test "dashboard_toolbar renders stale publish readiness summary" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          edit_mode?: true,
          dashboard_publish_readiness: %{
            status: "stale",
            label: "needs re-check",
            issues: []
          }
        )
      )

    summary =
      html
      |> editor_actions_presentation()
      |> editor_action("dashboard-publish-readiness-summary")

    assert summary["attrs"]["data-dashboard-publish-readiness-status"] == "stale"
    assert summary["attrs"]["data-dashboard-publish-readiness-issue-count"] == "0"
    assert Enum.map(summary["children"], & &1["key"]) == ["icon", "label"]
    assert Enum.at(summary["children"], 0)["attrs"]["class"] == "hero-arrow-path h-3 w-3"
    assert Enum.at(summary["children"], 1)["text"] == "Re-check publish"
  end

  test "dashboard_toolbar preserves every remaining publish readiness variant" do
    for {status, label, icon, class} <- [
          {"warnings", "Publish warnings", "hero-exclamation-circle",
           "border-warning/40 bg-warning/10 text-warning"},
          {"clean", "Publish ready", "hero-check-circle",
           "border-success/40 bg-success/10 text-success"},
          {"unknown", "Publish status", "hero-information-circle",
           "border-base-300 bg-base-100 text-base-content/70"}
        ] do
      summary =
        render_component(
          &DashboardToolbarComponents.dashboard_toolbar/1,
          toolbar_assigns(
            edit_mode?: true,
            dashboard_publish_readiness: %{status: status, issues: [%{severity: :warning}]}
          )
        )
        |> editor_actions_presentation()
        |> editor_action("dashboard-publish-readiness-summary")

      assert summary["attrs"] == %{
               "id" => "dashboard-publish-readiness-summary",
               "type" => "button",
               "phx-click" => "open_versions",
               "class" =>
                 "inline-flex h-6 items-center gap-1 rounded border px-2 text-[11px] font-medium #{class}",
               "data-dashboard-publish-readiness-status" => status,
               "data-dashboard-publish-readiness-issue-count" => "1"
             }

      assert Enum.at(summary["children"], 0)["attrs"]["class"] == "#{icon} h-3 w-3"
      assert Enum.at(summary["children"], 1)["text"] == label
      assert Enum.at(summary["children"], 2)["text"] == "1"
    end
  end

  test "dashboard_toolbar preserves the edit-mode action fragment contract" do
    presentation =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(edit_mode?: true)
      )
      |> editor_actions_presentation()

    assert presentation["elements"] == [
             %{
               "key" => "edit-paused-note",
               "tag" => "span",
               "attrs" => %{
                 "id" => "edit-paused-note",
                 "class" => "text-xs text-warning"
               },
               "text" => "Live updates paused while editing",
               "children" => []
             },
             %{
               "key" => "edit-layout-toggle",
               "tag" => "button",
               "attrs" => %{
                 "id" => "edit-layout-toggle",
                 "type" => "button",
                 "class" => "btn btn-primary btn-xs",
                 "phx-click" => "toggle_edit"
               },
               "text" => "Done",
               "children" => [
                 %{
                   "key" => "icon",
                   "tag" => "span",
                   "attrs" => %{"class" => "hero-arrows-pointing-out h-3.5 w-3.5"},
                   "text" => ""
                 }
               ]
             },
             %{
               "key" => "add-widget-button",
               "tag" => "button",
               "attrs" => %{
                 "id" => "add-widget-button",
                 "type" => "button",
                 "class" => "btn btn-ghost btn-xs",
                 "phx-click" => "open_add_widget"
               },
               "text" => "Widget",
               "children" => [
                 %{
                   "key" => "icon",
                   "tag" => "span",
                   "attrs" => %{"class" => "hero-plus h-3.5 w-3.5"},
                   "text" => ""
                 }
               ]
             },
             %{
               "key" => "manage-dashboard-sections",
               "tag" => "button",
               "attrs" => %{
                 "id" => "manage-dashboard-sections",
                 "type" => "button",
                 "class" => "btn btn-ghost btn-xs",
                 "phx-click" => "open_dashboard_sections"
               },
               "text" => "Sections",
               "children" => [
                 %{
                   "key" => "icon",
                   "tag" => "span",
                   "attrs" => %{"class" => "hero-rectangle-group h-3.5 w-3.5"},
                   "text" => ""
                 }
               ]
             }
           ]
  end

  test "dashboard_toolbar preserves editor-route state actions and conflict decisions" do
    saved =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(editor_route?: true)
      )
      |> editor_actions_presentation()

    assert Enum.map(saved["elements"], & &1["key"]) == [
             "dashboard-editor-save-state",
             "dashboard-editor-discard",
             "dashboard-editor-save",
             "dashboard-editor-review"
           ]

    assert editor_action(saved, "dashboard-editor-save-state") == %{
             "key" => "dashboard-editor-save-state",
             "tag" => "span",
             "attrs" => %{
               "id" => "dashboard-editor-save-state",
               "class" => "font-mono text-[0.65rem] uppercase tracking-wider text-success",
               "data-editor-dirty" => "false"
             },
             "text" => "Saved",
             "children" => []
           }

    assert editor_action(saved, "dashboard-editor-discard") == %{
             "key" => "dashboard-editor-discard",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-editor-discard",
               "type" => "button",
               "class" => "btn btn-ghost btn-xs",
               "phx-click" => "discard_editor",
               "data-editor-discard" => ""
             },
             "text" => "Discard",
             "children" => []
           }

    assert editor_action(saved, "dashboard-editor-save") == %{
             "key" => "dashboard-editor-save",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-editor-save",
               "type" => "button",
               "class" => "btn btn-primary btn-xs",
               "phx-click" => "save_editor",
               "disabled" => ""
             },
             "text" => "Save",
             "children" => [
               %{
                 "key" => "icon",
                 "tag" => "span",
                 "attrs" => %{"class" => "hero-check h-3.5 w-3.5"},
                 "text" => ""
               }
             ]
           }

    assert editor_action(saved, "dashboard-editor-review") == %{
             "key" => "dashboard-editor-review",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-editor-review",
               "type" => "button",
               "class" => "btn btn-ghost btn-xs",
               "phx-click" => "review_editor"
             },
             "text" => "Review & Publish",
             "children" => []
           }

    dirty =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(edit_mode?: true, editor_route?: true, editor_dirty?: true)
      )
      |> editor_actions_presentation()

    assert Enum.map(dirty["elements"], & &1["key"]) == [
             "edit-paused-note",
             "dashboard-editor-save-state",
             "dashboard-editor-discard",
             "dashboard-editor-save",
             "dashboard-editor-review",
             "add-widget-button",
             "manage-dashboard-sections"
           ]

    assert editor_action(dirty, "dashboard-editor-save-state")["attrs"] == %{
             "id" => "dashboard-editor-save-state",
             "class" => "font-mono text-[0.65rem] uppercase tracking-wider text-warning",
             "data-editor-dirty" => "true"
           }

    assert editor_action(dirty, "dashboard-editor-save-state")["text"] == "Unsaved changes"
    refute Map.has_key?(editor_action(dirty, "dashboard-editor-save")["attrs"], "disabled")
    refute Map.has_key?(editor_action(dirty, "dashboard-editor-review")["attrs"], "disabled")

    conflicted =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          edit_mode?: true,
          editor_route?: true,
          editor_dirty?: true,
          editor_conflict: %{current_version: 2}
        )
      )
      |> editor_actions_presentation()

    assert editor_action(conflicted, "dashboard-editor-save")["attrs"]["disabled"] == ""
    assert editor_action(conflicted, "dashboard-editor-review")["attrs"]["disabled"] == ""
  end

  test "dashboard_toolbar exposes the page-local Compare inspector" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          comparison_available?: true,
          comparison_open?: true,
          comparison_open_count: 2
        )
      )

    presentation = comparison_toggle_presentation(html)

    assert presentation == %{
             "root" => %{
               "tag" => "button",
               "class" =>
                 "btn btn-ghost btn-xs h-7 gap-1.5 border px-2 font-normal border-info/45 bg-info/10 text-info",
               "attrs" => %{
                 "id" => "dashboard-comparison-toggle",
                 "type" => "button",
                 "phx-click" => "toggle_comparison_inspector",
                 "aria-expanded" => "true",
                 "aria-controls" => "dashboard-comparison-inspector",
                 "data-dashboard-comparison-toggle" => ""
               }
             },
             "children" => [
               %{
                 "key" => "icon",
                 "tag" => "span",
                 "class" => "hero-scale h-3.5 w-3.5",
                 "attrs" => %{},
                 "text" => ""
               },
               %{
                 "key" => "label",
                 "tag" => "span",
                 "class" => "hidden sm:inline",
                 "attrs" => %{},
                 "text" => "Compare"
               },
               %{
                 "key" => "open-count",
                 "tag" => "span",
                 "class" => "badge badge-warning badge-xs",
                 "attrs" => %{"data-dashboard-comparison-open-count" => "2"},
                 "text" => "2"
               }
             ]
           }
  end

  test "dashboard_toolbar preserves the closed comparison toggle and zero-count badge semantics" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          comparison_available?: true,
          compare_data_view: "all_revisions",
          comparison_open?: false,
          comparison_open_count: 0
        )
      )

    presentation = comparison_toggle_presentation(html)

    assert presentation == %{
             "root" => %{
               "tag" => "button",
               "class" =>
                 "btn btn-ghost btn-xs h-7 gap-1.5 border px-2 font-normal border-base-300/70 bg-base-100/50",
               "attrs" => %{
                 "id" => "dashboard-comparison-toggle",
                 "type" => "button",
                 "phx-click" => "toggle_comparison_inspector",
                 "aria-expanded" => "false",
                 "aria-controls" => "dashboard-comparison-inspector",
                 "data-dashboard-comparison-toggle" => ""
               }
             },
             "children" => [
               %{
                 "key" => "icon",
                 "tag" => "span",
                 "class" => "hero-scale h-3.5 w-3.5",
                 "attrs" => %{},
                 "text" => ""
               },
               %{
                 "key" => "label",
                 "tag" => "span",
                 "class" => "hidden sm:inline",
                 "attrs" => %{},
                 "text" => "Compare"
               }
             ]
           }
  end

  test "dashboard_toolbar omits the island whenever the original comparison toggle is hidden" do
    for overrides <- [
          [comparison_available?: true],
          [
            comparison_available?: false,
            comparison_open?: true,
            comparison_open_count: 2,
            compare_data_view: "all_revisions"
          ],
          [edit_mode?: true, comparison_available?: true, comparison_open?: true]
        ] do
      document =
        render_component(
          &DashboardToolbarComponents.dashboard_toolbar/1,
          toolbar_assigns(overrides)
        )
        |> LazyHTML.from_fragment()

      assert [] =
               document
               |> LazyHTML.query("#dashboard-comparison-toggle-component")
               |> LazyHTML.attribute("id")
    end
  end

  test "healthy viewer keeps only scope and time as primary controls" do
    document =
      render_component(&DashboardToolbarComponents.dashboard_toolbar/1, toolbar_assigns([]))
      |> LazyHTML.from_fragment()

    assert ["scope", "time"] =
             document
             |> LazyHTML.query("[data-dashboard-primary-control]")
             |> LazyHTML.attribute("data-dashboard-primary-control")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-query-options")
             |> LazyHTML.attribute("open")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-data-override]")
             |> LazyHTML.attribute("data-dashboard-data-override")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-investigate-toggle")
             |> LazyHTML.attribute("id")
  end

  test "non-default data context opens provenance controls and exposes a compact override" do
    document =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(data_realm: "replay", data_view: "as_recorded", limit_mode: "current")
      )
      |> LazyHTML.from_fragment()

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-query-options")
             |> LazyHTML.attribute("open")

    assert [""] =
             document
             |> LazyHTML.query("[data-dashboard-data-override]")
             |> LazyHTML.attribute("data-dashboard-data-override")

    assert document |> LazyHTML.query("[data-dashboard-data-override]") |> LazyHTML.text() =~
             "Replay · As recorded"
  end

  test "dashboard_toolbar keeps telemetry primary and consolidates data issues" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_document: %{
            dashboard_id: "dashboard-1",
            name: "Ops",
            description: "Operations"
          },
          dashboard_degraded?: true,
          dashboard_warnings: [
            %{
              code: :stale_data,
              code_text: "stale_data",
              severity: :warning,
              label: "Stale data",
              message: "One widget is stale",
              details: %{},
              detail_rows: [],
              evidence: [],
              links: []
            }
          ],
          dashboard_health: %{state: :degraded, affected_count: 3}
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-telemetry-toolbar"] =
             document
             |> LazyHTML.query("#dashboard-telemetry-toolbar")
             |> LazyHTML.attribute("id")

    assert ["live"] =
             document
             |> LazyHTML.query("[data-dashboard-time-summary]")
             |> LazyHTML.attribute("data-dashboard-time-summary")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-data-issues")
             |> LazyHTML.attribute("data-dashboard-data-issue-count")

    assert ["data_sources"] =
             document
             |> LazyHTML.query("#dashboard-data-issues-open")
             |> LazyHTML.attribute("data-dashboard-data-issue-action")

    assert [source_path] =
             document
             |> LazyHTML.query("#dashboard-data-issues-open")
             |> LazyHTML.attribute("href")

    assert source_path =~ "/missions/mission-1/ops/data-sources"

    assert [diagnostics_path] =
             document
             |> LazyHTML.query("#dashboard-data-issues-diagnostics")
             |> LazyHTML.attribute("href")

    assert diagnostics_path =~ "/missions/mission-1/ops/dashboards/dashboard-1/diagnostics"

    assert ["dashboard-data-controls-panel"] =
             document
             |> LazyHTML.query("#dashboard-data-controls-panel")
             |> LazyHTML.attribute("id")

    assert ["dashboard-query-options-panel"] =
             document
             |> LazyHTML.query("#dashboard-query-options-panel")
             |> LazyHTML.attribute("id")

    assert ["dashboard-time-controls-panel"] =
             document
             |> LazyHTML.query("#dashboard-time-controls-panel")
             |> LazyHTML.attribute("id")

    assert ["Dashboard operational scope"] =
             document
             |> LazyHTML.query("#dashboard-data-controls-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["Dashboard data options"] =
             document
             |> LazyHTML.query("#dashboard-query-options-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["Dashboard time range"] =
             document
             |> LazyHTML.query("#dashboard-time-controls-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["dashboard-menu-menu"] =
             document
             |> LazyHTML.query("#dashboard-menu-menu")
             |> LazyHTML.attribute("id")

    assert ["dashboard-investigate-telemetry"] =
             document
             |> LazyHTML.query("#dashboard-menu-menu #dashboard-investigate-telemetry")
             |> LazyHTML.attribute("id")
  end

  test "publish readiness stays out of the viewing toolbar" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_publish_readiness: %{status: "blocked", issues: [%{severity: :error}]}
        )
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-editor-actions-component")
             |> LazyHTML.attribute("id")
  end

  test "viewing toolbar exposes correlated time state and context-preserving drilldowns" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_document: %{
            dashboard_id: "dashboard-1",
            name: "Ops",
            description: "Operations"
          },
          context_spacecraft_id: "spacecraft-1",
          time_mode: "archive",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          data_source_id: "source-1",
          source_binding_id: "binding-1"
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["archive"] =
             document
             |> LazyHTML.query("#dashboard-active-time-range")
             |> LazyHTML.attribute("data-dashboard-time-mode")

    assert ["set_time_preset"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("phx-click")

    assert ["live"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("phx-value-preset")

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-investigate-telemetry")
             |> LazyHTML.attribute("href")

    uri = URI.parse(href)
    query = URI.decode_query(uri.query)

    assert uri.path == "/missions/mission-1/ops/explore"
    assert query["source_dashboard_id"] == "dashboard-1"
    assert query["spacecraft_id"] == "spacecraft-1"
    assert query["from"] == "2026-06-17T12:00:00Z"
    assert query["to"] == "2026-06-17T12:05:00Z"
    assert query["data_source_id"] == "source-1"
    assert query["source_binding_id"] == "binding-1"
  end

  defp toolbar_assigns(overrides) do
    Keyword.merge(
      [
        dashboard_document: %{name: "Ops", description: "Operations"},
        dashboard_lifecycle_status: %{publish_available?: true, archive_available?: false},
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
        edit_mode?: false,
        show_context?: true,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [
          %{spacecraft_id: "spacecraft-1", display_name: "Alpha", scid: 101}
        ],
        scheduled_contacts: [],
        realized_contacts: [],
        context_spacecraft_id: nil,
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        selected_data_ref: nil,
        query: ""
      ],
      overrides
    )
  end

  defp editor_actions_presentation(html) do
    assert ["dashboard-editor-actions-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-editor-actions-component")
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: "dashboard-editor-actions-component")

    assert vue.component == "DashboardEditorActions"
    assert vue.id == "dashboard-editor-actions-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp context_selector_presentation(html) do
    assert ["dashboard-runtime-context-selector-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-runtime-context-selector-component")
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: "dashboard-runtime-context-selector-component")

    assert vue.component == "DashboardRuntimeContextSelector"
    assert vue.id == "dashboard-runtime-context-selector-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp context_node_by_attr(%{"attrs" => attrs} = node, attribute, value) do
    if attrs[attribute] == value do
      node
    else
      Enum.find_value(node["children"], fn
        child when is_map(child) -> context_node_by_attr(child, attribute, value)
        _text -> nil
      end)
    end
  end

  defp context_node_by_attr(_node, _attribute, _value), do: nil

  defp editor_action(presentation, id) do
    assert action = Enum.find(presentation["elements"], &(&1["attrs"]["id"] == id))
    action
  end

  defp comparison_toggle_presentation(html) do
    assert ["dashboard-comparison-toggle-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-comparison-toggle-component")
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: "dashboard-comparison-toggle-component")

    assert vue.component == "DashboardComparisonToggle"
    assert vue.id == "dashboard-comparison-toggle-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp data_binding do
    %DataBinding{
      binding_id: "flight-binding",
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end
end
