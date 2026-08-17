defmodule CadenceWeb.OpsDashboardShowLive.SelectionHydrationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SelectionHydration
  alias Phoenix.LiveView.Socket

  test "hydrate_from_query uses the selection panel hydrator by default" do
    socket =
      socket(%{
        dashboard_evidence_query: %{
          "selected_evidence_kind" => "frame",
          "selected_observable" => "HK.counter"
        }
      })

    socket = SelectionHydration.hydrate_from_query(socket)

    assert {:evidence, inspector} = socket.assigns.panel
    assert inspector.status == :missing
    assert inspector.kind == "frame"
    assert inspector.subject == "HK.counter"
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            panel: nil,
            dashboard_selection_query: nil,
            dashboard_evidence_query: nil,
            dashboard_engine_result: nil
          },
          assigns
        )
    }
  end
end
