defmodule CadenceWeb.Console.SpacecraftConfigAPITest do
  @moduledoc "Investigate's Configuration tab: GET …/spacecraft/:id/configuration."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(member, org)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")

    %{member: member, craft: craft, base: "/api/console/v1/missions/#{mission.mission_id}"}
  end

  test "a spacecraft's configuration; an unknown one is not found", c do
    conn = TestFixtures.member_conn(c.member)

    assert %{
             "data" => %{
               "spacecraft" => %{"name" => "EARENDIL-001", "archived" => nil},
               "catalog" => %{"running" => nil, "profile" => nil},
               "overrides" => [],
               "routing_rules" => [],
               "pending" => [],
               "recent_revisions" => recent
             }
           } =
             conn
             |> get(c.base <> "/spacecraft/#{c.craft.spacecraft_id}/configuration")
             |> json_response(200)

    assert is_list(recent)

    assert %{"error" => %{"code" => "spacecraft_not_found"}} =
             c.member
             |> TestFixtures.member_conn()
             |> get(c.base <> "/spacecraft/nobody/configuration")
             |> json_response(404)
  end
end
