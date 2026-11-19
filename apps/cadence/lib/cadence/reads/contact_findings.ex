defmodule Cadence.Reads.ContactFindings do
  @moduledoc """
  Contacts D4 "Needs a decision" (M22): problems across the mission's live bookings in a window
  (default: the next 6 h), each with a sentence. Built on the passes read (`Reads.Passes`) and
  station availability (S7):

  - `station_double_booked` (caution): two live bookings at the same station overlap. Bookings
    on different named antennas of the station don't conflict.
  - `booked_into_outage` (critical): a live booking falls in a station outage or maintenance.
  - `coverage_gap` (critical): a spacecraft has no live pass for longer than `max_gap_s`
    (default 4 h). Passes up to `max_gap_s` before the window count, so a pass just before it
    isn't mistaken for a gap.

  Live means requesting, pending, confirmed or active. Fix proposals (another station, an
  opportunity) need a provider search, which this read doesn't run: `fix` is `null`, and the
  console offers "Open in Plan".
  """

  alias Cadence.Comms.StationAvailability
  alias Cadence.Reads.Passes
  alias Cadence.SpacecraftStore

  @live ~w(requesting pending confirmed active)
  @default_max_gap_s 4 * 3600

  @spec load(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) :: map()
  def load(organization_id, mission_id, from, to, opts \\ []) do
    max_gap_s = Keyword.get(opts, :max_gap_s, @default_max_gap_s)

    %{passes: rows, truncated: truncated} =
      Passes.load(organization_id, mission_id, DateTime.add(from, -max_gap_s), to)

    build(%{
      from: from,
      to: to,
      max_gap_s: max_gap_s,
      truncated: truncated,
      passes: rows,
      outages: StationAvailability.blocking_windows(organization_id, mission_id, from, to),
      spacecraft: SpacecraftStore.list_spacecraft(organization_id, mission_id)
    })
  end

  @doc "Pure builder over pass rows (`Reads.Passes`), outages by station id and spacecraft."
  @spec build(map()) :: map()
  def build(%{from: from, to: to, max_gap_s: max_gap_s} = input) do
    live = Enum.filter(input.passes, &(&1.state in @live))
    in_window = Enum.filter(live, &DateTime.after?(&1.ends_at, from))

    findings =
      double_bookings(in_window) ++
        outage_bookings(in_window, input.outages) ++
        gaps(input.spacecraft, live, from, to, max_gap_s)

    %{
      from: from,
      to: to,
      max_gap_s: max_gap_s,
      truncated: Map.get(input, :truncated, false),
      findings: Enum.sort_by(findings, & &1.at, DateTime),
      counts: %{
        conflicts: Enum.count(findings, &(&1.kind != "coverage_gap")),
        gaps: Enum.count(findings, &(&1.kind == "coverage_gap"))
      }
    }
  end

  defp double_bookings(passes) do
    passes
    |> Enum.group_by(&station_key/1)
    |> Enum.reject(fn {key, _passes} -> is_nil(key) end)
    |> Enum.flat_map(fn {_key, station_passes} ->
      station_passes
      |> Enum.sort_by(& &1.starts_at, DateTime)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [a, b] -> overlap_s(a, b) > 0 and same_antenna?(a, b) end)
      |> Enum.map(fn [a, b] -> double_booked(a, b) end)
    end)
  end

  defp double_booked(a, b) do
    station = a.station
    overlap = overlap_s(a, b)

    %{
      id: "station_double_booked:#{a.id}:#{b.id}",
      kind: "station_double_booked",
      severity: "caution",
      at: b.starts_at,
      station: station,
      spacecraft: nil,
      passes: [pass(a), pass(b)],
      overlap_s: overlap,
      message:
        "#{craft(a)} and #{craft(b)} overlap by #{duration(overlap)} at #{station_label(station)}.",
      fix: nil
    }
  end

  defp outage_bookings(passes, outages) do
    for pass <- passes,
        id = pass.station.id,
        is_binary(id),
        window =
          StationAvailability.overlaps?(Map.get(outages, id, []), pass.starts_at, pass.ends_at),
        window != nil do
      %{
        id: "booked_into_outage:#{pass.id}:#{window.window_id}",
        kind: "booked_into_outage",
        severity: "critical",
        at: pass.starts_at,
        station: pass.station,
        spacecraft: pass.spacecraft,
        passes: [pass(pass)],
        overlap_s: nil,
        message:
          "#{craft(pass)}'s pass at #{station_label(pass.station)} falls in a station outage.",
        fix: nil
      }
    end
  end

  defp gaps(spacecraft, passes, from, to, max_gap_s) do
    by_craft = Enum.group_by(passes, & &1.spacecraft_id)

    for craft <- spacecraft,
        {gap_from, gap_to} <- craft_gaps(Map.get(by_craft, craft.spacecraft_id, []), from, to),
        DateTime.diff(gap_to, gap_from) > max_gap_s do
      gap_s = DateTime.diff(gap_to, gap_from)
      spacecraft = %{id: craft.spacecraft_id, name: craft.display_name, scid: craft.scid}

      %{
        id: "coverage_gap:#{craft.spacecraft_id}:#{DateTime.to_unix(gap_from)}",
        kind: "coverage_gap",
        severity: "critical",
        at: gap_from,
        station: nil,
        spacecraft: spacecraft,
        passes: [],
        gap: %{from: gap_from, to: gap_to, seconds: gap_s},
        overlap_s: nil,
        message: "#{spacecraft.name || craft.spacecraft_id} has no pass for #{duration(gap_s)}.",
        fix: nil
      }
    end
  end

  # Stretches without a live pass, from the last pass before the window (or its start) to the
  # window's end. A stretch still open at `to` counts up to `to`.
  defp craft_gaps(passes, from, to) do
    sorted = Enum.sort_by(passes, & &1.starts_at, DateTime)
    before = sorted |> Enum.filter(&DateTime.before?(&1.ends_at, from)) |> List.last()
    inside = Enum.reject(sorted, &DateTime.before?(&1.ends_at, from))
    start = (before && before.ends_at) || from

    {gaps, last_end} =
      Enum.reduce(inside, {[], start}, fn pass, {acc, cursor} ->
        acc =
          if DateTime.after?(pass.starts_at, cursor),
            do: [{cursor, pass.starts_at} | acc],
            else: acc

        {acc, later(cursor, pass.ends_at)}
      end)

    gaps = if DateTime.before?(last_end, to), do: [{last_end, to} | gaps], else: gaps

    gaps
    |> Enum.reverse()
    |> Enum.filter(fn {_gap_from, gap_to} -> DateTime.after?(gap_to, from) end)
  end

  defp later(a, b), do: if(DateTime.after?(b, a), do: b, else: a)

  defp station_key(%{station: %{id: id}}) when is_binary(id), do: id
  defp station_key(%{station: %{ref: ref}}) when is_binary(ref), do: ref
  defp station_key(_pass), do: nil

  defp same_antenna?(%{antenna: %{id: a}}, %{antenna: %{id: b}})
       when is_binary(a) and is_binary(b),
       do: a == b

  defp same_antenna?(_a, _b), do: true

  defp overlap_s(a, b) do
    start = later(a.starts_at, b.starts_at)
    stop = if DateTime.before?(a.ends_at, b.ends_at), do: a.ends_at, else: b.ends_at
    max(DateTime.diff(stop, start), 0)
  end

  defp pass(row),
    do: %{
      id: row.id,
      spacecraft: row.spacecraft,
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      state: row.state
    }

  defp craft(row),
    do: (row.spacecraft && (row.spacecraft.name || row.spacecraft.id)) || row.spacecraft_id

  defp station_label(%{code: code}) when is_binary(code), do: code
  defp station_label(%{name: name}) when is_binary(name), do: name
  defp station_label(%{ref: ref}) when is_binary(ref), do: ref
  defp station_label(_station), do: "a station"

  defp duration(seconds) when seconds < 60, do: "#{seconds} seconds"
  defp duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)} minutes"

  defp duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    if minutes == 0, do: "#{hours}h", else: "#{hours}h #{minutes}m"
  end
end
