defmodule Cadence.Reads.RepairDiff do
  @moduledoc """
  S8: what a repair changes, by comparing the source plan's selected passes
  with the repair run's candidate plan. Snapshots differ between runs, so a
  pass is matched by spacecraft + provider opportunity ref.

  - `kept`: in both.
  - `moved`: a spacecraft lost one pass and gained another (paired in time
    order), with `offset_s` between their starts.
  - `dropped` / `added`: the rest.
  """

  alias Cadence.ContactPlanning.ContactOpportunitySnapshot
  alias Cadence.Reads.StationRefs

  @spec diff(
          [ContactOpportunitySnapshot.t()],
          [ContactOpportunitySnapshot.t()],
          StationRefs.index()
        ) :: map()
  def diff(before, after_passes, stations \\ %{}) do
    before_keys = MapSet.new(before, &key/1)
    after_keys = MapSet.new(after_passes, &key/1)

    kept = Enum.filter(after_passes, &MapSet.member?(before_keys, key(&1)))
    gone = Enum.reject(before, &MapSet.member?(after_keys, key(&1)))
    new = Enum.reject(after_passes, &MapSet.member?(before_keys, key(&1)))

    {moved, dropped, added} = pair(gone, new, stations)
    pass = &pass(&1, stations)

    %{
      kept: Enum.map(kept, pass),
      moved: moved,
      dropped: Enum.map(dropped, pass),
      added: Enum.map(added, pass),
      totals: %{
        kept: length(kept),
        moved: length(moved),
        dropped: length(dropped),
        added: length(added)
      }
    }
  end

  defp pair(gone, new, stations) do
    gone_by = Enum.group_by(gone, &spacecraft/1)
    new_by = Enum.group_by(new, &spacecraft/1)

    (Map.keys(gone_by) ++ Map.keys(new_by))
    |> Enum.uniq()
    |> Enum.reduce({[], [], []}, fn spacecraft_id, {moved, dropped, added} ->
      old = gone_by |> Map.get(spacecraft_id, []) |> Enum.sort_by(& &1.starts_at, DateTime)
      fresh = new_by |> Map.get(spacecraft_id, []) |> Enum.sort_by(& &1.starts_at, DateTime)
      pairs = Enum.zip(old, fresh)

      {
        moved ++
          Enum.map(pairs, fn {from, to} ->
            %{
              spacecraft_id: spacecraft_id,
              from: pass(from, stations),
              to: pass(to, stations),
              offset_s: DateTime.diff(to.starts_at, from.starts_at)
            }
          end),
        dropped ++ Enum.drop(old, length(pairs)),
        added ++ Enum.drop(fresh, length(pairs))
      }
    end)
  end

  defp pass(snapshot, stations) do
    %{
      snapshot_id: snapshot.contact_opportunity_snapshot_id,
      spacecraft_id: spacecraft(snapshot),
      station: StationRefs.of_snapshot(snapshot, stations),
      starts_at: snapshot.starts_at,
      ends_at: snapshot.ends_at
    }
  end

  defp key(snapshot), do: {spacecraft(snapshot), snapshot.provider_opportunity_ref}
  defp spacecraft(snapshot), do: (snapshot.route_binding_document || %{})["spacecraft_id"]
end
