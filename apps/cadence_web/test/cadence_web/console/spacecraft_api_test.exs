defmodule CadenceWeb.Console.SpacecraftAPITest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, mission: mission}
  end

  test "lists spacecraft with identity, geometry and readiness", c do
    craft = TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-007")

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/spacecraft")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [row] = data["spacecraft"]
    assert row["id"] == craft.spacecraft_id
    assert row["name"] == "EARENDIL-007"
    assert row["routing_rule_count"] == 0
    assert row["ready"] == false
    assert row["last_received_at"] == nil
    assert Map.has_key?(row, "norad_id")
    assert Map.has_key?(row, "plane")
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{stranger.mission_id}/spacecraft")

    assert json_response(conn, 404)["error"]["code"] == "mission_not_found"
  end
end
