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

  defp host(c, path), do: c.user |> TestFixtures.member_conn() |> get("#{c.base}/#{path}")

  test "L9: rows carry status and surfaces; the host serves one surface's catalog with real permissions",
       c do
    not_installed = host(c, "limits/surfaces/manage/host")

    assert %{
             "code" => "application_not_installed",
             "details" => %{"status" => %{"state" => "not_installed"}}
           } =
             json_response(not_installed, 409)["error"]

    assert json_response(post_action(c, "limits", "install"), 200)

    limits = Enum.find(get_data(c)["apps"], &(&1["key"] == "limits"))
    assert %{"state" => "active", "version" => version} = limits["status"]
    assert is_integer(version)

    assert [
             %{
               "surface_id" => "manage",
               "label" => "Definitions",
               "order" => 10,
               "area" => "setup",
               "scope" => "mission"
             },
             %{"surface_id" => "activity", "area" => "setup"}
           ] = limits["surfaces"]

    data = c |> host("limits/surfaces/manage/host") |> json_response(200) |> Map.fetch!("data")

    assert %{"state" => "active"} = data["status"]
    assert [%{"surface_id" => "manage"}, %{"surface_id" => "activity"}] = data["surfaces"]

    catalog = data["catalog"]
    assert catalog["schema"] == "cadence.first-party-frontend-catalog.v1"

    assert [%{"applicationKey" => "limits", "surface" => %{"surfaceId" => "manage"}}] =
             catalog["applications"]

    # Real permissions: a member may operate the limits surface (today's Policy, todo(authz)).
    assert catalog["session"]["context"]["actor"]["permissions"] == [
             "applications:view",
             "applications:operate"
           ]

    assert is_binary(catalog["session"]["sessionId"]) and
             is_binary(catalog["session"]["csrfToken"])

    assert json_response(host(c, "limits/surfaces/nope/host"), 404)["error"]["code"] ==
             "surface_not_found"

    assert json_response(host(c, "nope/surfaces/manage/host"), 404)["error"]["code"] ==
             "application_not_found"
  end
end
