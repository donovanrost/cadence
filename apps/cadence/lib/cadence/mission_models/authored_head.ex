defmodule Cadence.MissionModels.AuthoredHead do
  @moduledoc """
  The mission's authored monitoring layer, versioned (ADR-020 P3 slice M1, #451).

  Each version names an immutable authored `Layer` and the applied monitoring change set and
  ledger revision that approved it: the set's own review, or its 'direct' apply, is the approval
  of the layer (the addendum's change-set lanes, #92 a). The newest version is the mission's
  **head**: every effective revision a craft runs is its composition compiled at the head
  (`Compositions.effective_revision/5`). A version is recorded only by an applied monitoring set,
  inside its transaction and under the mission head lock, so versions are a gapless sequence.
  """

  import Ecto.Query

  alias Cadence.MissionModels.AuthoredVersionRow
  alias Cadence.Repo

  @type version :: %{
          version: pos_integer(),
          layer_id: binary(),
          change_set_id: binary(),
          revision_number: pos_integer(),
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
  Records `layer_id` as the next version, approved by applied `change_set_id` as ledger revision
  `revision_number`. Run inside the apply's transaction, under the mission head lock.
  """
  @spec record(binary(), binary(), binary(), binary(), pos_integer()) ::
          {:ok, version()} | {:error, term()}
  def record(organization_id, mission_id, layer_id, change_set_id, revision_number)
      when is_binary(layer_id) and is_binary(change_set_id) and is_integer(revision_number) do
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
      change_set_id: change_set_id,
      revision_number: revision_number,
      decided_at: DateTime.utc_now()
    }
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, view(row)}
      {:error, reason} -> {:error, reason}
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

  defp scoped(organization_id, mission_id),
    do:
      where(
        AuthoredVersionRow,
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )

  defp view(nil), do: nil

  defp view(%AuthoredVersionRow{} = row),
    do: Map.take(row, [:version, :layer_id, :change_set_id, :revision_number, :decided_at])
end
