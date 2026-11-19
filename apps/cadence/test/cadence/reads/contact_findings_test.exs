defmodule Cadence.Reads.ContactFindingsTest do
  @moduledoc "M22 findings over pass rows (pure)."
  use ExUnit.Case, async: true

  alias Cadence.Reads.ContactFindings

  @from ~U[2026-11-10 00:00:00Z]
  @to ~U[2026-11-10 06:00:00Z]

  defp at(minute), do: DateTime.add(@from, minute * 60)

  defp pass(id, craft, station, from_min, to_min, opts \\ []) do
    %{
      id: id,
      spacecraft_id: craft,
      spacecraft: %{id: craft, name: String.upcase(craft), scid: nil},
      station: %{ref: station, id: "gs-" <> station, code: station, name: nil},
      antenna: (antenna = Keyword.get(opts, :antenna)) && %{id: antenna, label: nil},
      starts_at: at(from_min),
      ends_at: at(to_min),
      state: Keyword.get(opts, :state, "confirmed")
    }
  end

  defp craft(id), do: %{spacecraft_id: id, display_name: String.upcase(id), scid: nil}

  defp build(passes, opts \\ []) do
    ContactFindings.build(%{
      from: @from,
      to: @to,
      max_gap_s: Keyword.get(opts, :max_gap_s, 4 * 3600),
      passes: passes,
      outages: Keyword.get(opts, :outages, %{}),
      spacecraft: Keyword.get(opts, :spacecraft, [])
    })
  end

  test "overlapping live passes at one station are a double-booking; other antennas aren't" do
    passes = [
      pass("p1", "073", "SVB", 200, 210),
      pass("p2", "251", "SVB", 207, 217),
      pass("p3", "300", "SVB", 207, 217, state: "canceled"),
      pass("p4", "400", "AWA", 100, 110, antenna: "a1"),
      pass("p5", "401", "AWA", 105, 115, antenna: "a2")
    ]

    assert %{findings: [finding], counts: %{conflicts: 1}} = build(passes)

    assert %{kind: "station_double_booked", overlap_s: 180, message: message} = finding
    assert message == "073 and 251 overlap by 3 minutes at SVB."
  end

  test "a live pass in a station outage is critical" do
    outage = %{window_id: "w1", starts_at: at(60), ends_at: at(120), source: :operator}

    assert %{findings: [%{kind: "booked_into_outage", severity: "critical"}]} =
             build([pass("p1", "073", "SVB", 90, 100)], outages: %{"gs-SVB" => [outage]})
  end

  test "coverage gaps count the pass just before the window; short gaps aren't findings" do
    passes = [
      # Ended 10 minutes before the window: the gap runs from it, not from the window start.
      pass("p0", "389", "SVB", -10, -1),
      pass("p1", "389", "SVB", 330, 340),
      pass("p2", "390", "SVB", 60, 70),
      pass("p3", "390", "SVB", 200, 210)
    ]

    %{findings: findings} = build(passes, spacecraft: [craft("389"), craft("390"), craft("391")])
    gaps = Map.new(findings, &{&1.spacecraft.id, &1})

    assert %{gap: %{seconds: seconds}, message: "389 has no pass for 5h 31m."} = gaps["389"]
    assert seconds == 331 * 60
    refute Map.has_key?(gaps, "390")
    # No pass at all: the whole window.
    assert %{gap: %{seconds: 21_600}} = gaps["391"]
  end
end
