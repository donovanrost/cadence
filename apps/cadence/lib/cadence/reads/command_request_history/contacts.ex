defmodule Cadence.Reads.CommandRequestHistory.Contacts do
  @moduledoc """
  The contact an attempt released into, named for a person: "EARENDIL-007 · PUQ 07:20Z pass"
  for a booked pass (its AOS; the date when it isn't the attempt's day), "EARENDIL-007 · PUQ
  contact" for a hand-started one. The station is its code when known.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts
  alias Cadence.Reads.WindowMoveEvents
  alias Cadence.SpacecraftStore

  @spec load(binary(), binary(), [binary() | nil], binary() | nil) :: map()
  def load(org, mission, contact_ids, spacecraft_id) do
    ids = contact_ids |> Enum.filter(&is_binary/1) |> Enum.uniq()
    %{craft: craft(org, mission, spacecraft_id), by_id: by_id(org, mission, ids)}
  end

  @spec contact(map(), binary() | nil, DateTime.t() | nil) :: map() | nil
  def contact(_ctx, nil, _attempted_at), do: nil

  def contact(ctx, id, attempted_at) do
    %{id: id, label: label(ctx.craft, Map.get(ctx.by_id, id), attempted_at)}
  end

  defp label(craft, %{booked: true} = info, attempted_at),
    do: WindowMoveEvents.label(craft, info.station, info.starts_at, attempted_at)

  defp label(craft, %{station: station}, _attempted_at) when is_binary(station),
    do: "#{craft} · #{station} contact"

  defp label(craft, _info, _attempted_at), do: "#{craft} contact"

  defp craft(_org, _mission, nil), do: "the spacecraft"

  defp craft(org, mission, id) do
    case SpacecraftStore.display_names(org, mission, [id]) do
      {:ok, [%{"name" => name} | _]} when is_binary(name) -> name
      _unknown -> id
    end
  end

  defp by_id(_org, _mission, []), do: %{}

  # Through the Contacts facade: an attempt page names one or two contacts.
  defp by_id(org, mission, ids) do
    stations = StationRefs.index(org, mission)

    for id <- ids,
        {:ok, realized} <- [Contacts.fetch_realized_contact(org, mission, id)],
        into: %{} do
      pass = scheduled(org, mission, realized.scheduled_contact_id)
      ref = station_ref(realized.metadata) || (pass && station_ref(pass.metadata))
      resolved = StationRefs.resolve(ref, stations)

      {id,
       %{
         booked: is_binary(realized.scheduled_contact_id),
         station: resolved.code || resolved.name || ref,
         starts_at: pass && pass.starts_at
       }}
    end
  end

  defp scheduled(_org, _mission, nil), do: nil

  defp scheduled(org, mission, id) do
    case Contacts.fetch_scheduled_contact(org, mission, id) do
      {:ok, pass} -> pass
      _missing -> nil
    end
  end

  defp station_ref(%{"ground_station_ref" => ref}) when is_binary(ref) and ref != "", do: ref
  defp station_ref(_metadata), do: nil
end
