defmodule Cadence.MissionModels.AuthoredHead do
  @moduledoc """
  The mission's authored monitoring layer, versioned (ADR-020 P3 slice M1, #451).

  Each version names an immutable authored `Layer` and the applied monitoring change set and
  ledger revision that approved it: the set's own review, or its 'direct' apply, is the approval
  of the layer (the addendum's change-set lanes, #92 a). The newest version is the mission's
  **head**: every effective revision a craft runs is its composition compiled at the head
  (`Compositions.effective_revision/5`). A version is recorded only by an applied monitoring set,
  inside its transaction and under the mission head lock, so versions are a gapless sequence;
  `Control.AuthoredVersions.record/5` is the only way in.

  **A version is cumulative.** A head compiles as the composition's layers plus that one authored
  layer, so each version's layer holds every authored declaration of the mission, not a delta
  over the previous version. A retired declaration is simply absent from the next version.
  """

  import Ecto.Query

  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.MissionModels
  alias Cadence.MissionModels.AuthoredVersionRow
  alias Cadence.Repo

  @type version :: %{
          version: pos_integer(),
          layer_id: binary(),
          change_set_id: binary(),
          revision_number: pos_integer(),
          approval: binary(),
          decided_at: DateTime.t()
        }

  @doc "The mission's head, or nil before its first monitoring apply."
  @spec head(binary(), binary()) :: version() | nil
  def head(organization_id, mission_id) do
    organization_id
    |> scoped(mission_id)
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
    |> view()
  end

  @doc """
  Inserts `layer_id` as the next version, for an applied set the caller has already locked and
  checked. Only `Control.AuthoredVersions.record/5` calls it (it holds the set to the
  configuration store, which this context can't read). This side holds the layer and the set's
  uniqueness:

    * the layer is an authored layer of this mission (`:authored_version_layer_mismatch`);
    * the set records no other version (`:authored_version_already_recorded`, and a unique index).

  The layer and the ledger revision are also held by composite foreign keys.
  """
  @spec insert_version(binary(), binary(), binary(), %{
          change_set_id: binary(),
          revision_number: pos_integer(),
          approval: binary()
        }) :: {:ok, version()} | {:error, term()}
  def insert_version(
        organization_id,
        mission_id,
        layer_id,
        %{change_set_id: change_set_id} = approved
      )
      when is_binary(layer_id) do
    with :ok <- authored_layer(organization_id, mission_id, layer_id),
         :ok <- not_recorded(change_set_id) do
      insert(organization_id, mission_id, layer_id, approved)
    end
  end

  defp authored_layer(organization_id, mission_id, layer_id) do
    case MissionModels.fetch_layer(organization_id, mission_id, layer_id) do
      {:ok,
       %Layer{layer_kind: :authored, organization_id: ^organization_id, mission_id: ^mission_id}} ->
        :ok

      _other ->
        {:error, :authored_version_layer_mismatch}
    end
  end

  defp not_recorded(change_set_id) do
    if Repo.exists?(where(AuthoredVersionRow, [row], row.change_set_id == ^change_set_id)),
      do: {:error, :authored_version_already_recorded},
      else: :ok
  end

  defp insert(organization_id, mission_id, layer_id, approved) do
    next =
      case head(organization_id, mission_id) do
        nil -> 1
        %{version: version} -> version + 1
      end

    %AuthoredVersionRow{
      organization_id: organization_id,
      mission_id: mission_id,
      version: next,
      layer_id: layer_id,
      change_set_id: approved.change_set_id,
      revision_number: approved.revision_number,
      approval: approved.approval,
      decided_at: DateTime.utc_now()
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:revision_number,
      name: :mission_model_authored_versions_revision_fk
    )
    |> Ecto.Changeset.unique_constraint(:change_set_id,
      name: :mission_model_authored_versions_change_set_id_index
    )
    # Deferred to commit in an apply; immediate when a caller has set constraints immediate.
    |> Ecto.Changeset.check_constraint(:state,
      name: :mission_model_authored_versions_applied
    )
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, view(row)}
      {:error, %Ecto.Changeset{errors: errors}} -> {:error, refusal(errors)}
    end
  end

  @doc "Which of `layer_ids` are recorded versions of the mission (approved authored heads)."
  @spec recorded(binary(), binary(), [binary()]) :: MapSet.t(binary())
  def recorded(_organization_id, _mission_id, []), do: MapSet.new()

  def recorded(organization_id, mission_id, layer_ids) do
    organization_id
    |> scoped(mission_id)
    |> where([row], row.layer_id in ^layer_ids)
    |> select([row], row.layer_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp refusal(errors) do
    cond do
      Keyword.has_key?(errors, :revision_number) -> :authored_version_revision_unknown
      Keyword.has_key?(errors, :state) -> :authored_version_not_applied
      true -> :authored_version_already_recorded
    end
  end

  defp scoped(organization_id, mission_id),
    do:
      where(
        AuthoredVersionRow,
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )

  defp view(nil), do: nil

  defp view(%AuthoredVersionRow{} = row),
    do:
      Map.take(row, [
        :version,
        :layer_id,
        :change_set_id,
        :revision_number,
        :approval,
        :decided_at
      ])
end
