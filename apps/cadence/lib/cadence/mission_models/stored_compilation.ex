defmodule Cadence.MissionModels.StoredCompilation do
  @moduledoc """
  Stores a compiled revision's layer and revision rows, and says whether the revision already
  existed (#119). Identical content in the same organization and mission has the same layer and
  revision ids, so a re-import matches the stored revision instead of making a new one.

  - **Match:** the revision row goes in with `ON CONFLICT DO NOTHING`; zero rows inserted means it
    was already there. A concurrent identical import waits on the key and then inserts nothing, so
    it never touches the stored row's status or decision.
  - **Scope (mms-security, ca-security 11-19):** the ids are global primary keys, so after the
    inserts every layer and the revision are read back by id AND organization AND mission. Any row
    missing under that scope fails closed (`:mission_model_scope_mismatch`); another row's decision
    is never returned.
  """

  import Ecto.Query

  alias Cadence.Catalog.MissionModel.{Layer, Revision}
  alias Cadence.MissionModels.{LayerRow, RevisionRow}
  alias Ecto.Multi

  @type stored :: %{revision_id: binary(), status: binary(), matched_existing: boolean()}

  @doc "Adds the layer and revision inserts to `multi`; `:mission_model_revision` is `matched?`."
  @spec insert(Multi.t(), [Layer.t()], Revision.t()) :: Multi.t()
  def insert(multi, layers, %Revision{} = revision) do
    layers
    |> Enum.reduce(multi, fn layer, acc ->
      Multi.insert(acc, {:mission_model_layer, layer.layer_id}, LayerRow.changeset(layer),
        on_conflict: :nothing
      )
    end)
    |> Multi.run(:mission_model_revision, fn repo, _changes -> insert_revision(repo, revision) end)
  end

  @doc "Adds the fail-closed scope re-read; `:mission_model_stored` is a `t:stored/0`."
  @spec verify(Multi.t(), [Layer.t()], Revision.t()) :: Multi.t()
  def verify(multi, layers, %Revision{} = revision) do
    Multi.run(multi, :mission_model_stored, fn repo, %{mission_model_revision: matched?} ->
      layer_ids = layers |> Enum.map(& &1.layer_id) |> Enum.uniq()

      scoped_layers =
        from(row in LayerRow, where: row.layer_id in ^layer_ids, select: row.layer_id)
        |> in_scope(revision)
        |> repo.all()

      scoped_revision =
        from(row in RevisionRow,
          where: row.revision_id == ^revision.revision_id,
          select: row.status
        )
        |> in_scope(revision)
        |> repo.one()

      if is_binary(scoped_revision) and length(scoped_layers) == length(layer_ids) do
        {:ok,
         %{revision_id: revision.revision_id, status: scoped_revision, matched_existing: matched?}}
      else
        {:error, :mission_model_scope_mismatch}
      end
    end)
  end

  defp insert_revision(repo, revision) do
    with {:ok, row} <-
           revision |> RevisionRow.changeset() |> Ecto.Changeset.apply_action(:insert) do
      attrs =
        row
        |> Map.take(RevisionRow.__schema__(:fields))
        |> Map.put(:inserted_at, DateTime.utc_now())

      {inserted, _rows} = repo.insert_all(RevisionRow, [attrs], on_conflict: :nothing)
      {:ok, inserted == 0}
    end
  end

  defp in_scope(query, %Revision{organization_id: nil, mission_id: mission_id}),
    do: where(query, [row], is_nil(row.organization_id) and row.mission_id == ^mission_id)

  defp in_scope(query, %Revision{organization_id: organization_id, mission_id: mission_id}) do
    where(
      query,
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
  end
end
