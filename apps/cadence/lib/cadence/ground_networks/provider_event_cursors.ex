defmodule Cadence.GroundNetworks.ProviderEventCursors do
  @moduledoc "Persistence and lease boundary for durable provider polling cursors."

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.GroundNetworks.{ProviderAccountVersion, ProviderEventCursor, Validation}
  alias Cadence.GroundNetworks.ProviderEventCursors.CursorRow, as: ProviderEventCursorRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @default_lease_ms 30_000

  @spec ensure(ProviderAccountVersion.t(), keyword()) ::
          {:ok, ProviderEventCursor.t()} | {:error, term()}
  def ensure(%ProviderAccountVersion{} = version, opts \\ []) do
    attrs = %{
      organization_id: version.organization_id,
      provider_account_id: version.provider_account_id,
      provider_account_version: version.version,
      environment_ref: version.environment_ref,
      channel_ref: Keyword.get(opts, :channel_ref, event_ref(version, "channel_ref", "default")),
      stream_ref: Keyword.get(opts, :stream_ref, event_ref(version, "stream_ref", "events"))
    }

    ensure_cursor(attrs)
  end

  @spec ensure_cursor(map()) :: {:ok, ProviderEventCursor.t()} | {:error, term()}
  def ensure_cursor(attrs) when is_map(attrs) do
    cursor = ProviderEventCursor.new(attrs)

    cursor
    |> ProviderEventCursorRow.changeset()
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [
        :organization_id,
        :provider_account_id,
        :provider_account_version,
        :environment_ref,
        :channel_ref,
        :stream_ref
      ]
    )
    |> case do
      {:ok, _row} -> fetch_stream(cursor)
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in ArgumentError -> {:error, {:invalid_provider_event_cursor, Exception.message(error)}}
  end

  @spec fetch(binary(), binary()) :: {:ok, ProviderEventCursor.t()} | {:error, :not_found}
  def fetch(organization_id, provider_event_cursor_id) do
    ProviderEventCursorRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_event_cursor_id == ^provider_event_cursor_id
    )
    |> Repo.one()
    |> row_result()
  end

  @spec list(binary(), keyword()) :: [ProviderEventCursor.t()]
  def list(organization_id, opts \\ []) do
    ProviderEventCursorRow
    |> where([row], row.organization_id == ^organization_id)
    |> maybe_filter_account(Keyword.get(opts, :provider_account_id))
    |> order_by([row], asc: row.provider_account_id, asc: row.channel_ref, asc: row.stream_ref)
    |> Repo.all()
    |> Enum.map(&ProviderEventCursorRow.to_domain/1)
  end

  @spec claim(binary(), binary(), keyword()) ::
          {:ok, ProviderEventCursor.t()} | {:error, :not_found | :lease_unavailable}
  def claim(provider_event_cursor_id, lease_owner, opts \\ [])
      when is_binary(provider_event_cursor_id) and is_binary(lease_owner) do
    now = now(opts)
    expires_at = DateTime.add(now, Keyword.get(opts, :lease_ms, @default_lease_ms), :millisecond)

    query =
      from(row in ProviderEventCursorRow,
        where:
          row.provider_event_cursor_id == ^provider_event_cursor_id and row.health != "disabled" and
            (is_nil(row.lease_expires_at) or row.lease_expires_at <= ^now or
               row.lease_owner == ^lease_owner)
      )

    case Repo.update_all(query, set: [lease_owner: lease_owner, lease_expires_at: expires_at]) do
      {1, _rows} -> fetch_by_id(provider_event_cursor_id)
      {0, _rows} -> unavailable_or_missing(provider_event_cursor_id)
    end
  end

  @doc "Adds a lease-checked cursor advance to a caller-owned transaction."
  @spec put_advance(Multi.t(), Multi.name(), ProviderEventCursor.t(), binary(), term(), map()) ::
          Multi.t()
  def put_advance(
        %Multi{} = multi,
        name,
        %ProviderEventCursor{} = cursor,
        lease_owner,
        next,
        attrs
      )
      when is_binary(lease_owner) and is_map(attrs) do
    Multi.run(multi, name, fn repo, _changes ->
      fetched_at = Map.get(attrs, :last_fetched_at, DateTime.utc_now())
      last_event_at = Map.get(attrs, :last_event_at, cursor.last_event_at)

      query =
        from(row in ProviderEventCursorRow,
          where:
            row.provider_event_cursor_id == ^cursor.provider_event_cursor_id and
              row.lease_owner == ^lease_owner
        )

      updates = [
        cursor_document: JsonDocument.wrap_value(next),
        health: "healthy",
        last_fetched_at: fetched_at,
        last_advanced_at: fetched_at,
        last_event_at: last_event_at,
        lease_owner: nil,
        lease_expires_at: nil,
        consecutive_failures: 0,
        error_document: JsonDocument.wrap_value(%{}),
        updated_at: fetched_at
      ]

      case repo.update_all(query, set: updates) do
        {1, _rows} -> fetch_by_id(repo, cursor.provider_event_cursor_id)
        {0, _rows} -> {:error, :provider_event_cursor_lease_lost}
      end
    end)
  end

  @spec record_failure(ProviderEventCursor.t(), binary(), term(), keyword()) ::
          {:ok, ProviderEventCursor.t()} | {:error, term()}
  def record_failure(%ProviderEventCursor{} = cursor, lease_owner, reason, opts \\ []) do
    recorded_at = now(opts)

    query =
      from(row in ProviderEventCursorRow,
        where:
          row.provider_event_cursor_id == ^cursor.provider_event_cursor_id and
            row.lease_owner == ^lease_owner
      )

    updates = [
      health: "degraded",
      last_fetched_at: recorded_at,
      lease_owner: nil,
      lease_expires_at: nil,
      consecutive_failures: cursor.consecutive_failures + 1,
      error_document:
        JsonDocument.wrap_value(%{
          "reason" => sanitize_reason(reason),
          "recorded_at" => DateTime.to_iso8601(recorded_at)
        }),
      updated_at: recorded_at
    ]

    case Repo.update_all(query, set: updates) do
      {1, _rows} -> fetch_by_id(cursor.provider_event_cursor_id)
      {0, _rows} -> {:error, :provider_event_cursor_lease_lost}
    end
  end

  defp fetch_stream(cursor) do
    ProviderEventCursorRow
    |> where(
      [row],
      row.organization_id == ^cursor.organization_id and
        row.provider_account_id == ^cursor.provider_account_id and
        row.provider_account_version == ^cursor.provider_account_version and
        row.environment_ref == ^cursor.environment_ref and row.channel_ref == ^cursor.channel_ref and
        row.stream_ref == ^cursor.stream_ref
    )
    |> Repo.one()
    |> row_result()
  end

  defp fetch_by_id(provider_event_cursor_id), do: fetch_by_id(Repo, provider_event_cursor_id)

  defp fetch_by_id(repo, provider_event_cursor_id) do
    ProviderEventCursorRow
    |> where([row], row.provider_event_cursor_id == ^provider_event_cursor_id)
    |> repo.one()
    |> row_result()
  end

  defp unavailable_or_missing(provider_event_cursor_id) do
    case Repo.get(ProviderEventCursorRow, provider_event_cursor_id) do
      nil -> {:error, :not_found}
      _row -> {:error, :lease_unavailable}
    end
  end

  defp row_result(nil), do: {:error, :not_found}
  defp row_result(row), do: {:ok, ProviderEventCursorRow.to_domain(row)}

  defp maybe_filter_account(query, nil), do: query

  defp maybe_filter_account(query, provider_account_id),
    do: where(query, [row], row.provider_account_id == ^provider_account_id)

  defp event_ref(version, key, default),
    do: Map.get(version.event_configuration, key, default)

  defp sanitize_reason(reason) do
    case JsonDocument.encode(reason) do
      document when is_map(document) -> Validation.sanitize(document)
      value -> value
    end
  end

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
