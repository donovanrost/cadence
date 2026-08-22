defmodule CadenceWeb.OpsDashboardShowLive.RenderShellAssignsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.RenderShellAssigns
  alias Phoenix.LiveView.Socket

  test "projects shell render context from sockets and assigns maps" do
    expected = %{
      dashboard_id: "dashboard-1",
      render_items: [render_item("placement-1")],
      render_items_empty?: false,
      edit_mode?: true,
      edit_mode_text: "true",
      panel: :add_widget,
      panel_open?: true,
      show_context?: true
    }

    assert RenderShellAssigns.shell_context(%Socket{assigns: assigns()}) == expected
    assert RenderShellAssigns.shell_context(assigns()) == expected
  end

  test "projects empty shell defaults" do
    assert RenderShellAssigns.shell_context(
             assigns(%{dashboard_render_items: [], edit_mode?: false, panel: nil})
           ) == %{
             dashboard_id: "dashboard-1",
             render_items: [],
             render_items_empty?: true,
             edit_mode?: false,
             edit_mode_text: "false",
             panel: nil,
             panel_open?: false,
             show_context?: false
           }
  end

  test "projects dashboard id from string-key document maps" do
    assert RenderShellAssigns.shell_context(%{
             dashboard_document: %{"dashboard_id" => "dashboard-from-map"}
           }).dashboard_id == "dashboard-from-map"
  end

  defp assigns(overrides \\ %{}) do
    Map.merge(
      %{
        dashboard_document: %Document{dashboard_id: "dashboard-1"},
        dashboard_render_items: [render_item("placement-1")],
        edit_mode?: true,
        panel: :add_widget
      },
      overrides
    )
  end

  defp render_item(placement_id) do
    %{
      placement_id: placement_id,
      widget: %RenderWidget{
        widget_id: "widget-1",
        type: :value_tile,
        title: "Temperature",
        binding: %{source: :telemetry, mode: :context}
      }
    }
  end
end
