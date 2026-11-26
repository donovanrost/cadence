defmodule CadenceWeb.Console.SettingsApprovalAPITest do
  @moduledoc """
  #233 at the console edge (user ruling 11-18; ux U96): the governance fields say what the viewer
  may change (allowed_values, can_inherit; absent on other fields), an operator's change and a
  non-admin's loosening are 403s in ux's words by the level saved, a refused change writes
  nothing, and the audit says which way a change went, with the raw before and after.

  People are organization admins or members here; a mission admin is a service identity's
  capability today, so its row is tested in the domain (ApprovalSettingAccessTest).
  """
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  @section "cadence.governance"

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    member = TestFixtures.persist_user!(display_name: "Mo")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org, display_name: "EARENDIL")

    %{
      admin: admin,
      member: member,
      mission: mission,
      mission_base: "/api/v1/missions/#{mission.mission_id}/settings",
      org_base: "/api/v1/organizations/#{org.organization_id}/settings"
    }
  end

  test "the read: what each viewer may change; other fields carry neither key", c do
    assert %{"allowed_values" => ["direct", "independent"], "can_inherit" => true} =
             field(read(c.admin, c.mission_base), "approval_requirement")

    assert %{"allowed_values" => [], "can_inherit" => false} =
             field(read(c.member, c.mission_base), "approval_requirement")

    org = read(c.admin, c.org_base)
    assert %{"allowed_values" => ["direct", "independent"]} = field(org, "approval_requirement")
    assert %{"allowed_values" => [true, false]} = field(org, "allow_override")
    refute Map.has_key?(field(org, "approval_requirement"), "can_inherit")

    framing =
      read(c.admin, c.mission_base)["sections"]
      |> Enum.find(&(&1["key"] == "cadence.configuration"))
      |> Map.fetch!("fields")
      |> hd()

    refute Map.has_key?(framing, "allowed_values") or Map.has_key?(framing, "can_inherit")
  end

  test "a member's change is a 403 in ux's words, and nothing is written", c do
    assert %{
             "error" => %{
               "code" => "approval_policy_change_requires_organization_admin",
               "message" =>
                 "Not saved: only an organization admin can let changes on EARENDIL apply without approval."
             }
           } = save(c.member, c.mission_base, "direct") |> json_response(403)

    assert %{
             "error" => %{
               "code" => "approval_policy_change_requires_mission_admin",
               "message" =>
                 "Not saved: only a mission admin or an organization admin can change approval settings."
             }
           } = save(c.member, c.mission_base, "independent") |> json_response(403)

    assert %{"error" => %{"code" => code, "message" => message}} =
             save(c.member, c.org_base, "direct") |> json_response(403)

    assert code in ["approval_policy_change_requires_organization_admin", "forbidden"]
    assert message =~ "only an organization admin can change the organization's approval setting"

    assert governance(read(c.admin, c.mission_base))["version"] == nil
    assert audit(c, c.admin) == []
  end

  test "an organization admin loosens and tightens; the audit says which way, with raw values",
       c do
    assert save(c.admin, c.mission_base, "direct") |> json_response(201)
    assert save(c.admin, c.mission_base, "independent") |> json_response(201)
    assert save(c.admin, c.org_base, "independent", false) |> json_response(201)

    assert [org_change, tightened, loosened] = audit(c, c.admin)

    assert %{
             "action" =>
               "Loosened approval on EARENDIL: Needs a second person's approval → Applies without approval",
             "change" => %{
               "before" => %{"approval_requirement" => "independent", "override" => false},
               "after" => %{"approval_requirement" => "direct", "override" => true}
             },
             "mission" => %{"name" => "EARENDIL"}
           } = loosened

    assert tightened["action"] =~ "Tightened approval on EARENDIL: Applies without approval →"

    assert %{
             "action" => "Missions can no longer set their own approval setting.",
             "change" => %{
               "before" => %{"allow_override" => true},
               "after" => %{"allow_override" => false}
             }
           } = org_change

    # Enforced: nobody below changes the mission's value, the organization admin included.
    assert %{"allowed_values" => [], "can_inherit" => false} =
             field(read(c.admin, c.mission_base), "approval_requirement")

    assert %{"error" => %{"code" => "settings_enforced_by_organization"}} =
             save(c.admin, c.mission_base, "direct") |> json_response(409)
  end

  # #430: an organization save lists the missions it moved, named, in ux's words. Turning
  # overrides off moves a 'direct' pin to the default; turning them on applies it again (the save
  # that can loosen). Only organization admins read the organization audit (ca-security).
  test "an organization save names the missions it moved; only organization admins read it", c do
    id = c.mission.mission_id
    assert save(c.admin, c.mission_base, "direct") |> json_response(201)
    assert save(c.admin, c.org_base, "independent", false) |> json_response(201)
    assert save(c.admin, c.org_base, "independent", true) |> json_response(201)

    assert [on, off | _] = audit(c, c.admin)

    assert %{
             "action" =>
               "Missions may now set their own approval setting. " <>
                 "Changed on 1 mission to Applies without approval: EARENDIL.",
             "change" => %{
               "missions" => [
                 %{
                   "id" => ^id,
                   "name" => "EARENDIL",
                   "before" => "independent",
                   "after" => "direct"
                 }
               ]
             }
           } = on

    assert off["action"] =~ "Changed on 1 mission to Needs a second person's approval: EARENDIL."
    assert [%{"before" => "direct", "after" => "independent"}] = off["change"]["missions"]

    assert c.member
           |> TestFixtures.member_conn()
           |> get(String.replace(c.org_base, "/settings", "/audit"))
           |> json_response(403)
  end

  defp read(user, path),
    do:
      user |> TestFixtures.member_conn() |> get(path) |> json_response(200) |> Map.fetch!("data")

  defp governance(data), do: Enum.find(data["sections"], &(&1["key"] == @section))

  defp field(data, path), do: governance(data)["fields"] |> Enum.find(&(&1["path"] == path))

  defp save(user, base, requirement, allow_override \\ nil) do
    version = governance(read(user, base))["version"]

    values =
      %{"approval_requirement" => requirement}
      |> then(
        &if(is_nil(allow_override), do: &1, else: Map.put(&1, "allow_override", allow_override))
      )

    user
    |> TestFixtures.member_conn()
    |> put(base <> "/" <> @section, %{
      "values" => values,
      "expected_version" => version && version["version"]
    })
  end

  defp audit(c, user) do
    user
    |> TestFixtures.member_conn()
    |> get(c.org_base |> String.replace("/settings", "/audit?kinds=config"))
    |> json_response(200)
    |> get_in(["data", "events"])
    |> Enum.filter(&match?(%{"target" => %{"id" => @section}}, &1))
  end
end
