defmodule Cadence.Catalog.ChangeSetSpacecraft do
  @moduledoc """
  The spacecraft a change set's generation changed (#734), kept out of the activation metadata,
  which carries only `"change_set" => %{"id", "revision", "count"}`. The rows are keyed by change
  set id and revision, so a generation's metadata stays constant-size however many craft it touches
  and command authoring's metadata bound never depends on a change set's size.

  Every read takes the request's own organization and mission and refuses a reference to another
  mission's change set (the rows are filtered on both).
  """

  import Ecto.Query

  alias Cadence.Catalog.ChangeSetSpacecraft.Row
  alias Cadence.Repo

  @chunk 1_000

  @doc """
  Records the changed spacecraft of `change_set_id` at `revision` (idempotent) and returns the
  metadata value for it.
  """
  @spec store(String.t(), String.t(), String.t(), pos_integer(), [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def store(organization_id, mission_id, change_set_id, revision, [_ | _] = ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(change_set_id) and
             is_integer(revision) do
    ids = ids |> Enum.uniq() |> Enum.sort()

    case Repo.transaction(fn ->
           persist(organization_id, mission_id, change_set_id, revision, ids)
         end) do
      {:ok, :ok} ->
        {:ok, %{"id" => change_set_id, "revision" => revision, "count" => length(ids)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(organization_id, mission_id, change_set_id, revision, ids) do
    ids
    |> Enum.map(
      &%{
        organization_id: organization_id,
        mission_id: mission_id,
        change_set_id: change_set_id,
        revision: revision,
        spacecraft_id: &1
      }
    )
    |> Enum.chunk_every(@chunk)
    |> Enum.each(&Repo.insert_all(Row, &1, on_conflict: :nothing))

    stored = Repo.aggregate(scope(organization_id, mission_id, change_set_id, revision), :count)
    if stored == length(ids), do: :ok, else: Repo.rollback(:change_set_spacecraft_mismatch)
  end

  @doc "How many spacecraft the generation changed, from the reference alone (no query)."
  @spec count(map()) :: non_neg_integer() | nil
  def count(%{"change_set" => %{"count" => count}}) when is_integer(count) and count > 0,
    do: count

  def count(_metadata), do: nil

  @doc "The changed spacecraft ids, sorted; `[]` when the metadata names no change set."
  @spec spacecraft_ids(String.t(), String.t(), map()) :: [String.t()]
  def spacecraft_ids(organization_id, mission_id, %{
        "change_set" => %{"id" => change_set_id, "revision" => revision}
      })
      when is_binary(change_set_id) and is_integer(revision) do
    organization_id
    |> scope(mission_id, change_set_id, revision)
    |> select([r], r.spacecraft_id)
    |> Repo.all()
    |> Enum.sort()
  end

  def spacecraft_ids(_organization_id, _mission_id, _metadata), do: []

  @doc "Whether the metadata is a change set's generation."
  @spec change_set?(map()) :: boolean()
  def change_set?(%{"change_set" => %{"id" => id, "revision" => revision}})
      when is_binary(id) and is_integer(revision),
      do: true

  def change_set?(_metadata), do: false

  @doc "The `{change_set_id, revision}` keys among `keys` that changed `spacecraft_id`."
  @spec covering(String.t(), String.t(), [{String.t(), integer()}], String.t()) ::
          MapSet.t({String.t(), integer()})
  def covering(_organization_id, _mission_id, [], _spacecraft_id), do: MapSet.new()

  def covering(organization_id, mission_id, keys, spacecraft_id) do
    ids = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    Row
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.spacecraft_id == ^spacecraft_id and r.change_set_id in ^ids
    )
    |> select([r], {r.change_set_id, r.revision})
    |> Repo.all()
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(keys))
  end

  defp scope(organization_id, mission_id, change_set_id, revision) do
    where(
      Row,
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.change_set_id == ^change_set_id and r.revision == ^revision
    )
  end
end
