defmodule CadenceWeb.Console.AppAPITest do
  @moduledoc "A1 apps."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, base: "/api/console/v1/missions/#{mission.mission_id}/apps"}
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

  test "lists installable apps with state; install, disable and uninstall return the row", c do
    data = get_data(c)
    assert data["permissions"] == ["apps.install"]
    assert data["apps"] != []

    %{"key" => key} = optional = Enum.find(data["apps"], &(&1["platform"] == false))
    assert %{"state" => "not_installed", "installed" => false, "version" => nil} = optional

    assert %{"key" => ^key, "state" => "installed", "installed" => true} =
             c |> post_action(key, "install") |> json_response(200) |> Map.fetch!("data")

    assert %{"state" => "disabled"} =
             c |> post_action(key, "disable") |> json_response(200) |> Map.fetch!("data")

    assert %{"state" => "not_installed"} =
             c |> post_action(key, "uninstall") |> json_response(200) |> Map.fetch!("data")

    assert json_response(post_action(c, "no-such-app", "install"), 404)["error"]["code"] ==
             "app_not_found"
  end
end
