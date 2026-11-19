defmodule CadenceWeb.Console.OrganizationMissionsAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  test "lists the organization's missions with spacecraft count and worst state; rule groups" do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, display_name: "Earendil")
    empty = TestFixtures.persist_mission!(org, display_name: "Alpha")
    TestFixtures.persist_spacecraft!(mission)

    data =
      user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{org.organization_id}/missions")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [
             %{
               "id" => empty_id,
               "name" => "Alpha",
               "spacecraft_count" => 0,
               "worst_state" => nil
             },
             %{"name" => "Earendil", "spacecraft_count" => 1, "worst_state" => "never_heard"}
           ] = data["missions"]

    assert empty_id == empty.mission_id

    groups =
      user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{mission.mission_id}/routing-rules/groups")
      |> json_response(200)

    assert groups["data"] == %{"groups" => []}

    outsider = TestFixtures.persist_user!()

    assert outsider
           |> TestFixtures.member_conn()
           |> get("/api/console/v1/organizations/#{org.organization_id}/missions")
           |> json_response(404)
  end
end
