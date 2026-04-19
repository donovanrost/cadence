defmodule Cadence.NotificationsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.Ids
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias Cadence.Persistence.Schemas.UserRow
  alias Cadence.Repo

  setup do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: "recipient-#{System.unique_integer([:positive])}@example.com",
        display_name: "Recipient",
        capabilities: [],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    {:ok, _} = Repo.insert(UserRow.changeset(user))
    {:ok, user: user}
  end

  defp build_notification(user, overrides \\ []) do
    Notification.new(
      Enum.into(overrides, %{
        user_id: user.user_id,
        kind: :organization_invitation,
        title: "Invitation to Demo Org",
        body: "As member",
        metadata: %{"invitation_id" => "orginv_x"}
      })
    )
  end

  test "persist_notification inserts, returns the domain struct, and broadcasts", %{user: user} do
    :ok = Notifications.subscribe(user.user_id)
    notification = build_notification(user)

    assert {:ok, %Notification{} = persisted} = Notifications.persist_notification(notification)
    assert persisted.notification_id == notification.notification_id
    assert persisted.kind == :organization_invitation
    assert Notification.unread?(persisted)

    assert_receive {:notification_created, %Notification{notification_id: id}}
    assert id == notification.notification_id
  end

  test "list_notifications returns recent-first, filters by user, honors only_unread and limit",
       %{user: user} do
    other = user_fixture()
    {:ok, a} = Notifications.persist_notification(build_notification(user, title: "A"))
    {:ok, b} = Notifications.persist_notification(build_notification(user, title: "B"))
    {:ok, _} = Notifications.persist_notification(build_notification(other, title: "Other"))

    ids = Enum.map(Notifications.list_notifications(user.user_id), & &1.notification_id)
    assert ids == [b.notification_id, a.notification_id]

    limited = Notifications.list_notifications(user.user_id, limit: 1)
    assert length(limited) == 1

    {:ok, _} = Notifications.mark_notification_read(a.notification_id, user.user_id)
    unread = Notifications.list_notifications(user.user_id, only_unread: true)
    assert Enum.map(unread, & &1.notification_id) == [b.notification_id]
  end

  test "count_unread_notifications excludes read and other users", %{user: user} do
    other = user_fixture()
    {:ok, n1} = Notifications.persist_notification(build_notification(user))
    {:ok, _} = Notifications.persist_notification(build_notification(user))
    {:ok, _} = Notifications.persist_notification(build_notification(other))

    assert Notifications.count_unread_notifications(user.user_id) == 2

    {:ok, _} = Notifications.mark_notification_read(n1.notification_id, user.user_id)

    assert Notifications.count_unread_notifications(user.user_id) == 1
  end

  test "mark_notification_read enforces ownership and broadcasts", %{user: user} do
    other = user_fixture()
    {:ok, notification} = Notifications.persist_notification(build_notification(user))

    :ok = Notifications.subscribe(user.user_id)

    assert {:error, :forbidden} =
             Notifications.mark_notification_read(notification.notification_id, other.user_id)

    assert {:ok, updated} =
             Notifications.mark_notification_read(notification.notification_id, user.user_id)

    refute Notification.unread?(updated)
    assert_receive {:notification_updated, %Notification{notification_id: id}}
    assert id == notification.notification_id
  end

  test "mark_notification_read on already-read notification is a no-op that returns the current state",
       %{user: user} do
    {:ok, notification} = Notifications.persist_notification(build_notification(user))
    {:ok, _} = Notifications.mark_notification_read(notification.notification_id, user.user_id)

    assert {:ok, still_read} =
             Notifications.mark_notification_read(notification.notification_id, user.user_id)

    refute Notification.unread?(still_read)
  end

  test "fetch_notification returns :not_found for unknown id" do
    assert {:error, :not_found} = Notifications.fetch_notification("notif_missing")
  end

  defp user_fixture do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: "other-#{System.unique_integer([:positive])}@example.com",
        display_name: "Other",
        capabilities: [],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    {:ok, _} = Repo.insert(UserRow.changeset(user))
    user
  end
end
