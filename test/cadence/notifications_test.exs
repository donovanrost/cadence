defmodule Cadence.NotificationsTest do
  use Cadence.PureCase, async: false

  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryNotificationRepository

  describe "create_notification/1" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      user_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{user_id: user_id, org_id: org_id}
    end

    test "creates a notification with valid attrs", %{user_id: user_id, org_id: org_id} do
      attrs = %{
        user_id: user_id,
        organization_id: org_id,
        type: "procedure_submitted",
        title: "New procedure",
        body: "A new procedure has been submitted",
        severity: "info",
        resource_type: "procedure_version",
        resource_id: Ecto.UUID.generate()
      }

      assert {:ok, %Notification{} = notification} = Notifications.create_notification(attrs)
      assert notification.user_id == user_id
      assert notification.organization_id == org_id
      assert notification.type == "procedure_submitted"
      assert notification.title == "New procedure"
      assert notification.severity == "info"
      assert is_nil(notification.read_at)
      assert is_nil(notification.archived_at)
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Notifications.create_notification(%{})
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).organization_id
      assert "can't be blank" in errors_on(changeset).type
      assert "can't be blank" in errors_on(changeset).title
    end
  end

  describe "list_unread/2" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      user_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{user_id: user_id, org_id: org_id}
    end

    test "returns unread notifications for user", %{user_id: user_id, org_id: org_id} do
      # Create some notifications
      _n1 = notification_fixture(user_id: user_id, org_id: org_id, title: "First")
      _n2 = notification_fixture(user_id: user_id, org_id: org_id, title: "Second")

      # Mark one as read
      n3 = notification_fixture(user_id: user_id, org_id: org_id, title: "Third")
      Notifications.mark_read(n3)

      notifications = Notifications.list_unread(user_id)
      assert length(notifications) == 2
      titles = Enum.map(notifications, & &1.title)
      assert "First" in titles
      assert "Second" in titles
      refute "Third" in titles
    end

    test "respects limit option", %{user_id: user_id, org_id: org_id} do
      for i <- 1..5 do
        notification_fixture(user_id: user_id, org_id: org_id, title: "Notification #{i}")
      end

      notifications = Notifications.list_unread(user_id, limit: 3)
      assert length(notifications) == 3
    end
  end

  describe "list_inbox/2" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      user_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{user_id: user_id, org_id: org_id}
    end

    test "returns both read and unread notifications", %{user_id: user_id, org_id: org_id} do
      _n1 = notification_fixture(user_id: user_id, org_id: org_id, title: "Unread")
      n2 = notification_fixture(user_id: user_id, org_id: org_id, title: "Read")
      Notifications.mark_read(n2)

      notifications = Notifications.list_inbox(user_id)
      assert length(notifications) == 2
    end

    test "excludes archived notifications", %{user_id: user_id, org_id: org_id} do
      _n1 = notification_fixture(user_id: user_id, org_id: org_id, title: "Not archived")
      n2 = notification_fixture(user_id: user_id, org_id: org_id, title: "Archived")
      Notifications.archive(n2)

      notifications = Notifications.list_inbox(user_id)
      assert length(notifications) == 1
      assert hd(notifications).title == "Not archived"
    end
  end

  describe "unread_count/2" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      user_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{user_id: user_id, org_id: org_id}
    end

    test "returns correct count", %{user_id: user_id, org_id: org_id} do
      assert Notifications.unread_count(user_id) == 0

      notification_fixture(user_id: user_id, org_id: org_id)
      assert Notifications.unread_count(user_id) == 1

      notification_fixture(user_id: user_id, org_id: org_id)
      assert Notifications.unread_count(user_id) == 2
    end

    test "excludes read notifications", %{user_id: user_id, org_id: org_id} do
      n1 = notification_fixture(user_id: user_id, org_id: org_id)
      _n2 = notification_fixture(user_id: user_id, org_id: org_id)

      Notifications.mark_read(n1)
      assert Notifications.unread_count(user_id) == 1
    end
  end

  describe "mark_read/1" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      notification = notification_fixture()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{notification: notification}
    end

    test "marks notification as read", %{notification: notification} do
      assert is_nil(notification.read_at)

      {:ok, updated} = Notifications.mark_read(notification)
      assert not is_nil(updated.read_at)
    end

    test "accepts notification id", %{notification: notification} do
      {:ok, updated} = Notifications.mark_read(notification.id)
      assert not is_nil(updated.read_at)
    end
  end

  describe "mark_all_read/2" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      user_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{user_id: user_id, org_id: org_id}
    end

    test "marks all unread notifications as read", %{user_id: user_id, org_id: org_id} do
      notification_fixture(user_id: user_id, org_id: org_id)
      notification_fixture(user_id: user_id, org_id: org_id)
      notification_fixture(user_id: user_id, org_id: org_id)

      assert Notifications.unread_count(user_id) == 3

      {:ok, count} = Notifications.mark_all_read(user_id)
      assert count == 3
      assert Notifications.unread_count(user_id) == 0
    end
  end

  describe "archive/1" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      notification = notification_fixture()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{notification: notification}
    end

    test "archives notification", %{notification: notification} do
      assert is_nil(notification.archived_at)

      {:ok, updated} = Notifications.archive(notification)
      assert not is_nil(updated.archived_at)
    end
  end

  describe "preferences" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)

      user_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        InMemoryNotificationRepository.stop()
      end)

      %{user_id: user_id}
    end

    test "get_preferences/3 returns defaults when no preference exists", %{user_id: user_id} do
      prefs = Notifications.get_preferences(user_id, "procedure_submitted")

      assert prefs.in_app_enabled == true
      assert prefs.email_enabled == true
      assert prefs.email_frequency == "immediate"
    end

    test "set_preferences/4 creates new preference", %{user_id: user_id} do
      attrs = %{in_app_enabled: false, email_enabled: true, email_frequency: "daily_digest"}

      {:ok, pref} = Notifications.set_preferences(user_id, "procedure_submitted", attrs)

      assert pref.in_app_enabled == false
      assert pref.email_enabled == true
      assert pref.email_frequency == "daily_digest"
    end

    test "set_preferences/4 updates existing preference", %{user_id: user_id} do
      # Create initial preference
      {:ok, _} =
        Notifications.set_preferences(user_id, "procedure_submitted", %{
          in_app_enabled: true,
          email_enabled: true
        })

      # Update it
      {:ok, pref} =
        Notifications.set_preferences(user_id, "procedure_submitted", %{
          email_frequency: "weekly_digest"
        })

      assert pref.email_frequency == "weekly_digest"
    end

    test "get_preferences/3 returns stored preference", %{user_id: user_id} do
      {:ok, _} =
        Notifications.set_preferences(user_id, "procedure_approved", %{
          in_app_enabled: false,
          email_enabled: true,
          email_frequency: "daily_digest"
        })

      prefs = Notifications.get_preferences(user_id, "procedure_approved")

      assert prefs.in_app_enabled == false
      assert prefs.email_enabled == true
      assert prefs.email_frequency == "daily_digest"
    end

    test "list_preferences/2 returns all user preferences", %{user_id: user_id} do
      {:ok, _} =
        Notifications.set_preferences(user_id, "procedure_submitted", %{in_app_enabled: true})

      {:ok, _} =
        Notifications.set_preferences(user_id, "procedure_approved", %{in_app_enabled: false})

      prefs = Notifications.list_preferences(user_id)
      assert length(prefs) == 2
    end
  end

  describe "pubsub" do
    setup do
      {:ok, _} = InMemoryNotificationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      user_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :notification_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryNotificationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{user_id: user_id, org_id: org_id}
    end

    test "subscribe/1 subscribes to user notifications", %{user_id: user_id} do
      Notifications.subscribe(user_id)

      # This just tests that it doesn't crash
      assert true
    end

    test "creating notification broadcasts to subscriber", %{user_id: user_id, org_id: org_id} do
      Notifications.subscribe(user_id)

      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user_id,
          organization_id: org_id,
          type: "procedure_submitted",
          title: "Test",
          resource_type: "procedure_version",
          resource_id: Ecto.UUID.generate()
        })

      assert_receive {:event, {:notification_created, ^notification}}
    end
  end

  defp notification_fixture(opts \\ []) do
    user_id = Keyword.get(opts, :user_id, Ecto.UUID.generate())
    org_id = Keyword.get(opts, :org_id, Ecto.UUID.generate())
    title = Keyword.get(opts, :title, "Notification #{System.unique_integer([:positive])}")

    attrs = %{
      user_id: user_id,
      organization_id: org_id,
      type: "procedure_submitted",
      title: title,
      severity: "info",
      resource_type: "procedure_version",
      resource_id: Ecto.UUID.generate()
    }

    {:ok, notification} = Notifications.create_notification(attrs)
    notification
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
