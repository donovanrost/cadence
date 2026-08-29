defmodule CadenceWeb.OpsDashboardShowLive.DashboardCanvasPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DashboardCanvasPresentation

  test "build preserves grouped canvas topology raw attrs children and comparison presentation" do
    render_model = render_model(section_group(), true)

    presentation =
      DashboardCanvasPresentation.build(
        render_model,
        %{
          editor_route?: true,
          dashboard_author?: true,
          empty_edit_path: "/missions/mission-1/ops/dashboards/dashboard-1/edit"
        },
        widget_presentation: & &1,
        comparison_presentation: fn true, rollup, preset, review, saved ->
          %{
            inspector: %{root: %{attrs: %{"id" => "dashboard-comparison-inspector"}}},
            source: %{rollup: rollup, preset: preset, review: review, saved: saved}
          }
        end
      )

    json = Jason.decode!(Jason.encode!(presentation))
    assert json == Jason.decode!(Jason.encode!(json))

    assert Map.keys(json) |> Enum.sort() ==
             ~w(comparison_inspector content empty_state groups root)

    assert json["root"]["attrs"] == %{"class" => "flex flex-1 min-h-0"}

    assert json["content"]["attrs"] == %{
             "class" => "flex-1 min-w-0 min-h-0 overflow-y-auto",
             "data-empty" => "",
             "data-number" => "7"
           }

    assert [group] = json["groups"]

    assert group["root"]["attrs"] == %{
             "id" => "dashboard-widget-group-power",
             "class" => "border-b border-base-300/45 last:border-b-0",
             "data-dashboard-widget-group" => "power"
           }

    assert group["section"]["root"]["attrs"] == %{
             "id" => "dashboard-section-group-power",
             "open" => "",
             "class" => "group/dashboard-section",
             "data-dashboard-section" => "power"
           }

    assert group["section"]["summary"]["attrs"] == %{
             "class" =>
               "flex cursor-pointer list-none items-center gap-2 marker:hidden sticky top-0 z-10 border-b border-base-300/50 bg-base-200/90 px-3 py-2 backdrop-blur"
           }

    assert group["section"]["summary"]["icon"]["attrs"] == %{
             "class" =>
               "hero-chevron-right h-3.5 w-3.5 text-base-content/45 transition-transform group-data-[state=open]/dashboard-section:rotate-90"
           }

    assert group["section"]["summary"]["copy"]["title"]["text"] == "Power"
    assert group["section"]["summary"]["copy"]["description"]["text"] == "Bus health"
    assert group["section"]["summary"]["count"]["text"] == "1 widget"
    assert group["header"] == nil

    assert group["grid"]["root"]["attrs"] == %{
             "id" => "dashboard-grid-dashboard-1-power",
             "class" => "grid-stack gs-12",
             "data-dashboard-grid" => "true",
             "data-edit-mode" => "true"
           }

    assert [widget] = group["grid"]["widgets"]
    assert widget["key"] == "placement-1"

    assert widget["shell"]["attrs"] == %{
             "class" => "grid-stack-item",
             "gs-id" => "placement-1",
             "gs-x" => "2",
             "data-true" => ""
           }

    assert widget["host"]["attrs"] == %{
             "id" => "dashboard-widget-placement-1-component",
             "class" => "contents"
           }

    assert widget["presentation"] == %{
             "component_id" => "dashboard-widget-placement-1-component"
           }

    assert group["grid"]["controller"] == %{
             "host" => %{
               "attrs" => %{
                 "id" => "dashboard-grid-dashboard-1-power-controller",
                 "class" => "hidden"
               }
             },
             "props" => %{
               "target_id" => "dashboard-grid-dashboard-1-power",
               "edit_mode" => true,
               "item_ids" => ["placement-1"]
             }
           }

    assert json["empty_state"]["actions"]["action"] == %{
             "kind" => "button",
             "attrs" => %{
               "id" => "dashboard-editor-empty-add-widget",
               "type" => "button",
               "class" => "btn btn-primary btn-sm",
               "phx-click" => "open_add_widget"
             },
             "icon" => %{
               "attrs" => %{"class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"}
             },
             "text" => "Add widget"
           }

    assert json["comparison_inspector"]["host"]["attrs"] == %{
             "id" => "dashboard-comparison-inspector-component",
             "class" => "contents"
           }

    assert json["comparison_inspector"]["presentation"]["inspector"]["root"]["attrs"]["id"] ==
             "dashboard-comparison-inspector"
  end

  test "build preserves unsectioned viewer empty action and absent comparison branches" do
    render_model = render_model(unsectioned_group(), false)

    presentation =
      DashboardCanvasPresentation.build(
        render_model,
        %{
          editor_route?: false,
          dashboard_author?: true,
          empty_edit_path: "/missions/mission-2/ops/dashboards/dashboard-2/edit"
        },
        widget_presentation: & &1,
        comparison_presentation: fn false, _rollup, _preset, _review, _saved -> nil end
      )
      |> Jason.encode!()
      |> Jason.decode!()

    assert presentation["comparison_inspector"] == nil
    assert [group] = presentation["groups"]
    assert group["section"] == nil
    assert group["header"]["title"]["text"] == "Unsectioned canvas"
    assert group["header"]["count"] == nil
    assert group["root"]["attrs"]["class"] == "pt-1"

    assert presentation["empty_state"]["actions"]["action"] == %{
             "kind" => "link",
             "attrs" => %{
               "id" => "dashboard-viewer-empty-edit",
               "href" => "/missions/mission-2/ops/dashboards/dashboard-2/edit",
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push",
               "class" => "btn btn-primary btn-sm"
             },
             "icon" => %{
               "attrs" => %{"class" => "hero-pencil-square h-4 w-4"}
             },
             "text" => "Open Dashboard Editor"
           }
  end

  test "section root preserves exact raw server-open seed semantics" do
    Enum.each([{true, ""}, {false, nil}], fn {open?, expected_open} ->
      presentation =
        DashboardCanvasPresentation.build(
          render_model(Map.put(section_group(), :open?, open?), false),
          %{editor_route?: true},
          widget_presentation: & &1,
          comparison_presentation: fn false, _rollup, _preset, _review, _saved -> nil end
        )

      assert [group] = presentation.groups
      attrs = group.section.root.attrs

      assert Map.has_key?(attrs, "open") == open?
      assert Map.get(attrs, "open") == expected_open

      assert Map.drop(attrs, ["open"]) == %{
               "id" => "dashboard-section-group-power",
               "class" => "group/dashboard-section",
               "data-dashboard-section" => "power"
             }
    end)
  end

  defp render_model(group, comparison_open?) do
    %{
      content_attrs: %{
        "data-nil" => nil,
        "data-false" => false,
        "data-empty" => true,
        "data-number" => 7,
        class: "flex-1 min-w-0 min-h-0 overflow-y-auto"
      },
      widget_groups: [group],
      empty_state: %{
        visible?: true,
        wrapper_class: "p-8",
        card_class: "empty-card",
        icon_class: "hero-squares-plus empty-icon",
        title: "No widgets",
        message: "Add point-bound widgets, then arrange them in Edit Layout.",
        action_event: "open_add_widget",
        action_icon: "hero-plus",
        action_label: "Add widget"
      },
      comparison_inspector_open?: comparison_open?,
      comparison_rollup: %{visible?: comparison_open?},
      comparison_preset: %{id: "preset-1"},
      open_review_summary: %{open_count: 1},
      comparison_presets: [%{id: "saved-1"}]
    }
  end

  defp section_group do
    %{
      id: "power",
      section: %{title: "Power", description: "Bus health"},
      widget_items: [widget_item()],
      grid_props: %{
        "data-dashboard-grid" => "true",
        "data-edit-mode" => "true",
        id: "dashboard-grid-dashboard-1-power",
        class: "grid-stack gs-12"
      },
      grid_controller_props: %{
        id: "dashboard-grid-dashboard-1-power-controller",
        target_id: "dashboard-grid-dashboard-1-power",
        edit_mode: true,
        item_ids: ["placement-1"]
      },
      open?: true,
      show_header?: true
    }
  end

  defp unsectioned_group do
    Map.merge(section_group(), %{
      id: "unsectioned",
      section: nil,
      widget_items: [],
      show_header?: true,
      grid_props: %{
        "data-dashboard-grid" => "true",
        "data-edit-mode" => "false",
        id: "dashboard-grid-dashboard-2-unsectioned",
        class: "grid-stack gs-12"
      },
      grid_controller_props: %{
        id: "dashboard-grid-dashboard-2-unsectioned-controller",
        target_id: "dashboard-grid-dashboard-2-unsectioned",
        edit_mode: false,
        item_ids: []
      }
    })
  end

  defp widget_item do
    %{
      shell_attrs: %{
        :"gs-id" => "placement-1",
        "gs-x" => 2,
        "data-nil" => nil,
        "data-false" => false,
        "data-true" => true,
        class: "grid-stack-item"
      },
      content_class: "grid-stack-item-content cadence-dashboard-panel",
      component_props: %{component_id: "dashboard-widget-placement-1-component"}
    }
  end
end
