defmodule Cadence.Notifications do
  @moduledoc """
  Context facade for managing user notifications and preferences.

  This module provides the public API for:
  - Creating and querying notifications
  - Managing notification preferences
  - Determining notification recipients
  - Real-time notification broadcasting

  This module delegates to:
  - `Cadence.Application.Notifications.NotificationOperations` for write operations
  - `Cadence.Application.Notifications.NotificationQueries` for read operations
  """

  alias Cadence.Application.Notifications.NotificationOperations
  alias Cadence.Application.Notifications.NotificationQueries
  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Ports.Repository.Notifications.NotificationRepository
  alias Cadence.Repo
  alias Cadence.Notifications.{Notification, NotificationPreference}
  alias Cadence.Missions

  # ============================================================================
  # Notification CRUD - Delegated to Application Layer
  # ============================================================================

  @doc """
  Creates a notification and broadcasts it via PubSub.

  Returns `{:ok, notification}` or `{:error, changeset}`.
  """
  def create_notification(attrs) do
    NotificationOperations.create(normalize_attrs(attrs))
  end

  @doc """
  Creates notifications for multiple recipients in a single transaction.

  Returns `{:ok, notifications}` or `{:error, failed_changesets}`.
  """
  def create_notifications_batch(notifications_attrs) do
    normalized = Enum.map(notifications_attrs, &normalize_attrs/1)
    NotificationOperations.create_batch(normalized)
  end

  @doc """
  Gets a notification by ID.
  """
  def get_notification(id) do
    case NotificationQueries.find_unscoped(id) do
      {:ok, notification} -> notification
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a notification by ID, raising if not found.
  """
  def get_notification!(id) do
    case NotificationQueries.find_unscoped(id) do
      {:ok, notification} -> notification
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Notification
    end
  end

  @doc """
  Lists unread notifications for a user.
  """
  def list_unread(user_id, opts \\ []) do
    NotificationQueries.list_unread(user_id, opts)
  end

  @doc """
  Lists all non-archived notifications for a user (inbox view).
  """
  def list_inbox(user_id, opts \\ []) do
    NotificationQueries.list_inbox(user_id, opts)
  end

  @doc """
  Lists all notifications for a user with optional filtering.
  """
  def list_notifications(user_id, opts \\ []) do
    NotificationQueries.list(user_id, opts)
  end

  @doc """
  Gets unread notification count for a user.
  """
  def unread_count(user_id, opts \\ []) do
    NotificationQueries.count_unread(user_id, opts)
  end

  @doc """
  Marks a notification as read.

  Accepts either a `%Notification{}` struct or a notification ID (binary).
  """
  def mark_read(%Notification{} = notification) do
    NotificationOperations.mark_read(notification)
  end

  def mark_read(notification_id) when is_binary(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification -> NotificationOperations.mark_read(notification)
    end
  end

  @doc """
  Marks all unread notifications as read for a user.
  """
  def mark_all_read(user_id, opts \\ []) do
    NotificationOperations.mark_all_read(user_id, opts)
  end

  @doc """
  Archives a notification.

  Accepts either a `%Notification{}` struct or a notification ID (binary).
  """
  def archive(%Notification{} = notification) do
    NotificationOperations.archive(notification)
  end

  def archive(notification_id) when is_binary(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification -> NotificationOperations.archive(notification)
    end
  end

  # ============================================================================
  # Recipient Discovery
  # ============================================================================

  @doc """
  Finds users who should receive notifications for a procedure event.

  For procedure submissions: returns mission members with engineer or admin roles
  For approval/rejection: returns the submitter
  For finalization: returns all users who voted
  """
  def find_procedure_recipients(event_type, procedure_version, opts \\ []) do
    exclude_actor_id = Keyword.get(opts, :exclude_actor_id)

    case event_type do
      :submitted ->
        find_potential_approvers(procedure_version, exclude_actor_id)

      type when type in [:approved, :rejected] ->
        find_submitter(procedure_version)

      :finalized ->
        find_voters(procedure_version)

      :withdrawn ->
        # No notifications for withdrawal
        []
    end
  end

  defp find_potential_approvers(procedure_version, exclude_actor_id) do
    procedure_version = Repo.preload(procedure_version, procedure: :mission)
    mission = procedure_version.procedure.mission

    memberships = Missions.list_members(mission.id)

    memberships
    |> Enum.filter(fn m -> m.role in [:engineer, :admin] end)
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&(&1 == exclude_actor_id))
    |> Enum.uniq()
  end

  defp find_submitter(procedure_version) do
    if procedure_version.submitted_by_id do
      [procedure_version.submitted_by_id]
    else
      []
    end
  end

  defp find_voters(procedure_version) do
    procedure_version = Repo.preload(procedure_version, approvals: [])

    procedure_version.approvals
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()
  end

  # ============================================================================
  # Preferences
  # ============================================================================

  # Repository accessor for preferences (not yet in application layer)
  defp notifications_repo, do: NotificationRepository.impl()

  @doc """
  Gets effective preferences for a user and notification type.

  Checks mission-specific preferences first, falls back to global preferences,
  then to system defaults.
  """
  def get_preferences(user_id, notification_type, mission_id \\ nil) do
    # Try mission-specific preference first
    mission_pref =
      if mission_id do
        find_preference(user_id, notification_type, mission_id)
      end

    # Fall back to global preference
    global_pref = find_preference(user_id, notification_type, nil)

    cond do
      mission_pref -> preference_to_map(mission_pref)
      global_pref -> preference_to_map(global_pref)
      true -> NotificationPreference.defaults()
    end
  end

  defp preference_to_map(%NotificationPreference{} = pref) do
    %{
      in_app_enabled: pref.in_app_enabled,
      email_enabled: pref.email_enabled,
      email_frequency: pref.email_frequency
    }
  end

  @doc """
  Sets user preferences for a notification type.
  """
  def set_preferences(user_id, notification_type, attrs, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:notification_type, notification_type)
      |> Map.put(:mission_id, mission_id)

    notifications_repo().save_preference(attrs)
  end

  defp find_preference(user_id, notification_type, mission_id) do
    case notifications_repo().find_preference(user_id, notification_type, mission_id) do
      {:ok, preference} -> preference
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Lists all preferences for a user.
  """
  def list_preferences(user_id, opts \\ []) do
    notifications_repo().list_preferences(user_id, opts)
  end

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  defp event_publisher, do: EventPublisher.impl()

  @doc """
  Subscribes the current process to notifications for a user.
  """
  def subscribe(user_id) do
    event_publisher().subscribe("notifications:#{user_id}")
  end

  @doc """
  Unsubscribe the current process from notifications for a user.
  """
  def unsubscribe(user_id) do
    event_publisher().unsubscribe("notifications:#{user_id}")
  end

  # Private helper to normalize attrs to atom keys
  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {k, v}, acc when is_binary(k) -> Map.put(acc, String.to_existing_atom(k), v)
      {k, v}, acc when is_atom(k) -> Map.put(acc, k, v)
    end)
  end
end
