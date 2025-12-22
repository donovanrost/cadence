defmodule Cadence.Domain.Organizations.Entities.OrganizationTest do
  use Cadence.PureCase

  alias Cadence.Domain.Organizations.Entities.Organization
  alias Cadence.Domain.Organizations.ValueObjects.OrganizationStatus
  alias Cadence.Domain.Organizations.ValueObjects.SubscriptionTier

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Test Organization",
        slug: "test-org-#{unique_integer()}"
      },
      overrides
    )
  end

  describe "new/1" do
    test "creates an organization with valid attributes" do
      attrs = valid_attrs()
      assert {:ok, org} = Organization.new(attrs)

      assert org.name == attrs.name
      assert org.slug == attrs.slug
      assert org.status == :active
      assert org.subscription_tier == :free
    end

    test "sets default status to active" do
      assert {:ok, org} = Organization.new(valid_attrs())
      assert org.status == :active
    end

    test "sets default tier to free" do
      assert {:ok, org} = Organization.new(valid_attrs())
      assert org.subscription_tier == :free
    end

    test "creates quotas from tier defaults" do
      assert {:ok, org} = Organization.new(valid_attrs())
      assert org.quotas.max_missions == 5
      assert org.quotas.max_users == 10
    end

    test "allows custom quotas" do
      attrs = valid_attrs(%{max_missions: 50, max_users: 100})
      assert {:ok, org} = Organization.new(attrs)
      assert org.quotas.max_missions == 50
      assert org.quotas.max_users == 100
    end

    test "allows custom tier" do
      attrs = valid_attrs(%{subscription_tier: :enterprise})
      assert {:ok, org} = Organization.new(attrs)
      assert org.subscription_tier == :enterprise
      # Enterprise tier has higher defaults
      assert org.quotas.max_missions == 100
    end

    test "fails with missing name" do
      attrs = valid_attrs() |> Map.delete(:name)
      assert {:error, {:missing_fields, [:name]}} = Organization.new(attrs)
    end

    test "fails with missing slug" do
      attrs = valid_attrs() |> Map.delete(:slug)
      assert {:error, {:missing_fields, [:slug]}} = Organization.new(attrs)
    end

    test "fails with invalid slug format" do
      attrs = valid_attrs(%{slug: "Invalid Slug!"})
      assert {:error, :invalid_slug_format} = Organization.new(attrs)
    end

    test "fails with empty name" do
      attrs = valid_attrs(%{name: ""})
      assert {:error, :name_too_short} = Organization.new(attrs)
    end
  end

  describe "update/2" do
    test "updates organization name" do
      {:ok, org} = Organization.new(valid_attrs())
      assert {:ok, updated} = Organization.update(org, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "merges settings" do
      {:ok, org} = Organization.new(valid_attrs(%{settings: %{a: 1}}))
      assert {:ok, updated} = Organization.update(org, %{settings: %{b: 2}})
      assert updated.settings == %{a: 1, b: 2}
    end

    test "does not change slug" do
      {:ok, org} = Organization.new(valid_attrs())
      original_slug = org.slug
      assert {:ok, updated} = Organization.update(org, %{slug: "new-slug"})
      # Slug should remain unchanged (update ignores slug)
      assert updated.slug == original_slug
    end
  end

  describe "status transitions" do
    test "suspend/1 transitions active to suspended" do
      {:ok, org} = Organization.new(valid_attrs())
      assert {:ok, suspended} = Organization.suspend(org)
      assert suspended.status == :suspended
    end

    test "reactivate/1 transitions suspended to active" do
      {:ok, org} = Organization.new(valid_attrs(%{status: :suspended}))
      assert {:ok, active} = Organization.reactivate(org)
      assert active.status == :active
    end

    test "terminate/1 transitions to terminated" do
      {:ok, org} = Organization.new(valid_attrs())
      assert {:ok, terminated} = Organization.terminate(org)
      assert terminated.status == :terminated
    end

    test "cannot transition from terminated" do
      {:ok, org} = Organization.new(valid_attrs(%{status: :terminated}))
      assert {:error, {:invalid_transition, :terminated, :active}} = Organization.reactivate(org)
    end
  end

  describe "quota checks" do
    test "check_mission_quota/2 returns :ok when under quota" do
      {:ok, org} = Organization.new(valid_attrs())
      assert :ok = Organization.check_mission_quota(org, 3)
    end

    test "check_mission_quota/2 returns error when at quota" do
      {:ok, org} = Organization.new(valid_attrs())
      # Default is 5 missions for free tier
      assert {:error, :quota_exceeded} = Organization.check_mission_quota(org, 5)
    end

    test "check_user_quota/2 returns :ok when under quota" do
      {:ok, org} = Organization.new(valid_attrs())
      assert :ok = Organization.check_user_quota(org, 5)
    end

    test "check_user_quota/2 returns error when at quota" do
      {:ok, org} = Organization.new(valid_attrs())
      # Default is 10 users for free tier
      assert {:error, :quota_exceeded} = Organization.check_user_quota(org, 10)
    end
  end

  describe "predicates" do
    test "active?/1 returns true for active organizations" do
      {:ok, org} = Organization.new(valid_attrs())
      assert Organization.active?(org) == true
    end

    test "active?/1 returns false for suspended organizations" do
      {:ok, org} = Organization.new(valid_attrs(%{status: :suspended}))
      assert Organization.active?(org) == false
    end

    test "terminated?/1 returns true for terminated organizations" do
      {:ok, org} = Organization.new(valid_attrs(%{status: :terminated}))
      assert Organization.terminated?(org) == true
    end
  end
end
