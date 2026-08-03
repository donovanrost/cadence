defmodule Cadence.Reads.AlarmsTest do
  use ExUnit.Case, async: true

  alias Cadence.Limits.Event
  alias Cadence.Reads.Alarms

  test "summarizes active conditions and filters the canonical latest-state rows" do
    observed_at = ~U[2026-08-01 12:10:00Z]

    snapshot =
      Alarms.snapshot("org-1", "mission-1",
        observed_at: fn -> observed_at end,
        latest_states: fn "org-1", "mission-1", [] ->
          [
            event("red", :red, true, "SC-1", "EPS.voltage", ~U[2026-08-01 12:03:00Z]),
            event("yellow", :yellow, true, "SC-2", "THERM.temp", ~U[2026-08-01 12:02:00Z]),
            event("green", :green, false, "SC-1", "EPS.current", ~U[2026-08-01 12:01:00Z])
          ]
        end,
        filters: %{"severity" => "critical", "spacecraft_id" => "SC-1", "state" => "active"}
      )

    assert [%{id: "red", subsystem: "EPS", severity: :critical}] = snapshot.rows
    assert snapshot.summary.active_count == 2
    assert snapshot.summary.critical_count == 1
    assert snapshot.summary.warning_count == 1
    assert snapshot.summary.status == :critical
    assert snapshot.summary.latest_transition_at == ~U[2026-08-01 12:03:00Z]
    assert snapshot.observed_at == observed_at
  end

  test "an empty current projection is nominal rather than unavailable" do
    snapshot =
      Alarms.snapshot("org-1", "mission-1",
        latest_states: fn _organization_id, _mission_id, [] -> [] end
      )

    assert snapshot.rows == []
    assert snapshot.summary.active_count == 0
    assert snapshot.summary.status == :nominal
    assert snapshot.summary.freshness == :current
  end

  defp event(id, normalized_state, violation, spacecraft_id, point_id, receipt_time) do
    %Event{
      limit_event_id: id,
      mission_id: "mission-1",
      spacecraft_id: spacecraft_id,
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-#{id}",
      limit_definition_id: "definition-#{id}",
      limit_definition_version: 1,
      limit_set_name: "DEFAULT",
      evaluated_value: 42,
      limit_state: normalized_state,
      normalized_state: normalized_state,
      violation: violation,
      receipt_time: receipt_time,
      provenance: %{}
    }
  end
end
