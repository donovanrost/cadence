defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditingTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3, to_form: 2]

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
  end

  test "saves a widget through injected persistence and resets editor state" do
    socket =
      socket()
      |> WidgetEditing.open_add_widget()
      |> WidgetEditing.pick_point("HK.counter")

    socket =
      WidgetEditing.save_widget(
        socket,
        %{"type" => "value_tile", "title" => "Counter", "mode" => "context"},
        test_opts()
      )

    assert socket.assigns.panel == nil
    assert socket.assigns.widget_error == nil
    assert socket.assigns.selected_point_id == nil
    assert socket.assigns.selected_point_ids == []
    assert socket.assigns.refreshed? == true
    assert socket.assigns.persist_opts == [change_summary: "Added widget"]

    assert [%{widget_def: %{title: "Counter", binding: %{observables: ["HK.counter"]}}}] =
             socket.assigns.dashboard_document.placements
  end

  test "reports widget validation errors without persisting" do
    socket = WidgetEditing.open_add_widget(socket())

    socket =
      WidgetEditing.save_widget(
        socket,
        %{"type" => "value_tile", "title" => "Counter", "mode" => "context"},
        test_opts()
      )

    assert socket.assigns.widget_error == "a telemetry point is required"
    refute Map.has_key?(socket.assigns, :persist_opts)
  end

  test "reports operational observable authoring scope errors without persisting" do
    socket =
      socket(%{
        dashboard_scope_context: %{
          primary: %{kind: "transport", mode: "one", ids: ["transport-1"]}
        }
      })
      |> WidgetEditing.open_add_widget()
      |> WidgetEditing.pick_point("commanding.queue_depth")

    socket =
      WidgetEditing.save_widget(
        socket,
        %{
          "type" => "value_tile",
          "title" => "Command Queue",
          "binding_source" => "operational_observables",
          "mode" => "context"
        },
        test_opts()
      )

    assert socket.assigns.widget_error =~ "selected context does not support"
    assert socket.assigns.widget_error =~ "commanding.queue_depth"
    refute Map.has_key?(socket.assigns, :persist_opts)
  end

  defp test_opts do
    [
      dashboard_list_path: fn _socket -> "/dashboards" end,
      assign_runtime_context: fn socket, _document -> socket end,
      persist_document: fn socket, %Document{} = document, persist_opts ->
        {:ok,
         socket
         |> assign(:dashboard_document, document)
         |> assign(:dashboard_render_items, RenderItem.from_document(document))
         |> assign(:persist_opts, persist_opts)}
      end,
      refresh_widget_data: &assign(&1, :refreshed?, true)
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
