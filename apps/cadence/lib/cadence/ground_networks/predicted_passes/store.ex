defmodule Cadence.GroundNetworks.PredictedPasses.Store do
  @moduledoc false
  # Writes for predicted passes (#891): the per-mission lock every recompute takes, deletes by
  # scope, bulk inserts (typed arrays, one statement per 2,000 rows) and the mission's
  # prediction state. Callers run these inside one transaction.

  import Ecto.Query

  alias Cadence.GroundNetworks.PredictedPasses.{PredictedPassRow, PredictionStateRow}
  alias Cadence.Persistence.BulkInsert
  alias Cadence.Repo

  @insert_batch 2_000

  @doc "Serializes recompute runs of one mission until the transaction ends."
  @spec lock!(binary()) :: :ok
  def lock!(mission_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["predicted_passes:" <> mission_id])
    :ok
  end

  @spec state(binary(), binary()) :: PredictionStateRow.t() | nil
  def state(organization_id, mission_id),
    do: Repo.get_by(PredictionStateRow, organization_id: organization_id, mission_id: mission_id)

  @doc "Every mission's prediction state, for the daily maintenance."
  @spec states() :: [PredictionStateRow.t()]
  def states, do: Repo.all(PredictionStateRow)

  @spec put_state!(binary(), binary(), map()) :: :ok
  def put_state!(organization_id, mission_id, attrs) do
    row =
      struct!(
        PredictionStateRow,
        Map.merge(attrs, %{organization_id: organization_id, mission_id: mission_id})
      )

    Repo.insert!(row,
      on_conflict:
        {:replace, [:horizon_end, :computed_at, :unpropagated, :not_bracketed, :search_basis]},
      conflict_target: :mission_id
    )

    :ok
  end

  @doc """
  Deletes the mission's passes that end after `after_time`, narrowed by `scope`:
  `{:spacecraft, ids}`, `{:stations, ids}` or `:mission`. Returns the count.
  """
  @spec delete_after!(binary(), binary(), DateTime.t(), term()) :: non_neg_integer()
  def delete_after!(organization_id, mission_id, after_time, scope) do
    {count, _} =
      organization_id
      |> mission(mission_id)
      # No pass lasts a day, so the AOS bound lets the AOS indexes find them.
      |> where([row], row.aos > ^DateTime.add(after_time, -86_400) and row.los > ^after_time)
      |> scoped(scope)
      |> Repo.delete_all()

    count
  end

  @doc "Deletes the mission's passes whose AOS is at or after `time` (a shortened horizon)."
  @spec delete_from_aos!(binary(), binary(), DateTime.t()) :: non_neg_integer()
  def delete_from_aos!(organization_id, mission_id, time) do
    {count, _} =
      organization_id
      |> mission(mission_id)
      |> where([row], row.aos >= ^time)
      |> Repo.delete_all()

    count
  end

  @doc """
  Deletes the mission's passes that ended before `before`. A pass that ended before then also
  started before then, so the AOS bound lets the mission's AOS index find them.
  """
  @spec prune!(binary(), binary(), DateTime.t()) :: non_neg_integer()
  def prune!(organization_id, mission_id, before) do
    {count, _} =
      organization_id
      |> mission(mission_id)
      |> where([row], row.aos < ^before and row.los < ^before)
      |> Repo.delete_all()

    count
  end

  @spec insert!(binary(), binary(), DateTime.t(), [map()]) :: non_neg_integer()
  def insert!(organization_id, mission_id, computed_at, rows) do
    shared = [organization_id: organization_id, mission_id: mission_id, computed_at: computed_at]

    rows
    |> Enum.chunk_every(@insert_batch)
    |> Enum.reduce(0, fn chunk, count ->
      count + BulkInsert.insert!(PredictedPassRow, chunk, shared)
    end)
  end

  defp mission(organization_id, mission_id) do
    where(
      PredictedPassRow,
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
  end

  defp scoped(query, :mission), do: query

  defp scoped(query, {:spacecraft, ids}),
    do: where(query, [row], row.spacecraft_id in ^ids)

  defp scoped(query, {:stations, ids}),
    do: where(query, [row], row.ground_station_id in ^ids)
end
