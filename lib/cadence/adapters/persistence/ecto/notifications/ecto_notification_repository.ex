defmodule Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository do
  @moduledoc """
  Ecto-based implementation of the NotificationRepository port.

  This adapter provides persistence for notifications using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :notification_repository, Cadence.Adapters.Persistence.Ecto.Notifications.EctoNotificationRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Notifications.NotificationRepository.impl()
      {:ok, notification} = repo.find(id, user_id)
  """

  @behaviour Cadence.Ports.Repository.Notifications.NotificationRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Notifications.Notification

  # ===========================================================================
  # NotificationRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, user_id) do
    query =
      from n in Notification,
        where: n.id == ^id and n.user_id == ^user_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      notification -> {:ok, Repo.preload(notification, [:actor, :mission])}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Repo.get(Notification, id) do
      nil -> {:error, :not_found}
      notification -> {:ok, Repo.preload(notification, [:actor, :mission])}
    end
  end

  @impl true
  def list(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    mission_id = Keyword.get(opts, :mission_id)
    unread_only = Keyword.get(opts, :unread_only, false)
    include_archived = Keyword.get(opts, :include_archived, false)

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:actor, :mission]

    query = apply_filters(query, mission_id: mission_id, unread_only: unread_only, include_archived: include_archived)

    Repo.all(query)
  end

  @impl true
  def list_unread(user_id, opts \\ []) do
    list(user_id, Keyword.put(opts, :unread_only, true))
  end

  @impl true
  def count_unread(user_id, opts \\ []) do
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

  @impl true
  def save(%Notification{id: nil} = notification) do
    %Notification{}
    |> Notification.changeset(Map.from_struct(notification))
    |> Repo.insert()
    |> case do
      {:ok, notification} -> {:ok, Repo.preload(notification, [:actor, :mission])}
      error -> error
    end
  end

  def save(%Notification{} = notification) do
    notification
    |> Notification.changeset(Map.from_struct(notification))
    |> Repo.update()
    |> case do
      {:ok, notification} -> {:ok, Repo.preload(notification, [:actor, :mission])}
      error -> error
    end
  end

  @impl true
  def save_batch(notifications) do
    Repo.transaction(fn ->
      Enum.map(notifications, fn notification ->
        case save(notification) do
          {:ok, saved} -> saved
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  @impl true
  def mark_read(%Notification{} = notification) do
    notification
    |> Notification.mark_read_changeset()
    |> Repo.update()
  end

  @impl true
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
    {:ok, count}
  end

  @impl true
  def archive(%Notification{} = notification) do
    notification
    |> Notification.mark_archived_changeset()
    |> Repo.update()
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:mission_id, nil}, q ->
        q

      {:mission_id, mission_id}, q ->
        from(n in q, where: n.mission_id == ^mission_id)

      {:unread_only, false}, q ->
        q

      {:unread_only, true}, q ->
        from(n in q, where: is_nil(n.read_at))

      {:include_archived, true}, q ->
        q

      {:include_archived, false}, q ->
        from(n in q, where: is_nil(n.archived_at))
    end)
  end
end
