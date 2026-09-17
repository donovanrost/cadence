defmodule Cadence.Reads.Catalog.SpacecraftUsage do
  @moduledoc false
  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.SpacecraftStore

  def load(mission, catalog_id) do
    ConfigurationLock.run(mission.organization_id, mission.mission_id, fn ->
      with {:ok, usage} <- usage(mission, catalog_id) do
        {:ok, %{mission_id: mission.mission_id, usage: usage}}
      end
    end)
  end

  defp usage(mission, catalog_id) do
    org = mission.organization_id
    mission_id = mission.mission_id

    with {:ok, active} <- Active.load(mission) do
      saved_ids = Drafts.catalog_usage_ids(org, mission_id, catalog_id)

      active_ids = active_usage_ids(active.entries, catalog_id)

      ids = (active_ids ++ saved_ids) |> Enum.uniq() |> Enum.sort() |> Enum.take(100)

      usage_rows(org, mission_id, ids, saved_ids, active_ids)
    end
  end

  defp active_usage_ids(entries, catalog_id) do
    Enum.flat_map(entries, fn {id, entry} ->
      if entry["catalog_revision_id"] == catalog_id, do: [id], else: []
    end)
  end

  defp usage_rows(org, mission_id, ids, saved_ids, active_ids) do
    with {:ok, spacecraft} <- SpacecraftStore.fetch_spacecrafts(org, mission_id, ids) do
      {:ok,
       Enum.map(ids, fn id ->
         craft = Map.fetch!(spacecraft, id)

         %{
           id: id,
           name: craft.display_name,
           active: id in active_ids,
           saved: id in saved_ids,
           href: "/missions/#{mission_id}/spacecraft/#{id}?section=changes"
         }
       end)}
    end
  end
end
