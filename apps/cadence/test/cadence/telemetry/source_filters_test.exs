defmodule Cadence.Telemetry.SourceFiltersTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.{Sample, SourceFilters}

  test "normalizes singular and plural source endpoint filters" do
    assert %{source_endpoint_ids: ["endpoint-a"]} =
             SourceFilters.normalize(source_endpoint_id: "endpoint-a")

    assert %{source_endpoint_ids: ["endpoint-a", "endpoint-b"]} =
             SourceFilters.normalize(source_endpoint_ids: ["endpoint-a", "", "endpoint-b"])
  end

  test "matches source endpoint ids from storage provenance" do
    sample = sample("endpoint-a")

    assert SourceFilters.sample_matches?(sample,
             source_endpoint_ids: ["endpoint-a", "endpoint-b"]
           )

    refute SourceFilters.sample_matches?(sample, source_endpoint_ids: ["endpoint-c"])
  end

  test "normalizes and matches replay run filters from storage provenance" do
    sample = sample("endpoint-a", replay_run_id: "replay-run-1")

    assert SourceFilters.normalize(replay_run_id: :replay_run_1).replay_run_id == "replay_run_1"
    assert SourceFilters.replay_run_id(replay_run_id: "replay-run-1") == "replay-run-1"
    assert SourceFilters.sample_matches?(sample, replay_run_id: "replay-run-1")
    refute SourceFilters.sample_matches?(sample, replay_run_id: "replay-run-2")

    assert SourceFilters.sample_identity(sample) == %{
             realm: "flight",
             data_source_id: "managed_questdb_primary",
             binding_id: "default_flight_telemetry",
             replay_run_id: "replay-run-1"
           }

    assert SourceFilters.sample_key(sample) ==
             {"flight", "managed_questdb_primary", "default_flight_telemetry"}
  end

  defp sample(source_endpoint_id, opts \\ []) do
    %Sample{
      sample_id: "sample-1",
      mission_id: "mission-1",
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      receipt_time: ~U[2026-06-26 12:00:00Z],
      provenance: %{
        "storage" => %{
          "realm" => "flight",
          "data_source_id" => "managed_questdb_primary",
          "binding_id" => "default_flight_telemetry",
          "source_endpoint_id" => source_endpoint_id,
          "replay_run_id" => Keyword.get(opts, :replay_run_id)
        }
      }
    }
  end
end
