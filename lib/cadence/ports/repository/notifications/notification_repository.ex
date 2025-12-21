defmodule Cadence.Ports.Repository.Notifications.NotificationRepository do
  @moduledoc """
  Port (behavior) defining the contract for notification persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Multi-tenancy

  Notifications are user-scoped. The `find/2` function requires both the
  notification ID and user ID to ensure users can only access their own
  notifications.

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryNotificationRepository` - In-memory for tests
  """

  alias Cadence.Notifications.Notification

  @type id :: String.t()
  @type user_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds a notification by its ID scoped to a user.

  Returns `{:ok, notification}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id(), user_id()) :: {:ok, Notification.t()} | {:error, :not_found}

  @doc """
  Finds a notification by ID without user scoping.

  WARNING: Only use for internal operations where user context is verified elsewhere.
  """
  @callback find_unscoped(id()) :: {:ok, Notification.t()} | {:error, :not_found}

  @doc """
  Lists notifications for a user with optional filtering.

  ## Options

  - `:mission_id` - Filter by specific mission
  - `:unread_only` - Only return unread notifications
  - `:include_archived` - Include archived notifications (default: false)
  - `:limit` - Maximum number of results (default: 50)
  - `:offset` - Pagination offset (default: 0)
  """
  @callback list(user_id(), opts()) :: [Notification.t()]

  @doc """
  Lists unread notifications for a user.

  Convenience wrapper around `list/2` with `:unread_only` option.
  """
  @callback list_unread(user_id(), opts()) :: [Notification.t()]

  @doc """
  Counts unread notifications for a user.

  ## Options

  - `:mission_id` - Filter by specific mission
  """
  @callback count_unread(user_id(), opts()) :: non_neg_integer()

  @doc """
  Persists a notification (insert or update).

  Returns `{:ok, notification}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(Notification.t()) :: {:ok, Notification.t()} | {:error, error()}

  @doc """
  Persists multiple notifications in a single transaction.

  Returns `{:ok, notifications}` or `{:error, reason}` on failure.
  """
  @callback save_batch([Notification.t()]) :: {:ok, [Notification.t()]} | {:error, error()}

  @doc """
  Marks a notification as read.
  """
  @callback mark_read(Notification.t()) :: {:ok, Notification.t()} | {:error, error()}

  @doc """
  Marks all unread notifications as read for a user.

  ## Options

  - `:mission_id` - Only mark notifications for a specific mission

  Returns `{:ok, count}` with the number of notifications marked as read.
  """
  @callback mark_all_read(user_id(), opts()) :: {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Archives a notification.
  """
  @callback archive(Notification.t()) :: {:ok, Notification.t()} | {:error, error()}

  @doc """
  Returns the configured notification repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :notification_repository,
      Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository
    )
  end
end
