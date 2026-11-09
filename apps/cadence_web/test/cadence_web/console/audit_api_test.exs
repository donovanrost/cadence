defmodule CadenceWeb.Console.AuditAPITest do
  @moduledoc "AU1 organization audit log."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    member = TestFixtures.persist_user!(display_name: "Mira")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    %{
      admin: admin,
      member: member,
      mission: mission,
      base: "/api/console/v1/organizations/#{org.organization_id}"
    }
  end

  defp get_audit(c, user, query),
    do: user |> TestFixtures.member_conn() |> get(c.base <> "/audit" <> query)

  test "merges access, settings and other sources newest first, with filters", c do
    c.admin
    |> TestFixtures.member_conn()
    |> post(c.base <> "/invitations", %{"email" => "ana@example.com"})
    |> json_response(201)

    c.admin
    |> TestFixtures.member_conn()
    |> put(
      "/api/console/v1/missions/#{c.mission.mission_id}/settings/cadence.configuration",
      %{"values" => %{"profile_framing_generations" => false}}
    )
    |> json_response(201)

    data = c |> get_audit(c.admin, "") |> json_response(200) |> Map.fetch!("data")

    assert data["sources"] == %{
             "included" => ["config", "commanding", "access"],
             "missing" => ["alarms", "contacts", "data"]
           }

    actions = Enum.map(data["events"], & &1["action"])
    assert "Invited ana@example.com as member" in actions
    assert "Joined as member" in actions
    assert "Changed Configuration settings" in actions

    settings = Enum.find(data["events"], &(&1["action"] == "Changed Configuration settings"))

    assert %{"kind" => "config", "actor" => %{"name" => "Ada"}, "mission" => %{"id" => _}} =
             settings

    ats = Enum.map(data["events"], & &1["at"])
    assert ats == Enum.sort(ats, :desc)

    only_access = c |> get_audit(c.admin, "?kinds=access") |> json_response(200)
    assert Enum.all?(only_access["data"]["events"], &(&1["kind"] == "access"))

    paged = c |> get_audit(c.admin, "?limit=1") |> json_response(200)
    assert length(paged["data"]["events"]) == 1
    assert paged["data"]["next_cursor"] == "1"

    assert json_response(get_audit(c, c.admin, "?kinds=bogus"), 422)["error"]["details"]["kinds"]
    assert json_response(get_audit(c, c.member, ""), 403)
  end
end
