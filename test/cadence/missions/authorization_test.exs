defmodule Cadence.Missions.AuthorizationTest do
  use Cadence.DataCase

  alias Cadence.{Accounts, Organizations, Missions}
  alias Cadence.Accounts.Scope

  describe "mission authorization flow" do
    setup do
      # Create organization
      {:ok, org} =
        Organizations.create_organization(%{
          name: "Test Org",
          slug: "test-org-#{System.unique_integer([:positive])}",
          status: "active",
          subscription_tier: "pro"
        })

      # Create user with organization membership
      {:ok, user} =
        Accounts.register_user(%{
          email: "user@example.com",
          organization_id: org.id,
          role: "admin"
        })

      # Create another organization for other_user
      {:ok, other_org} =
        Organizations.create_organization(%{
          name: "Other Test Org",
          slug: "other-test-org-#{System.unique_integer([:positive])}",
          status: "active",
          subscription_tier: "pro"
        })

      # Create another user in a DIFFERENT organization
      {:ok, other_user} =
        Accounts.register_user(%{
          email: "other@example.com",
          organization_id: other_org.id,
          role: "admin"
        })

      %{org: org, user: user, other_user: other_user, other_org: other_org}
    end

    test "user gets organization_membership on registration", %{user: user, org: org} do
      memberships = Organizations.list_organization_memberships(org.id)

      assert length(memberships) == 1
      assert hd(memberships).user_id == user.id
      assert hd(memberships).role == "admin"
    end

    test "user can create mission and gets mission_membership", %{user: user, org: org} do
      # Create mission with creator_user_id
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Test Mission",
          slug: "test-mission-#{System.unique_integer([:positive])}",
          description: "Test mission",
          status: "active",
          creator_user_id: user.id
        })

      # Verify mission was created
      assert mission.organization_id == org.id
      assert mission.name == "Test Mission"

      # Verify mission_membership was auto-created
      memberships = Missions.list_mission_memberships(mission)
      assert length(memberships) == 1
      assert hd(memberships).user_id == user.id
      assert hd(memberships).role == "admin"
    end

    test "user can view their own mission", %{user: user, org: org} do
      # Create mission
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "My Mission",
          slug: "my-mission-#{System.unique_integer([:positive])}",
          status: "active",
          creator_user_id: user.id
        })

      # Get scope for user
      scope = Scope.for_user(user)

      # Verify user can view the mission
      assert {:ok, _mission} = Missions.get_mission_authorized(mission.id, scope)
    end

    test "user cannot view mission they're not a member of", %{
      user: user,
      other_user: other_user,
      other_org: other_org
    } do
      # Other user creates a mission in their org
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: other_org.id,
          name: "Other Mission",
          slug: "other-mission-#{System.unique_integer([:positive])}",
          status: "active",
          creator_user_id: other_user.id
        })

      # Get scope for first user
      scope = Scope.for_user(user)

      # Verify first user CANNOT view the other user's mission
      assert {:error, :unauthorized} = Missions.get_mission_authorized(mission.id, scope)
    end

    test "user can update their own mission", %{user: user, org: org} do
      # Create mission
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Original Name",
          slug: "original-#{System.unique_integer([:positive])}",
          status: "active",
          creator_user_id: user.id
        })

      # Get scope for user
      scope = Scope.for_user(user)

      # Update mission
      {:ok, updated} = Missions.update_mission_authorized(mission, %{name: "Updated Name"}, scope)

      assert updated.name == "Updated Name"
    end

    test "user cannot update mission they're not a member of", %{
      user: user,
      other_user: other_user,
      other_org: other_org
    } do
      # Other user creates a mission in their org
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: other_org.id,
          name: "Other Mission",
          slug: "other-mission-#{System.unique_integer([:positive])}",
          status: "active",
          creator_user_id: other_user.id
        })

      # Get scope for first user
      scope = Scope.for_user(user)

      # Try to update - should fail
      assert {:error, :unauthorized} =
               Missions.update_mission_authorized(mission, %{name: "Hacked"}, scope)
    end

    test "user can delete their own mission", %{user: user, org: org} do
      # Create mission
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "To Delete",
          slug: "to-delete-#{System.unique_integer([:positive])}",
          status: "active",
          creator_user_id: user.id
        })

      # Get scope for user
      scope = Scope.for_user(user)

      # Delete mission
      {:ok, _deleted} = Missions.delete_mission_authorized(mission, scope)

      # Verify it's gone
      assert_raise Ecto.NoResultsError, fn ->
        Missions.get_mission!(mission.id)
      end
    end

    test "user cannot delete mission they're not a member of", %{
      user: user,
      other_user: other_user,
      other_org: other_org
    } do
      # Other user creates a mission in their org
      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: other_org.id,
          name: "Protected Mission",
          slug: "protected-#{System.unique_integer([:positive])}",
          status: "active",
          creator_user_id: other_user.id
        })

      # Get scope for first user
      scope = Scope.for_user(user)

      # Try to delete - should fail
      assert {:error, :unauthorized} = Missions.delete_mission_authorized(mission, scope)

      # Verify mission still exists
      assert Missions.get_mission!(mission.id)
    end
  end
end
