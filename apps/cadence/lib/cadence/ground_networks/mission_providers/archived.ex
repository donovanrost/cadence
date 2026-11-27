defmodule Cadence.GroundNetworks.MissionProviders.Archived do
  @moduledoc """
  Which pinned mission provider versions belong to an archived provider (#985). Archiving adds a
  newer, archived version while transports keep pinning the older active one, so the pinned
  version alone still looks active.
  """

  import Ecto.Query

  alias Cadence.GroundNetworks.MissionProviders.ProviderRow, as: MissionProviderRow
  alias Cadence.Repo

  @doc """
  The `{provider_id, version}` keys among `keys` whose provider has a NEWER archived version (#985):
  archiving adds an archived version while transports keep pinning the older active one. One
  query for the whole batch.
  """
  @spec archived_since(binary(), binary(), [{binary(), pos_integer()}]) :: MapSet.t()
  def archived_since(_organization_id, _mission_id, []), do: MapSet.new()

  def archived_since(organization_id, mission_id, keys) do
    ids = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    latest_archived =
      MissionProviderRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.provider_id in ^ids and row.lifecycle_state == "archived"
      )
      |> group_by([row], row.provider_id)
      |> select([row], {row.provider_id, max(row.version)})
      |> Repo.all()
      |> Map.new()

    keys
    |> Enum.filter(fn {id, version} ->
      case Map.get(latest_archived, id) do
        nil -> false
        archived -> archived > version
      end
    end)
    |> MapSet.new()
  end
end
