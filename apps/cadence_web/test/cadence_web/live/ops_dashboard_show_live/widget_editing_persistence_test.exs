defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditingPersistenceTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3, to_form: 2]

  alias Cadence.Dashboards.{Document, RenderItem}
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditing
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation
  alias Phoenix.LiveView.Socket

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
