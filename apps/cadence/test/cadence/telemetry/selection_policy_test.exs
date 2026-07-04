defmodule Cadence.Telemetry.SelectionPolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{Sample, SelectionPolicy}

  test "defaults operational reads to canonical samples" do
    assert SelectionPolicy.validity_state_filter([]) == :canonical
    assert SelectionPolicy.selected_sample?(sample("canonical"), [])
    assert SelectionPolicy.selected_sample?(sample(nil), [])
    refute SelectionPolicy.selected_sample?(sample("conflict"), [])
  end

  test "allows explicit all-revision reads" do
    assert SelectionPolicy.validity_state_filter(view: :all_revisions) == nil
    assert SelectionPolicy.selected_sample?(sample("conflict"), view: :all_revisions)
  end

  test "honors explicit validity-state filters" do
    assert SelectionPolicy.validity_state_filter(validity_state: "conflict") == :conflict
    assert SelectionPolicy.selected_sample?(sample("conflict"), validity_state: :conflict)
    refute SelectionPolicy.selected_sample?(sample(nil), validity_state: :conflict)
  end

  defp sample(validity_state) do
    %Sample{
      sample_id: "sample-#{validity_state || "legacy"}",
      mission_id: "mission-selection",
      spacecraft_id: nil,
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-1",
      packet_definition_version: 1,
      packet_id: "packet-#{validity_state || "legacy"}",
      evidence_id: "evidence-#{validity_state || "legacy"}",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      receipt_time: ~U[2026-06-22 12:00:00Z],
      generation_time: ~U[2026-06-22 12:00:00Z],
      provenance: provenance(validity_state)
    }
  end

  defp provenance(nil), do: %{}
  defp provenance(validity_state), do: %{"storage" => %{"validity_state" => validity_state}}
end
