defmodule CadenceWeb.Console.PassReservationAPITest do
  @moduledoc "L14 / A11: the route answers in the console envelope (the read's own test covers rows)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  test "an unknown pass is a 404 problem" do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Operator")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    body =
      user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{mission.mission_id}/passes/nope/reservation")
      |> json_response(404)

    assert body["error"]["code"] == "pass_not_found"
  end
end
