defmodule Cadence.Application.Notifications.NotificationOperations do
  @moduledoc """
  Use case module for notification operations.

  This module provides operations for creating notifications,
  marking them as read/archived, and broadcasting updates.

  All operations:
  1. Validate using schema/changeset logic
  2. Persist via repository
  3. Broadcast for real-time updates

  ## Usage

      # Create a notification
      {:ok, notification} = NotificationOperations.create(attrs)

      # Mark as read
      {:ok, notification} = NotificationOperations.mark_read(notification)

      # Mark all as read
      {:ok, count} = NotificationOperations.mark_all_read(user_id)
  """

  alias Cadence.Notifications.Notification
  alias Cadence.Application.Notifications.NotificationQueries

  @type notification_id :: String.t()
  @type user_id :: String.t()
  @type opts :: keyword()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :notification_repository,
      Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository
    )
  end

  # Get configured event publisher
  defp event_publisher do
    Application.get_env(
      :cadence,
      :event_publisher,
      Cadence.Adapters.Messaging.PhoenixEventPublisher
    )
  end

  @doc """
  Creates a new notification.

  ## Parameters

  - `attrs` - Map containing notification attributes:
    - `:user_id` (required) - Recipient user
    - `:organization_id` (required)
    - `:type` (required) - Notification type
    - `:title` (required)
    - `:body` (optional)
    - `:severity` (optional, default: "info")
    - `:mission_id` (optional)
    - `:actor_id` (optional) - User who triggered the event
    - `:resource_type` (optional)
    - `:resource_id` (optional)
    - `:action_url` (optional)
    - `:metadata` (optional)

  ## Returns

  - `{:ok, notification}` - Successfully created
  - `{:error, changeset}` - Validation failed
  """
  @spec create(map()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    notification = struct(Notification, attrs)

    case repo().save(notification) do
      {:ok, saved} ->
        broadcast_created(saved)
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Creates notifications for multiple recipients in a single transaction.

  ## Returns

  - `{:ok, notifications}` - Successfully created
  - `{:error, reason}` - Failed
  """
  @spec create_batch([map()]) :: {:ok, [Notification.t()]} | {:error, term()}
  def create_batch(notifications_attrs) do
    notifications = Enum.map(notifications_attrs, &struct(Notification, &1))

    case repo().save_batch(notifications) do
      {:ok, saved} ->
        Enum.each(saved, &broadcast_created/1)
        {:ok, saved}

      error ->
        error
    end
  end

  @doc """
  Marks a notification as read.

  Accepts either a `%Notification{}` struct or a tuple of {notification_id, user_id}.

  ## Returns

  - `{:ok, notification}` - Successfully marked as read
  - `{:error, :not_found}` - Notification not found
  - `{:error, changeset}` - Update failed
  """
  @spec mark_read(Notification.t()) :: {:ok, Notification.t()} | {:error, term()}
  def mark_read(%Notification{} = notification) do
    case repo().mark_read(notification) do
      {:ok, updated} ->
        broadcast_read(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  @spec mark_read(notification_id(), user_id()) :: {:ok, Notification.t()} | {:error, term()}
  def mark_read(notification_id, user_id) when is_binary(notification_id) do
    case NotificationQueries.find(notification_id, user_id) do
      {:ok, notification} -> mark_read(notification)
      error -> error
    end
  end

  @doc """
  Marks all unread notifications as read for a user.

  ## Options

  - `:mission_id` - Only mark notifications for a specific mission

  ## Returns

  - `{:ok, count}` - Number of notifications marked as read
  """
  @spec mark_all_read(user_id(), opts()) :: {:ok, non_neg_integer()} | {:error, term()}
  def mark_all_read(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    case repo().mark_all_read(user_id, opts) do
      {:ok, count} ->
        broadcast_all_read(user_id, mission_id)
        {:ok, count}

      error ->
        error
    end
  end

  @doc """
  Archives a notification.

  Accepts either a `%Notification{}` struct or a tuple of {notification_id, user_id}.

  ## Returns

  - `{:ok, notification}` - Successfully archived
  - `{:error, :not_found}` - Notification not found
  - `{:error, changeset}` - Update failed
  """
  @spec archive(Notification.t()) :: {:ok, Notification.t()} | {:error, term()}
  def archive(%Notification{} = notification) do
    case repo().archive(notification) do
      {:ok, updated} ->
        broadcast_archived(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  @spec archive(notification_id(), user_id()) :: {:ok, Notification.t()} | {:error, term()}
  def archive(notification_id, user_id) when is_binary(notification_id) do
    case NotificationQueries.find(notification_id, user_id) do
      {:ok, notification} -> archive(notification)
      error -> error
    end
  end

  # ===========================================================================
  # Private Helpers - Broadcasting
  # ===========================================================================

  defp broadcast_created(%Notification{user_id: user_id} = notification) do
    event_publisher().publish(
      "notifications:#{user_id}",
      {:notification_created, notification}
    )
  rescue
    _ -> :ok
  end

  defp broadcast_read(%Notification{user_id: user_id} = notification) do
    event_publisher().publish(
      "notifications:#{user_id}",
      {:notification_read, notification}
    )
  rescue
    _ -> :ok
  end

  defp broadcast_all_read(user_id, mission_id) do
    event_publisher().publish(
      "notifications:#{user_id}",
      {:all_notifications_read, mission_id}
    )
  rescue
    _ -> :ok
  end

  defp broadcast_archived(%Notification{user_id: user_id} = notification) do
    event_publisher().publish(
      "notifications:#{user_id}",
      {:notification_archived, notification}
    )
  rescue
    _ -> :ok
  end
end
