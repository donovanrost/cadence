defmodule Cadence.Settings.PolicyTest do
  use Cadence.DataCase, async: true

  import Cadence.AccountsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures

  alias Cadence.Accounts.Scope
  alias Cadence.Missions.MissionMembership
  alias Cadence.Organizations.OrganizationMembership
  alias Cadence.Repo
  alias Cadence.Settings.Policy

  describe "organization settings authorization" do
    setup do
      org = organization_fixture()
      other_org = organization_fixture()

      # Create users with different roles
      owner = user_fixture()
      admin = user_fixture()
      member = user_fixture()
      non_member = user_fixture()

      # Set up organization memberships
      Repo.insert!(%OrganizationMembership{
        user_id: owner.id,
        organization_id: org.id,
        role: "owner"
      })

      Repo.insert!(%OrganizationMembership{
        user_id: admin.id,
        organization_id: org.id,
        role: "admin"
      })

      Repo.insert!(%OrganizationMembership{
        user_id: member.id,
        organization_id: org.id,
        role: "member"
      })

      # Non-member belongs to a different org
      Repo.insert!(%OrganizationMembership{
        user_id: non_member.id,
        organization_id: other_org.id,
        role: "member"
      })

      # Reload users with memberships
      owner = Repo.preload(owner, [:organization_memberships], force: true)
      admin = Repo.preload(admin, [:organization_memberships], force: true)
      member = Repo.preload(member, [:organization_memberships], force: true)
      non_member = Repo.preload(non_member, [:organization_memberships], force: true)

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
      org = organization_fixture()
      admin = user_fixture()

      Repo.insert!(%OrganizationMembership{
        user_id: admin.id,
        organization_id: org.id,
        role: "admin"
      })

      admin = Repo.preload(admin, [:organization_memberships], force: true)
      scope = Scope.for_user(admin, current_organization_id: org.id)

      %{org: org, scope: scope}
    end

    test "scope-based authorization works for org settings", %{org: org, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, scope, org)
      assert :ok = Bodyguard.permit(Policy, :manage_settings, scope, org)
    end
  end

  describe "mission settings authorization" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      other_org = organization_fixture()

      # Create users with different roles
      org_admin = user_fixture()
      mission_admin = user_fixture()
      mission_engineer = user_fixture()
      mission_operator = user_fixture()
      mission_viewer = user_fixture()
      non_member = user_fixture()

      # Set up org membership for org admin
      Repo.insert!(%OrganizationMembership{
        user_id: org_admin.id,
        organization_id: org.id,
        role: "admin"
      })

      # Set up org membership for mission members (as regular members)
      for user <- [mission_admin, mission_engineer, mission_operator, mission_viewer] do
        Repo.insert!(%OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: "member"
        })
      end

      # Non-member in different org
      Repo.insert!(%OrganizationMembership{
        user_id: non_member.id,
        organization_id: other_org.id,
        role: "member"
      })

      # Set up mission memberships
      Repo.insert!(%MissionMembership{
        user_id: mission_admin.id,
        mission_id: mission.id,
        role: "admin"
      })

      Repo.insert!(%MissionMembership{
        user_id: mission_engineer.id,
        mission_id: mission.id,
        role: "engineer"
      })

      Repo.insert!(%MissionMembership{
        user_id: mission_operator.id,
        mission_id: mission.id,
        role: "operator"
      })

      Repo.insert!(%MissionMembership{
        user_id: mission_viewer.id,
        mission_id: mission.id,
        role: "viewer"
      })

      # Reload users with memberships
      org_admin = Repo.preload(org_admin, [:organization_memberships], force: true)
      mission_admin = Repo.preload(mission_admin, [:organization_memberships], force: true)
      mission_engineer = Repo.preload(mission_engineer, [:organization_memberships], force: true)
      mission_operator = Repo.preload(mission_operator, [:organization_memberships], force: true)
      mission_viewer = Repo.preload(mission_viewer, [:organization_memberships], force: true)
      non_member = Repo.preload(non_member, [:organization_memberships], force: true)

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
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      engineer = user_fixture()

      Repo.insert!(%OrganizationMembership{
        user_id: engineer.id,
        organization_id: org.id,
        role: "member"
      })

      Repo.insert!(%MissionMembership{
        user_id: engineer.id,
        mission_id: mission.id,
        role: "engineer"
      })

      engineer = Repo.preload(engineer, [:organization_memberships], force: true)
      scope = Scope.for_user(engineer, current_organization_id: org.id)

      %{mission: mission, scope: scope}
    end

    test "scope-based authorization works for mission settings", %{mission: mission, scope: scope} do
      assert :ok = Bodyguard.permit(Policy, :view_settings, scope, mission)
      assert :ok = Bodyguard.permit(Policy, :manage_settings, scope, mission)
    end
  end

  describe "system admin authorization" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Create a system admin (no org memberships needed)
      system_admin = user_fixture()
      system_admin = %{system_admin | system_admin: true}

      scope = %Scope{user: system_admin, system_admin?: true}

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
end
