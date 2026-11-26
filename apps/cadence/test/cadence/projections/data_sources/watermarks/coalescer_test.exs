defmodule Cadence.Projections.DataSources.Watermarks.CoalescerTest do
  use ExUnit.Case, async: true

  alias Cadence.DataSources.SourceWatermarkEvent
  alias Cadence.Projections.DataSources.Watermarks.Coalescer

  defp attrs(mission_id, seconds, sample_id, count \\ 1) do
    at = DateTime.add(~U[2026-06-17 12:00:00.000000Z], seconds, :second)

    %{
      organization_id: "org",
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "ds",
      source_binding_id: "binding",
      realm: :flight,
      replay_run_id: nil,
      dataset: nil,
      complete_through: at,
      latest_receipt_time: at,
      retention_starts_at: at,
      sample_count: count,
      confidence: :best_effort,
      reason: :telemetry_storage_write,
      observed_at: at,
      payload: %{
        kind: "telemetry_storage_write",
        observation_count: count,
        first_sample_id: sample_id,
        last_sample_id: sample_id,
        replay_run_id: nil
      }
    }
  end

  defp pending(attrs) do
    key = {SourceWatermarkEvent.new(attrs).source_watermark_key, nil, false}
    [{^key, _version, _mission, merged}] = :ets.lookup(Coalescer, key)
    :ets.delete(Coalescer, key)
    merged
  end

  test "merge takes the earliest start, the latest watermark, the summed count and the window's ends" do
    merged = Coalescer.merge(attrs("m", 5, "a", 2), attrs("m", 2, "b", 3))

    assert merged.retention_starts_at == DateTime.add(~U[2026-06-17 12:00:00.000000Z], 2, :second)
    assert merged.latest_receipt_time == DateTime.add(~U[2026-06-17 12:00:00.000000Z], 5, :second)
    assert merged.complete_through == merged.latest_receipt_time
    assert merged.sample_count == 5
    assert merged.payload.observation_count == 5
    assert merged.payload.first_sample_id == "a"
    assert merged.payload.last_sample_id == "b"
  end

  test "concurrent writers to one row lose no observation" do
    mission = "mission-coalescer-#{System.unique_integer([:positive])}"

    1..200
    |> Task.async_stream(
      fn n -> Coalescer.observe(attrs(mission, n, "s#{n}")) end,
      max_concurrency: 32
    )
    |> Stream.run()

    merged = pending(attrs(mission, 0, "x"))
    assert merged.sample_count == 200
    assert merged.payload.observation_count == 200

    assert merged.latest_receipt_time ==
             DateTime.add(~U[2026-06-17 12:00:00.000000Z], 200, :second)

    assert merged.retention_starts_at == DateTime.add(~U[2026-06-17 12:00:00.000000Z], 1, :second)
  end

  test "rows of different keys stay separate" do
    mission = "mission-coalescer-#{System.unique_integer([:positive])}"
    other = put_in(attrs(mission, 1, "a"), [:source_binding_id], "other-binding")

    assert :ok = Coalescer.observe(attrs(mission, 1, "a"))
    assert :ok = Coalescer.observe(other)

    assert pending(attrs(mission, 1, "a")).sample_count == 1
    assert pending(other).sample_count == 1
  end
end
