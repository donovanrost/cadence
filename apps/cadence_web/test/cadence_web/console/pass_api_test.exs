defmodule CadenceWeb.Console.PassAPITest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, mission: mission}
  end

  defp get_passes(c, query, mission_id \\ nil) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{mission_id || c.mission.mission_id}/passes" <> query)
  end

  test "defaults to the next 24 hours and returns an empty list for a mission with no bookings",
       c do
    data = c |> get_passes("") |> json_response(200) |> Map.fetch!("data")

    assert data["passes"] == []
    assert data["truncated"] == false
    {:ok, from, _} = DateTime.from_iso8601(data["from"])
    {:ok, to, _} = DateTime.from_iso8601(data["to"])
    assert DateTime.diff(to, from) == 86_400
    assert abs(DateTime.diff(from, DateTime.utc_now())) < 60
  end

  test "rejects windows over 7 days and unknown states", c do
    body =
      c
      |> get_passes("?from=2026-11-01T00:00:00Z&to=2026-11-09T00:00:00Z&states=confirmed,bogus")
      |> json_response(422)

    assert %{"code" => "invalid_params", "details" => details} = body["error"]
    assert Map.has_key?(details, "from")

    body = c |> get_passes("?states=confirmed,bogus") |> json_response(422)
    assert %{"details" => %{"states" => _}} = body["error"]
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c |> get_passes("", stranger.mission_id) |> json_response(404)
  end
end
