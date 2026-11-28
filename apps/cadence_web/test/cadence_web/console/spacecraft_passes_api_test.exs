defmodule CadenceWeb.Console.SpacecraftPassesAPITest do
  @moduledoc "Investigate Passes: GET /spacecraft/:id/passes (P1 coverage, P3 queued counts)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.MissionReadModelFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    MissionReadModelFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)
    %{user: user, mission: mission}
  end

  defp get_json(c, spacecraft_id, status) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{c.mission.mission_id}/spacecraft/#{spacecraft_id}/passes")
    |> json_response(status)
  end

  test "a spacecraft with nothing booked reads as one uncovered day and no contact rule", c do
    data = get_json(c, "spacecraft-001", 200)["data"]

    assert %{
             "last_contact" => nil,
             "next_contact" => nil,
             "passes_next_24h" => 0,
             "none_within_6h" => true,
             "longest_gap" => %{"seconds" => 86_400, "from" => _, "to" => _},
             "contact_rule" => %{"state" => "none", "rules" => []}
           } = data["coverage"]

    assert data["queued"] == %{}
    assert is_binary(data["observed_at"])
  end

  test "an unknown spacecraft is 404", c do
    assert %{"error" => %{"code" => "spacecraft_not_found"}} = get_json(c, "spacecraft-nope", 404)
  end
end
