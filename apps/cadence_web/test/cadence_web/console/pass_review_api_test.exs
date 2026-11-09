defmodule CadenceWeb.Console.PassReviewAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, base: "/api/console/v1/missions/#{mission.mission_id}/pass-review"}
  end

  defp get_json(c, path, status \\ 200),
    do: c.user |> TestFixtures.member_conn() |> get(c.base <> path) |> json_response(status)

  test "an empty span: zero counts, settings, and day/span windows", c do
    data = get_json(c, "?day=2026-11-08&span=week")["data"]

    assert data["from"] == "2026-11-02T00:00:00.000Z"
    assert data["to"] == "2026-11-09T00:00:00.000Z"
    assert data["planned"] == 0
    assert data["threshold"] == 0.95
    assert data["target"] == 0.98
    assert data["by_station"] == []
    assert data["failed"] == 0

    assert data["missed_by_owner"] == %{
             "provider" => 0,
             "us" => 0,
             "weather" => 0,
             "unknown" => 0
           }

    assert %{"provider_bytes" => nil, "received_bytes" => nil, "provider_reported_passes" => 0} =
             data["volume"]

    rows = get_json(c, "/rows?day=2026-11-08&outcome=missed,partial")
    assert rows["data"]["rows"] == []
    assert rows["data"]["total"] == 0
    assert rows["meta"]["next_cursor"] == nil
    assert Map.fetch!(rows["data"], "next_cursor") == nil

    daily = get_json(c, "/daily?day=2026-11-08")["data"]
    assert daily["days"] == []
    assert daily["target"] == 0.98
  end

  test "validation", c do
    assert %{"error" => %{"details" => %{"span" => _}}} = get_json(c, "?span=year", 422)
    assert %{"error" => %{"details" => %{"day" => _}}} = get_json(c, "?day=yesterday", 422)

    assert %{"error" => %{"details" => %{"outcome" => _}}} =
             get_json(c, "/rows?outcome=lost", 422)

    assert %{"error" => %{"details" => %{"limit" => _}}} = get_json(c, "/rows?limit=0", 422)
  end
end
