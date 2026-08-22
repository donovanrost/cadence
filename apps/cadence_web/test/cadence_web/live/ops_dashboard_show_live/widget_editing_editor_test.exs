defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditingEditorTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Dashboards.{Document, PlacementEditor, RenderItem}
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditing
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Socket

  test "opens add widget with cleared selection and default form" do
    socket =
      socket(%{
        panel: :versions,
        widget_error: "bad widget",
        selected_point_id: "HK.counter",
        selected_point_ids: ["HK.counter"]
      })

    socket = WidgetEditing.open_add_widget(socket)

    assert socket.assigns.panel == :add_widget
    assert socket.assigns.widget_error == nil
    assert socket.assigns.selected_point_id == nil
    assert socket.assigns.selected_point_ids == []
    assert Form.input_value(socket.assigns.widget_form, :type) == "value_tile"
  end

  test "prefills edit widget state from an existing placement" do
    {:ok, placement} =
      PlacementEditor.build_placement(
        %{"type" => "value_tile", "title" => "Counter", "mode" => "context"},
        "HK.counter",
        :add_widget
      )

    document = Document.put_placement(document(), placement)

    socket =
      socket(%{
        dashboard_document: document,
        dashboard_render_items: RenderItem.from_document(document)
      })

    socket = WidgetEditing.open_widget_config(socket, placement.placement_id)

    assert socket.assigns.panel == {:edit_placement, placement.placement_id}
    assert socket.assigns.selected_point_id == "HK.counter"
    assert socket.assigns.selected_point_ids == ["HK.counter"]
    assert Form.input_value(socket.assigns.widget_form, :title) == "Counter"
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            panel: nil,
            widget_error: nil,
            selected_point_id: nil,
            selected_point_ids: [],
            widget_form: to_form(WidgetFormPresentation.widget_form_defaults(), as: :widget),
            dashboard_document: document(),
            dashboard_render_items: []
          },
          assigns
        )
    }
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard",
      metadata: %{version: 1}
    }
  end
end
