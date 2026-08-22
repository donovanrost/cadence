defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditingSelectionTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditing
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation
  alias Phoenix.LiveView.Socket

  test "single and multi select point picking follows the current widget form" do
    socket =
      socket()
      |> WidgetEditing.open_add_widget()
      |> WidgetEditing.pick_point("HK.counter")
      |> WidgetEditing.pick_point("HK.voltage")

    assert socket.assigns.selected_point_id == "HK.voltage"
    assert socket.assigns.selected_point_ids == ["HK.voltage"]

    socket =
      socket()
      |> WidgetEditing.open_add_widget()
      |> WidgetEditing.validate_widget(%{"type" => "status_matrix", "title" => "Matrix"})
      |> WidgetEditing.pick_point("HK.counter")
      |> WidgetEditing.pick_point("HK.voltage")

    assert socket.assigns.selected_point_id == "HK.counter"
    assert socket.assigns.selected_point_ids == ["HK.counter", "HK.voltage"]

    socket = WidgetEditing.pick_point(socket, "HK.counter")

    assert socket.assigns.selected_point_id == "HK.voltage"
    assert socket.assigns.selected_point_ids == ["HK.voltage"]

    socket =
      socket()
      |> WidgetEditing.open_add_widget()
      |> WidgetEditing.validate_widget(%{
        "type" => "state_timeline",
        "title" => "Operations State",
        "binding_source" => "operational_observables"
      })
      |> WidgetEditing.pick_point("contacts.phase")
      |> WidgetEditing.pick_point("comms.transport.connection_state")

    assert socket.assigns.selected_point_id == "contacts.phase"

    assert socket.assigns.selected_point_ids == [
             "contacts.phase",
             "comms.transport.connection_state"
           ]
  end

  defp socket(assigns \\ %{}) do
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
