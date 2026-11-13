defmodule CadenceWeb.Console.SpacecraftAppAPITest do
  @moduledoc "L19: the apps installable on one spacecraft."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-004")

    %{
      user: user,
      base:
        "/api/console/v1/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}/apps",
      missing: "/api/console/v1/missions/#{mission.mission_id}/spacecraft/nope/apps"
    }
  end

  defp get_conn(c, path), do: c.user |> TestFixtures.member_conn() |> get(path)

  test "lists the spacecraft-scope apps with only spacecraft surfaces; an unknown one is 404",
       c do
    data = c |> get_conn(c.base) |> json_response(200) |> Map.fetch!("data")

    assert data["permissions"] == ["apps.install"]
    keys = Enum.map(data["apps"], & &1["key"])
    assert "telemetry_decom" in keys

    for app <- data["apps"], surface <- app["surfaces"] do
      assert surface["scope"] == "spacecraft"
    end

    for app <- data["apps"] do
      assert %{"state" => _, "status" => _} = app
    end

    assert c |> get_conn(c.missing) |> json_response(404) |> get_in(["error", "code"]) ==
             "spacecraft_not_found"
  end
end
