defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.ComparisonReviewQueue

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarWarningPresentation
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents
  alias Phoenix.LiveView.JS

  defp time_picker_presentation(html) do
    html
    |> toolbar_presentation()
    |> get_in(["viewer", "time_picker"])
  end

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

    context = context_selector_presentation(html)
    mission = context_node_by_attr(context, "phx-value-scope-kind", "mission")
    input = context_node_by_attr(context, "id", "context-search")

    assert mission["attrs"]["phx-value-scope-kind"] == "mission"
    assert mission["attrs"]["phx-value-scope-id"] == "mission-1"
    assert List.first(mission["children"]) == "Lunar Demo"

    assert input["attrs"]["placeholder"] ==
             "Find mission, spacecraft, contact, source, transport, ground, or link"

    assert toolbar_menu_item(html, "dashboard-versions-button")["link"]["attrs"]["href"] == "#"
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

    runtime_controls = ViewTestSupport.dashboard_runtime_controls(html)
    fallback = runtime_controls["form"]["semantics"]["badge"]

    assert fallback["attrs"]["data-requested-limit-mode"] == "projected"

    assert fallback["attrs"]["data-applied-limit-mode"] == "observed"

    assert fallback["attrs"]["data-limit-mode-fallback-reason"] ==
             "unsupported_limit_semantics_mode"

    assert fallback["attrs"]["title"] ==
             "Requested projected limit semantics; using observed."
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

    presentation = editor_actions_presentation(html)

    assert editor_action(presentation, "edit-paused-note")["text"] ==
             "Live updates paused while editing"

    assert editor_action(presentation, "edit-layout-toggle")["text"] == "Done"

    refute Enum.any?(
             presentation["elements"],
             &(&1["attrs"]["id"] == "dashboard-lifecycle-publish")
           )

    refute Enum.any?(
             presentation["elements"],
             &(&1["attrs"]["id"] == "dashboard-lifecycle-archive")
           )

    historical_request_path =
      toolbar_menu_item(html, "dashboard-historical-workflow-request-button")["link"]["attrs"][
        "href"
      ]

    assert historical_request_path =~ "/missions/mission-1/ops/data-operations?"

    assert toolbar_menu_item(html, "dashboard-diagnostics-button")["link"]["attrs"]["href"] ==
             "#"

    assert toolbar_presentation(html)["viewer"] == nil
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
      presentation =
        render_component(
          &DashboardToolbarComponents.dashboard_toolbar/1,
          toolbar_assigns(overrides)
        )
        |> toolbar_presentation()

      assert presentation["comparison_toggle"] == nil
    end
  end

  test "healthy viewer keeps only scope and time as primary controls" do
    html = render_component(&DashboardToolbarComponents.dashboard_toolbar/1, toolbar_assigns([]))
    presentation = toolbar_presentation(html)
    time_picker = time_picker_presentation(html)

    assert presentation["viewer"]["operational_scope"]["root"]["attrs"][
             "data-dashboard-primary-control"
           ] == "scope"

    assert time_picker["overlay"]["root"]["attrs"]["data-dashboard-primary-control"] ==
             "time"

    refute presentation["viewer"]["operational_scope"]["panel"]["body"]["query_options"][
             "attrs"
           ]["open"]

    assert presentation["viewer"]["operational_scope"]["trigger"]["override"] == nil
    refute toolbar_menu_item(html, "dashboard-investigate-toggle")
  end

  test "non-default data context opens provenance controls and exposes a compact override" do
    presentation =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(data_realm: "replay", data_view: "as_recorded", limit_mode: "current")
      )
      |> toolbar_presentation()

    assert presentation["viewer"]["operational_scope"]["panel"]["body"]["query_options"][
             "attrs"
           ]["open"]

    override = presentation["viewer"]["operational_scope"]["trigger"]["override"]
    assert override["attrs"]["data-dashboard-data-override"] == ""
    assert override["text"] =~ "Replay · As recorded"
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

    presentation = toolbar_presentation(html)
    time_picker = time_picker_presentation(html)

    assert presentation["root"]["attrs"]["id"] == "dashboard-telemetry-toolbar"

    assert time_picker["overlay"]["trigger"]["active_range"]["attrs"][
             "data-dashboard-time-summary"
           ] == "live"

    data_health = presentation["data_health"]
    assert data_health["root"]["attrs"]["data-dashboard-data-issue-count"] == "3"

    assert [warning] = data_health["panel"]["body"]["warnings"]
    assert warning["component_id"] == "dashboard-data-issue-warning-0-component"
    assert warning["overlay"]["attrs"]["data-engine-warning-detail"] == "stale_data"

    assert data_health["panel"]["body"]["action"]["attrs"][
             "data-dashboard-data-issue-action"
           ] == "data_sources"

    source_path = data_health["panel"]["body"]["action"]["attrs"]["href"]

    assert source_path =~ "/missions/mission-1/ops/data-sources"

    diagnostics_path =
      data_health["panel"]["body"]["diagnostics_action"]["attrs"]["href"]

    assert diagnostics_path =~ "/missions/mission-1/ops/dashboards/dashboard-1/diagnostics"

    assert presentation["viewer"]["operational_scope"]["panel"]["attrs"]["id"] ==
             "dashboard-data-controls-panel"

    assert presentation["viewer"]["operational_scope"]["panel"]["body"]["query_options"][
             "panel"
           ]["attrs"]["id"] == "dashboard-query-options-panel"

    assert time_picker["overlay"]["panel"]["attrs"]["id"] ==
             "dashboard-time-controls-panel"

    assert presentation["viewer"]["operational_scope"]["trigger"]["attrs"]["aria-label"] ==
             "Dashboard operational scope"

    assert presentation["viewer"]["operational_scope"]["panel"]["body"]["query_options"][
             "summary"
           ]["attrs"]["aria-label"] == "Dashboard data options"

    assert time_picker["overlay"]["trigger"]["attrs"]["aria-label"] ==
             "Dashboard time range"

    assert presentation["menu"]["panel"]["attrs"]["id"] == "dashboard-menu-menu"

    assert toolbar_menu_item(html, "dashboard-investigate-telemetry")["key"] ==
             "dashboard-investigate-telemetry"
  end

  test "toolbar-owned warning presentation preserves the existing warning contract" do
    warning = %{
      code_text: "source_degraded",
      label: "Source degraded",
      message: "Telemetry source returned degraded data.",
      severity: :warning,
      details: %{
        source_request_id: "request-1",
        logical_source: "simulator",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        data_view: "canonical",
        time_mode: "wall_clock",
        time_axis: "receipt_time",
        replay_run_id: "replay-1"
      },
      detail_rows: [%{label: "Source request", value: "request-1"}],
      evidence: [
        %{
          kind_text: "source",
          id: "request-1",
          source_text: "simulator",
          observed_at_text: "2026-06-17T12:00:00Z"
        }
      ],
      links: [
        %{
          link_id: "warning-link-1",
          target_text: "telemetry_sample",
          target_id: "sample-1",
          source_text: "telemetry"
        }
      ]
    }

    expected =
      render_component(
        &WidgetWarningComponents.engine_warning_badge/1,
        id: "dashboard-data-issue-warning-0",
        warning: warning
      )
      |> LiveVue.Test.get_vue(id: "dashboard-data-issue-warning-0-component")
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")

    actual = DashboardToolbarWarningPresentation.build("dashboard-data-issue-warning-0", warning)

    assert Jason.decode!(Jason.encode!(actual)) == expected
  end

  test "publish readiness stays out of the viewing toolbar" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_publish_readiness: %{status: "blocked", issues: [%{severity: :error}]}
        )
      )

    assert toolbar_presentation(html)["editor_actions"] == nil
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

    time_picker = time_picker_presentation(html)

    live_preset =
      time_picker
      |> get_in(["time_picker", "quick_ranges", "presets", "items"])
      |> Enum.find(&(&1["attrs"]["id"] == "dashboard-time-preset-live"))

    assert time_picker["overlay"]["trigger"]["active_range"]["attrs"][
             "data-dashboard-time-mode"
           ] == "archive"

    assert live_preset["attrs"]["phx-click"] == "set_time_preset"
    assert live_preset["attrs"]["phx-value-preset"] == "live"

    href = toolbar_menu_item(html, "dashboard-investigate-telemetry")["link"]["attrs"]["href"]

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
    html
    |> toolbar_presentation()
    |> Map.fetch!("editor_actions")
  end

  defp context_selector_presentation(html) do
    html
    |> toolbar_presentation()
    |> get_in(["viewer", "operational_scope", "panel", "body", "context"])
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
    html
    |> toolbar_presentation()
    |> Map.fetch!("comparison_toggle")
  end

  defp toolbar_presentation(html) do
    assert ["dashboard-toolbar-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-toolbar-component")
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: "dashboard-toolbar-component")

    assert vue.component == "DashboardToolbar"
    assert vue.id == "dashboard-toolbar-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert vue.handlers["select-range"] == JS.push("set_chart_time_range")
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp toolbar_menu_item(html, id) do
    html
    |> toolbar_presentation()
    |> get_in(["menu", "panel", "items"])
    |> Enum.find(&(&1["key"] == id))
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
