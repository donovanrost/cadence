defmodule CadenceWeb.OpsDashboardSharingLiveTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CadenceWeb.TestFixtures

  test "missing share and snapshot subjects are contained compiled pages" do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    for {segment, id, contribution} <- [
          {"dashboard-shares", "share-1", "dashboards.share"},
          {"dashboard-snapshots", "snapshot-1", "dashboards.snapshot"}
        ] do
      {:ok, view, _} =
        live(
          TestFixtures.member_conn(user),
          "/missions/#{mission.mission_id}/ops/#{segment}/#{id}"
        )

      page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
      assert page["id"] == contribution
      assert page["status"] == "unavailable"
      assert page["context"]["resourceId"] == id
      assert page["context"]["missionId"] == mission.mission_id
    end
  end
end
