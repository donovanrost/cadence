defmodule Cadence.Reads.ScidMismatchEvents do
  @moduledoc """
  The Timeline words for `contact_scid_mismatch` (ux U81 §2, DECISIONS #102): most of a settled
  pass's TM frames carried another SCID, so Cadence refused them before reassembly.

  - Title: "EARENDIL-312 · Most frames on the FBK 03:10Z pass carried another SCID." Without a
    spacecraft name the "EARENDIL-312 · " part is dropped; without a station, "the 03:10Z pass".
  - Detail: "412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. Cadence kept them as
    raw evidence and made no telemetry from them." Without a name, "not this pass's SCID 1".

  SCIDs read "SCID 3", "SCIDs 3 and 7", "SCIDs 3, 7 and 9", more than three "12 different
  SCIDs", and "at least 12 different SCIDs" when the list (at most 8) may be short. Never an id.
  """

  @max_scids 8

  @doc "The row's title from the event payload, the spacecraft name and the station."
  @spec title(map(), binary() | nil, map() | nil) :: binary()
  def title(payload, spacecraft_name, station) do
    pass = [station_label(station), short_time(payload["contact_started_at"])]

    pass =
      case Enum.reject(pass, &is_nil/1) do
        [] -> "the pass"
        parts -> "the #{Enum.join(parts, " ")} pass"
      end

    "#{prefix(spacecraft_name)}Most frames on #{pass} carried another SCID."
  end

  @doc "The row's secondary line."
  @spec detail(map(), binary() | nil) :: binary()
  def detail(payload, spacecraft_name) do
    frames = payload["frames"] || 0
    total = payload["frames_total"] || frames
    whose = if spacecraft_name, do: "#{spacecraft_name}'s", else: "this pass's"

    "#{frames} of #{total} frames carried #{scid_words(payload)}, not #{whose} SCID " <>
      "#{payload["expected_scid"]}. Cadence kept them as raw evidence and made no telemetry " <>
      "from them."
  end

  @doc "The observed SCIDs in words (ux U81 §2)."
  @spec scid_words(map()) :: binary()
  def scid_words(payload) do
    scids = payload["scids"] |> List.wrap() |> Enum.filter(&is_integer/1) |> Enum.sort()
    count = max(payload["scid_count"] || 0, length(scids))

    cond do
      count == 0 -> "another SCID"
      count != length(scids) or length(scids) >= @max_scids -> "at least #{count} different SCIDs"
      count > 3 -> "#{count} different SCIDs"
      count == 1 -> "SCID #{hd(scids)}"
      true -> "SCIDs #{Enum.join(Enum.drop(scids, -1), ", ")} and #{List.last(scids)}"
    end
  end

  defp prefix(name) when is_binary(name) and name != "", do: "#{name} · "
  defp prefix(_none), do: ""

  # The title names the station by its code (ux), else its name.
  defp station_label(%{code: code}) when is_binary(code) and code != "", do: code
  defp station_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp station_label(_none), do: nil

  defp short_time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> Calendar.strftime(at, "%H:%MZ")
      _bad -> nil
    end
  end

  defp short_time(_none), do: nil
end
