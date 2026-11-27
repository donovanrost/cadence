defmodule Cadence.GroundNetworks.PredictedPasses.Recompute do
  @moduledoc """
  One recompute run of a mission's predicted passes (#891, docs/pass-prediction-design.md). Each
  run holds the mission's advisory lock for its whole transaction, so runs of one mission never
  interleave, and loads, computes and writes inside it. The search itself touches no database.

  "Now" splits history from prediction: a run replaces the passes that end after now (a pass in
  progress included, re-found whole because the search traces a pass open at its window start
  back to its AOS) and leaves passes that already ended for planning history until the prune.

  | Run | Recomputes |
  | --- | --- |
  | `:full` | every spacecraft and station over `[now, now + horizon)` |
  | `{:spacecraft, ids}` | those spacecraft, every station, up to the stored horizon end |
  | `{:stations, ids}` | those stations, every spacecraft, up to the stored horizon end |
  | `:extend` | `[old horizon end, now + horizon)`: passes ending after the old end are deleted and found again whole, so a pass that crosses it is replaced, not stored twice |
  | `:prune` | deletes passes that ended more than 7 days ago |

  Only active spacecraft are predicted: archiving one stages its spacecraft run, which then only
  deletes its passes from now on.

  A spacecraft, station or extension run on a mission with no stored state, or whose horizon end
  has already passed, runs `:full` instead.
  """

  alias Cadence.Comms.GroundStationStore
  alias Cadence.GroundNetworks.ElementSets
  alias Cadence.GroundNetworks.PredictedPasses.{Compute, Settings, Store}
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @prune_after_days 7

  @type kind :: :full | :extend | :prune | {:spacecraft, [binary()]} | {:stations, [binary()]}
  @type summary :: %{
          run: atom(),
          deleted: non_neg_integer(),
          inserted: non_neg_integer(),
          unpropagated: non_neg_integer(),
          not_bracketed: non_neg_integer()
        }

  @spec run(binary(), binary(), kind(), DateTime.t()) :: {:ok, summary()} | {:error, term()}
  def run(organization_id, mission_id, kind, now \\ DateTime.utc_now()) do
    Repo.transaction(
      fn ->
        :ok = Store.lock!(mission_id)
        state = Store.state(organization_id, mission_id)
        do_run(kind, {organization_id, mission_id}, state, now)
      end,
      timeout: :infinity
    )
  end

  defp do_run(:prune, {org, mission}, _state, now) do
    deleted = Store.prune!(org, mission, DateTime.add(now, -@prune_after_days * 86_400))
    summary(:prune, deleted, 0, %{unpropagated: %{}, not_bracketed: %{}})
  end

  defp do_run(:full, scope, _state, now), do: full(scope, now)

  defp do_run(_kind, scope, nil, now), do: full(scope, now)

  defp do_run(kind, scope, state, now) do
    if DateTime.compare(state.horizon_end, now) == :gt,
      do: incremental(kind, scope, state, now),
      else: full(scope, now)
  end

  defp full({org, mission}, now) do
    to = horizon_end(org, mission, now)
    stations = Compute.stations(GroundStationStore.list_ground_stations(org, mission))
    result = Compute.run(active_sets(org, mission), stations, now, to)
    deleted = Store.delete_after!(org, mission, now, :mission)
    inserted = Store.insert!(org, mission, now, result.rows)

    :ok =
      Store.put_state!(org, mission, %{
        horizon_end: to,
        computed_at: now,
        unpropagated: result.unpropagated,
        not_bracketed: result.not_bracketed
      })

    summary(:full, deleted, inserted, result)
  end

  defp incremental({:spacecraft, ids}, {org, mission}, state, now) do
    stations = Compute.stations(GroundStationStore.list_ground_stations(org, mission))
    sets = active_sets(org, mission, ids)
    result = Compute.run(sets, stations, now, state.horizon_end)
    deleted = Store.delete_after!(org, mission, now, {:spacecraft, ids})
    inserted = Store.insert!(org, mission, now, result.rows)

    :ok =
      Store.put_state!(org, mission, %{
        horizon_end: state.horizon_end,
        computed_at: now,
        unpropagated: state.unpropagated |> Map.drop(ids) |> Map.merge(result.unpropagated),
        not_bracketed: replace_pairs(state.not_bracketed, result.not_bracketed, 0, ids)
      })

    summary(:spacecraft, deleted, inserted, result)
  end

  defp incremental({:stations, ids}, {org, mission}, state, now) do
    chosen =
      org
      |> GroundStationStore.list_ground_stations(mission)
      |> Enum.filter(&(&1.ground_station_id in ids))

    sets = active_sets(org, mission)
    result = Compute.run(sets, Compute.stations(chosen), now, state.horizon_end)
    deleted = Store.delete_after!(org, mission, now, {:stations, ids})
    inserted = Store.insert!(org, mission, now, result.rows)

    :ok =
      Store.put_state!(org, mission, %{
        horizon_end: state.horizon_end,
        computed_at: now,
        unpropagated: Map.merge(state.unpropagated, result.unpropagated),
        not_bracketed: replace_pairs(state.not_bracketed, result.not_bracketed, 1, ids)
      })

    summary(:stations, deleted, inserted, result)
  end

  defp incremental(:extend, {org, mission}, state, now) do
    old_end = state.horizon_end
    new_end = horizon_end(org, mission, now)

    if DateTime.compare(new_end, old_end) == :gt do
      stations = Compute.stations(GroundStationStore.list_ground_stations(org, mission))
      sets = active_sets(org, mission)
      result = Compute.run(sets, stations, old_end, new_end)
      deleted = Store.delete_after!(org, mission, old_end, :mission)
      inserted = Store.insert!(org, mission, now, result.rows)

      :ok =
        Store.put_state!(org, mission, %{
          horizon_end: new_end,
          computed_at: now,
          unpropagated: Map.merge(state.unpropagated, result.unpropagated),
          not_bracketed:
            Map.merge(state.not_bracketed, result.not_bracketed, fn _, a, b -> a + b end)
        })

      summary(:extend, deleted, inserted, result)
    else
      # The horizon setting shrank: drop what now lies beyond it.
      deleted = Store.delete_from_aos!(org, mission, new_end)

      :ok =
        Store.put_state!(org, mission, %{
          horizon_end: new_end,
          computed_at: now,
          unpropagated: state.unpropagated,
          not_bracketed: state.not_bracketed
        })

      summary(:extend, deleted, 0, %{unpropagated: %{}, not_bracketed: %{}})
    end
  end

  # Only active spacecraft are predicted: an archived one keeps its element sets (history) but
  # gets no passes, and its run only deletes them.
  defp active_sets(org, mission, ids \\ nil) do
    active = org |> SpacecraftStore.active_identities(mission) |> MapSet.new(& &1.id)

    sets =
      if ids,
        do: ElementSets.current_for(org, mission, ids),
        else: ElementSets.current_for_mission(org, mission)

    Enum.filter(sets, &MapSet.member?(active, &1.spacecraft_id))
  end

  defp horizon_end(org, mission, now),
    do: DateTime.add(now, Settings.horizon_days(org, mission) * 86_400)

  # Drops the pairs whose spacecraft (part 0) or station (part 1) was recomputed, then adds the
  # run's counts.
  defp replace_pairs(stored, fresh, part, ids) do
    stored
    |> Map.reject(fn {key, _count} -> Enum.at(String.split(key, "|", parts: 2), part) in ids end)
    |> Map.merge(fresh)
  end

  defp summary(run, deleted, inserted, result) do
    %{
      run: run,
      deleted: deleted,
      inserted: inserted,
      unpropagated: map_size(result.unpropagated),
      not_bracketed: result.not_bracketed |> Map.values() |> Enum.sum()
    }
  end
end
