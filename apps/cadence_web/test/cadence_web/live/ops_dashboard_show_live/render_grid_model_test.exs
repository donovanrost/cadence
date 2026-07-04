defmodule CadenceWeb.OpsDashboardShowLive.RenderGridModelTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RenderGridModel

  test "content_attrs exposes the scroll container contract" do
    assert RenderGridModel.content_attrs() == %{class: "flex-1 min-h-0 overflow-y-auto"}
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
end
