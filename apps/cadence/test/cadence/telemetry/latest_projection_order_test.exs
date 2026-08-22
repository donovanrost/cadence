defmodule Cadence.Telemetry.LatestProjectionOrderTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.LatestProjectionOrder

  test "orders latest projections by generation time before receipt time" do
    current = sample("current", ~U[2026-06-21 12:10:00Z], ~U[2026-06-21 12:10:05Z])
    late_arrival = sample("late", ~U[2026-06-21 12:00:00Z], ~U[2026-06-21 12:15:00Z])

    refute LatestProjectionOrder.newer?(late_arrival, current, :sample_id)
    assert LatestProjectionOrder.compare(late_arrival, current, :sample_id) == :lt
  end

  test "falls back to receipt time when generation time is missing" do
    current = sample("current", nil, ~U[2026-06-21 12:00:00Z])
    newer = sample("newer", nil, ~U[2026-06-21 12:00:01Z])

    assert LatestProjectionOrder.newer?(newer, current, :sample_id)
  end

  test "uses receipt time then stable id as deterministic tie breakers" do
    current = sample("sample-a", ~U[2026-06-21 12:00:00Z], ~U[2026-06-21 12:00:00Z])
    later_receipt = sample("sample-b", ~U[2026-06-21 12:00:00Z], ~U[2026-06-21 12:00:01Z])
    same_time_later_id = sample("sample-c", ~U[2026-06-21 12:00:00Z], ~U[2026-06-21 12:00:00Z])

    assert LatestProjectionOrder.newer?(later_receipt, current, :sample_id)
    assert LatestProjectionOrder.newer?(same_time_later_id, current, :sample_id)
  end

  test "supports projection-specific stable id fields" do
    current = %{
      generation_time: ~U[2026-06-21 12:00:00Z],
      receipt_time: ~U[2026-06-21 12:00:00Z],
      limit_event_id: "limit-event-a"
    }

    newer = %{current | limit_event_id: "limit-event-b"}

    assert LatestProjectionOrder.newer?(newer, current, :limit_event_id)
  end

  defp sample(sample_id, generation_time, receipt_time) do
    %{
      sample_id: sample_id,
      generation_time: generation_time,
      receipt_time: receipt_time
    }
  end
end
