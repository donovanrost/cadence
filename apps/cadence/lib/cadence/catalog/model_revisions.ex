defmodule Cadence.Catalog.ModelRevisions do
  @moduledoc """
  Which catalog revision introduced each mission-model revision (ux U65: the console names a
  model by its catalog revision, "catalog rev 4"). A model revision can come from more than one
  catalog revision; the first recorded wins (domain 11-15).
  """

  import Ecto.Query

  alias Cadence.Catalog.RevisionRow
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
  `%{mission_model_revision_id => revision_number}`: the first catalog revision OF ONE DATABASE
  that names each model revision (#119's runs table; absent: none in that database).
  """
  @spec numbers_in_database(binary(), binary(), binary(), [binary()]) :: %{binary() => integer()}
  def numbers_in_database(_organization_id, _mission_id, _database_id, []), do: %{}

  def numbers_in_database(organization_id, mission_id, database_id, ids) do
    from(row in RevisionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.catalog_database_id == ^database_id and row.mission_model_revision_id in ^ids,
      order_by: [asc: row.inserted_at, asc: row.catalog_revision_id],
      select: {row.mission_model_revision_id, row.revision_number}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {model, number}, acc -> Map.put_new(acc, model, number) end)
  end
end
