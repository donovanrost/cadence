defmodule CadenceWeb.OpsDashboardShowLive.RenameFlowTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.RenameFlow
  alias Phoenix.LiveView.Socket

  test "renamed_document normalizes name and description" do
    document = document(%{name: "Power"})

    renamed =
      RenameFlow.renamed_document(document, %{
        "name" => "  Power North  ",
        "description" => "  EPS  "
      })

    assert renamed.name == "Power North"
    assert renamed.description == "EPS"
  end

  test "renamed_document keeps the current name when submitted name is blank" do
    renamed =
      document(%{name: "Power", description: "old"})
      |> RenameFlow.renamed_document(%{"name" => " ", "description" => ""})

    assert renamed.name == "Power"
    assert renamed.description == nil
  end

  test "rename persists the renamed document, refreshes summaries, and closes the panel" do
    socket = socket(%{panel: :rename, dashboard_document: document(%{name: "Power"})})

    assert {:ok, socket} =
             RenameFlow.rename(
               socket,
               %{"name" => "Power North", "description" => "EPS"},
               persist_document: fn socket, %Document{} = document, opts ->
                 assert document.name == "Power North"
                 assert document.description == "EPS"
                 assert opts == [change_summary: "Renamed dashboard"]
                 {:ok, socket}
               end,
               list_dashboard_summaries: fn %{organization_id: "org-1"},
                                            %{mission_id: "mission-1"} ->
                 [%{dashboard_id: "dashboard-1", name: "Power North"}]
               end
             )

    assert socket.assigns.ops_dashboards == [%{dashboard_id: "dashboard-1", name: "Power North"}]
    assert socket.assigns.panel == nil
  end

  test "rename returns persistence errors without refreshing summaries or closing the panel" do
    socket = socket(%{panel: :rename})

    assert {:error, socket} =
             RenameFlow.rename(
               socket,
               %{"name" => "Power North"},
               persist_document: fn socket, _document, _opts -> {:error, socket} end,
               list_dashboard_summaries: fn _scope, _mission -> flunk("should not refresh") end
             )

    assert socket.assigns.panel == :rename
    refute Map.has_key?(socket.assigns, :ops_dashboards)
  end

  defp socket(overrides) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            dashboard_document: document(%{}),
            panel: nil
          },
          overrides
        )
    }
  end

  defp document(attrs) do
    attrs =
      Map.merge(
        %{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          description: nil,
          placements: [],
          metadata: %{version: 1}
        },
        attrs
      )

    struct!(Document, attrs)
  end
end
