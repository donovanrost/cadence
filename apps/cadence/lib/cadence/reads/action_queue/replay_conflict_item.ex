defmodule Cadence.Reads.ActionQueue.ReplayConflictItem do
  @moduledoc """
  The wire fields of a `replay_conflict` attention item (#99 follow-up, ux U84 'Stuck processing'):
  its source keys, the affected craft named as spacecraftRefs (U25: names, not ids) and the pass
  label (station code + AOS). Contract: docs/apogee/api/contacts.md.
  """

  alias Cadence.Reads.ActionQueue.SourceKeys

  @doc "`spacecraft` is the lookups' id => member map; `station` the item's resolved station."
  @spec fields(map(), map(), map()) :: map()
  def fields(attention, spacecraft, station) do
    attention
    |> SourceKeys.take()
    |> Map.merge(%{
      affected_spacecraft: Enum.map(attention.spacecraft_ids, &ref(&1, spacecraft)),
      contact: contact(attention, station)
    })
  end

  # No pass to label (a timer unit, or a hand-started contact with no booking): null, never an
  # object that half-describes one (lead, fe-ops).
  defp contact(%{contact_id: nil}, _station), do: nil

  defp contact(attention, station),
    do: %{id: attention.contact_id, station_code: station.code, starts_at: attention.starts_at}

  defp ref(id, spacecraft) do
    case Map.fetch(spacecraft, id) do
      {:ok, member} -> %{id: id, name: Map.get(member, :name), scid: Map.get(member, :scid)}
      :error -> %{id: id, name: nil, scid: nil}
    end
  end
end
