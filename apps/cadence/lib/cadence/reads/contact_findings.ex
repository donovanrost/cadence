defmodule Cadence.Reads.ContactFindings do
  @moduledoc """
  Contacts D4 "Needs a decision" (M22): problems across the mission's live bookings in a window
  (default: the next 6 h), each with a sentence. Derived from bookings and station availability:

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

  alias Cadence.Comms.{StationAvailability, StationRefs}
  alias Cadence.Contacts.FindingWindows
  alias Cadence.Reads.WindowCursor
  alias Cadence.SpacecraftStore

  @default_max_gap_s 4 * 3600
  @default_limit 100

  @spec load(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, map()} | {:error, :invalid_cursor}
  def load(organization_id, mission_id, from, to, opts \\ []) do
    max_gap_s = Keyword.get(opts, :max_gap_s, @default_max_gap_s)
    limit = Keyword.get(opts, :limit, @default_limit)

    basis =
      {:contact_findings, organization_id, mission_id, DateTime.to_unix(from, :microsecond),
       DateTime.to_unix(to, :microsecond), max_gap_s}

    with {:ok, after_key} <- WindowCursor.decode(Keyword.get(opts, :cursor), basis, [0]) do
      stations = StationRefs.index(organization_id, mission_id)

      craft =
        Map.new(SpacecraftStore.active_identities(organization_id, mission_id), &{&1.id, &1})

      {counts, rows} =
        FindingWindows.page(organization_id, mission_id, from, to,
          max_gap_s: max_gap_s,
          limit: limit,
          after: after_key,
          station_ids_by_ref: Map.new(stations, fn {ref, station} -> {ref, station.id} end),
          spacecraft_ids: Map.keys(craft),
          outages: StationAvailability.blocking_windows(organization_id, mission_id, from, to)
        )

      truncated = length(rows) > limit
      findings = Enum.map(Enum.take(rows, limit), &finding(&1, stations, craft))

      next_cursor =
        if truncated do
          finding = List.last(findings)
          WindowCursor.encode(finding.at, finding.id, 0, basis)
        end

      {:ok,
       %{
         from: from,
         to: to,
         max_gap_s: max_gap_s,
         counts: counts,
         truncated: truncated,
         next_cursor: next_cursor,
         findings: findings
       }}
    end
  end

  defp finding(%{"kind" => "station_double_booked"} = fact, stations, craft),
    do:
      double_booked(
        booking(fact["first"], stations, craft),
        booking(fact["second"], stations, craft)
      )

  defp finding(%{"kind" => "booked_into_outage"} = fact, stations, craft),
    do: outage_booked(booking(fact["first"], stations, craft), fact["id"])

  defp finding(%{"kind" => "coverage_gap"} = fact, _stations, craft),
    do: gap(Map.fetch!(craft, fact["spacecraft_id"]), utc(fact["at"]), utc(fact["gap_end"]))

  defp booking(fact, stations, craft) do
    id = fact["spacecraft_id"]
    antenna = fact["antenna_ref"]

    %{
      id: fact["id"],
      spacecraft_id: id,
      spacecraft: Map.get(craft, id, %{id: id, name: nil, scid: nil}),
      station: StationRefs.resolve(fact["station_ref"], stations),
      antenna: antenna && %{id: antenna},
      starts_at: utc(fact["starts_at"]),
      ends_at: utc(fact["ends_at"]),
      state: fact["state"]
    }
  end

  defp utc(value), do: value |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")

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

  defp outage_booked(pass, id) do
    %{
      id: id,
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

  defp gap(spacecraft, gap_from, gap_to) do
    gap_s = DateTime.diff(gap_to, gap_from)

    %{
      id: "coverage_gap:#{spacecraft.id}:#{DateTime.to_unix(gap_from)}",
      kind: "coverage_gap",
      severity: "critical",
      at: gap_from,
      station: nil,
      spacecraft: spacecraft,
      passes: [],
      gap: %{from: gap_from, to: gap_to, seconds: gap_s},
      overlap_s: nil,
      message: "#{spacecraft.name || spacecraft.id} has no pass for #{duration(gap_s)}.",
      fix: nil
    }
  end

  defp later(a, b), do: if(DateTime.after?(b, a), do: b, else: a)

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
