defmodule Cadence.AccountsNotificationDispatchTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts

  alias Cadence.Accounts.{
    OrganizationInvitationRow,
    Password,
    User,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.Ids
  alias Cadence.Notifications
  alias Cadence.Organizations.Organization
  alias Cadence.Repo

  setup do
    inviter =
      User.new(%{
        user_id: Ids.new("user"),
        email: "admin-#{System.unique_integer([:positive])}@example.com",
        display_name: "Admin",
        capabilities: [:platform_admin],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    {:ok, _} = Repo.insert(UserRow.changeset(inviter))

    org =
      Organization.new(%{
        display_name: "Demo Org",
        slug: "demo-#{System.unique_integer([:positive])}"
      })

    {:ok, persisted_org} = Cadence.Organizations.persist_organization(org)

    {:ok, inviter: inviter, org: persisted_org}
  end

  # Creates a durable (active, confirmed, password-credentialed) user so
  # durable_user_by_email/1 returns {:ok, user} instead of :not_found.
  defp durable_user!(email) do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: email,
        display_name: "Durable User",
        capabilities: [],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    {:ok, _} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password("test-password-123!")

    {:ok, _} =
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

  describe "establish_organization_access/3 notification dispatch" do
    test ":granted branch dispatches :organization_access_granted to existing user", %{
      inviter: admin,
      org: org
    } do
      existing = durable_user!("existing-#{System.unique_integer([:positive])}@example.com")

      assert {:ok, %{mode: :granted}} =
               Accounts.establish_organization_access(existing.email, org.organization_id,
                 membership_role: :member,
                 invited_by_user_id: admin.user_id
               )

      notifications = Cadence.Notifications.list_notifications(existing.user_id)
      assert [%{kind: :organization_access_granted, title: title}] = notifications
      assert title =~ "Demo Org"
    end

    test ":invited with force_invitation=true dispatches :organization_invitation to existing user",
         %{inviter: admin, org: org} do
      existing = durable_user!("existing-#{System.unique_integer([:positive])}@example.com")

      assert {:ok, %{mode: :invited, invitation: inv}} =
               Accounts.establish_organization_access(existing.email, org.organization_id,
                 membership_role: :member,
                 invited_by_user_id: admin.user_id,
                 force_invitation: true
               )

      [notification] = Cadence.Notifications.list_notifications(existing.user_id)
      assert notification.kind == :organization_invitation
      assert notification.metadata["organization_invitation_id"] == inv.organization_invitation_id
    end

    test ":invited without existing user dispatches no notification", %{
      inviter: admin,
      org: org
    } do
      email = "newcomer-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, %{mode: :invited}} =
               Accounts.establish_organization_access(email, org.organization_id,
                 membership_role: :member,
                 invited_by_user_id: admin.user_id
               )

      assert Repo.all(Cadence.Notifications.NotificationRow) == []
    end

    test ":invited with existing non-durable user (e.g. bootstrap admin) still dispatches",
         %{inviter: admin, org: org} do
      email = "bootstrap-#{System.unique_integer([:positive])}@example.com"

      user =
        User.new(%{
          user_id: Ids.new("user"),
          email: email,
          display_name: "Bootstrap",
          capabilities: [:platform_admin],
          confirmed_at: DateTime.utc_now(),
          lifecycle_state: :active,
          metadata: %{}
        })

      {:ok, _} = Repo.insert(UserRow.changeset(user))

      assert {:ok, %{mode: :invited, invitation: invitation}} =
               Accounts.establish_organization_access(email, org.organization_id,
                 membership_role: :organization_admin,
                 invited_by_user_id: admin.user_id
               )

      [notification] = Cadence.Notifications.list_notifications(user.user_id)
      assert notification.kind == :organization_invitation

      assert notification.metadata["organization_invitation_id"] ==
               invitation.organization_invitation_id
    end
  end

  describe "accept_invitation_as_user/2" do
    test "inserts membership, marks invitation accepted, and marks related notifications read",
         %{inviter: admin, org: org} do
      user = durable_user!("recipient-#{System.unique_integer([:positive])}@example.com")

      {:ok, %{invitation: invitation}} =
        Accounts.establish_organization_access(user.email, org.organization_id,
          membership_role: :organization_admin,
          invited_by_user_id: admin.user_id,
          force_invitation: true
        )

      [notification] = Cadence.Notifications.list_notifications(user.user_id, only_unread: true)
      assert notification.kind == :organization_invitation

      :ok = Notifications.subscribe(user.user_id)

      assert {:ok, %{membership: membership}} =
               Accounts.accept_invitation_as_user(
                 user.user_id,
                 invitation.organization_invitation_id
               )

      assert membership.user_id == user.user_id
      assert membership.organization_id == org.organization_id
      assert membership.role == :organization_admin

      row = Repo.get(OrganizationInvitationRow, invitation.organization_invitation_id)
      accepted = OrganizationInvitationRow.to_domain(row)
      assert accepted.status == :accepted
      assert accepted.accepted_by_user_id == user.user_id

      assert_receive {:invitation_accepted, %{organization_invitation_id: id}}
      assert id == invitation.organization_invitation_id

      reloaded = Cadence.Notifications.list_notifications(user.user_id)
      assert Enum.all?(reloaded, fn n -> n.read_at != nil end)
    end

    test "returns :email_mismatch if user's email doesn't match", %{inviter: admin, org: org} do
      invitee = durable_user!("invitee-#{System.unique_integer([:positive])}@example.com")
      other = durable_user!("other-#{System.unique_integer([:positive])}@example.com")

      {:ok, %{invitation: invitation}} =
        Accounts.establish_organization_access(invitee.email, org.organization_id,
          membership_role: :member,
          invited_by_user_id: admin.user_id,
          force_invitation: true
        )

      assert {:error, :email_mismatch} =
               Accounts.accept_invitation_as_user(
                 other.user_id,
                 invitation.organization_invitation_id
               )
    end

    test "returns :invitation_not_found for unknown id", %{inviter: _admin, org: _org} do
      user = durable_user!("x-#{System.unique_integer([:positive])}@example.com")

      assert {:error, :invitation_not_found} =
               Accounts.accept_invitation_as_user(user.user_id, "orginvite_missing")
    end

    test "returns :user_not_found for unknown user id" do
      assert {:error, :user_not_found} =
               Accounts.accept_invitation_as_user("user_missing", "orginvite_whatever")
    end
  end
end
