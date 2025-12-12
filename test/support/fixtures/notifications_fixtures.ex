defmodule Cadence.NotificationsFixtures do
  @moduledoc """
  Test helpers for creating notification entities.
  """

  import Cadence.AccountsFixtures
  import Cadence.OrganizationsFixtures

  alias Cadence.Notifications
  alias Cadence.Repo

  def notification_fixture(attrs \\ %{}) do
    # Convert keyword list to map if needed
    attrs = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs

    user = Map.get(attrs, :user) || user_fixture()
    org = Map.get(attrs, :organization) || organization_fixture()

    attrs =
      attrs
      |> Map.delete(:user)
      |> Map.delete(:organization)
      |> Map.put_new(:user_id, user.id)
      |> Map.put_new(:organization_id, org.id)
      |> Map.put_new(:type, "procedure_submitted")
      |> Map.put_new(:title, "Test Notification")
      |> Map.put_new(:body, "This is a test notification body")
      |> Map.put_new(:severity, "info")
      |> Map.put_new(:resource_type, "procedure_version")
      |> Map.put_new(:resource_id, Ecto.UUID.generate())

    {:ok, notification} = Notifications.create_notification(attrs)
    notification
  end

  def notification_preference_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || user_fixture()

    attrs =
      attrs
      |> Map.delete(:user)
      |> Map.put_new(:user_id, user.id)
      |> Map.put_new(:notification_type, "procedure_submitted")
      |> Map.put_new(:in_app_enabled, true)
      |> Map.put_new(:email_enabled, true)
      |> Map.put_new(:email_frequency, "immediate")

    {:ok, pref} =
      %Notifications.NotificationPreference{}
      |> Notifications.NotificationPreference.changeset(attrs)
      |> Repo.insert()

    pref
  end

  def unread_notification_fixture(attrs \\ %{}) do
    notification_fixture(attrs)
  end

  def read_notification_fixture(attrs \\ %{}) do
    notification = notification_fixture(attrs)
    {:ok, notification} = Notifications.mark_read(notification)
    notification
  end
end
