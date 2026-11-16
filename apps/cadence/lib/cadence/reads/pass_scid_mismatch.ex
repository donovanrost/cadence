defmodule Cadence.Reads.PassScidMismatch do
  @moduledoc """
  A pass detail's `scid_mismatch` (ux U81 §2, DECISIONS #102): TM frames whose header SCID wasn't
  the pass's, refused before reassembly, so they made no telemetry (the bytes stay in the journal).
  From the settlement domain records on the realized contact,
  `metadata["settlement"]["scid_mismatch"]` (one entry per path that checked a frame):

      %{expected_scid, paths: [%{station, frames, scids, scid_count, path_id, provider_binding_id}]}

  Only paths that refused a frame are listed (`frames > 0`), most frames first; `scids` sorted, at
  most 8; `station` is the entry's `ground_station_ref` resolved like the pass rows' (nil without
  one). nil when nothing was refused, the contact hasn't settled, or the record predates it, never
  an empty list.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts

  @max_scids 8

  @spec read(binary(), binary(), binary() | nil) :: map() | nil
  def read(_org, _mission, nil), do: nil

  def read(org, mission, realized_contact_id) do
    case Contacts.fetch_realized_contact(org, mission, realized_contact_id) do
      {:ok, contact} -> from_metadata(contact.metadata, fn -> StationRefs.index(org, mission) end)
      _missing -> nil
    end
  end

  @doc "The field from a realized contact's metadata (`index` is called only when needed)."
  @spec from_metadata(term(), (-> StationRefs.index())) :: map() | nil
  def from_metadata(%{} = metadata, index) do
    case refused(get_in(metadata, ["settlement", "scid_mismatch"])) do
      [] -> nil
      entries -> build(entries, index.())
    end
  end

  def from_metadata(_metadata, _index), do: nil

  defp refused(entries) when is_list(entries) do
    Enum.filter(entries, fn
      %{"frames" => frames, "expected_scid" => scid} -> positive?(frames) and is_integer(scid)
      _other -> false
    end)
  end

  defp refused(_none), do: []

  defp build([first | _] = entries, index) do
    %{
      expected_scid: first["expected_scid"],
      paths:
        entries
        |> Enum.sort_by(& &1["frames"], :desc)
        |> Enum.map(&path(&1, index))
    }
  end

  defp path(entry, index) do
    scids = scids(entry["scids"])

    %{
      station: station(entry["ground_station_ref"], index),
      frames: entry["frames"],
      scids: scids,
      scid_count: count(entry["scid_count"], scids),
      path_id: entry["path_id"],
      provider_binding_id: entry["provider_binding_id"]
    }
  end

  defp scids(list) when is_list(list),
    do: list |> Enum.filter(&is_integer/1) |> Enum.uniq() |> Enum.sort() |> Enum.take(@max_scids)

  defp scids(_none), do: []

  # domain's count is uncapped; never below what the list shows.
  defp count(n, scids) when is_integer(n), do: max(n, length(scids))
  defp count(_none, scids), do: length(scids)

  defp station(ref, index) when is_binary(ref) and ref != "", do: StationRefs.resolve(ref, index)
  defp station(_none, _index), do: nil

  defp positive?(n), do: is_integer(n) and n > 0
end
