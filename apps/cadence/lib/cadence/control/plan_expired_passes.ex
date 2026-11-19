defmodule Cadence.Control.PlanExpiredPasses do
  @moduledoc """
  #273: the passes an approval leaves out because their offer has already expired, for the
  approve answer's `expired`. It uses the rule execution applies to each item
  (`ContactPlanExecutions`: an opportunity whose `expires_at` is not after now is never booked),
  so the answer counts exactly what booking will skip.

  `nil` when every selected pass can still be booked; otherwise
  `%{"count", "reservable_count", "items" => [%{"spacecraft", "station", "aos"}]}`, the shape the
  console's `expiredReader` reads. Items are in AOS order, capped at 5,000; `count` is never
  capped. The keys are strings and the times ISO-8601, so a replayed answer reads the same.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.SpacecraftStore

  @max_items 5_000

  @spec at(binary(), binary(), binary(), pos_integer(), DateTime.t()) :: map() | nil
  def at(organization_id, mission_id, plan_id, version, %DateTime{} = now) do
    passes =
      ManagementContacts.selected_opportunities(organization_id, mission_id, plan_id, version)

    case Enum.reject(passes, &DateTime.after?(&1.expires_at, now)) do
      [] ->
        nil

      expired ->
        shown =
          expired
          |> Enum.sort_by(&DateTime.to_unix(&1.starts_at, :microsecond))
          |> Enum.take(@max_items)

        stations = StationRefs.index(organization_id, mission_id)
        craft = spacecraft(organization_id, mission_id, shown)

        %{
          "count" => length(expired),
          "reservable_count" => length(passes) - length(expired),
          "items" => Enum.map(shown, &item(&1, craft, stations))
        }
    end
  end

  defp item(snapshot, craft, stations),
    do: %{
      "spacecraft" => Map.get(craft, spacecraft_id(snapshot)),
      "station" => station(StationRefs.of_snapshot(snapshot, stations)),
      "aos" => DateTime.to_iso8601(snapshot.starts_at)
    }

  defp spacecraft(organization_id, mission_id, snapshots) do
    ids = snapshots |> Enum.map(&spacecraft_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case SpacecraftStore.fetch_spacecrafts(organization_id, mission_id, ids) do
      {:ok, found} ->
        Map.new(found, fn {id, craft} ->
          {id, %{"id" => id, "name" => craft.display_name, "scid" => craft.scid}}
        end)

      # Past the store's batch bound: the items still count, with no names.
      {:error, _bounds} ->
        %{}
    end
  end

  defp spacecraft_id(snapshot), do: (snapshot.route_binding_document || %{})["spacecraft_id"]

  defp station(%{id: nil, code: nil, name: nil}), do: nil
  defp station(ref), do: %{"id" => ref.id, "code" => ref.code, "name" => ref.name}
end
