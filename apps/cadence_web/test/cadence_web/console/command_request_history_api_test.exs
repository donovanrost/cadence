defmodule CadenceWeb.Console.CommandRequestHistoryAPITest do
  @moduledoc "U68 R3/R4: the route answers in the console envelope (the read's own test covers rows)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  test "an unknown request is a 404 problem; the route is mission-scoped" do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Operator")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    body =
      user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{mission.mission_id}/command-requests/nope/history")
      |> json_response(404)

    assert body["code"] == "command_request_not_found" or
             get_in(body, ["error", "code"]) == "command_request_not_found"
  end
end
