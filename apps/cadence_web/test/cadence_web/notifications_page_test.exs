defmodule CadenceWeb.NotificationsPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.{Accounts, Notifications}
  alias Cadence.Notifications.Notification
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    %{user: user, conn: TestFixtures.member_conn(user)}
  end

  test "user-scoped core inbox works without membership and ignores foreign identity parameters",
       c do
    own = notification!(c.user)
    other = TestFixtures.persist_user!()
    foreign = notification!(other)

    {:ok, view, _} =
      live(c.conn, "/notifications?user_id=#{other.user_id}&organization_id=foreign")

    assert has_element?(view, "#application-shell")
    assert page(view)["user_id"] == c.user.user_id
    assert Enum.map(page(view)["data"]["notifications"], & &1["id"]) == [own.notification_id]
    refute Enum.any?(page(view)["data"]["notifications"], &(&1["id"] == foreign.notification_id))
    assert Accounts.list_user_memberships(c.user.user_id) == []
  end

  test "read action refreshes inbox and unread count and PubSub supplies a new own notification",
       c do
    own = notification!(c.user)
    {:ok, view, _} = live(c.conn, "/notifications?unread=true")
    assert snapshot(view)["context"]["unread_count"] == 1
    act(view, "mark_notification_read", own.notification_id, "/notifications?unread=true")
    assert page(view)["data"]["notifications"] == []
    assert {:ok, read} = Notifications.fetch_notification(own.notification_id)
    assert read.read_at != nil
    next = notification!(c.user)
    assert Enum.map(page(view)["data"]["notifications"], & &1["id"]) == [next.notification_id]
    assert snapshot(view)["context"]["unread_count"] == 1
  end

  test "accepting a read invitation uses authoritative status and grants the recipient membership",
       c do
    org = TestFixtures.persist_org!()

    assert {:ok, %{invitation: invitation}} =
             Accounts.establish_organization_access(c.user.email, org.organization_id,
               invited_by_user_id: c.user.user_id,
               force_invitation: true
             )

    [notification] = Notifications.list_notifications(c.user.user_id)

    assert {:ok, _} =
             Notifications.mark_notification_read(notification.notification_id, c.user.user_id)

    {:ok, view, _} = live(c.conn, "/notifications")
    assert hd(page(view)["data"]["notifications"])["invitation_status"] == "pending"
    act(view, "accept_invitation", notification.notification_id)
    assert {:ok, membership} = Accounts.fetch_user_membership(c.user.user_id, org.organization_id)
    assert membership.lifecycle_state == :active

    assert Cadence.Repo.get!(
             Cadence.Accounts.OrganizationInvitationRow,
             invitation.organization_invitation_id
           ).status == "accepted"

    assert hd(page(view)["data"]["notifications"])["invitation_status"] == "accepted"
  end

  test "foreign notification, stale token and actions after leaving inbox cannot mutate", c do
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(c.user, org)
    own = notification!(c.user)
    foreign = notification!(TestFixtures.persist_user!())
    {:ok, view, _} = live(c.conn, "/notifications")
    token = page(view)["action_token"]
    act(view, "mark_notification_read", foreign.notification_id)

    render_hook(view, "host:notifications", %{
      "path" => "/notifications",
      "token" => "foreign",
      "event" => "mark_notification_read",
      "input" => %{"notification_id" => own.notification_id}
    })

    render_hook(view, "host:context", %{"path" => "/notifications?unread=true"})
    assert page(view)["action_token"] != token

    render_hook(view, "host:notifications", %{
      "path" => "/notifications?unread=true",
      "token" => token,
      "event" => "mark_notification_read",
      "input" => %{"notification_id" => own.notification_id}
    })

    current_token = page(view)["action_token"]
    render_hook(view, "host:context", %{"path" => "/"})
    assert page(view) == nil

    render_hook(view, "host:notifications", %{
      "path" => "/notifications?unread=true",
      "token" => current_token,
      "event" => "mark_notification_read",
      "input" => %{"notification_id" => own.notification_id}
    })

    for n <- [own, foreign] do
      assert {:ok, unread} = Notifications.fetch_notification(n.notification_id)
      assert unread.read_at == nil
    end
  end

  test "revoked sessions cannot act or refresh and anonymous requests redirect", c do
    own = notification!(c.user)
    {:ok, view, _} = live(c.conn, "/notifications")
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    act(view, "mark_notification_read", own.notification_id)
    assert_redirect(view, "/sign-in")
    assert {:ok, unread} = Notifications.fetch_notification(own.notification_id)
    assert unread.read_at == nil
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), "/notifications")
  end

  defp snapshot(view), do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
  defp page(view), do: snapshot(view)["notifications_page"]

  defp act(view, event, id, path \\ "/notifications") do
    render_hook(view, "host:notifications", %{
      "path" => path,
      "token" => page(view)["action_token"],
      "event" => event,
      "input" => %{"notification_id" => id}
    })
  end

  defp notification!(user) do
    {:ok, n} =
      Notifications.persist_notification(
        Notification.new(%{
          user_id: user.user_id,
          kind: :organization_access_granted,
          title: "Access granted"
        })
      )

    n
  end
end
