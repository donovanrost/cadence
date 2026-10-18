defmodule Cadence.Reads.Catalog.SpacecraftUsage do
  @moduledoc "Catalog usage from active configurations and each spacecraft's latest saved configuration."
  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.SpacecraftStore

  # Read both sources under the same lock used by configuration saves and activation.
  # Counts use the complete snapshot; only the displayed spacecraft rows are bounded.
  def snapshot(mission) do
    ConfigurationLock.run(mission.organization_id, mission.mission_id, fn ->
      with {:ok, active} <- Active.load(mission) do
        saved = Drafts.catalog_usage_entries(mission.organization_id, mission.mission_id)

        {:ok,
         %{
           active:
             Enum.map(active.entries, fn {id, entry} -> {id, entry["catalog_revision_id"]} end),
           saved: Enum.map(saved, &{&1.spacecraft_id, &1.catalog_revision_id})
         }}
      end
    end)
  end

  def summary(snapshot, revision_ids) do
    %{
      active_count: snapshot.active |> matching_ids(revision_ids) |> MapSet.size(),
      saved_count: snapshot.saved |> matching_ids(revision_ids) |> MapSet.size()
    }
  end

  def load(mission, catalog_id) do
    with {:ok, snapshot} <- snapshot(mission) do
      active_ids = matching_ids(snapshot.active, [catalog_id])
      saved_ids = matching_ids(snapshot.saved, [catalog_id])
      ids = MapSet.union(active_ids, saved_ids) |> Enum.sort()
      displayed_ids = Enum.take(ids, 100)

      with {:ok, spacecraft} <-
             SpacecraftStore.fetch_spacecrafts(
               mission.organization_id,
               mission.mission_id,
               displayed_ids
             ) do
        {:ok,
         %{
           mission_id: mission.mission_id,
           total_count: length(ids),
           usage:
             Enum.map(displayed_ids, fn id ->
               craft = Map.fetch!(spacecraft, id)

               %{
                 id: id,
                 name: craft.display_name,
                 active: MapSet.member?(active_ids, id),
                 saved: MapSet.member?(saved_ids, id),
                 href: "/missions/#{mission.mission_id}/spacecraft/#{id}?section=changes"
               }
             end)
         }}
      end
    end
  end

  defp matching_ids(entries, revision_ids) do
    revisions = MapSet.new(revision_ids)

    entries
    |> Enum.filter(fn {_id, revision} -> MapSet.member?(revisions, revision) end)
    |> MapSet.new(fn {id, _revision} -> id end)
  end
end
