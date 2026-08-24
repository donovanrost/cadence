defmodule CadenceWeb.OpsDashboardShowLive.DashboardHealthComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.DashboardHealthComponents

  test "dashboard health strip summarizes affected widget groups and evidence" do
    snapshot_id = "dashboard_health_snapshot_abc123"

    html =
      render_component(&DashboardHealthComponents.dashboard_health_strip/1,
        health: dashboard_health(snapshot_id)
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-health-rollup-component")

    assert vue.component == "DashboardHealth"
    assert vue.id == "dashboard-health-rollup-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]

    assert presentation |> Map.keys() |> Enum.sort() ==
             ~w(capture controls_class copy_host copy_props evidence groups label root status summary)

    root = presentation["root"]

    assert root["attrs"]["data-dashboard-health-state"] == "blocked"
    assert root["attrs"]["data-dashboard-health-snapshot-id"] == snapshot_id
    assert root["attrs"]["data-dashboard-health-affected"] == "2"
    assert root["id"] == "dashboard-health-rollup"

    assert root["class"] ==
             "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b text-xs border-error/30 bg-error/10"

    assert root["attrs"] == %{
             "data-dashboard-health-affected" => "2",
             "data-dashboard-health-affected-placements" =>
               "blocked-placement,degraded-placement",
             "data-dashboard-health-blocked" => "1",
             "data-dashboard-health-blocked-placements" => "blocked-placement",
             "data-dashboard-health-degraded" => "1",
             "data-dashboard-health-degraded-placements" => "degraded-placement",
             "data-dashboard-health-ready" => "1",
             "data-dashboard-health-rollup" => "",
             "data-dashboard-health-severity" => "error",
             "data-dashboard-health-snapshot-id" => snapshot_id,
             "data-dashboard-health-stale" => "0",
             "data-dashboard-health-stale-placements" => "",
             "data-dashboard-health-state" => "blocked",
             "data-dashboard-health-states" => "ready,degraded,blocked",
             "data-dashboard-health-widgets" => "3"
           }

    assert presentation["label"] == %{"class" => "hud-label", "text" => "Dashboard health"}

    assert presentation["status"] == %{
             "class" => "badge badge-xs badge-error",
             "text" => "Blocked"
           }

    assert presentation["summary"] == %{
             "class" => "text-base-content/70",
             "text" => "widgets 3 / affected 2 / blocked 1 / stale 0 / degraded 1"
           }

    assert presentation["controls_class"] == "ml-auto flex items-center gap-1"

    assert presentation["copy_host"] == %{
             "class" => "contents",
             "id" => "dashboard-health-snapshot-copy-component"
           }

    [blocked_group, degraded_group] = presentation["groups"]

    assert blocked_group["overlay"]["attrs"]["data-dashboard-health-group-placements"] ==
             "blocked-placement"

    [blocked_item] = blocked_group["items"]
    assert blocked_item["href"] == "#widget-blocked-placement"
    assert blocked_item["attrs"]["data-dashboard-health-item-reason"] == "source_unavailable"
    assert blocked_item["key"] == "dashboard-health-item-blocked-0-blocked-placement"

    evidence = presentation["evidence"]

    assert evidence["attrs"]["phx-click"] == "open_evidence"
    assert evidence["attrs"]["phx-value-kind"] == "dashboard_health"

    assert evidence["attrs"]["phx-value-dashboard-health-schema"] ==
             "dashboard_health_snapshot.v1"

    assert evidence["attrs"]["phx-value-dashboard-health-snapshot-id"] == snapshot_id
    assert evidence["attrs"]["phx-value-dashboard-health-state"] == "blocked"

    assert evidence["attrs"]["phx-value-dashboard-health-affected-placements"] ==
             "blocked-placement,degraded-placement"

    assert evidence["id"] == nil
    assert evidence["type"] == "button"
    assert evidence["class"] == "btn btn-ghost btn-xs btn-square"
    assert evidence["title"] == "Open dashboard health evidence"
    assert evidence["aria_label"] == "Open dashboard health evidence"
    assert evidence["icon"] == %{"class" => "h-3.5 w-3.5", "name" => "hero-link"}

    assert evidence["attrs"] == %{
             "data-dashboard-health-evidence-open" => "",
             "phx-click" => "open_evidence",
             "phx-value-dashboard-health-affected" => "2",
             "phx-value-dashboard-health-affected-placements" =>
               "blocked-placement,degraded-placement",
             "phx-value-dashboard-health-blocked" => "1",
             "phx-value-dashboard-health-blocked-placements" => "blocked-placement",
             "phx-value-dashboard-health-degraded" => "1",
             "phx-value-dashboard-health-degraded-placements" => "degraded-placement",
             "phx-value-dashboard-health-ready" => "1",
             "phx-value-dashboard-health-schema" => "dashboard_health_snapshot.v1",
             "phx-value-dashboard-health-severity" => "error",
             "phx-value-dashboard-health-snapshot-id" => snapshot_id,
             "phx-value-dashboard-health-stale" => "0",
             "phx-value-dashboard-health-state" => "blocked",
             "phx-value-dashboard-health-states" => "ready,degraded,blocked",
             "phx-value-dashboard-health-widgets" => "3",
             "phx-value-kind" => "dashboard_health"
           }

    copy = presentation["copy_props"]

    assert copy["button_id"] == "dashboard-health-snapshot-copy"
    assert copy["button_class"] == "btn btn-ghost btn-xs btn-square"
    assert copy["icon"] == "hero-clipboard-document"
    assert copy["icon_class"] == "h-3.5 w-3.5"
    assert copy["label"] == ""
    assert copy["title"] == "Copy dashboard health snapshot"
    assert copy["aria_label"] == "Copy dashboard health snapshot"

    assert copy["data_attrs"] == %{
             "data-dashboard-health-snapshot-copy" => "",
             "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1",
             "data-dashboard-health-snapshot-id" => snapshot_id
           }

    snapshot_json = copy["clipboard_text"]

    assert Jason.decode!(snapshot_json) == dashboard_health_snapshot(snapshot_id)

    assert copy == %{
             "aria_label" => "Copy dashboard health snapshot",
             "button_class" => "btn btn-ghost btn-xs btn-square",
             "button_id" => "dashboard-health-snapshot-copy",
             "clipboard_text" => snapshot_json,
             "data_attrs" => %{
               "data-dashboard-health-snapshot-copy" => "",
               "data-dashboard-health-snapshot-id" => snapshot_id,
               "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1"
             },
             "icon" => "hero-clipboard-document",
             "icon_class" => "h-3.5 w-3.5",
             "label" => "",
             "title" => "Copy dashboard health snapshot"
           }

    assert presentation["copy_host"]["class"] == "contents"
    refute vue.ssr

    capture = presentation["capture"]

    assert capture["attrs"]["phx-click"] == "capture_dashboard_health_snapshot"
    assert capture["attrs"]["data-dashboard-health-snapshot-id"] == snapshot_id
    assert capture_snapshot_json = capture["attrs"]["phx-value-snapshot"]

    assert Jason.decode!(capture_snapshot_json) == Jason.decode!(snapshot_json)

    assert capture["id"] == "dashboard-health-snapshot-capture"
    assert capture["type"] == "button"
    assert capture["class"] == "btn btn-ghost btn-xs btn-square"
    assert capture["title"] == "Capture dashboard health snapshot"
    assert capture["aria_label"] == "Capture dashboard health snapshot"

    assert capture["icon"] == %{
             "class" => "h-3.5 w-3.5",
             "name" => "hero-bookmark-square"
           }

    assert capture["attrs"] == %{
             "data-dashboard-health-snapshot-capture" => "",
             "data-dashboard-health-snapshot-id" => snapshot_id,
             "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1",
             "phx-click" => "capture_dashboard_health_snapshot",
             "phx-value-snapshot" => snapshot_json
           }

    assert Enum.map(presentation["groups"], & &1["order"]) == [0, 1]

    assert Enum.map(
             presentation["groups"],
             & &1["overlay"]["attrs"]["data-dashboard-health-group"]
           ) ==
             ["blocked", "degraded"]

    assert blocked_group["key"] == "dashboard-health-group-blocked-0"
    assert blocked_group["overlay"]["id"] == "dashboard-health-group-blocked"
    assert blocked_group["overlay"]["class"] == "cadence-overlay"
    assert blocked_group["overlay"]["open_attr"] == ""

    assert blocked_group["overlay"]["attrs"] == %{
             "data-dashboard-health-group" => "blocked",
             "data-dashboard-health-group-count" => "1",
             "data-dashboard-health-group-placements" => "blocked-placement",
             "data-overlay-kind" => "popover",
             "data-overlay-placement" => "bottom-end"
           }

    assert blocked_group["overlay"]["trigger"] == %{
             "aria_expanded" => %{"closed" => "false", "open" => "true"},
             "attrs" => %{
               "aria-controls" => "dashboard-health-group-blocked-panel",
               "aria-haspopup" => "dialog",
               "aria-label" => "Blocked widgets",
               "data-overlay-trigger" => ""
             },
             "class" => "cadence-overlay-trigger",
             "id" => "dashboard-health-group-blocked-trigger",
             "type" => "button"
           }

    assert blocked_group["overlay"]["panel"] == %{
             "attrs" => %{
               "aria-label" => "Blocked widgets",
               "data-overlay-panel" => "",
               "data-overlay-width" => "md"
             },
             "class" => "cadence-overlay-panel cadence-popover-panel",
             "id" => "dashboard-health-group-blocked-panel"
           }

    assert blocked_group["badge"] == %{
             "attrs" => %{
               "data-dashboard-health-badge" => "blocked",
               "data-dashboard-health-badge-count" => "1",
               "data-dashboard-health-badge-placements" => "blocked-placement"
             },
             "class" => "badge badge-xs cursor-pointer gap-1 badge-error",
             "count" => "1",
             "count_class" => "font-mono",
             "icon" => %{"class" => "h-3 w-3", "name" => "hero-no-symbol"},
             "label" => "Blocked",
             "title" => "Blocked: 1"
           }

    assert blocked_group["details"] == %{
             "class" => "p-2 text-xs",
             "heading" => %{
               "class" => "font-semibold text-base-content",
               "text" => "Blocked widgets"
             },
             "items_class" => "mt-2 space-y-1"
           }

    assert blocked_item["order"] == 0

    assert blocked_item["class"] ==
             "grid grid-cols-[minmax(0,1fr)_auto] gap-2 rounded px-2 py-1 hover:bg-base-200"

    assert blocked_item["attrs"] == %{
             "data-dashboard-health-item" => "blocked-placement",
             "data-dashboard-health-item-lifecycle" => "ready",
             "data-dashboard-health-item-reason" => "source_unavailable",
             "data-dashboard-health-item-source" => "unavailable",
             "data-dashboard-health-item-state" => "blocked",
             "data-dashboard-health-item-warnings" => ""
           }

    assert blocked_item["title"] == %{
             "class" => "min-w-0 truncate",
             "text" => "Blocked widget"
           }

    assert blocked_item["reason"] == %{
             "class" => "font-mono text-base-content/60",
             "text" => "source_unavailable"
           }

    assert degraded_group["badge"]["icon"] == %{
             "class" => "h-3 w-3",
             "name" => "hero-exclamation-triangle"
           }

    assert Enum.map(degraded_group["items"], & &1["href"]) == ["#widget-degraded-placement"]

    assert degraded_group == %{
             "badge" => %{
               "attrs" => %{
                 "data-dashboard-health-badge" => "degraded",
                 "data-dashboard-health-badge-count" => "1",
                 "data-dashboard-health-badge-placements" => "degraded-placement"
               },
               "class" => "badge badge-xs cursor-pointer gap-1 badge-warning badge-outline",
               "count" => "1",
               "count_class" => "font-mono",
               "icon" => %{
                 "class" => "h-3 w-3",
                 "name" => "hero-exclamation-triangle"
               },
               "label" => "Degraded",
               "title" => "Degraded: 1"
             },
             "details" => %{
               "class" => "p-2 text-xs",
               "heading" => %{
                 "class" => "font-semibold text-base-content",
                 "text" => "Degraded widgets"
               },
               "items_class" => "mt-2 space-y-1"
             },
             "items" => [
               %{
                 "attrs" => %{
                   "data-dashboard-health-item" => "degraded-placement",
                   "data-dashboard-health-item-lifecycle" => "no_data",
                   "data-dashboard-health-item-reason" => "lifecycle_no_data",
                   "data-dashboard-health-item-source" => "no_data",
                   "data-dashboard-health-item-state" => "degraded",
                   "data-dashboard-health-item-warnings" => ""
                 },
                 "class" =>
                   "grid grid-cols-[minmax(0,1fr)_auto] gap-2 rounded px-2 py-1 hover:bg-base-200",
                 "href" => "#widget-degraded-placement",
                 "key" => "dashboard-health-item-degraded-0-degraded-placement",
                 "order" => 0,
                 "reason" => %{
                   "class" => "font-mono text-base-content/60",
                   "text" => "lifecycle_no_data"
                 },
                 "title" => %{
                   "class" => "min-w-0 truncate",
                   "text" => "No data widget"
                 }
               }
             ],
             "key" => "dashboard-health-group-degraded-1",
             "order" => 1,
             "overlay" => %{
               "attrs" => %{
                 "data-dashboard-health-group" => "degraded",
                 "data-dashboard-health-group-count" => "1",
                 "data-dashboard-health-group-placements" => "degraded-placement",
                 "data-overlay-kind" => "popover",
                 "data-overlay-placement" => "bottom-end"
               },
               "class" => "cadence-overlay",
               "id" => "dashboard-health-group-degraded",
               "open_attr" => "",
               "panel" => %{
                 "attrs" => %{
                   "aria-label" => "Degraded widgets",
                   "data-overlay-panel" => "",
                   "data-overlay-width" => "md"
                 },
                 "class" => "cadence-overlay-panel cadence-popover-panel",
                 "id" => "dashboard-health-group-degraded-panel"
               },
               "trigger" => %{
                 "aria_expanded" => %{"closed" => "false", "open" => "true"},
                 "attrs" => %{
                   "aria-controls" => "dashboard-health-group-degraded-panel",
                   "aria-haspopup" => "dialog",
                   "aria-label" => "Degraded widgets",
                   "data-overlay-trigger" => ""
                 },
                 "class" => "cadence-overlay-trigger",
                 "id" => "dashboard-health-group-degraded-trigger",
                 "type" => "button"
               }
             }
           }
  end

  test "dashboard health strip renders no island unless visibility is exactly true" do
    for visible? <- [false, nil, "true", 1] do
      html =
        render_component(&DashboardHealthComponents.dashboard_health_strip/1,
          health: %{dashboard_health("hidden") | visible?: visible?}
        )

      assert [] =
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#dashboard-health-rollup-component")
               |> LazyHTML.attribute("id")
    end
  end

  test "dashboard health DTO preserves nil false and number data attribute semantics" do
    health = dashboard_health("attribute-semantics")
    [blocked_group | remaining_groups] = health.groups
    [blocked_item] = blocked_group.items

    health = %{
      health
      | state_text: "false",
        severity_text: 7,
        states: false,
        blocked_placements: true,
        stale_placements: nil,
        groups: [
          %{
            blocked_group
            | placement_ids: false,
              items: [
                %{blocked_item | source_state_text: nil, warning_codes_text: false}
              ]
          }
          | remaining_groups
        ]
    }

    html =
      render_component(&DashboardHealthComponents.dashboard_health_strip/1, health: health)

    vue = LiveVue.Test.get_vue(html, id: "dashboard-health-rollup-component")
    presentation = vue.props["presentation"]
    root_attrs = presentation["root"]["attrs"]

    refute Map.has_key?(root_attrs, "data-dashboard-health-states")
    assert root_attrs["data-dashboard-health-state"] == "false"
    assert root_attrs["data-dashboard-health-severity"] == "7"
    assert root_attrs["data-dashboard-health-blocked-placements"] == ""
    refute Map.has_key?(root_attrs, "data-dashboard-health-stale-placements")

    [group | _remaining_groups] = presentation["groups"]
    [item] = group["items"]

    refute Map.has_key?(
             group["overlay"]["attrs"],
             "data-dashboard-health-group-placements"
           )

    assert group["overlay"]["attrs"]["data-dashboard-health-group-count"] == "1"
    refute Map.has_key?(item["attrs"], "data-dashboard-health-item-warnings")
    refute Map.has_key?(item["attrs"], "data-dashboard-health-item-source")

    refute Map.has_key?(
             presentation["evidence"]["attrs"],
             "phx-value-dashboard-health-states"
           )

    assert presentation["evidence"]["attrs"]["phx-value-dashboard-health-state"] == "false"
    assert presentation["evidence"]["attrs"]["phx-value-dashboard-health-severity"] == "7"

    assert presentation["evidence"]["attrs"]["phx-value-dashboard-health-blocked-placements"] ==
             ""

    refute Map.has_key?(
             presentation["evidence"]["attrs"],
             "phx-value-dashboard-health-stale-placements"
           )

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
  end

  defp dashboard_health(snapshot_id) do
    %{
      visible?: true,
      snapshot_schema: "dashboard_health_snapshot.v1",
      snapshot_id: snapshot_id,
      snapshot: dashboard_health_snapshot(snapshot_id),
      state: :blocked,
      state_text: "blocked",
      label: "Blocked",
      severity: :error,
      severity_text: "error",
      widget_count: 3,
      ready_count: 1,
      degraded_count: 1,
      stale_count: 0,
      blocked_count: 1,
      affected_count: 2,
      states: "ready,degraded,blocked",
      affected_placements: "blocked-placement,degraded-placement",
      blocked_placements: "blocked-placement",
      stale_placements: "",
      degraded_placements: "degraded-placement",
      groups: [
        %{
          key: "blocked",
          state: :blocked,
          label: "Blocked",
          count: 1,
          placement_ids: "blocked-placement",
          items: [
            %{
              placement_id: "blocked-placement",
              title: "Blocked widget",
              state_text: "blocked",
              lifecycle_state_text: "ready",
              source_state_text: "unavailable",
              warning_codes_text: "",
              reason: "source_unavailable"
            }
          ]
        },
        %{
          key: "degraded",
          state: :degraded,
          label: "Degraded",
          count: 1,
          placement_ids: "degraded-placement",
          items: [
            %{
              placement_id: "degraded-placement",
              title: "No data widget",
              state_text: "degraded",
              lifecycle_state_text: "no_data",
              source_state_text: "no_data",
              warning_codes_text: "",
              reason: "lifecycle_no_data"
            }
          ]
        }
      ]
    }
  end

  defp dashboard_health_snapshot(snapshot_id) do
    %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => snapshot_id,
      "dashboard_id" => "dashboard-1",
      "state" => "blocked",
      "counts" => %{
        "widgets" => 3,
        "ready" => 1,
        "degraded" => 1,
        "stale" => 0,
        "blocked" => 1,
        "affected" => 2
      },
      "placement_ids" => %{
        "affected" => ["blocked-placement", "degraded-placement"],
        "blocked" => ["blocked-placement"],
        "stale" => [],
        "degraded" => ["degraded-placement"]
      }
    }
  end
end
