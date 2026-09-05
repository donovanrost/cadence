defmodule CadenceWeb.SpacecraftTelemetryDecomLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.Scope
  alias CadenceWeb.SpacecraftTelemetryDecomLive
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "canonical telemetry surface render exposes the federated mount" do
    {_conn, scope, mission, spacecraft} = signed_in_spacecraft()

    html =
      render_component(&SpacecraftTelemetryDecomLive.render/1, %{
        flash: %{},
        current_scope: scope,
        current_mission: mission,
        current_spacecraft: spacecraft
      })

    vue = Test.get_vue(html, id: "spacecraft-telemetry-decom-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "spacecraft-telemetry-decom-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
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
