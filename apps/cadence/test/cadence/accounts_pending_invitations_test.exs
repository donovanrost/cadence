defmodule Cadence.AccountsPendingInvitationsTest do
  use Cadence.DataCase, async: true
  alias Cadence.Accounts
  alias Cadence.Accounts.{OrganizationInvitation, OrganizationInvitationRow, User, UserRow}
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization

  test "counts every usable recipient invitation without depending on notification paging" do
    user = user!("recipient")
    other = user!("other")

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{
          organization_id: "org-pending",
          slug: "pending",
          display_name: "Pending"
        })
      )

    for i <- 1..125, do: invitation!(org, user, "pending-#{i}")
    invitation!(org, other, "foreign")
    invitation!(org, user, "expired-by-time", "pending", DateTime.add(DateTime.utc_now(), -60))
    for status <- ~w(accepted revoked expired), do: invitation!(org, user, status, status)
    assert Accounts.count_pending_invitations_for_user(user.user_id) == 125
    assert Accounts.count_pending_invitations_for_user(other.user_id) == 1
    assert Accounts.count_pending_invitations_for_user("missing") == 0
  end

  test "recipient email and account state come from the current persisted user" do
    user = user!("recipient")

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{
          organization_id: "org-current",
          slug: "current",
          display_name: "Current"
        })
      )

    invitation!(org, user, "invitation")
    assert Accounts.count_pending_invitations_for_user(user.user_id) == 1
    row = Repo.get!(UserRow, user.user_id)
    row |> Ecto.Changeset.change(lifecycle_state: "disabled") |> Repo.update!()
    assert Accounts.count_pending_invitations_for_user(user.user_id) == 0

    Repo.get!(UserRow, user.user_id)
    |> Ecto.Changeset.change(lifecycle_state: "active", email: "changed@example.test")
    |> Repo.update!()

    assert Accounts.count_pending_invitations_for_user(user.user_id) == 0
  end

  defp user!(id) do
    user = User.new(%{user_id: id, email: "#{id}@example.test", display_name: id})
    Repo.insert!(UserRow.changeset(user))
    user
  end

  defp invitation!(
         org,
         user,
         id,
         status \\ "pending",
         expires \\ DateTime.add(DateTime.utc_now(), 3600)
       ) do
    invitation =
      OrganizationInvitation.new(%{
        organization_invitation_id: id,
        organization_id: org.organization_id,
        email: user.email,
        invited_by_user_id: user.user_id,
        status: status,
        membership_role: :member,
        grant_platform_admin: false,
        token_digest: "digest-#{id}",
        token_hint: "hint",
        expires_at: expires
      })

    Repo.insert!(OrganizationInvitationRow.changeset(invitation))
  end
end
