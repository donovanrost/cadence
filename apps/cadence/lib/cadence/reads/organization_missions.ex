defmodule Cadence.Reads.OrganizationMissions do
  @moduledoc """
  The organization's missions for the console (ux pass-2 #11): each with its
  spacecraft count and worst fleet state (`FleetStatus` counts, worst first:
  `critical | caution | stale | nominal | never_heard`; `nil` with no
  spacecraft). Callers authorize the organization first.
  """

  alias Cadence.Missions
  alias Cadence.Reads.FleetStatus

  @worst_first [:critical, :caution, :stale, :nominal, :never_heard]

  @spec list(binary()) :: [map()]
  def list(organization_id) do
    organization_id
    |> Missions.list_missions()
    |> Enum.map(fn mission ->
      counts = FleetStatus.load(organization_id, mission.mission_id).counts

      %{
        id: mission.mission_id,
        slug: mission.slug,
        name: mission.display_name,
        spacecraft_count: counts.total,
        worst_state: worst(counts)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.name || ""))
  end

  @doc "Pure: the worst state with any spacecraft in it."
  @spec worst(map()) :: atom() | nil
  def worst(counts), do: Enum.find(@worst_first, &(Map.get(counts, &1, 0) > 0))
end
