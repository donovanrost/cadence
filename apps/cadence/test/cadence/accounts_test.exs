defmodule Cadence.AccountsTest do
  use Cadence.DataCase, async: true

  alias Cadence.Accounts

  alias Cadence.Accounts.{
    EnvironmentAdminPolicy,
    OrganizationMembership,
    OrganizationMembershipRow,
    Password,
    User,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Repo

  @environment_admin_email "environment-admin@example.com"
  @environment_admin_password "environment-admin-password-123"

  describe "sign_in/2" do
    test "durable user with only a password credential can sign in" do
      password = "durable-password-123"
      persist_durable_user!(email: "ops@example.com", password: password)

      assert {:ok, session} = Accounts.sign_in("ops@example.com", password)
      assert is_binary(session.session_token)
    end

    test "durable user with wrong password fails with :invalid_credentials" do
      persist_durable_user!(email: "ops@example.com", password: "correct")

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "wrong")
    end

    test "unconfirmed durable user fails with :invalid_credentials" do
      persist_durable_user!(email: "ops@example.com", password: "pw-123", confirmed_at: nil)

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "pw-123")
    end

    test "inactive durable user fails with :invalid_credentials" do
      persist_durable_user!(
        email: "ops@example.com",
        password: "pw-123",
        lifecycle_state: :disabled
      )

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "pw-123")
    end

    test "environment admin with configured credentials signs in directly to admin mode" do
      assert {:ok, _user} =
               Cadence.Auth.reconcile_environment_admin(environment_admin_policy())

      assert {:ok, session} =
               Accounts.sign_in(@environment_admin_email, @environment_admin_password)

      assert is_binary(session.session_token)
      assert session.admin_mode?
    end

    test "environment admin with wrong password fails with :invalid_credentials" do
      assert {:ok, _user} =
               Cadence.Auth.reconcile_environment_admin(environment_admin_policy())

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@environment_admin_email, "wrong")
    end

    test "disabling the environment admin rejects its credentials and existing sessions" do
      assert {:ok, _user} =
               Cadence.Auth.reconcile_environment_admin(environment_admin_policy())

      assert {:ok, session} =
               Accounts.sign_in(@environment_admin_email, @environment_admin_password)

      assert {:ok, nil} =
               Cadence.Auth.reconcile_environment_admin(
                 EnvironmentAdminPolicy.from_config(enabled: false)
               )

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@environment_admin_email, @environment_admin_password)

      assert {:error, :unauthenticated} =
               Accounts.authenticate_user_session(session.session_token)
    end

    test "environment admin reconciliation never elevates a durable user with the same email" do
      durable_user =
        persist_durable_user!(
          email: @environment_admin_email,
          password: "durable-password-123",
          capabilities: []
        )

      assert {:error, %Ecto.Changeset{}} =
               Cadence.Auth.reconcile_environment_admin(environment_admin_policy())

      assert {:ok, unchanged_user} = Accounts.fetch_user(durable_user.user_id)
      refute :platform_admin in unchanged_user.capabilities
    end

    test "email not found fails with :invalid_credentials" do
      assert {:error, :invalid_credentials} =
               Accounts.sign_in("nobody@example.com", "anything")
    end
  end

  describe "list_user_memberships/1" do
    test "returns active memberships with organizations, ordered by organization display_name" do
      user = persist_user!()
      org_b = persist_organization!(display_name: "Beta Space")
      org_a = persist_organization!(display_name: "Alpha Space")
      grant_membership!(user, org_a)
      grant_membership!(user, org_b)

      result = Cadence.Accounts.list_user_memberships(user.user_id)

      assert [
               %{membership: m1, organization: %{display_name: "Alpha Space"}},
               %{membership: m2, organization: %{display_name: "Beta Space"}}
             ] = result

      assert m1.user_id == user.user_id
      assert m2.user_id == user.user_id
      assert m1.lifecycle_state == :active
      assert m2.lifecycle_state == :active
    end

    test "excludes revoked memberships" do
      user = persist_user!()
      org_active = persist_organization!(display_name: "Active Co")
      org_revoked = persist_organization!(display_name: "Revoked Co")
      grant_membership!(user, org_active)
      grant_membership!(user, org_revoked, lifecycle_state: :revoked)

      result = Cadence.Accounts.list_user_memberships(user.user_id)

      assert [%{organization: %{display_name: "Active Co"}}] = result
    end

    test "returns empty list for a user with no memberships" do
      user = persist_user!()
      assert Cadence.Accounts.list_user_memberships(user.user_id) == []
    end
  end

  describe "fetch_user_membership/2" do
    test "returns {:ok, membership} for an active membership" do
      user = persist_user!()
      org = persist_organization!(display_name: "Fetch Co")
      _ = grant_membership!(user, org)

      assert {:ok, membership} =
               Cadence.Accounts.fetch_user_membership(user.user_id, org.organization_id)

      assert membership.user_id == user.user_id
      assert membership.organization_id == org.organization_id
      assert membership.lifecycle_state == :active
    end

    test "returns {:error, :not_found} for a revoked membership" do
      user = persist_user!()
      org = persist_organization!(display_name: "Revoked")
      _ = grant_membership!(user, org, lifecycle_state: :revoked)

      assert {:error, :not_found} =
               Cadence.Accounts.fetch_user_membership(user.user_id, org.organization_id)
    end

    test "returns {:error, :not_found} when the user is not a member" do
      user = persist_user!()
      org = persist_organization!(display_name: "Empty")

      assert {:error, :not_found} =
               Cadence.Accounts.fetch_user_membership(user.user_id, org.organization_id)
    end

    test "returns {:error, :not_found} for a mismatched user_id" do
      user_a = persist_user!()
      user_b = persist_user!()
      org = persist_organization!(display_name: "Cross User")
      _ = grant_membership!(user_a, org)

      assert {:error, :not_found} =
               Cadence.Accounts.fetch_user_membership(user_b.user_id, org.organization_id)
    end
  end

  describe "preferred_organization_membership/2 with multiple active memberships" do
    test "returns the oldest active membership when current_organization_id is nil" do
      user = persist_user!()
      org_later = persist_organization!(display_name: "Later Org")
      org_earlier = persist_organization!(display_name: "Earlier Org")

      # Grant the earlier membership first so inserted_at orders it first.
      _ = grant_membership!(user, org_earlier)
      _ = grant_membership!(user, org_later)

      assert {:ok, membership} =
               Cadence.Accounts.preferred_organization_membership(user.user_id, nil)

      assert membership.organization_id == org_earlier.organization_id
    end

    test "returns the passed current_organization_id's membership when present and active" do
      user = persist_user!()
      org_a = persist_organization!(display_name: "Org A")
      org_b = persist_organization!(display_name: "Org B")
      _ = grant_membership!(user, org_a)
      _ = grant_membership!(user, org_b)

      assert {:ok, membership} =
               Cadence.Accounts.preferred_organization_membership(
                 user.user_id,
                 org_b.organization_id
               )

      assert membership.organization_id == org_b.organization_id
    end

    test "falls back to any active membership when the passed organization_id is not a match" do
      user = persist_user!()
      org_active = persist_organization!(display_name: "Active Org")
      _ = grant_membership!(user, org_active)

      other_org = persist_organization!(display_name: "Other")

      assert {:ok, membership} =
               Cadence.Accounts.preferred_organization_membership(
                 user.user_id,
                 other_org.organization_id
               )

      assert membership.organization_id == org_active.organization_id
    end
  end

  ## Fixtures

  defp environment_admin_policy do
    EnvironmentAdminPolicy.from_config(
      enabled: true,
      email: @environment_admin_email,
      display_name: "Environment Admin",
      password: @environment_admin_password
    )
  end

  defp persist_durable_user!(opts) when is_list(opts) do
    password = Keyword.fetch!(opts, :password)
    email = Keyword.fetch!(opts, :email)
    confirmed_at = Keyword.get(opts, :confirmed_at, DateTime.utc_now())
    lifecycle_state = Keyword.get(opts, :lifecycle_state, :active)

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: Keyword.get(opts, :display_name, "Durable User"),
        capabilities: Keyword.get(opts, :capabilities, []),
        confirmed_at: confirmed_at,
        lifecycle_state: lifecycle_state,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  defp persist_user!(opts \\ []) do
    email = Keyword.get(opts, :email, "user-#{System.unique_integer([:positive])}@example.com")
    display_name = Keyword.get(opts, :display_name, "Test User")

    user =
      User.new(%{
        email: email,
        display_name: display_name,
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active
      })

    {:ok, _row} = Repo.insert(UserRow.changeset(user))

    user
  end

  defp persist_organization!(opts) when is_list(opts) do
    display_name = Keyword.fetch!(opts, :display_name)

    slug =
      Keyword.get(opts, :slug, "org-#{System.unique_integer([:positive])}")

    organization =
      Organization.new(%{
        display_name: display_name,
        slug: slug
      })

    {:ok, persisted_organization} = Cadence.Organizations.persist_organization(organization)
    persisted_organization
  end

  defp grant_membership!(user, organization, opts \\ []) do
    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: Keyword.get(opts, :role, :member),
        lifecycle_state: Keyword.get(opts, :lifecycle_state, :active)
      })

    {:ok, _row} = Repo.insert(OrganizationMembershipRow.changeset(membership))

    membership
  end
end
