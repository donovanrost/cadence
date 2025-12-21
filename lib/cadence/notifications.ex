defmodule Cadence.Notifications do
  @moduledoc """
  Context for managing user notifications and preferences.

  This module provides the public API for:
  - Creating and querying notifications
  - Managing notification preferences
  - Determining notification recipients
  - Real-time notification broadcasting
  """

  import Ecto.Query, warn: false

  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Repo
  alias Cadence.Notifications.{Notification, NotificationPreference}
  alias Cadence.Missions

  @pubsub Cadence.PubSub

  # ============================================================================
  # Notification CRUD
  # ============================================================================

  @doc """
  Creates a notification and broadcasts it via PubSub.

  Returns `{:ok, notification}` or `{:error, changeset}`.
  """
  def create_notification(attrs) do
    result =
      %Notification{}
      |> Notification.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, notification} ->
        broadcast_notification(notification)
        {:ok, notification}

      error ->
        error
    end
  end

  @doc """
  Creates notifications for multiple recipients in a single transaction.

  Returns `{:ok, notifications}` or `{:error, failed_changesets}`.
  """
  def create_notifications_batch(notifications_attrs) do
    Repo.transaction(fn ->
      Enum.map(notifications_attrs, fn attrs ->
        case create_notification(attrs) do
          {:ok, notification} -> notification
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Gets a notification by ID.
  """
  def get_notification(id), do: Repo.get(Notification, id)

  @doc """
  Gets a notification by ID, raising if not found.
  """
  def get_notification!(id), do: Repo.get!(Notification, id)

  @doc """
  Lists unread notifications for a user.
  """
  def list_unread(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    mission_id = Keyword.get(opts, :mission_id)

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        where: is_nil(n.read_at),
        where: is_nil(n.archived_at),
        order_by: [desc: n.inserted_at],
        limit: ^limit,
        preload: [:actor, :mission]

    query =
      if mission_id do
        where(query, [n], n.mission_id == ^mission_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists all non-archived notifications for a user (inbox view).
  """
  def list_inbox(user_id, opts \\ []) do
    list_notifications(user_id, Keyword.put(opts, :include_archived, false))
  end

  @doc """
  Lists all notifications for a user with optional filtering.
  """
  def list_notifications(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    include_archived = Keyword.get(opts, :include_archived, false)
    unread_only = Keyword.get(opts, :unread_only, false)

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:actor, :mission]

    query =
      unless include_archived do
        where(query, [n], is_nil(n.archived_at))
      else
        query
      end

    query =
      if unread_only do
        where(query, [n], is_nil(n.read_at))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets unread notification count for a user.
  """
  def unread_count(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        where: is_nil(n.read_at),
        where: is_nil(n.archived_at),
        select: count(n.id)

    query =
      if mission_id do
        where(query, [n], n.mission_id == ^mission_id)
      else
        query
      end

    Repo.one(query)
  end

  @doc """
  Marks a notification as read.

  Accepts either a `%Notification{}` struct or a notification ID (binary).
  """
  def mark_read(%Notification{} = notification) do
    notification
    |> Notification.mark_read_changeset()
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> broadcast_notification_read(updated)
      _ -> :ok
    end)
  end

  def mark_read(notification_id) when is_binary(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification -> mark_read(notification)
    end
  end

  @doc """
  Marks all unread notifications as read for a user.
  """
  def mark_all_read(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    now = DateTime.utc_now()

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        where: is_nil(n.read_at),
        where: is_nil(n.archived_at)

    query =
      if mission_id do
        where(query, [n], n.mission_id == ^mission_id)
      else
        query
      end

    {count, _} = Repo.update_all(query, set: [read_at: now])
    broadcast_all_read(user_id, mission_id)
    {:ok, count}
  end

  @doc """
  Archives a notification.

  Accepts either a `%Notification{}` struct or a notification ID (binary).
  """
  def archive(%Notification{} = notification) do
    notification
    |> Notification.mark_archived_changeset()
    |> Repo.update()
  end

  def archive(notification_id) when is_binary(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification -> archive(notification)
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
    # Get mission memberships with engineer or admin roles
    procedure_version = Repo.preload(procedure_version, procedure: :mission)
    mission = procedure_version.procedure.mission

    memberships = Missions.list_mission_memberships(mission)

    memberships
    |> Enum.filter(fn m -> m.role in ["engineer", "admin"] end)
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

    # Find or create preference - use query to handle nil mission_id
    pref =
      find_preference(user_id, notification_type, mission_id) || %NotificationPreference{}

    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:notification_type, notification_type)
      |> Map.put(:mission_id, mission_id)

    pref
    |> NotificationPreference.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp find_preference(user_id, notification_type, nil) do
    from(p in NotificationPreference,
      where: p.user_id == ^user_id,
      where: p.notification_type == ^notification_type,
      where: is_nil(p.mission_id)
    )
    |> Repo.one()
  end

  defp find_preference(user_id, notification_type, mission_id) do
    Repo.get_by(NotificationPreference,
      user_id: user_id,
      notification_type: notification_type,
      mission_id: mission_id
    )
  end

  @doc """
  Lists all preferences for a user.
  """
  def list_preferences(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    query =
      from p in NotificationPreference,
        where: p.user_id == ^user_id,
        order_by: [asc: p.notification_type]

    query =
      if mission_id do
        where(query, [p], p.mission_id == ^mission_id or is_nil(p.mission_id))
      else
        query
      end

    Repo.all(query)
  end

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  @doc """
  Subscribes the current process to notifications for a user.
  """
  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(@pubsub, "notifications:#{user_id}")
  end

  @doc """
  Unsubscribes the current process from notifications for a user.
  """
  def unsubscribe(user_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, "notifications:#{user_id}")
  end

  defp event_publisher, do: EventPublisher.impl()

  defp broadcast_notification(%Notification{} = notification) do
    event_publisher().publish(
      "notifications:#{notification.user_id}",
      {:notification_created, notification}
    )
  end

  defp broadcast_notification_read(%Notification{} = notification) do
    event_publisher().publish(
      "notifications:#{notification.user_id}",
      {:notification_read, notification}
    )
  end

  defp broadcast_all_read(user_id, mission_id) do
    event_publisher().publish(
      "notifications:#{user_id}",
      {:all_notifications_read, mission_id}
    )
  end
end
