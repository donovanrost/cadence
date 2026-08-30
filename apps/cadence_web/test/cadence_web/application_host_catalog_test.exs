defmodule CadenceWeb.ApplicationHostCatalogTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Auth.Scope
  alias CadenceWeb.{ApplicationHostCatalog, TestFixtures}

  test "admits the registered telemetry packet_bindings surface only after release lookup", %{
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

    assert {:error, :unknown_application_release} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings"
             )
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
end
