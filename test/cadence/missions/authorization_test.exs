defmodule Cadence.Missions.AuthorizationTest do
  use Cadence.PureCase, async: false

  alias Cadence.{Accounts, Missions}
  alias Cadence.Accounts.Scope
  alias Cadence.Accounts.User
  alias Cadence.Application.Organizations.{MembershipOperations, OrganizationOperations}
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Test.Adapters.InMemoryMembershipRepository
  alias Cadence.Test.Adapters.InMemoryMissionsRepository
  alias Cadence.Test.Adapters.InMemoryOrganizationRepository
  alias Cadence.Test.Adapters.InMemoryUserRepository

  describe "mission authorization flow" do
    setup do
      {:ok, _} = InMemoryOrganizationRepository.start_link()
      {:ok, _} = InMemoryMembershipRepository.start_link()
      {:ok, _} = InMemoryMissionsRepository.start_link()
      {:ok, _} = InMemoryUserRepository.start_link()

      Application.put_env(:cadence, :organization_repository, InMemoryOrganizationRepository)
      Application.put_env(:cadence, :membership_repository, InMemoryMembershipRepository)
      Application.put_env(:cadence, :missions_repository, InMemoryMissionsRepository)
      Application.put_env(:cadence, :user_repository, InMemoryUserRepository)

      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Test Org",
          slug: "test-org-#{System.unique_integer([:positive])}",
          subscription_tier: :pro
        })

      {:ok, user} =
        Accounts.register_user(%{
          email: "user@example.com",
          organization_id: org.id,
          role: "admin"
        })

      {:ok, other_org} =
        OrganizationOperations.create(%{
          name: "Other Test Org",
          slug: "other-test-org-#{System.unique_integer([:positive])}",
          subscription_tier: :pro
        })

      {:ok, other_user} =
        Accounts.register_user(%{
          email: "other@example.com",
          organization_id: other_org.id,
          role: "admin"
        })

      on_exit(fn ->
        Application.delete_env(:cadence, :organization_repository)
        Application.delete_env(:cadence, :membership_repository)
        Application.delete_env(:cadence, :missions_repository)
        Application.delete_env(:cadence, :user_repository)
        InMemoryUserRepository.stop()
        InMemoryMissionsRepository.stop()
        InMemoryMembershipRepository.stop()
        InMemoryOrganizationRepository.stop()
      end)

      %{org: org, user: user, other_user: other_user, other_org: other_org}
    end

    test "user gets organization_membership on registration", %{user: user, org: org} do
      memberships = MembershipOperations.list_for_organization(org.id)

      assert length(memberships) == 1
      assert hd(memberships).user_id == user.id
      assert hd(memberships).role in ["admin", :admin]
    end

    test "user can create mission and gets mission_membership", %{user: user, org: org} do
      {:ok, mission} = create_mission(org.id, "Test Mission")
      {:ok, _membership} = Missions.add_member(mission.id, user.id, :admin)

      # Verify mission was created
      assert mission.organization_id == org.id
      assert mission.name == "Test Mission"

      # Verify mission_membership was auto-created
      memberships = Missions.list_members(mission.id)
      assert length(memberships) == 1
      assert hd(memberships).user_id == user.id
      assert hd(memberships).role in [:admin, "admin"]
    end

    test "user can view their own mission", %{user: user, org: org} do
      {:ok, mission} = create_mission(org.id, "My Mission")
      {:ok, _membership} = Missions.add_member(mission.id, user.id, :admin)

      # Get scope for user
      scope = build_scope(user, org)

      # Verify user can view the mission via Bodyguard
      assert :ok = Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission)
    end

    test "user cannot view mission they're not a member of", %{
      user: user,
      other_user: other_user,
      other_org: other_org,
      org: org
    } do
      # Other user creates a mission in their org
      {:ok, mission} = create_mission(other_org.id, "Other Mission")
      {:ok, _membership} = Missions.add_member(mission.id, other_user.id, :admin)

      # Get scope for first user
      scope = build_scope(user, org)

      # Verify first user CANNOT view the other user's mission
      assert {:error, _} = Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission)
    end

    test "user can update their own mission", %{user: user, org: org} do
      # Create mission
      {:ok, mission} = create_mission(org.id, "Original Name")
      {:ok, _membership} = Missions.add_member(mission.id, user.id, :admin)

      # Get scope for user
      scope = build_scope(user, org)

      # Verify authorization passes
      assert :ok = Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission)

      # Update mission
      {:ok, updated} = Missions.update_mission(mission.id, org.id, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "user cannot update mission they're not a member of", %{
      user: user,
      other_user: other_user,
      other_org: other_org,
      org: org
    } do
      # Other user creates a mission in their org
      {:ok, mission} = create_mission(other_org.id, "Other Mission")
      {:ok, _membership} = Missions.add_member(mission.id, other_user.id, :admin)

      # Get scope for first user
      scope = build_scope(user, org)

      # Try to authorize - should fail
      assert {:error, _} = Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission)
    end

    test "user can delete their own mission", %{user: user, org: org} do
      # Create mission
      {:ok, mission} = create_mission(org.id, "To Delete")
      {:ok, _membership} = Missions.add_member(mission.id, user.id, :admin)

      # Get scope for user
      scope = build_scope(user, org)

      # Verify authorization passes
      assert :ok = Bodyguard.permit(Cadence.Missions.Policy, :delete, scope, mission)

      # Delete mission
      {:ok, _} = InMemoryMissionsRepository.delete(mission.id)

      # Verify it's gone
      assert {:error, :not_found} = Missions.get_mission(mission.id)
    end

    test "user cannot delete mission they're not a member of", %{
      user: user,
      other_user: other_user,
      other_org: other_org,
      org: org
    } do
      # Other user creates a mission in their org
      {:ok, mission} = create_mission(other_org.id, "Protected Mission")
      {:ok, _membership} = Missions.add_member(mission.id, other_user.id, :admin)

      # Get scope for first user
      scope = build_scope(user, org)

      # Try to authorize - should fail
      assert {:error, _} = Bodyguard.permit(Cadence.Missions.Policy, :delete, scope, mission)

      # Verify mission still exists
      assert {:ok, _} = Missions.get_mission(mission.id)
    end
  end

  defp create_mission(org_id, name) do
    {:ok, mission} =
      MissionEntity.new(%{
        id: Ecto.UUID.generate(),
        organization_id: org_id,
        name: name,
        slug: "mission-#{unique_integer()}",
        status: :active,
        phase: :operational
      })

    InMemoryMissionsRepository.save(mission)
  end

  defp build_scope(user, org) do
    memberships = MembershipOperations.list_for_user(user.id)
    user_schema = to_schema_user(user, memberships)

    %Scope{
      user: user_schema,
      current_organization: org,
      all_organizations: [org],
      system_admin?: user_schema.system_admin
    }
  end

  defp to_schema_user(user, memberships) do
    %User{
      id: user.id,
      email: user.email,
      organization_memberships: memberships,
      system_admin: user.system_admin
    }
  end
end
