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
             "included" => [
               "config",
               "commanding",
               "access",
               "alarms",
               "contacts",
               "data",
               "provider_accounts",
               "account",
               "platform"
             ],
             "missing" => []
           }

    actions = Enum.map(data["events"], & &1["action"])
    assert "Invited ana@example.com as member" in actions
    assert "Joined as member" in actions
    assert "Changed Configuration settings" in actions

    settings = Enum.find(data["events"], &(&1["action"] == "Changed Configuration settings"))

    assert %{"id" => "config:settings:cadence.configuration:" <> _, "at" => _} = settings

    assert Map.drop(settings, ["id", "at", "mission"]) == %{
             "kind" => "config",
             "action" => "Changed Configuration settings",
             "actor" => %{"kind" => "user", "id" => nil, "name" => "Ada"},
             "target" => %{
               "kind" => "settings",
               "id" => "cadence.configuration",
               "label" => "Configuration"
             },
             "reason" => nil
           }

    assert %{"id" => mission_id, "name" => _} = settings["mission"]
    assert mission_id == c.mission.mission_id

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

  test "contact plan approvals appear under contacts" do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    fixture = CadenceWeb.ContactPlanningFixtures.plan_fixture(org, admin, membership, mission)
    # Under 'direct' approval an admin may approve their own submit; approving is its own
    # action since #257 (director 11-19).
    CadenceWeb.ContactPlanningFixtures.approve_directly!(org, admin, membership, mission)
    plans = "/api/console/v1/missions/#{mission.mission_id}/contact-plans"

    admin
    |> TestFixtures.member_conn()
    |> post("#{plans}/#{fixture.plan.contact_plan_id}/submit", %{
      "expected_version" => 1,
      "operation_id" => "op-audit"
    })
    |> json_response(200)

    admin
    |> TestFixtures.member_conn()
    |> post("#{plans}/#{fixture.plan.contact_plan_id}/approve", %{
      "expected_version" => 1,
      "operation_id" => "op-audit-approve"
    })
    |> json_response(202)

    events =
      admin
      |> TestFixtures.member_conn()
      |> get(
        "/api/console/v1/organizations/#{org.organization_id}/audit?kinds=contacts&from=2000-01-01T00:00:00Z"
      )
      |> json_response(200)
      |> get_in(["data", "events"])

    assert [%{"action" => "Approved contact plan v1", "actor" => %{"name" => "Ada"}} | _] = events
  end
end
