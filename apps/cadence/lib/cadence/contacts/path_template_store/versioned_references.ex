defmodule Cadence.Contacts.PathTemplateStore.VersionedReferences do
  @moduledoc false

  import Ecto.Query

  alias Cadence.Repo

  def refs(ids, [], id_key), do: Enum.map(ids, &%{id_key => &1})
  def refs(_ids, refs, _id_key), do: refs

  def key(ref, id_key) do
    version = Map.get(ref, "version")
    {Map.get(ref, id_key), if(is_integer(version) and version > 0, do: version)}
  end

  def in_scope(query, org, mission) when is_binary(org) and org != "" do
    where(query, [row], row.organization_id == ^org and row.mission_id == ^mission)
  end

  def in_scope(query, _org, mission), do: where(query, [row], row.mission_id == ^mission)

  # Read only the requested pinned rows and the latest row for each requested current version.
  # Fixed-size array parameters keep large batches from exceeding the statement parameter limit.
  def load(_query, _id_field, [], _latest_ids, _to_domain), do: %{}

  def load(query, id_field, keys, latest_ids, to_domain) do
    {ids, versions} =
      keys |> Enum.uniq() |> Enum.reject(fn {_id, version} -> is_nil(version) end) |> Enum.unzip()

    latest_ids = Enum.uniq(latest_ids)

    latest =
      query
      |> where([row], field(row, ^id_field) in ^latest_ids)
      |> distinct([row], field(row, ^id_field))
      |> order_by([row], desc: row.version)

    pinned =
      where(
        query,
        [row],
        fragment(
          "(?, ?) IN (SELECT * FROM unnest(?::text[], ?::bigint[]))",
          field(row, ^id_field),
          row.version,
          type(^ids, {:array, :string}),
          type(^versions, {:array, :integer})
        )
      )

    latest_ids = MapSet.new(latest_ids)

    from(row in subquery(latest), select: row)
    |> union_all(^pinned)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, index ->
      id = Map.fetch!(row, id_field)
      domain = to_domain.(row)
      index = Map.put(index, {id, row.version}, domain)

      if MapSet.member?(latest_ids, id) do
        Map.update(
          index,
          {id, nil},
          domain,
          &Enum.max_by([&1, domain], fn item -> item.version end)
        )
      else
        index
      end
    end)
  end

  def fetch(index, key, not_found) do
    case Map.get(index, key) do
      nil -> {:error, not_found}
      %{lifecycle_state: :deleted} -> {:error, not_found}
      record -> {:ok, record}
    end
  end
end
