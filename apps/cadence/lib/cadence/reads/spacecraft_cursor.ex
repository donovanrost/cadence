defmodule Cadence.Reads.SpacecraftCursor do
  @moduledoc """
  The opaque cursor of a mission's spacecraft paged by name, then id (the names read #847 and the
  Setup directory #796): the last row's sort key, so a craft added or renamed between pages
  neither repeats nor skips one that stays.
  """

  @spec encode({binary(), binary()}) :: binary()
  def encode({name, id}) when is_binary(name) and is_binary(id),
    do: [name, id] |> Jason.encode!() |> Base.url_encode64(padding: false)

  @spec decode(term()) :: {:ok, {binary(), binary()} | nil} | {:error, :invalid_cursor}
  def decode(nil), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) and byte_size(cursor) <= 1_024 do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, [name, id]} when is_binary(name) and is_binary(id) <- Jason.decode(json) do
      {:ok, {name, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}
end
