defmodule Cadence.GroundNetworks.ElementSets.HistoryCursor do
  @moduledoc """
  Keyset paging over a spacecraft's element-set history (#889): newest epoch first, then
  element-set id, both descending. The cursor carries the last row's `{epoch, id}`, so a set
  stored while a client pages (newer, or older) never shifts a page boundary. Opaque on the wire.
  The id column is bytewise (#949), so the tie break is the same on every database.
  """

  import Ecto.Query

  @type key :: {DateTime.t(), binary()}

  @spec after_key(Ecto.Query.t(), key() | nil) :: Ecto.Query.t()
  def after_key(query, nil), do: query

  def after_key(query, {epoch, id}),
    do:
      where(
        query,
        [row],
        row.epoch < ^epoch or (row.epoch == ^epoch and row.element_set_id < ^id)
      )

  @spec encode(%{epoch: DateTime.t(), element_set_id: binary()}) :: binary()
  def encode(%{epoch: epoch, element_set_id: id}),
    do: [DateTime.to_iso8601(epoch), id] |> Jason.encode!() |> Base.url_encode64(padding: false)

  @spec decode(binary() | nil) :: {:ok, key() | nil} | {:error, :invalid_cursor}
  def decode(nil), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, [iso, id]} when is_binary(iso) and is_binary(id) <- Jason.decode(json),
         {:ok, epoch, 0} <- DateTime.from_iso8601(iso) do
      {:ok, {epoch, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}
end
