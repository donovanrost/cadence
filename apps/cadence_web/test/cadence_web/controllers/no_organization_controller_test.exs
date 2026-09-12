defmodule CadenceWeb.NoOrganizationControllerTest do
  use CadenceWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cadence.Accounts
  alias Cadence.Accounts.OrganizationInvitationRow
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "an authenticated recipient without invitations gets the versioned empty page" do
    user = TestFixtures.persist_user!()
    page = no_organization_page(TestFixtures.member_conn(user))
    assert page["version"] == 1
    assert page["pending_invitations_count"] == 0
    assert is_binary(page["csrf_token"]) and page["csrf_token"] != ""
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

  test "unauthenticated requests require sign-in", %{conn: conn} do
    assert redirected_to(get(conn, "/no-organization")) == "/sign-in"
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

  defp no_organization_page(conn) do
    {:ok, view, _} = live(conn, "/no-organization")
    vue = Test.get_vue(view, id: "no-organization-page-component")
    assert vue.component == "NoOrganizationPage"
    assert vue.ssr == false
    assert vue.handlers == %{}
    vue.props["page"]
  end
end
