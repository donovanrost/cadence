defmodule CadenceWeb.NoOrganizationControllerTest do
  @moduledoc """
  /no-organization now redirects to the console's screen (L5); the pending-invitation count the
  old page showed is the console session's `pending_invitations_count` (L21), checked here.
  """
  use CadenceWeb.ConnCase, async: true
  alias Cadence.Accounts
  alias Cadence.Accounts.OrganizationInvitationRow
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  test "an authenticated recipient goes to the console's screen, with no invitations counted" do
    user = TestFixtures.persist_user!()
    conn = user |> TestFixtures.member_conn() |> get("/no-organization")
    assert redirected_to(conn) == "/console/no-organization"
    assert no_organization_page(TestFixtures.member_conn(user))["pending_invitations_count"] == 0
  end

  test "reading an invitation notification does not hide a pending invitation" do
    user = TestFixtures.persist_user!()
    invitation!(user)
    assert [notification] = Notifications.list_notifications(user.user_id)

    assert {:ok, _} =
             Notifications.mark_notification_read(notification.notification_id, user.user_id)

    assert no_organization_page(TestFixtures.member_conn(user))["pending_invitations_count"] == 1
  end

  test "notification badges do not substitute for usable invitations" do
    user = TestFixtures.persist_user!()
    expired = invitation!(user)
    revoked = invitation!(user)

    Repo.get!(OrganizationInvitationRow, expired.organization_invitation_id)
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60))
    |> Repo.update!()

    Repo.get!(OrganizationInvitationRow, revoked.organization_invitation_id)
    |> Ecto.Changeset.change(status: "revoked")
    |> Repo.update!()

    assert {:ok, _} =
             Notifications.persist_notification(
               Notification.new(%{
                 user_id: user.user_id,
                 kind: :organization_invitation,
                 title: "Old invitation",
                 metadata: %{}
               })
             )

    assert no_organization_page(TestFixtures.member_conn(user))["pending_invitations_count"] == 0
    invitation!(user)
    invitation!(user)
    assert no_organization_page(TestFixtures.member_conn(user))["pending_invitations_count"] == 2
  end

  test "signed out, it goes to the console's screen too (which sends you to sign in)", %{
    conn: conn
  } do
    assert redirected_to(get(conn, "/no-organization")) == "/console/no-organization"
  end

  defp invitation!(user) do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()

    assert {:ok, %{invitation: invitation}} =
             Accounts.establish_organization_access(user.email, org.organization_id,
               force_invitation: true,
               invited_by_user_id: admin.user_id
             )

    invitation
  end

  # What the console's no-organization screen reads.
  defp no_organization_page(conn),
    do: conn |> get("/api/console/v1/session") |> json_response(200) |> Map.fetch!("data")
end
