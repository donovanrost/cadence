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

  test "lists the mission's apps; each is a platform app, so none installs", c do
    data = get_data(c)
    assert data["permissions"] == ["apps.install"]
    assert data["apps"] != []
    assert data["spacecraft_count"] == 0

    # The only optional app left is spacecraft-scoped (Telemetry Decom, SpacecraftAppAPITest).
    assert Enum.all?(data["apps"], & &1["platform"])

    assert json_response(post_action(c, "ops_console", "install"), 422)["error"]["code"] ==
             "platform_application"

    assert json_response(post_action(c, "no-such-app", "install"), 404)["error"]["code"] ==
             "app_not_found"
  end

  test "spacecraft_count is the mission's active spacecraft", c do
    TestFixtures.persist_spacecraft!(c.mission)
    TestFixtures.persist_spacecraft!(c.mission)

    assert get_data(c)["spacecraft_count"] == 2
  end

  defp host(c, path), do: c.user |> TestFixtures.member_conn() |> get("#{c.base}/#{path}")

  test "L9: rows carry status and surfaces; the host serves one surface's catalog with real permissions",
       c do
    ops = Enum.find(get_data(c)["apps"], &(&1["key"] == "ops_console"))
    assert %{"state" => "active", "version" => version} = ops["status"]
    assert is_integer(version)

    assert %{
             "surface_id" => "workspace",
             "label" => "Ops Console",
             "order" => 10,
             "scope" => "mission"
           } = Enum.find(ops["surfaces"], &(&1["surface_id"] == "workspace"))

    data =
      c
      |> host("ops_console/surfaces/data_sources/host")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"state" => "active"} = data["status"]

    assert Enum.map(data["surfaces"], & &1["surface_id"]) ==
             Enum.map(ops["surfaces"], & &1["surface_id"])

    catalog = data["catalog"]
    assert catalog["schema"] == "cadence.first-party-frontend-catalog.v1"

    assert [%{"applicationKey" => "ops_console", "surface" => %{"surfaceId" => "data_sources"}}] =
             catalog["applications"]

    # Real permissions: a member may operate a surface with actions (today's Policy, todo(authz)).
    assert catalog["session"]["context"]["actor"]["permissions"] == [
             "applications:view",
             "applications:operate"
           ]

    assert is_binary(catalog["session"]["sessionId"]) and
             is_binary(catalog["session"]["csrfToken"])

    assert json_response(host(c, "ops_console/surfaces/nope/host"), 404)["error"]["code"] ==
             "surface_not_found"

    assert json_response(host(c, "nope/surfaces/manage/host"), 404)["error"]["code"] ==
             "application_not_found"
  end
end
