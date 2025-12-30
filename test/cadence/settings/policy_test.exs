defmodule Cadence.Settings.PolicyTest do
  use Cadence.PureCase, async: true

  alias Cadence.Accounts.Scope
  alias Cadence.Accounts.User
  alias Cadence.Missions.Mission
  alias Cadence.Missions.MissionMembership
  alias Cadence.Organizations.Organization
  alias Cadence.Organizations.OrganizationMembership
  alias Cadence.Settings.Policy

  describe "organization settings authorization" do
    setup do
      org = build_org()
      other_org = build_org()

      owner = build_user() |> with_org_membership(org, "owner")
      admin = build_user() |> with_org_membership(org, "admin")
      member = build_user() |> with_org_membership(org, "member")
      non_member = build_user() |> with_org_membership(other_org, "member")

      %{
        org: org,
        owner: owner,
        admin: admin,
        member: member,
        non_member: non_member
      }
    end

    test "org owner can view org settings", %{org: org, owner: owner} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, owner, org)
    end

    test "org owner can manage org settings", %{org: org, owner: owner} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, owner, org)
    end

    test "org admin can view org settings", %{org: org, admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, admin, org)
    end

    test "org admin can manage org settings", %{org: org, admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, admin, org)
    end

    test "org member can view org settings", %{org: org, member: member} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, member, org)
    end

    test "org member cannot manage org settings", %{org: org, member: member} do
      assert {:error, _} = Bodyguard.permit(Policy, :manage_settings, member, org)
    end

    test "non-member cannot view org settings", %{org: org, non_member: non_member} do
      assert {:error, _} = Bodyguard.permit(Policy, :view_settings, non_member, org)
    end

    test "non-member cannot manage org settings", %{org: org, non_member: non_member} do
      assert {:error, _} = Bodyguard.permit(Policy, :manage_settings, non_member, org)
    end
  end

  describe "organization settings with Scope" do
    setup do
      org = build_org()
      admin = build_user() |> with_org_membership(org, "admin")
      scope = build_scope(admin, current_org: org)

      %{org: org, scope: scope}
    end

    test "scope-based authorization works for org settings", %{org: org, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, scope, org)
      assert :ok = Bodyguard.permit(Policy, :manage_settings, scope, org)
    end
  end

  describe "mission settings authorization" do
    setup do
      org = build_org()
      mission = build_mission(org)
      other_org = build_org()

      org_admin = build_user() |> with_org_membership(org, "admin")
      mission_admin = build_user() |> with_mission_membership(mission, "admin")
      mission_engineer = build_user() |> with_mission_membership(mission, "engineer")
      mission_operator = build_user() |> with_mission_membership(mission, "operator")
      mission_viewer = build_user() |> with_mission_membership(mission, "viewer")
      non_member = build_user() |> with_org_membership(other_org, "member")

      %{
        org: org,
        mission: mission,
        org_admin: org_admin,
        mission_admin: mission_admin,
        mission_engineer: mission_engineer,
        mission_operator: mission_operator,
        mission_viewer: mission_viewer,
        non_member: non_member
      }
    end

    test "org admin can view mission settings", %{mission: mission, org_admin: org_admin} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, org_admin, mission)
    end

    test "org admin can manage mission settings", %{mission: mission, org_admin: org_admin} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, org_admin, mission)
    end

    test "mission admin can view mission settings", %{mission: mission, mission_admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, admin, mission)
    end

    test "mission admin can manage mission settings", %{mission: mission, mission_admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, admin, mission)
    end

    test "mission engineer can view mission settings", %{
      mission: mission,
      mission_engineer: engineer
    } do
      assert :ok = Bodyguard.permit(Policy, :view_settings, engineer, mission)
    end

    test "mission engineer can manage mission settings", %{
      mission: mission,
      mission_engineer: engineer
    } do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, engineer, mission)
    end

    test "mission operator can view mission settings", %{
      mission: mission,
      mission_operator: operator
    } do
      assert :ok = Bodyguard.permit(Policy, :view_settings, operator, mission)
    end

    test "mission operator cannot manage mission settings", %{
      mission: mission,
      mission_operator: operator
    } do
      assert {:error, _} = Bodyguard.permit(Policy, :manage_settings, operator, mission)
    end

    test "mission viewer can view mission settings", %{mission: mission, mission_viewer: viewer} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, viewer, mission)
    end

    test "mission viewer cannot manage mission settings", %{
      mission: mission,
      mission_viewer: viewer
    } do
      assert {:error, _} = Bodyguard.permit(Policy, :manage_settings, viewer, mission)
    end

    test "non-member cannot view mission settings", %{mission: mission, non_member: non_member} do
      assert {:error, _} = Bodyguard.permit(Policy, :view_settings, non_member, mission)
    end

    test "non-member cannot manage mission settings", %{mission: mission, non_member: non_member} do
      assert {:error, _} = Bodyguard.permit(Policy, :manage_settings, non_member, mission)
    end
  end

  describe "mission settings with Scope" do
    setup do
      org = build_org()
      mission = build_mission(org)
      engineer = build_user() |> with_mission_membership(mission, "engineer")
      scope = build_scope(engineer, current_org: org)

      %{mission: mission, scope: scope}
    end

    test "scope-based authorization works for mission settings", %{mission: mission, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, scope, mission)
      assert :ok = Bodyguard.permit(Policy, :manage_settings, scope, mission)
    end
  end

  describe "system admin authorization" do
    setup do
      org = build_org()
      mission = build_mission(org)

      # Create a system admin (no org memberships needed)
      system_admin = build_user(system_admin: true)

      scope = %Scope{
        user: system_admin,
        current_organization: org,
        all_organizations: [org],
        system_admin?: true
      }

      %{org: org, mission: mission, system_admin: system_admin, scope: scope}
    end

    test "system admin can view org settings", %{org: org, system_admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, admin, org)
    end

    test "system admin can manage org settings", %{org: org, system_admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, admin, org)
    end

    test "system admin can view mission settings", %{mission: mission, system_admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, admin, mission)
    end

    test "system admin can manage mission settings", %{mission: mission, system_admin: admin} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, admin, mission)
    end

    test "system admin scope can view org settings", %{org: org, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, scope, org)
    end

    test "system admin scope can manage org settings", %{org: org, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, scope, org)
    end

    test "system admin scope can view mission settings", %{mission: mission, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, scope, mission)
    end

    test "system admin scope can manage mission settings", %{mission: mission, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :manage_settings, scope, mission)
    end
  end

  defp build_org do
    %Organization{
      id: random_id(),
      name: unique_string("org"),
      slug: unique_string("org")
    }
  end

  defp build_mission(%Organization{id: org_id}) do
    %Mission{
      id: random_id(),
      organization_id: org_id,
      name: unique_string("mission"),
      slug: unique_string("mission")
    }
  end

  defp build_user(opts \\ []) do
    %User{
      id: random_id(),
      email: unique_email(),
      organization_memberships: Keyword.get(opts, :organization_memberships, []),
      mission_memberships: Keyword.get(opts, :mission_memberships, []),
      system_admin: Keyword.get(opts, :system_admin, false)
    }
  end

  defp build_scope(%User{} = user, opts) do
    current_org = Keyword.get(opts, :current_org)

    %Scope{
      user: user,
      current_organization: current_org,
      all_organizations: if(current_org, do: [current_org], else: []),
      system_admin?: user.system_admin
    }
  end

  defp with_org_membership(%User{} = user, %Organization{id: org_id}, role) do
    membership = %OrganizationMembership{
      user_id: user.id,
      organization_id: org_id,
      role: role
    }

    %{user | organization_memberships: [membership | user.organization_memberships]}
  end

  defp with_mission_membership(%User{} = user, %Mission{id: mission_id}, role) do
    membership = %MissionMembership{
      user_id: user.id,
      mission_id: mission_id,
      role: role
    }

    %{user | mission_memberships: [membership | user.mission_memberships]}
  end
end
