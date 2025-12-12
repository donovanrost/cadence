defmodule Cadence.NotificationsTest do
  use Cadence.DataCase, async: true

  import Cadence.AccountsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.NotificationsFixtures

  alias Cadence.Notifications
  alias Cadence.Notifications.Notification

  describe "create_notification/1" do
    setup do
      user = user_fixture()
      org = organization_fixture()
      %{user: user, org: org}
    end

    test "creates a notification with valid attrs", %{user: user, org: org} do
      attrs = %{
        user_id: user.id,
        organization_id: org.id,
        type: "procedure_submitted",
        title: "New procedure",
        body: "A new procedure has been submitted",
        severity: "info",
        resource_type: "procedure_version",
        resource_id: Ecto.UUID.generate()
      }

      assert {:ok, %Notification{} = notification} = Notifications.create_notification(attrs)
      assert notification.user_id == user.id
      assert notification.organization_id == org.id
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
      user = user_fixture()
      org = organization_fixture()
      %{user: user, org: org}
    end

    test "returns unread notifications for user", %{user: user, org: org} do
      # Create some notifications
      _n1 = notification_fixture(user: user, organization: org, title: "First")
      _n2 = notification_fixture(user: user, organization: org, title: "Second")

      # Mark one as read
      n3 = notification_fixture(user: user, organization: org, title: "Third")
      Notifications.mark_read(n3)

      notifications = Notifications.list_unread(user.id)
      assert length(notifications) == 2
      titles = Enum.map(notifications, & &1.title)
      assert "First" in titles
      assert "Second" in titles
      refute "Third" in titles
    end

    test "respects limit option", %{user: user, org: org} do
      for i <- 1..5 do
        notification_fixture(user: user, organization: org, title: "Notification #{i}")
      end

      notifications = Notifications.list_unread(user.id, limit: 3)
      assert length(notifications) == 3
    end
  end

  describe "list_inbox/2" do
    setup do
      user = user_fixture()
      org = organization_fixture()
      %{user: user, org: org}
    end

    test "returns both read and unread notifications", %{user: user, org: org} do
      _n1 = notification_fixture(user: user, organization: org, title: "Unread")
      n2 = notification_fixture(user: user, organization: org, title: "Read")
      Notifications.mark_read(n2)

      notifications = Notifications.list_inbox(user.id)
      assert length(notifications) == 2
    end

    test "excludes archived notifications", %{user: user, org: org} do
      _n1 = notification_fixture(user: user, organization: org, title: "Not archived")
      n2 = notification_fixture(user: user, organization: org, title: "Archived")
      Notifications.archive(n2)

      notifications = Notifications.list_inbox(user.id)
      assert length(notifications) == 1
      assert hd(notifications).title == "Not archived"
    end
  end

  describe "unread_count/2" do
    setup do
      user = user_fixture()
      org = organization_fixture()
      %{user: user, org: org}
    end

    test "returns correct count", %{user: user, org: org} do
      assert Notifications.unread_count(user.id) == 0

      notification_fixture(user: user, organization: org)
      assert Notifications.unread_count(user.id) == 1

      notification_fixture(user: user, organization: org)
      assert Notifications.unread_count(user.id) == 2
    end

    test "excludes read notifications", %{user: user, org: org} do
      n1 = notification_fixture(user: user, organization: org)
      _n2 = notification_fixture(user: user, organization: org)

      Notifications.mark_read(n1)
      assert Notifications.unread_count(user.id) == 1
    end
  end

  describe "mark_read/1" do
    setup do
      user = user_fixture()
      org = organization_fixture()
      notification = notification_fixture(user: user, organization: org)
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
      user = user_fixture()
      org = organization_fixture()
      %{user: user, org: org}
    end

    test "marks all unread notifications as read", %{user: user, org: org} do
      notification_fixture(user: user, organization: org)
      notification_fixture(user: user, organization: org)
      notification_fixture(user: user, organization: org)

      assert Notifications.unread_count(user.id) == 3

      {:ok, count} = Notifications.mark_all_read(user.id)
      assert count == 3
      assert Notifications.unread_count(user.id) == 0
    end
  end

  describe "archive/1" do
    setup do
      user = user_fixture()
      org = organization_fixture()
      notification = notification_fixture(user: user, organization: org)
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
      user = user_fixture()
      %{user: user}
    end

    test "get_preferences/3 returns defaults when no preference exists", %{user: user} do
      prefs = Notifications.get_preferences(user.id, "procedure_submitted")

      assert prefs.in_app_enabled == true
      assert prefs.email_enabled == true
      assert prefs.email_frequency == "immediate"
    end

    test "set_preferences/4 creates new preference", %{user: user} do
      attrs = %{in_app_enabled: false, email_enabled: true, email_frequency: "daily_digest"}

      {:ok, pref} = Notifications.set_preferences(user.id, "procedure_submitted", attrs)

      assert pref.in_app_enabled == false
      assert pref.email_enabled == true
      assert pref.email_frequency == "daily_digest"
    end

    test "set_preferences/4 updates existing preference", %{user: user} do
      # Create initial preference
      {:ok, _} =
        Notifications.set_preferences(user.id, "procedure_submitted", %{
          in_app_enabled: true,
          email_enabled: true
        })

      # Update it
      {:ok, pref} =
        Notifications.set_preferences(user.id, "procedure_submitted", %{
          email_frequency: "weekly_digest"
        })

      assert pref.email_frequency == "weekly_digest"
    end

    test "get_preferences/3 returns stored preference", %{user: user} do
      {:ok, _} =
        Notifications.set_preferences(user.id, "procedure_approved", %{
          in_app_enabled: false,
          email_enabled: true,
          email_frequency: "daily_digest"
        })

      prefs = Notifications.get_preferences(user.id, "procedure_approved")

      assert prefs.in_app_enabled == false
      assert prefs.email_enabled == true
      assert prefs.email_frequency == "daily_digest"
    end

    test "list_preferences/2 returns all user preferences", %{user: user} do
      {:ok, _} =
        Notifications.set_preferences(user.id, "procedure_submitted", %{in_app_enabled: true})

      {:ok, _} =
        Notifications.set_preferences(user.id, "procedure_approved", %{in_app_enabled: false})

      prefs = Notifications.list_preferences(user.id)
      assert length(prefs) == 2
    end
  end

  describe "pubsub" do
    setup do
      user = user_fixture()
      org = organization_fixture()
      %{user: user, org: org}
    end

    test "subscribe/1 subscribes to user notifications", %{user: user} do
      Notifications.subscribe(user.id)

      # This just tests that it doesn't crash
      assert true
    end

    test "creating notification broadcasts to subscriber", %{user: user, org: org} do
      Notifications.subscribe(user.id)

      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          organization_id: org.id,
          type: "procedure_submitted",
          title: "Test",
          resource_type: "procedure_version",
          resource_id: Ecto.UUID.generate()
        })

      assert_receive {:notification_created, ^notification}
    end
  end
end
