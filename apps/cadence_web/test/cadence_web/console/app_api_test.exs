defmodule CadenceWeb.Console.AppAPITest do
  @moduledoc "A1 apps."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, mission: mission, base: "/api/v1/missions/#{mission.mission_id}/apps"}
  end

  defp get_data(c),
    do:
      c.user
      |> TestFixtures.member_conn()
      |> get(c.base)
      |> json_response(200)
      |> Map.fetch!("data")

  defp post_action(c, key, action),
    do: c.user |> TestFixtures.member_conn() |> post("#{c.base}/#{key}/#{action}", %{})

  test "no app installs on the whole mission; an unknown one is 404", c do
    data = get_data(c)
    assert data["permissions"] == ["apps.install"]
    assert data["spacecraft_count"] == 0

    # The only available app is spacecraft-scoped (Telemetry Decom, SpacecraftAppAPITest), and
    # its rows' status and shape are tested there.
    assert data["apps"] == []

    assert json_response(post_action(c, "no-such-app", "install"), 404)["error"]["code"] ==
             "app_not_found"
  end

  test "spacecraft_count is the mission's active spacecraft", c do
    TestFixtures.persist_spacecraft!(c.mission)
    TestFixtures.persist_spacecraft!(c.mission)

    assert get_data(c)["spacecraft_count"] == 2
  end
end
