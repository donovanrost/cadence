defmodule Cadence.NotificationsTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{User, UserRow}
  alias Cadence.Ids
  alias Cadence.Notifications
  alias Cadence.Notifications.{Notification, NotificationRow}
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

  describe "listed notices (#709: the console lists organization_access_granted only)" do
    defp granted(user, org \\ "Acme") do
      {:ok, n} =
        Notifications.persist_notification(
          build_notification(user,
            kind: :organization_access_granted,
            title: "You were added to #{org}",
            metadata: %{
              "organization_id" => "org_#{org}",
              "organization_display_name" => org,
              "membership_role" => "member"
            }
          )
        )

      n
    end

    test "a page lists only the listed kinds, the person's own, newest first", %{user: user} do
      other = user_fixture()
      first = granted(user, "Acme")
      second = granted(user, "Borealis")
      {:ok, _invitation} = Notifications.persist_notification(build_notification(user))
      granted(other)

      assert {:ok, %{entries: entries, next_cursor: nil}} =
               Notifications.listed_page(user.user_id)

      assert Enum.map(entries, & &1.notification_id) == [
               second.notification_id,
               first.notification_id
             ]
    end

    test "pages by cursor without repeating or skipping, ties broken by id", %{user: user} do
      ids = for i <- 1..5, do: granted(user, "Org#{i}").notification_id
      at = ~U[2026-11-27 10:00:00.000000Z]

      Repo.update_all(from(n in NotificationRow, where: n.notification_id in ^ids),
        set: [inserted_at: at]
      )

      walk = fn walk, cursor, seen ->
        {:ok, page} = Notifications.listed_page(user.user_id, cursor: cursor, limit: 2)
        seen = seen ++ Enum.map(page.entries, & &1.notification_id)
        if page.next_cursor, do: walk.(walk, page.next_cursor, seen), else: seen
      end

      seen = walk.(walk, nil, [])
      assert length(seen) == 5
      assert Enum.sort(seen) == Enum.sort(ids)
    end

    test "refuses a cursor it didn't make", %{user: user} do
      assert {:error, :invalid_cursor} = Notifications.listed_page(user.user_id, cursor: "nope")

      forged = Base.url_encode64(Jason.encode!(["not a time", "notif_x"]), padding: false)
      assert {:error, :invalid_cursor} = Notifications.listed_page(user.user_id, cursor: forged)
    end

    test "the unread count counts exactly the listed, unread rows", %{user: user} do
      a = granted(user)
      granted(user)
      {:ok, _invitation} = Notifications.persist_notification(build_notification(user))
      granted(user_fixture())

      assert Notifications.listed_unread_count(user.user_id) == 2
      {:ok, _} = Notifications.mark_listed_read(user.user_id, a.notification_id)
      assert Notifications.listed_unread_count(user.user_id) == 1
    end

    test "Mark read is the owner's, of a listed kind, and idempotent", %{user: user} do
      notice = granted(user)
      {:ok, invitation} = Notifications.persist_notification(build_notification(user))
      other = user_fixture()

      assert {:error, :not_found} =
               Notifications.mark_listed_read(other.user_id, notice.notification_id)

      assert {:error, :not_found} =
               Notifications.mark_listed_read(user.user_id, invitation.notification_id)

      assert {:error, :not_found} = Notifications.mark_listed_read(user.user_id, "notif_missing")

      assert {:ok, read} = Notifications.mark_listed_read(user.user_id, notice.notification_id)
      refute Notification.unread?(read)
      assert {:ok, again} = Notifications.mark_listed_read(user.user_id, notice.notification_id)
      assert again.read_at == read.read_at
    end
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
