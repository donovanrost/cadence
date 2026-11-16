defmodule CadenceWeb.Console.CommandGroupListAPITest do
  @moduledoc "U69 A5: the list's params and envelope (the search read's own test covers rows)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Operator")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, base: "/api/console/v1/missions/#{mission.mission_id}/command-groups"}
  end

  defp get_json(c, query), do: c.user |> TestFixtures.member_conn() |> get(c.base <> query)

  test "rows come with meta.next_cursor; filters are accepted", c do
    body =
      c
      |> get_json("?q=load&target=sc-1&stage=queued_for_contact,in_flight&mine=true&limit=50")
      |> json_response(200)

    assert body["data"]["groups"] == []
    assert body["meta"] == %{"next_cursor" => nil}
  end

  test "bad params are 422 with the field named", c do
    for {query, field} <- [
          {"?stage=lost", "stage"},
          {"?state=done", "state"},
          {"?limit=0", "limit"},
          {"?q=" <> String.duplicate("x", 101), "q"},
          {"?cursor=nope", "cursor"}
        ] do
      body = c |> get_json(query) |> json_response(422)
      assert Map.has_key?(body["error"]["details"], field), query
    end
  end
end
