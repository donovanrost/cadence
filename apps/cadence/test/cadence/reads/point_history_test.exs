defmodule Cadence.Reads.PointHistoryTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.PointHistory
  alias Cadence.Telemetry.Sample

  @from ~U[2026-11-08 02:00:00.000Z]

  defp sample(seconds, value, opts \\ []) do
    at = DateTime.add(@from, seconds)

    %Sample{
      engineering_value: value,
      generation_time: if(Keyword.get(opts, :generation?, true), do: at),
      receipt_time: at
    }
  end

  test "bucket width yields at most max_points buckets" do
    to = DateTime.add(@from, 3_600)
    assert PointHistory.bucket_width_ms(@from, to, 500) == 7_200
    assert PointHistory.bucket_width_ms(@from, DateTime.add(@from, 1, :millisecond), 500) == 1
  end

  test "buckets numeric samples into min/max/mean, skipping non-numeric values" do
    buckets =
      PointHistory.bucket_samples(
        [
          sample(0, 1.0),
          sample(5, 3.0),
          sample(9, "OFF"),
          sample(12, 10, generation?: false),
          sample(25, true)
        ],
        DateTime.add(@from, 3),
        10_000
      )

    assert [
             %{t: t0, min: 1.0, max: 3.0, mean: 2.0, count: 2},
             %{min: 10, max: 10, count: 1},
             %{min: 1, max: 1, count: 1}
           ] = buckets

    assert t0 == @from
    assert hd(buckets).t_end == DateTime.add(@from, 10)
  end

  test "an enumerated point (engineering = label after calibration, #92 (c)) plots its raw states" do
    states = [
      %{sample(0, "SAFE") | raw_value: 2},
      %{sample(5, "SCIENCE") | raw_value: 4},
      %{sample(12, "SCIENCE") | raw_value: 4}
    ]

    assert [%{min: 2, max: 4, count: 2}, %{min: 4, max: 4, count: 1}] =
             PointHistory.bucket_samples(states, @from, 10_000)
  end
end
