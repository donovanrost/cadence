defmodule CadenceWeb.ApplicationHostCatalogTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Auth.Scope
  alias CadenceWeb.{ApplicationHostCatalog, TestFixtures}

  @comms_surfaces ~w(overview validation transports transport routing routing_detail ground_stations ground_station)

  test "admits the registered telemetry packet_bindings surface after release lookup", %{
    conn: _conn
  } do
    {scope, route_context} = installed_telemetry_context()

    assert {:ok, definition} =
             Cadence.ExtensionCatalog.fetch_available_application("telemetry_decom")

    assert {:ok, surface} =
             ApplicationRegistry.fetch_surface(
               definition,
               :spacecraft,
               "packet_bindings"
             )

    assert surface.surface_id == "packet_bindings"

    assert {:ok, admission} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings"
             )

    assert admission.release.release_id == "telemetry-decom-v1"
    assert admission.release.remote_name == "cadence_telemetry_decom"

    assert admission.release.manifest_path ==
             "/assets/application-host/telemetry-decom/mf-manifest.json"
  end

  test "admits all mission Comms v1 surfaces and keeps fallback paths server-owned" do
    {scope, %{mission: mission} = route_context} = installed_comms_context()

    for surface_id <- @comms_surfaces do
      assert {:ok, admission} =
               ApplicationHostCatalog.admit_application(
                 scope,
                 route_context,
                 "comms",
                 surface_id
               )

      assert admission.definition.application_key == "comms"
      assert admission.definition.version == 1
      assert admission.surface.data_contract.version == 1
      assert admission.release.release_id == "comms-v1"
      assert admission.release.remote_name == "cadence_comms"
      assert admission.release.manifest_path == "/assets/application-host/comms/mf-manifest.json"
      assert admission.release.exposed_module == "./Application"
    end

    assert ApplicationHostCatalog.fallback_href(route_context, "comms", "overview") ==
             "/missions/#{mission.mission_id}/comms"

    assert ApplicationHostCatalog.fallback_href(route_context, "comms", "validation") ==
             "/missions/#{mission.mission_id}/comms/validation"

    assert ApplicationHostCatalog.fallback_href(
             route_context,
             "comms",
             "transport",
             "transport-1"
           ) ==
             "/missions/#{mission.mission_id}/comms/transports/transport-1"

    assert ApplicationHostCatalog.fallback_href(
             route_context,
             "comms",
             "routing_detail",
             "routing-rule-1"
           ) == "/missions/#{mission.mission_id}/comms/routing/routing-rule-1"

    assert ApplicationHostCatalog.fallback_href(
             route_context,
             "comms",
             "ground_station",
             "ground-station-1"
           ) == "/missions/#{mission.mission_id}/comms/ground-stations/ground-station-1"
  end

  defp installed_telemetry_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "telemetry_decom")

    {scope,
     %{
       host_context: host_context,
       mission: mission,
       spacecraft: spacecraft
     }}
  end

  defp installed_comms_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, mission_id: "mission-comms-registry")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.mission(mission.mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "comms")

    {scope, %{host_context: host_context, mission: mission, spacecraft: nil}}
  end
end
