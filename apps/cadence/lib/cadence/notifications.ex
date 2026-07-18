defmodule Cadence.Notifications do
  @moduledoc """
  Per-user notification persistence and PubSub broadcasts.
  """

  import Ecto.Query

  alias Cadence.Notifications.{Notification, NotificationRow}
  alias Cadence.Repo

  @pubsub Cadence.PubSub

  @spec persist_notification(Notification.t()) :: {:ok, Notification.t()} | {:error, term()}
  def persist_notification(%Notification{} = notification) do
    case Repo.insert(NotificationRow.changeset(notification)) do
      {:ok, row} ->
        persisted = NotificationRow.to_domain(row)
        broadcast(persisted.user_id, {:notification_created, persisted})
        {:ok, persisted}

      {:error, _changeset} = error ->
        error
    end
  end

  @spec fetch_notification(binary()) :: {:ok, Notification.t()} | {:error, :not_found}
  def fetch_notification(notification_id) when is_binary(notification_id) do
    case Repo.get(NotificationRow, notification_id) do
      %NotificationRow{} = row -> {:ok, NotificationRow.to_domain(row)}
      nil -> {:error, :not_found}
    end
  end

  @spec list_notifications(binary(), keyword()) :: [Notification.t()]
  def list_notifications(user_id, opts \\ []) when is_binary(user_id) do
    limit = Keyword.get(opts, :limit)
    only_unread = Keyword.get(opts, :only_unread, false)

    query =
      NotificationRow
      |> where([n], n.user_id == ^user_id)
      |> order_by([n], desc: n.inserted_at)

    query = if only_unread, do: where(query, [n], is_nil(n.read_at)), else: query
    query = if is_integer(limit), do: limit(query, ^limit), else: query

    query
    |> Repo.all()
    |> Enum.map(&NotificationRow.to_domain/1)
  end

  @spec count_unread_notifications(binary()) :: non_neg_integer()
  def count_unread_notifications(user_id) when is_binary(user_id) do
    NotificationRow
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> select([n], count(n.notification_id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @spec mark_notification_read(binary(), binary()) ::
          {:ok, Notification.t()} | {:error, :not_found | :forbidden | term()}
  def mark_notification_read(notification_id, user_id)
      when is_binary(notification_id) and is_binary(user_id) do
    case Repo.get(NotificationRow, notification_id) do
      nil ->
        {:error, :not_found}

      %NotificationRow{user_id: ^user_id} = row ->
        update_and_broadcast(row)

      %NotificationRow{} ->
        {:error, :forbidden}
    end
  end

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(user_id) when is_binary(user_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(user_id))
  end

  @spec broadcast(binary(), term()) :: :ok
  def broadcast(user_id, message) when is_binary(user_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(user_id), message)
  end

  defp update_and_broadcast(%NotificationRow{read_at: nil} = row) do
    now = DateTime.utc_now()

    case Repo.update(NotificationRow.mark_read_changeset(row, now)) do
      {:ok, updated} ->
        domain = NotificationRow.to_domain(updated)
        broadcast(domain.user_id, {:notification_updated, domain})
        {:ok, domain}

      {:error, _changeset} = error ->
        error
    end
  end

  defp update_and_broadcast(%NotificationRow{} = row) do
    {:ok, NotificationRow.to_domain(row)}
  end

  defp topic(user_id), do: "notifications:#{user_id}"
end
