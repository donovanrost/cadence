defmodule CadenceWeb.Console.FleetAPITest do
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Reads.FleetStatus
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    craft =
      TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")

    %{user: user, mission: mission, craft: craft}
  end

  test "returns counts, command counts and one row per spacecraft", c do
    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{c.mission.mission_id}/fleet")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["telemetry"] == "ok"

    assert data["stale_after_s"] == FleetStatus.stale_after_s()
    assert data["last_received_at"] == nil
    assert data["limits"] == %{"configured" => false}

    assert %{"total" => 1, "never_heard" => 1, "critical" => 0, "in_contact" => nil} =
             data["counts"]

    assert %{"queued" => 0, "approval_pending" => 0, "awaiting_viewer" => 0} = data["commands"]

    assert [row] = data["spacecraft"]
    assert row["id"] == c.craft.spacecraft_id
    assert row["name"] == "EARENDIL-001"
    assert row["state"] == "never_heard"
    assert row["limit_state"] == "no_data"
    assert row["stale"] == false
    assert row["worst_point"] == nil
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{stranger.mission_id}/fleet")

    assert %{"error" => %{"code" => "mission_not_found"}} = json_response(conn, 404)
  end
end
