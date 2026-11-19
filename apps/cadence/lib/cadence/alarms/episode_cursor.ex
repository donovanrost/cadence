defmodule Cadence.Alarms.EpisodeCursor do
  @moduledoc """
  U69 A6d: keyset paging over the alarm-episode list in its own order. "Load more" never repeats
  or skips a row that keeps its place; a row that moves between pages (acknowledged, escalated)
  shows where it now sorts, so it can appear twice or not at all:

    * active (and `all`): critical first, unacknowledged first, newest opened, then id;
    * cleared: newest cleared, then id.

  The cursor carries the key values (not just an id), so a page boundary stays put even if the
  row it came from is acknowledged or cleared in the meantime. Opaque on the wire.
  """

  import Ecto.Query

  alias Cadence.Alarms.EpisodeRow

  @type key ::
          {:active, 0 | 1, 0 | 1, DateTime.t(), binary()} | {:cleared, DateTime.t(), binary()}

  @spec key(EpisodeRow.t(), binary()) :: key()
  def key(%EpisodeRow{} = row, "cleared"), do: {:cleared, row.cleared_at, row.episode_id}

  def key(%EpisodeRow{} = row, _state),
    do:
      {:active, severity_rank(row.severity), if(is_nil(row.acknowledged_at), do: 0, else: 1),
       row.opened_at, row.episode_id}

  defp severity_rank("critical"), do: 0
  defp severity_rank(_caution), do: 1

  @spec after_key(Ecto.Queryable.t(), binary(), key() | nil) :: Ecto.Query.t()
  def after_key(query, _state, nil), do: query

  def after_key(query, "cleared", {:cleared, cleared_at, id}),
    do:
      where(
        query,
        [e],
        e.cleared_at < ^cleared_at or (e.cleared_at == ^cleared_at and e.episode_id > ^id)
      )

  # A key from the other list's order (a cursor reused across state=) matches nothing.
  def after_key(query, "cleared", _active_key), do: where(query, false)

  def after_key(query, _state, {:active, severity, unacked, opened_at, id}) do
    where(
      query,
      [e],
      fragment(
        "(CASE ? WHEN 'critical' THEN 0 ELSE 1 END, CASE WHEN ? IS NULL THEN 0 ELSE 1 END) > (?, ?)",
        e.severity,
        e.acknowledged_at,
        ^severity,
        ^unacked
      ) or
        (fragment(
           "(CASE ? WHEN 'critical' THEN 0 ELSE 1 END, CASE WHEN ? IS NULL THEN 0 ELSE 1 END) = (?, ?)",
           e.severity,
           e.acknowledged_at,
           ^severity,
           ^unacked
         ) and
           (e.opened_at < ^opened_at or (e.opened_at == ^opened_at and e.episode_id > ^id)))
    )
  end

  def after_key(query, _state, _cleared_key), do: where(query, false)

  @spec encode(key() | nil) :: binary() | nil
  def encode(nil), do: nil

  def encode({:cleared, at, id}), do: pack(["c", DateTime.to_iso8601(at), id])

  def encode({:active, severity, unacked, at, id}),
    do: pack(["a", severity, unacked, DateTime.to_iso8601(at), id])

  @spec decode(binary() | nil) :: {:ok, key() | nil} | {:error, :invalid_cursor}
  def decode(nil), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, parts} <- Jason.decode(json),
         {:ok, key} <- unpack(parts) do
      {:ok, key}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}

  defp pack(parts), do: parts |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp unpack(["c", iso, id]) when is_binary(id) do
    with {:ok, at, 0} <- DateTime.from_iso8601(iso), do: {:ok, {:cleared, at, id}}
  end

  defp unpack(["a", severity, unacked, iso, id])
       when severity in [0, 1] and unacked in [0, 1] and is_binary(id) do
    with {:ok, at, 0} <- DateTime.from_iso8601(iso),
         do: {:ok, {:active, severity, unacked, at, id}}
  end

  defp unpack(_parts), do: :error
end
