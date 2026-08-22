defmodule CadenceWeb.LegacyApplicationRedirectControllerTest do
  use CadenceWeb.ConnCase, async: true

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "redirects retired telemetry URLs to the generic application host" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, slug: "primary")
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    canonical_path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"

    for legacy_path <- [
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry",
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
        ] do
      conn = get(TestFixtures.member_conn(user), legacy_path)

      assert redirected_to(conn, 301) == canonical_path
    end
  end

  test "requires authentication before redirecting a legacy application URL", %{conn: conn} do
    conn = get(conn, "/missions/mission-id/spacecraft/spacecraft-id/telemetry")

    assert redirected_to(conn) == "/sign-in"
  end
end
