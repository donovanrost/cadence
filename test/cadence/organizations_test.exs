defmodule Cadence.OrganizationsTest do
  use Cadence.PureCase, async: false

  alias Cadence.Application.Organizations.OrganizationOperations
  alias Cadence.Application.Organizations.OrganizationQueries
  alias Cadence.Application.Organizations.QuotaService
  alias Cadence.Domain.Organizations.Entities.Organization
  alias Cadence.Test.Adapters.InMemoryOrganizationRepository

  setup do
    {:ok, _} = InMemoryOrganizationRepository.start_link()
    Application.put_env(:cadence, :organization_repository, InMemoryOrganizationRepository)

    on_exit(fn ->
      Application.delete_env(:cadence, :organization_repository)
      InMemoryOrganizationRepository.stop()
    end)

    :ok
  end

  describe "organizations" do
    test "list_organizations/0 returns all organizations" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Test Org",
          slug: "test-org"
        })

      organizations = OrganizationQueries.list()
      assert length(organizations) == 1
      assert hd(organizations).id == org.id
    end

    test "get_organization!/1 returns the organization with given id" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Test Org",
          slug: "test-org"
        })

      assert {:ok, found} = OrganizationQueries.find(org.id)
      assert found.id == org.id
    end

    test "get_organization_by_slug/1 returns organization by slug" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Test Org",
          slug: "test-org"
        })

      assert {:ok, found} = OrganizationQueries.find_by_slug("test-org")
      assert found.id == org.id
    end

    test "create_organization/1 with valid data creates an organization" do
      valid_attrs = %{
        name: "Test Organization",
        slug: "test-org",
        status: :active
      }

      assert {:ok, %Organization{} = org} = OrganizationOperations.create(valid_attrs)
      assert org.name == "Test Organization"
      assert org.slug == "test-org"
      assert org.status == :active
    end

    test "create_organization/1 with invalid data returns error changeset" do
      invalid_attrs = %{name: nil, slug: nil}

      assert {:error, {:missing_fields, missing}} = OrganizationOperations.create(invalid_attrs)
      assert :name in missing
      assert :slug in missing
    end

    test "update_organization/2 with valid data updates the organization" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Test Org",
          slug: "test-org"
        })

      update_attrs = %{name: "Updated Name"}

      assert {:ok, %Organization{} = updated} =
               OrganizationOperations.update(org.id, update_attrs)

      assert updated.name == "Updated Name"
    end

    test "delete_organization/1 deletes the organization" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Test Org",
          slug: "test-org"
        })

      assert {:ok, %Organization{}} = OrganizationOperations.delete(org.id)
      assert {:error, :not_found} = OrganizationQueries.find(org.id)
    end
  end

  describe "quota management" do
    test "check_mission_quota/1 returns :ok when under quota" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Quota Org",
          slug: "quota-org",
          max_missions: 5
        })

      InMemoryOrganizationRepository.set_mission_count(org.id, 0)

      assert :ok = QuotaService.check_mission_quota(org.id)
    end

    test "check_mission_quota/1 returns error when at quota" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Quota Org",
          slug: "quota-org",
          max_missions: 1
        })

      InMemoryOrganizationRepository.set_mission_count(org.id, 1)

      assert {:error, :quota_exceeded} = QuotaService.check_mission_quota(org.id)
    end

    test "check_user_quota/1 returns :ok when under quota" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Quota Org",
          slug: "quota-org",
          max_users: 10
        })

      InMemoryOrganizationRepository.set_user_count(org.id, 0)

      assert :ok = QuotaService.check_user_quota(org.id)
    end

    test "get_organization_stats/1 returns usage statistics" do
      {:ok, org} =
        OrganizationOperations.create(%{
          name: "Quota Org",
          slug: "quota-org",
          max_missions: 5,
          max_users: 10
        })

      InMemoryOrganizationRepository.set_mission_count(org.id, 0)
      InMemoryOrganizationRepository.set_user_count(org.id, 0)

      assert {:ok, stats} = OrganizationQueries.get_stats(org.id)

      assert stats.mission_count == 0
      assert stats.mission_quota == 5
      assert stats.user_count == 0
      assert stats.user_quota == 10
    end
  end
end
