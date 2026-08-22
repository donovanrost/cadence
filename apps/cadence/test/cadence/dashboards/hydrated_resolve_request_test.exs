defmodule Cadence.Dashboards.HydratedResolveRequestTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    HydratedResolveRequest,
    Placement
  }

  test "rejects unresolved library placements at the planning boundary" do
    request = %DashboardResolveRequest{
      document: %Document{
        dashboard_id: "dashboard-unresolved-library",
        organization_id: "org-hydration-boundary",
        mission_id: "mission-hydration-boundary",
        name: "Unresolved library",
        placements: [
          %Placement{
            placement_id: "placement-unresolved-library",
            content_kind: :library,
            library_widget_id: "library-widget-missing",
            library_version: 1
          }
        ]
      }
    }

    assert {:error, {:unresolved_library_placements, ["placement-unresolved-library"]}} =
             HydratedResolveRequest.new(request)
  end
end
