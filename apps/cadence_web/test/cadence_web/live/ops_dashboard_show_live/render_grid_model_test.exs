defmodule CadenceWeb.OpsDashboardShowLive.RenderGridModelTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RenderGridModel

  test "content_attrs exposes the scroll container contract" do
    assert RenderGridModel.content_attrs() == %{class: "flex-1 min-w-0 min-h-0 overflow-y-auto"}
  end

  test "grid_props exposes gridstack attrs from dashboard and edit state" do
    props =
      %{dashboard_document: %{dashboard_id: "dashboard-1"}, edit_mode?: true}
      |> RenderGridModel.grid_props()

    assert props == %{
             id: "dashboard-grid-dashboard-1",
             "phx-hook": "DashboardGrid",
             "data-edit-mode": "true",
             class: "grid-stack gs-12"
           }
  end

  test "empty_state reflects whether the render grid has widgets" do
    empty_state =
      %{dashboard_render_items: []}
      |> RenderGridModel.empty_state()

    assert empty_state.visible? == true
    assert empty_state.wrapper_class == "p-8"
    assert empty_state.title == "No widgets"

    assert empty_state.message ==
             "Add point-bound widgets, then arrange them in Edit Layout."

    assert empty_state.action_event == "open_add_widget"
    assert empty_state.action_icon == "hero-plus"
    assert empty_state.action_label == "Add widget"

    populated_state =
      %{dashboard_render_items: [%{placement_id: "placement-1"}]}
      |> RenderGridModel.empty_state()

    assert populated_state.visible? == false
  end

  test "widget_groups preserves section order and isolates section grids" do
    sections = [
      %{section_id: "power", title: "Power", collapsed_by_default?: false},
      %{section_id: "comms", title: "Comms", collapsed_by_default?: true}
    ]

    items = [
      %{item: %{placement: %{section_id: "comms"}}, placement_id: "comms-1"},
      %{item: %{placement: %{section_id: nil}}, placement_id: "general-1"},
      %{item: %{placement: %{section_id: "power"}}, placement_id: "power-1"}
    ]

    groups =
      RenderGridModel.widget_groups(
        %{
          dashboard_document: %{dashboard_id: "dashboard-1", sections: sections},
          edit_mode?: false
        },
        items
      )

    assert [unsectioned, power, comms] = groups
    assert Enum.map(unsectioned.widget_items, & &1.placement_id) == ["general-1"]
    assert Enum.map(power.widget_items, & &1.placement_id) == ["power-1"]
    assert Enum.map(comms.widget_items, & &1.placement_id) == ["comms-1"]
    assert power.open?
    refute comms.open?
    assert power.grid_props.id == "dashboard-grid-dashboard-1-power"
  end
end
