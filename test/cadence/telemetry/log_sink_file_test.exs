defmodule Cadence.Telemetry.LogSink.FileTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{LogEnvelope, LogSink}

  test "appends log envelopes to file sink" do
    base_dir =
      Path.join(System.tmp_dir!(), "cadence-log-test-#{System.unique_integer([:positive])}")

    mission_id = "mission-test"
    lane = :payload
    shard_id = 0

    envelope = %LogEnvelope{
      mission_id: mission_id,
      target_id: "TARGET",
      apid: 100,
      lane: lane,
      shard_id: shard_id,
      router_version: 1,
      config_version: 1,
      sequence: 1,
      ingest_monotonic_ns: 1,
      source_wall_clock_ms: nil,
      checksum: nil,
      payload: %{"ok" => true},
      meta: %{}
    }

    assert {:ok, _meta} =
             LogSink.File.append(
               shard_id,
               [envelope],
               base_dir: base_dir
             )

    log_path = Path.join([base_dir, mission_id, Atom.to_string(lane), "#{shard_id}.log"])
    assert File.exists?(log_path)

    [line | _] = File.read!(log_path) |> String.split("\n", trim: true)
    decoded = line |> Base.decode64!() |> :erlang.binary_to_term()

    assert %LogEnvelope{} = decoded
    assert decoded.mission_id == mission_id
    assert decoded.target_id == "TARGET"
    assert decoded.apid == 100
  end
end
