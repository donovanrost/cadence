defmodule Cadence.OrganizationsTest do
  use Cadence.DataCase, async: true

  import Cadence.OrganizationsFixtures

  alias Cadence.Organizations
  alias Cadence.Organizations.Organization

  describe "organizations" do
    test "list_organizations/0 returns all organizations" do
      org = organization_fixture()
      assert Organizations.list_organizations() == [org]
    end

    test "get_organization!/1 returns the organization with given id" do
      org = organization_fixture()
      assert Organizations.get_organization!(org.id).id == org.id
    end

    test "get_organization_by_slug/1 returns organization by slug" do
      org = organization_fixture(slug: "test-org")
      assert Organizations.get_organization_by_slug("test-org").id == org.id
    end

    test "create_organization/1 with valid data creates an organization" do
      valid_attrs = %{
        name: "Test Organization",
        slug: "test-org",
        status: "active"
      }

      assert {:ok, %Organization{} = org} = Organizations.create_organization(valid_attrs)
      assert org.name == "Test Organization"
      assert org.slug == "test-org"
      assert org.status == "active"
    end

    test "create_organization/1 with invalid data returns error changeset" do
      invalid_attrs = %{name: nil, slug: nil}
      assert {:error, %Ecto.Changeset{}} = Organizations.create_organization(invalid_attrs)
    end

    test "update_organization/2 with valid data updates the organization" do
      org = organization_fixture()
      update_attrs = %{name: "Updated Name"}

      assert {:ok, %Organization{} = org} = Organizations.update_organization(org, update_attrs)
      assert org.name == "Updated Name"
    end

    test "delete_organization/1 deletes the organization" do
      org = organization_fixture()
      assert {:ok, %Organization{}} = Organizations.delete_organization(org)
      assert_raise Ecto.NoResultsError, fn -> Organizations.get_organization!(org.id) end
    end

    test "change_organization/1 returns an organization changeset" do
      org = organization_fixture()
      assert %Ecto.Changeset{} = Organizations.change_organization(org)
    end
  end

  describe "quota management" do
    test "check_mission_quota/1 returns :ok when under quota" do
      org = organization_fixture(max_missions: 5)
      assert :ok = Organizations.check_mission_quota(org)
    end

    test "check_mission_quota/1 returns error when at quota" do
      org = organization_fixture(max_missions: 1)

      # Create a mission to reach the quota
      {:ok, _mission} =
        Cadence.Missions.create_mission(%{
          organization_id: org.id,
          name: "Test Mission",
          slug: "test-mission",
          status: "active"
        })

      assert {:error, :quota_exceeded} = Organizations.check_mission_quota(org)
    end

    test "check_user_quota/1 returns :ok when under quota" do
      org = organization_fixture(max_users: 10)
      assert :ok = Organizations.check_user_quota(org)
    end

    test "get_organization_stats/1 returns usage statistics" do
      org = organization_fixture(max_missions: 5, max_users: 10)
      stats = Organizations.get_organization_stats(org)

      assert stats.mission_count == 0
      assert stats.mission_quota == 5
      assert stats.user_count == 0
      assert stats.user_quota == 10
    end
  end
end
