defmodule CadenceWeb.SpacecraftTelemetrySurfaceTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias CadenceWeb.TestFixtures

  test "telemetry surface requires its dependency before mounting the federated surface" do
    {conn, scope, mission, spacecraft} = signed_in_spacecraft()

    path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/spacecraft/telemetry_decom"

    applications_path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

    assert {:error, {:live_redirect, %{to: ^applications_path}}} = live(conn, path)

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               scope,
               HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
               "telemetry_decom"
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/spacecraft/telemetry_decom"
      )

    vue = LiveVue.Test.get_vue(view, id: "application-surface-component")
    assert vue.component == "FederatedFullPageSurface"

    assert vue.props == %{
             "application_key" => "spacecraft",
             "application_version" => 1,
             "surface_version" => 1,
             "organization_id" => nil,
             "user_id" => nil,
             "surface_id" => "telemetry_decom",
             "host_scope" => "spacecraft",
             "mission_id" => mission.mission_id,
             "spacecraft_id" => spacecraft.spacecraft_id,
             "query_params" => %{}
           }
  end

  test "unauthenticated telemetry requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               build_conn(),
               "/missions/mission-test/spacecraft/spacecraft-test/applications/telemetry_decom/manage"
             )
  end

  defp signed_in_spacecraft do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    {TestFixtures.member_conn(user), scope, mission, spacecraft}
  end
end
