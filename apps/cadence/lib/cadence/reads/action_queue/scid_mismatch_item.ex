defmodule Cadence.Reads.ActionQueue.ScidMismatchItem do
  @moduledoc """
  The `contact_scid_mismatch` attention item's own fields (ux U81 §2, DECISIONS #102), from
  `Cadence.Contacts.ScidMismatchAttention`'s row: the pass's craft, named, and its refused frames
  summed over the settlement's per-path entries.

      realized_contact_id,
      spacecraft: %{id, name, scid} | nil,
      scid_mismatch: %{expected_scid, frames, frames_total, scids, scid_count}

  `frames` sums the refused frames, `frames_total` every integrity-checked frame (all paths, so
  'most' reads the same as domain's rule), `scids` the observed SCIDs over all paths (sorted, at
  most 8) and `scid_count` the larger of the largest per-path count and the union's size before
  the cap, so the list is complete exactly when `scid_count == length(scids) < 8`.
  """

  @max_scids 8

  @spec fields(map(), map()) :: map()
  def fields(attention, spacecraft_names) do
    entries = attention |> Map.get(:scid_mismatch) |> List.wrap() |> Enum.filter(&is_map/1)

    %{
      realized_contact_id: Map.get(attention, :realized_contact_id),
      spacecraft: spacecraft(Map.get(attention, :spacecraft_id), spacecraft_names),
      scid_mismatch: summary(entries)
    }
  end

  defp spacecraft(nil, _names), do: nil

  defp spacecraft(id, names) do
    case Map.get(names, id) do
      %{name: name, scid: scid} -> %{id: id, name: name, scid: scid}
      _unknown -> %{id: id, name: nil, scid: nil}
    end
  end

  defp summary([]), do: nil

  defp summary([first | _] = entries) do
    union = entries |> Enum.flat_map(&integers(&1["scids"])) |> Enum.uniq() |> Enum.sort()

    %{
      expected_scid: first["expected_scid"],
      frames: sum(entries, "frames"),
      frames_total: sum(entries, "frames_total"),
      scids: Enum.take(union, @max_scids),
      scid_count: Enum.max([length(union) | Enum.map(entries, &count(&1["scid_count"]))])
    }
  end

  defp integers(list) when is_list(list), do: Enum.filter(list, &is_integer/1)
  defp integers(_none), do: []

  defp count(n) when is_integer(n), do: n
  defp count(_none), do: 0

  defp sum(entries, key) do
    Enum.reduce(entries, 0, fn entry, acc ->
      case entry[key] do
        n when is_integer(n) and n > 0 -> acc + n
        _none -> acc
      end
    end)
  end
end
