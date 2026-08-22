defmodule Cadence.Application.Notifications.NotificationQueries do
  @moduledoc """
  Use case module for querying notifications.

  This module provides read-only operations for listing, counting,
  and finding notifications. It works with domain entities and uses
  repository ports for data access.

  ## Usage

      # List notifications for a user
      notifications = NotificationQueries.list(user_id)

      # List unread only
      notifications = NotificationQueries.list_unread(user_id)

      # Find specific notification
      {:ok, notification} = NotificationQueries.find(id, user_id)

      # Get unread count
      count = NotificationQueries.count_unread(user_id)
  """

  alias Cadence.Notifications.Notification

  @type id :: String.t()
  @type user_id :: String.t()
  @type opts :: keyword()

  # Get configured repository (allows for DI in tests)
  defp repo do
    Application.get_env(
      :cadence,
      :notification_repository,
      Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository
    )
  end

  @doc """
  Finds a notification by ID scoped to a user.

  Returns `{:ok, notification}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(id(), user_id()) :: {:ok, Notification.t()} | {:error, :not_found}
  def find(id, user_id), do: repo().find(id, user_id)

  @doc """
  Finds a notification by ID scoped to a user, raising if not found.
  """
  @spec find!(id(), user_id()) :: Notification.t()
  def find!(id, user_id) do
    case find(id, user_id) do
      {:ok, notification} -> notification
      {:error, :not_found} -> raise "Notification not found: #{id}"
    end
  end

  @doc """
  Finds a notification by ID without user scoping.

  WARNING: Only use for internal operations where user context is verified elsewhere.
  """
  @spec find_unscoped(id()) :: {:ok, Notification.t()} | {:error, :not_found}
  def find_unscoped(id), do: repo().find_unscoped(id)

  @doc """
  Lists notifications for a user.

  ## Options

  - `:mission_id` - Filter by mission
  - `:unread_only` - Only return unread notifications
  - `:include_archived` - Include archived notifications (default: false)
  - `:limit` - Maximum number of results (default: 50)
  - `:offset` - Offset for pagination

  ## Examples

      # All non-archived notifications
      NotificationQueries.list(user_id)

      # Only unread notifications for a mission
      NotificationQueries.list(user_id, mission_id: mission_id, unread_only: true)
  """
  @spec list(user_id(), opts()) :: [Notification.t()]
  def list(user_id, opts \\ []) do
    repo().list(user_id, opts)
  end

  @doc """
  Lists unread notifications for a user.

  Convenience wrapper around `list/2` with `:unread_only` option.

  ## Options

  - `:mission_id` - Filter by mission
  - `:limit` - Maximum number of results (default: 50)
  """
  @spec list_unread(user_id(), opts()) :: [Notification.t()]
  def list_unread(user_id, opts \\ []) do
    repo().list_unread(user_id, opts)
  end

  @doc """
  Lists inbox notifications (non-archived) for a user.

  ## Options

  - `:limit` - Maximum number of results (default: 50)
  - `:offset` - Offset for pagination
  """
  @spec list_inbox(user_id(), opts()) :: [Notification.t()]
  def list_inbox(user_id, opts \\ []) do
    list(user_id, Keyword.put(opts, :include_archived, false))
  end

  @doc """
  Counts unread notifications for a user.

  ## Options

  - `:mission_id` - Filter by mission
  """
  @spec count_unread(user_id(), opts()) :: non_neg_integer()
  def count_unread(user_id, opts \\ []) do
    repo().count_unread(user_id, opts)
  end

  @doc """
  Checks if a user has any unread notifications.
  """
  @spec has_unread?(user_id()) :: boolean()
  def has_unread?(user_id) do
    count_unread(user_id) > 0
  end
end
