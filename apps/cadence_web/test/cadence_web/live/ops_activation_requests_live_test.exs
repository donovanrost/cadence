defmodule CadenceWeb.OpsActivationRequestsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "organization administrators mount the activation federated surface" do
    {conn, mission} = signed_in(:organization_admin)

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/activations")

    assert_surface(view, "activation-requests-component", "activation_requests", mission, %{})
  end

  test "ordinary members cannot open the activation route" do
    {conn, mission} = signed_in(:member)

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/activations")
  end

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: role)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "ops_console",
      "surface_id" => surface_id,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end
end
