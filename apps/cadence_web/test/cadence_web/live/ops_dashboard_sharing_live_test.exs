defmodule CadenceWeb.OpsDashboardSharingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "share and snapshot routes forward their exact subjects" do
    {conn, mission} = signed_in()

    {:ok, share, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboard-shares/share-1")

    assert_surface(
      share,
      "ops-dashboard-share-component",
      "dashboard_share",
      mission,
      %{
        "share_id" => "share-1"
      },
      "h-full"
    )

    {:ok, snapshot, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboard-snapshots/snapshot-1")

    assert_surface(
      snapshot,
      "ops-dashboard-snapshot-component",
      "dashboard_snapshot",
      mission,
      %{
        "snapshot_id" => "snapshot-1"
      },
      "h-full"
    )
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, _id, surface_id, mission, query_params, _class) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "ops_console",
      "surface_id" => surface_id,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end
end
