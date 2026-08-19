defmodule CadenceWeb.NotificationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Accounts
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias CadenceWeb.TestFixtures

  defp user_and_conn do
    user = TestFixtures.persist_user!()
    conn = TestFixtures.member_conn(user)
    {user, conn}
  end

  defp admin_fixture do
    user = TestFixtures.persist_user!(capabilities: [:platform_admin])
    user
  end

  defp create_invitation_and_notification(user, role \\ :member) do
    admin = admin_fixture()
    org = TestFixtures.persist_org!(display_name: "Demo Org")

    {:ok, %{invitation: invitation}} =
      Accounts.establish_organization_access(user.email, org.organization_id,
        membership_role: role,
        invited_by_user_id: admin.user_id,
        force_invitation: true
      )

    [notification] =
      user.user_id
      |> Cadence.Notifications.list_notifications()
      |> Enum.filter(&(&1.kind == :organization_invitation))

    {org, invitation, notification}
  end

  describe "render" do
    test "renders empty state when there are no notifications" do
      {_user, conn} = user_and_conn()

      {:ok, _view, html} = live(conn, ~p"/notifications")

      assert html =~ "No notifications"
      assert html =~ "All caught up"
    end

    test "renders invitation card with Accept button" do
      {user, conn} = user_and_conn()
      _ = create_invitation_and_notification(user)

      {:ok, _view, html} = live(conn, ~p"/notifications")

      assert html =~ "Invitation to join Demo Org"
      assert html =~ "Accept"
    end
  end

  describe "accept_invitation event" do
    test "accepts the invitation, flashes success, and navigates to /" do
      {user, conn} = user_and_conn()

      {_org, _invitation, notification} =
        create_invitation_and_notification(user, :organization_admin)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      view
      |> element("button[phx-value-notification_id='#{notification.notification_id}']", "Accept")
      |> render_click()

      assert_redirect(view, "/")

      # Membership exists
      assert Cadence.Accounts.preferred_organization_membership(user.user_id) |> elem(1)
    end

    test "flashes error if the invitation is already accepted" do
      {user, conn} = user_and_conn()
      {_org, invitation, notification} = create_invitation_and_notification(user)

      # Accept directly via the domain.
      assert {:ok, _} =
               Cadence.Accounts.accept_invitation_as_user(
                 user.user_id,
                 invitation.organization_invitation_id
               )

      {:ok, view, _html} = live(conn, ~p"/notifications")

      # Send the event directly — the notification is already read so no button is rendered.
      html =
        render_click(view, "accept_invitation", %{
          "notification_id" => notification.notification_id
        })

      assert html =~ "no longer available" or html =~ "already been taken"
    end
  end

  describe "real-time handlers" do
    test "a new notification appears in the list via PubSub" do
      {user, conn} = user_and_conn()

      {:ok, view, _html} = live(conn, ~p"/notifications")
      assert render(view) =~ "No notifications"

      {:ok, n} =
        Notifications.persist_notification(
          Notification.new(%{
            user_id: user.user_id,
            kind: :organization_access_granted,
            title: "Granted access",
            metadata: %{}
          })
        )

      # Wait for the PubSub message to propagate.
      _ = render(view)
      assert render(view) =~ "Granted access"
      assert n.kind == :organization_access_granted
    end
  end
end
