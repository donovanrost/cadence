defmodule Cadence.Reads.ApplicationSurfaces.MissionCatalogTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    Registry,
    SurfaceQueryRequest
  }

  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.MissionCatalog, as: MissionCatalogProvider

  @organization_id "mission-catalog-provider-org"
  @mission_id "mission-catalog-provider-mission"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "mission-catalog-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope}
  end

  test "loads the organization mission list through the generic dispatcher", %{scope: scope} do
    {:ok, definition} = Registry.fetch_available("mission_catalog")
    {:ok, surface} = Registry.fetch_surface(definition, :organization, "mission_list")

    assert {:ok, %{"navigation" => navigation, "data" => data}} =
             ApplicationSurfaces.load(
               scope,
               HostContext.organization(@organization_id),
               "mission_catalog",
               1,
               surface
             )

    assert navigation["fallback_href"] == "/missions"
    assert data["presentation"]["header"]["title"]["text"] == "Missions"
    assert [%{"slug" => @mission_id}] = data["presentation"]["card"]["rows"]
  end

  test "catalog index supplies the named breadcrumb contract without an installation", %{
    scope: scope
  } do
    {:ok, definition} = Registry.fetch_available("mission_catalog")
    {:ok, surface} = Registry.fetch_surface(definition, :mission, "catalog_index")

    assert {:ok, %{"data" => %{"presentation" => presentation}}} =
             ApplicationSurfaces.load(
               scope,
               HostContext.mission(@mission_id),
               "mission_catalog",
               1,
               surface
             )

    breadcrumbs = presentation["header"]["breadcrumbs"]
    assert breadcrumbs["mission"]["attrs"]["href"] == "/missions/#{@mission_id}"
    assert is_map(breadcrumbs["separator"]["attrs"])
    assert breadcrumbs["current"]["text"] == "Catalog"
  end

  test "rejects a cross-organization organization surface", %{scope: scope} do
    {:ok, definition} = Registry.fetch_available("mission_catalog")
    {:ok, surface} = Registry.fetch_surface(definition, :organization, "mission_list")

    assert {:error, :scope_mismatch} =
             ApplicationSurfaces.load(
               %{scope | organization_id: "other-organization"},
               HostContext.organization(@organization_id),
               "mission_catalog",
               1,
               surface
             )
  end

  test "derives installation policy from registered platform definitions", %{scope: scope} do
    assert ApplicationSurfaces.organization_installation_exempt?("mission_catalog")
    assert ApplicationSurfaces.installation_exempt?("mission_catalog", :organization)
    assert ApplicationSurfaces.installation_exempt?("mission_catalog", :mission)
    assert ApplicationSurfaces.installation_exempt?("spacecraft", :spacecraft)
    assert ApplicationSurfaces.installation_exempt?("comms", :mission)
    assert ApplicationSurfaces.installation_exempt?("ops_console", :mission)
    refute ApplicationSurfaces.installation_exempt?("telemetry_decom", :spacecraft)

    refute ApplicationSurfaces.installation_exempt?("mission_catalog", :user)
    refute ApplicationSurfaces.installation_exempt?("mission_catalog", :admin)
    refute ApplicationSurfaces.installation_exempt?("organization_admin", :mission)
    refute ApplicationSurfaces.installation_exempt?("organization_admin", :spacecraft)

    for placement <- [:organization, :user, :admin, :mission, :spacecraft] do
      refute ApplicationSurfaces.installation_exempt?("third_party", placement)
    end

    assert {:error, :application_installation_scope_required} =
             ApplicationInstallations.fetch_installed(
               scope,
               HostContext.organization(@organization_id),
               "third_party"
             )
  end

  test "requires exactly one bounded subject parameter for every detail surface", %{scope: scope} do
    host_context = HostContext.mission(@mission_id)

    for {surface_id, key} <- [
          {"catalog_database_show", "catalog_database_id"},
          {"catalog_revision_show", "catalog_revision_id"},
          {"catalog_artifact_show", "artifact_id"},
          {"catalog_import_run_show", "import_run_id"}
        ] do
      request = %SurfaceQueryRequest{
        application_key: "mission_catalog",
        application_version: 1,
        surface_id: surface_id,
        surface_version: 1,
        query_id: "cadence.mission_catalog.#{surface_id}",
        query_version: 1,
        params: %{}
      }

      assert {:error, :invalid_application_request} =
               MissionCatalogProvider.load(scope, host_context, request)

      invalid_request = %SurfaceQueryRequest{
        request
        | params: %{key => "subject", "extra" => "rejected"}
      }

      assert {:error, :invalid_application_request} =
               MissionCatalogProvider.load(scope, host_context, invalid_request)
    end
  end
end
