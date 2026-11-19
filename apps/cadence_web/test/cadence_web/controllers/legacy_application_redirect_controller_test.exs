defmodule CadenceWeb.LegacyApplicationRedirectControllerTest do
  use CadenceWeb.ConnCase, async: true

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "redirects retired telemetry URLs to the spacecraft's decom app in the console" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, slug: "primary")
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    canonical_path =
      "/console/#{organization.slug}/primary/setup/spacecraft/#{spacecraft.spacecraft_id}/apps/telemetry_decom"

    for legacy_path <- [
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry",
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
        ] do
      conn = get(TestFixtures.member_conn(user), legacy_path)

      assert redirected_to(conn, 301) == canonical_path
    end
  end

  test "the legacy Ops explore and comms aliases go to the console (DECISIONS #79)" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, slug: "primary")
    console = "/console/#{organization.slug}/primary"
    legacy = "/missions/#{mission.mission_id}"
    go = fn path -> user |> TestFixtures.member_conn() |> get(path) |> redirected_to(301) end

    assert go.(legacy <> "/ops/telemetry/explore?from=now-6h&to=now&junk=1") ==
             console <> "/telemetry?from=now-6h&to=now"

    assert go.(legacy <> "/comms/links") == console <> "/setup/comms"
    assert go.(legacy <> "/comms/provider-profiles") == console <> "/setup/comms/transports"
  end

  test "requires authentication before redirecting a legacy application URL", %{conn: conn} do
    conn = get(conn, "/missions/mission-id/spacecraft/spacecraft-id/telemetry")

    assert redirected_to(conn) == "/sign-in"
  end
end
