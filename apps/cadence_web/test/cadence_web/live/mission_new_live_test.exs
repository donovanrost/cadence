defmodule CadenceWeb.MissionNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated organization members mount the mission new surface" do
    {conn, organization} = signed_in_org()

    {:ok, view, _html} = live(conn, ~p"/missions/new")

    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "mission_catalog",
      "surface_id" => "mission_new",
      "host_scope" => "organization",
      "organization_id" => organization.organization_id,
      "query_params" => %{}
    })
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions/new")
  end

  defp signed_in_org do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    {TestFixtures.member_conn(user), organization}
  end
end
