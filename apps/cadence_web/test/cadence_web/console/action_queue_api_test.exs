defmodule CadenceWeb.Console.ActionQueueAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.ControlPlaneApiFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{user: user, org: org, mission: mission}
  end

  defp get_queue(c, mission_id \\ nil) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/console/v1/missions/#{mission_id || c.mission.mission_id}/action-queue")
  end

  test "an empty mission has only setup items, ranked P3", c do
    data = c |> get_queue() |> json_response(200) |> Map.fetch!("data")

    assert is_integer(data["stale_after_s"])
    assert is_integer(data["failure_lookback_s"])
    assert %{"p1" => 0, "p2" => 0, "spacecraft_p1" => 0} = data["counts"]

    assert data["items"] != []
    assert Enum.all?(data["items"], &(&1["priority"] == 3))

    assert %{"kind" => "setup", "state" => "off", "finding" => %{"cause" => "no_spacecraft"}} =
             Enum.find(data["items"], &(&1["id"] == "setup:fleet.no_spacecraft"))
  end

  test "a caution alarm is a P2 item naming the spacecraft and point", c do
    ControlPlaneApiFixtures.seed_mission_read_models(c.org.organization_id, c.mission.mission_id)

    data = c |> get_queue() |> json_response(200) |> Map.fetch!("data")

    assert %{"priority" => 2, "state" => "caution", "count" => 1} =
             item = Enum.find(data["items"], &(&1["kind"] == "alarm"))

    assert item["point"]["id"] == "HK.counter"
    assert [%{"id" => "spacecraft-001", "name" => "SC-001", "value" => 30}] = item["spacecraft"]
    assert item["command_requests"] == []
    assert item["due_at"] == nil
    refute Enum.any?(data["items"], &(&1["id"] == "limits_not_configured"))
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c |> get_queue(stranger.mission_id) |> json_response(404)
  end
end
