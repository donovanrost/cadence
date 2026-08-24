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
  alias Phoenix.LiveView.JS

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

  defp persist_notification!(user, attrs) do
    notification =
      attrs
      |> Map.put(:user_id, user.user_id)
      |> Map.put_new(:metadata, %{})
      |> Notification.new()

    assert {:ok, persisted} = Notifications.persist_notification(notification)
    persisted
  end

  defp notification_prop(vue, notification_id) do
    Enum.find(vue.props["notifications"], fn notification ->
      notification["notification_id"] == notification_id
    end)
  end

  describe "render" do
    test "renders empty state when there are no notifications" do
      {_user, conn} = user_and_conn()

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notifications-page")
      assert has_element?(view, "#notifications-empty-state", "No notifications")
      assert has_element?(view, "#notifications-empty-state", "All caught up")
      refute has_element?(view, "#notifications-panel-component")
    end

    test "renders invitation data and existing actions through LiveVue" do
      {user, conn} = user_and_conn()
      {_org, _invitation, notification} = create_invitation_and_notification(user)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notifications-panel-component")
      refute has_element?(view, "#notifications-empty-state")

      vue = LiveVue.Test.get_vue(view, id: "notifications-panel-component")
      notification_prop = notification_prop(vue, notification.notification_id)

      assert vue.component == "NotificationsPanel"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert notification_prop == %{
               "action" => "accept_invitation",
               "action_label" => "Accept",
               "body" => "As Member",
               "id" => "notification-#{notification.notification_id}",
               "kind" => "organization_invitation",
               "notification_id" => notification.notification_id,
               "state_label" => nil,
               "title" => "Invitation to join Demo Org",
               "unread" => true
             }

      assert vue.handlers == %{
               "accept-invitation" => JS.push("accept_invitation"),
               "mark-read" => JS.push("mark_read")
             }
    end
  end

  describe "accept_invitation event" do
    test "accepts the invitation, flashes success, and navigates to /" do
      {user, conn} = user_and_conn()

      {_org, _invitation, notification} =
        create_invitation_and_notification(user, :organization_admin)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      render_click(view, "accept_invitation", %{
        "notification_id" => notification.notification_id
      })

      {"/", flash} = assert_redirect(view)
      assert flash["info"] == "Joined Demo Org."

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
      vue = LiveVue.Test.get_vue(view, id: "notifications-panel-component")
      notification_prop = notification_prop(vue, notification.notification_id)

      assert notification_prop["unread"] == false
      assert notification_prop["action"] == nil
      assert notification_prop["state_label"] == "Accepted"

      render_click(view, "accept_invitation", %{
        "notification_id" => notification.notification_id
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "That invitation is no longer available."
             )
    end
  end

  describe "mark_read event" do
    test "marks an owned notification read and updates its Vue prop" do
      {user, conn} = user_and_conn()

      notification =
        persist_notification!(user, %{
          kind: :organization_access_granted,
          title: "Granted access",
          body: "As Member"
        })

      {:ok, view, _html} = live(conn, ~p"/notifications")

      initial_vue = LiveVue.Test.get_vue(view, id: "notifications-panel-component")
      initial_prop = notification_prop(initial_vue, notification.notification_id)

      assert initial_prop["unread"] == true
      assert initial_prop["action"] == "mark_read"
      assert initial_prop["action_label"] == "Mark read"

      render_click(view, "mark_read", %{"notification_id" => notification.notification_id})

      assert {:ok, updated} = Notifications.fetch_notification(notification.notification_id)
      refute is_nil(updated.read_at)

      updated_vue = LiveVue.Test.get_vue(view, id: "notifications-panel-component")
      updated_prop = notification_prop(updated_vue, notification.notification_id)

      assert updated_prop["unread"] == false
      assert updated_prop["action"] == nil
      assert updated_prop["action_label"] == nil
    end
  end

  describe "real-time handlers" do
    test "a new notification appears in the list via PubSub" do
      {user, conn} = user_and_conn()

      {:ok, view, _html} = live(conn, ~p"/notifications")
      assert has_element?(view, "#notifications-empty-state")

      n =
        persist_notification!(user, %{
          kind: :organization_access_granted,
          title: "Granted access"
        })

      # Wait for the PubSub message to propagate.
      _ = render(view)

      assert has_element?(view, "#notifications-panel-component")
      refute has_element?(view, "#notifications-empty-state")

      vue = LiveVue.Test.get_vue(view, id: "notifications-panel-component")
      notification_prop = notification_prop(vue, n.notification_id)

      assert notification_prop["title"] == "Granted access"
      assert notification_prop["unread"] == true
      assert n.kind == :organization_access_granted
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/notifications")
    end
  end
end
