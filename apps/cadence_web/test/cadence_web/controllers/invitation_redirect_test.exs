defmodule CadenceWeb.InvitationRedirectTest do
  use CadenceWeb.ConnCase, async: true

  import Ecto.Changeset, only: [change: 2]

  alias Cadence.Accounts.OrganizationInvitationRow
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  # L5: the page's GET goes to the console's invitation screen (the page itself is gone, #79).
  test "GET goes to the console's invitation screen with the token, whatever its state", %{
    conn: conn
  } do
    %{path: path} = invitation_fixture()
    token = String.replace_prefix(path, "/invitations/", "")
    assert redirected_to(get(conn, path)) == "/console/invitations/" <> token

    expired = invitation_fixture()

    expired.row
    |> change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert redirected_to(get(recycle(conn), expired.path)) =~ "/console/invitations/"

    assert redirected_to(get(recycle(conn), "/invitations/not-a-valid-token")) ==
             "/console/invitations/not-a-valid-token"
  end

  defp invitation_fixture(email \\ nil) do
    inviter = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Cadence Operations")

    assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: invitation_token}} =
             Cadence.Accounts.establish_organization_access(
               email || "invitee-#{System.unique_integer([:positive])}@example.com",
               organization.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: inviter.user_id,
               display_name: "Invited Operator",
               force_invitation: true
             )

    %{
      path: "/invitations/#{invitation_token}",
      row: Repo.get!(OrganizationInvitationRow, invitation.organization_invitation_id)
    }
  end
end
