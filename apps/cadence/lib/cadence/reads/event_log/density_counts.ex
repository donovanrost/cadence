defmodule Cadence.Reads.EventLog.DensityCounts do
  @moduledoc """
  `EventLog.density/3` without loading event rows (lead 11-15): `Reads.EventDensity` counts per
  bucket in SQL; each count group is classified with the page's own rules
  (`EventLog.classify_entry/1`), so the bar and the list agree. The two small extra sources
  (applied configuration revisions, off-plan bookings) are read as entries, as on the page.
  """

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.{ConfigRevisionEvents, EventDensity, EventLog, OffPlanBookingEvents}
  alias Cadence.Reads.EventLog.RawKinds

  @spec density(binary(), binary(), map()) :: map()
  def density(organization_id, mission_id, opts) do
    origin = DateTime.to_unix(opts.from)

    counted =
      organization_id
      |> EventDensity.groups(
        mission_id,
        opts.from,
        opts.to,
        opts.bucket_s,
        EventLog.skip_housekeeping?(opts[:kinds])
      )
      |> Enum.map(fn group -> {group.bucket, classify(group), group.count, group.kind} end)

    extras =
      organization_id
      |> extra_entries(mission_id, opts)
      |> Enum.map(fn entry ->
        {div(DateTime.to_unix(entry.occurred_at) - origin, opts.bucket_s),
         EventLog.classify_entry(entry), 1, to_string(entry.kind)}
      end)

    buckets =
      (counted ++ extras)
      |> Enum.filter(fn {_bucket, {kind, severity}, _count, raw} ->
        selected?(kind, opts[:kinds]) and RawKinds.selected?(raw, opts[:raw_kinds]) and
          EventLog.at_least?(severity, opts[:severity_at_least])
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {index, rows} -> bucket(origin + index * opts.bucket_s, rows) end)

    %{bucket_s: opts.bucket_s, buckets: buckets, truncated: false}
  end

  defp bucket(at, rows) do
    totals =
      Enum.reduce(rows, %{}, fn {_bucket, {_kind, severity}, count, _raw}, acc ->
        Map.update(acc, severity, count, &(&1 + count))
      end)

    %{
      t: DateTime.from_unix!(at),
      critical: Map.get(totals, :critical, 0),
      caution: Map.get(totals, :caution, 0),
      nominal: Map.get(totals, :nominal, 0),
      info: Map.get(totals, :info, 0)
    }
  end

  # A watermark retreat's severity comes from its sentence (caution with a replay or late data).
  @doc false
  def classify(%{kind: "source_watermark_retreated", retreat_reason: reason} = group) do
    {kind, _severity} = EventLog.classify_entry(entry(group))
    {kind, if(reason, do: :caution, else: :info)}
  end

  def classify(group), do: EventLog.classify_entry(entry(group))

  defp entry(group) do
    %Entry{
      kind: known(group.kind),
      category: category(group.source, group.category),
      source_record_kind: known(group.source_record_kind),
      status: if(group.cleared, do: "cleared"),
      severity: known(group.severity)
    }
  end

  # Operational categories as the timeline projects them (Projections.MissionEvents).
  defp category("operational", category) when category in ~w(contact commanding dashboard),
    do: :operations

  defp category("operational", category)
       when category in ~w(limits data_source source_credential),
       do: :health

  defp category("operational", "comms"), do: :transport
  defp category("operational", _category), do: :runtime
  defp category(_projected, category), do: known(category)

  # Stored strings become the atoms the classifier matches, never new atoms.
  defp known(nil), do: nil

  defp known(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp extra_entries(organization_id, mission_id, opts) do
    window = [from_occurred_at: opts.from, to_occurred_at: opts.to]

    ConfigRevisionEvents.entries(organization_id, mission_id, window) ++
      OffPlanBookingEvents.entries(organization_id, mission_id, window)
  end

  defp selected?(_kind, nil), do: true
  defp selected?(_kind, []), do: true
  defp selected?(kind, kinds), do: kind in kinds
end
