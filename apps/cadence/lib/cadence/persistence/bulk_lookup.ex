defmodule Cadence.Persistence.BulkLookup do
  @moduledoc false

  import Ecto.Query

  alias Cadence.Repo

  @batch_size 500

  def by_id(query, id_field, ids) do
    ids
    |> Enum.uniq()
    |> Enum.chunk_every(@batch_size)
    |> Enum.flat_map(fn ids ->
      Repo.all(where(query, [row], field(row, ^id_field) in ^ids))
    end)
  end

  def by_version(query, id_field, keys) do
    keys
    |> Enum.uniq()
    |> Enum.chunk_every(@batch_size)
    |> Enum.flat_map(fn keys ->
      pins = Enum.map(keys, fn {id, version} -> %{id: id, version: version} end)
      types = %{id: :string, version: :integer}

      query
      |> join(:inner, [row], pin in values(pins, types),
        on: field(row, ^id_field) == pin.id and row.version == pin.version
      )
      |> Repo.all()
    end)
  end
end
