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

  @listed_kinds ["organization_access_granted"]
  @max_page 50

  @doc """
  The kinds the console lists (#709; session.md "Account: notices"). Invitations have their own
  list (`Accounts.list_pending_invitations_for_user/1`), so they aren't listed twice. The page,
  the unread count and Mark read all filter by these, so the account menu's count is the list's.
  """
  @spec listed_kinds() :: [binary()]
  def listed_kinds, do: @listed_kinds

  @doc """
  One page of the person's listed notices, newest first (by `inserted_at`, then id), after an
  opaque `cursor`, `limit` 1..#{@max_page} (default #{@max_page}). One query.
  """
  @spec listed_page(binary(), keyword()) ::
          {:ok, %{entries: [Notification.t()], next_cursor: binary() | nil}}
          | {:error, :invalid_cursor}
  def listed_page(user_id, opts \\ []) when is_binary(user_id) do
    with {:ok, after_key} <- decode_cursor(Keyword.get(opts, :cursor)) do
      size = page_size(Keyword.get(opts, :limit))

      rows =
        NotificationRow
        |> where([n], n.user_id == ^user_id and n.kind in ^@listed_kinds)
        |> after_key(after_key)
        |> order_by([n],
          desc: n.inserted_at,
          desc: fragment("? COLLATE \"C\"", n.notification_id)
        )
        |> limit(^(size + 1))
        |> Repo.all()

      entries = rows |> Enum.take(size) |> Enum.map(&NotificationRow.to_domain/1)
      last = List.last(entries)

      {:ok,
       %{
         entries: entries,
         next_cursor:
           if(length(rows) > size, do: encode_cursor(last.inserted_at, last.notification_id))
       }}
    end
  end

  @doc "How many listed notices the person hasn't read (the account menu's count)."
  @spec listed_unread_count(binary()) :: non_neg_integer()
  def listed_unread_count(user_id) when is_binary(user_id) do
    NotificationRow
    |> where([n], n.user_id == ^user_id and n.kind in ^@listed_kinds and is_nil(n.read_at))
    |> select([n], count(n.notification_id))
    |> Repo.one()
  end

  @doc """
  Marks one of the person's listed notices read (idempotent: a read one keeps its `read_at`).
  Someone else's, an unlisted kind and an unknown id are all `:not_found`, so ids don't leak.
  """
  @spec mark_listed_read(binary(), binary()) :: {:ok, Notification.t()} | {:error, :not_found}
  def mark_listed_read(user_id, notification_id)
      when is_binary(user_id) and is_binary(notification_id) do
    NotificationRow
    |> where(
      [n],
      n.user_id == ^user_id and n.notification_id == ^notification_id and
        n.kind in ^@listed_kinds
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> update_and_broadcast(row)
    end
  end

  defp after_key(query, nil), do: query

  defp after_key(query, {at, id}) do
    where(
      query,
      [n],
      n.inserted_at < ^at or
        (n.inserted_at == ^at and
           fragment(~s(? COLLATE "C" < ? COLLATE "C"), n.notification_id, ^id))
    )
  end

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_page, do: limit
  defp page_size(_limit), do: @max_page

  defp encode_cursor(at, id),
    do: [DateTime.to_iso8601(at), id] |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(token) when is_binary(token) and byte_size(token) <= 1_024 do
    with {:ok, bytes} <- Base.url_decode64(token, padding: false),
         {:ok, [time, id]} when is_binary(time) and is_binary(id) and id != "" <-
           Jason.decode(bytes),
         {:ok, at, 0} <- DateTime.from_iso8601(time) do
      {:ok, {at, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_token), do: {:error, :invalid_cursor}

  @doc "Fetches a notification only inside its recipient boundary."
  def fetch_notification_for_user(user_id, notification_id)
      when is_binary(user_id) and is_binary(notification_id) do
    case Repo.get_by(NotificationRow, user_id: user_id, notification_id: notification_id) do
      nil -> {:error, :not_found}
      row -> {:ok, NotificationRow.to_domain(row)}
    end
  end
end
