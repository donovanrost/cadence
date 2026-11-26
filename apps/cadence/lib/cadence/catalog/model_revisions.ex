defmodule Cadence.Catalog.ModelRevisions do
  @moduledoc """
  Which catalog revision introduced each mission-model revision (ux U65: the console names a
  model by its catalog revision, "catalog rev 4"). A model revision can come from more than one
  catalog revision; the first recorded wins (domain 11-15).
  """

  import Ecto.Query

  alias Cadence.Catalog.{DatabaseRow, RevisionRow}
  alias Cadence.Repo

  @type catalog_revision :: %{
          id: binary(),
          number: integer(),
          label: binary() | nil,
          database_id: binary()
        }

  @doc "`%{mission_model_revision_id => catalog_revision}` for `ids` (absent: none recorded)."
  @spec for_models(binary(), binary(), [binary()]) :: %{binary() => catalog_revision()}
  def for_models(_organization_id, _mission_id, []), do: %{}

  def for_models(organization_id, mission_id, ids) do
    from(row in RevisionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.mission_model_revision_id in ^ids,
      order_by: [asc: row.inserted_at, asc: row.catalog_revision_id],
      select: %{
        model: row.mission_model_revision_id,
        id: row.catalog_revision_id,
        number: row.revision_number,
        label: row.revision_label,
        database_id: row.catalog_database_id
      }
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.model, Map.delete(row, :model)) end)
  end

  @doc """
  D2 (#543, domain's rule (b)): for each group of model revisions, the earliest catalog revision in
  the tenant that names any of them (by `inserted_at`, then `catalog_revision_id`), with its
  database. A layer's group is the revisions that carry it, so this is the earliest catalog
  revision that imported the layer. Absent: no catalog revision names any of them.
  """
  @spec first_for_groups(binary(), binary(), %{term() => [binary()]}) :: %{
          term() => %{
            id: binary(),
            number: integer(),
            database: %{id: binary(), name: binary() | nil}
          }
        }
  def first_for_groups(organization_id, mission_id, groups) do
    ids = groups |> Map.values() |> List.flatten() |> Enum.uniq()
    rows = ordered(organization_id, mission_id, ids)

    for {key, members} <- groups,
        members = MapSet.new(members),
        %{} = row <- [Enum.find(rows, &MapSet.member?(members, &1.model))],
        into: %{},
        do: {key, %{id: row.id, number: row.number, database: row.database}}
  end

  defp ordered(_organization_id, _mission_id, []), do: []

  defp ordered(organization_id, mission_id, ids) do
    from(row in RevisionRow,
      left_join: database in DatabaseRow,
      on:
        database.catalog_database_id == row.catalog_database_id and
          database.organization_id == row.organization_id and
          database.mission_id == row.mission_id,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.mission_model_revision_id in ^ids,
      order_by: [asc: row.inserted_at, asc: row.catalog_revision_id],
      select: %{
        model: row.mission_model_revision_id,
        id: row.catalog_revision_id,
        number: row.revision_number,
        database: %{id: row.catalog_database_id, name: database.name}
      }
    )
    |> Repo.all()
  end

  @doc """
  The catalog revision `for_models/3` names for one model revision, as the whole `Revision`
  (same order: the first recorded), or nil. One query, so a reader gets every field or none.
  """
  @spec first_for_model(binary(), binary(), binary()) :: Cadence.Catalog.Revision.t() | nil
  def first_for_model(organization_id, mission_id, mission_model_revision_id) do
    from(row in RevisionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.mission_model_revision_id == ^mission_model_revision_id,
      order_by: [asc: row.inserted_at, asc: row.catalog_revision_id],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> nil
      %RevisionRow{} = row -> RevisionRow.to_domain(row)
    end
  end
end
