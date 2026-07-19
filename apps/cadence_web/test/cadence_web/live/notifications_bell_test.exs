defmodule CadenceWeb.NotificationsBellTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias CadenceWeb.NotificationsBell
  alias CadenceWeb.TestFixtures

  defp socket_for(user) do
    {:ok, scope} = Cadence.Auth.authenticate_api_token(TestFixtures.member_session_token!(user))
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: scope, flash: %{}}}
  end

  defp build_notification(user, overrides) do
    Notification.new(
      Enum.into(overrides, %{
        user_id: user.user_id,
        kind: :organization_invitation,
        title: "Invite",
        metadata: %{}
      })
    )
  end

  test "attach populates zero count and empty list when no user in scope" do
    socket =
      NotificationsBell.attach(%Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}})

    assert socket.assigns.unread_notifications_count == 0
    assert socket.assigns.recent_notifications == []
  end

  test "attach assigns current count and recent notifications for authenticated user" do
    user = TestFixtures.persist_user!()
    {:ok, _} = Notifications.persist_notification(build_notification(user, title: "A"))
    {:ok, _} = Notifications.persist_notification(build_notification(user, title: "B"))

    socket = NotificationsBell.attach(socket_for(user))

    assert socket.assigns.unread_notifications_count == 2
    assert length(socket.assigns.recent_notifications) == 2
    titles = Enum.map(socket.assigns.recent_notifications, & &1.title)
    assert "A" in titles and "B" in titles
  end
end
