defmodule CadenceWeb.Console.PassReservationAPITest do
  @moduledoc "L14 / A11 + A13: the routes answer in the console envelope (the reads' tests cover rows)."
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
      |> get("/api/v1/missions/#{mission.mission_id}/passes/nope/reservation")
      |> json_response(404)

    assert body["error"]["code"] == "pass_not_found"

    body =
      user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{mission.mission_id}/contacts/nope/record")
      |> json_response(404)

    assert body["error"]["code"] == "contact_not_found"
  end
end
