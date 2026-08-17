defmodule Cadence.Dashboards.ResolveRequestHydratorTest do
  use Cadence.DataCase, async: false

  import Cadence.Dashboards.EngineFixtures

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    HydratedResolveRequest,
    Management,
    Placement,
    ResolveRequestHydrator,
    WidgetDef
  }

  test "hydrates a pinned library widget and applies placement overrides" do
    organization_id = "org-resolve-hydrator"
    mission_id = "mission-resolve-hydrator"
    persist_mission_scope(organization_id, mission_id)

    widget_def = fixture_widget_def()

    assert {:ok, item} =
             Management.create_library_item(
               organization_id,
               mission_id,
               %{
                 name: "Reusable battery voltage",
                 widget_definition: WidgetDef.to_map(widget_def)
               }
             )

    request =
      resolve_request(
        organization_id,
        mission_id,
        "dashboard-hydrated-library",
        %Placement{
          placement_id: "placement-hydrated-library",
          content_kind: :library,
          library_widget_id: item.dashboard_library_item_id,
          library_version: 1,
          overrides: %{title: "Overridden battery voltage"}
        }
      )

    assert %HydratedResolveRequest{} =
             hydrated_request =
             ResolveRequestHydrator.hydrate(request)

    hydrated_request = HydratedResolveRequest.unwrap(hydrated_request)
    assert [placement] = hydrated_request.document.placements
    assert placement.content_kind == :library
    assert placement.library_widget_id == item.dashboard_library_item_id
    assert %WidgetDef{title: "Overridden battery voltage"} = placement.widget_def
  end

  test "materializes an unavailable widget when a pinned library version is missing" do
    organization_id = "org-resolve-hydrator-missing"
    mission_id = "mission-resolve-hydrator-missing"
    persist_mission_scope(organization_id, mission_id)

    request =
      resolve_request(
        organization_id,
        mission_id,
        "dashboard-missing-library",
        %Placement{
          placement_id: "placement-missing-library",
          content_kind: :library,
          library_widget_id: "library-widget-missing",
          library_version: 404
        }
      )

    assert %HydratedResolveRequest{} =
             hydrated_request =
             ResolveRequestHydrator.hydrate(request)

    hydrated_request = HydratedResolveRequest.unwrap(hydrated_request)
    assert [placement] = hydrated_request.document.placements

    assert %WidgetDef{
             widget_type_id: "unavailable_library_reference",
             title: "Unavailable library item"
           } = placement.widget_def
  end

  defp fixture_widget_def do
    document = load_fixture!("value_tile_latest.v1.json")
    [placement | _rest] = document.placements
    placement.widget_def
  end

  defp resolve_request(organization_id, mission_id, dashboard_id, placement) do
    %DashboardResolveRequest{
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id,
      document: %Document{
        dashboard_id: dashboard_id,
        organization_id: organization_id,
        mission_id: mission_id,
        name: "Hydration boundary",
        placements: [placement]
      }
    }
  end
end
