defmodule Cadence.Telemetry.LogSink.FileTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{LogEnvelope, LogSink}

  setup do
    base_dir =
      Path.join(
        System.tmp_dir!(),
        "cadence-log-test-#{System.unique_integer([:positive, :monotonic])}-#{unique_suffix()}"
      )

    File.mkdir_p!(base_dir)

    on_exit(fn ->
      File.rm_rf!(base_dir)
    end)

    {:ok, base_dir: base_dir}
  end

  test "appends log envelopes to file sink", %{base_dir: base_dir} do
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

  test "recovers from an invalid segment manifest", %{base_dir: base_dir} do
    mission_id = "mission-test"
    lane = :payload
    shard_id = 1
    lane_path = Path.join([base_dir, mission_id, Atom.to_string(lane)])
    File.mkdir_p!(lane_path)
    File.write!(Path.join(lane_path, "#{shard_id}.manifest"), "not-an-integer")
    File.write!(Path.join(lane_path, "#{shard_id}-2.log"), "existing-segment-bytes")

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
               base_dir: base_dir,
               segment_bytes: 1
             )

    assert File.read!(Path.join(lane_path, "#{shard_id}.manifest")) == "3\n"
    assert File.exists?(Path.join(lane_path, "#{shard_id}-3.log"))
  end

  test "retains only the configured number of segments", %{base_dir: base_dir} do
    mission_id = "mission-test"
    lane = :payload
    shard_id = 2

    for sequence <- 1..4 do
      envelope = envelope(mission_id, lane, shard_id, sequence, %{"seq" => sequence})

      assert {:ok, _meta} =
               LogSink.File.append(
                 shard_id,
                 [envelope],
                 base_dir: base_dir,
                 segment_bytes: 1,
                 max_segments: 2
               )
    end

    lane_path = Path.join([base_dir, mission_id, Atom.to_string(lane)])

    segment_files =
      lane_path
      |> Path.join("#{shard_id}-*.log")
      |> Path.wildcard()
      |> Enum.sort()

    assert Enum.map(segment_files, &Path.basename/1) == ["2-2.log", "2-3.log"]
    assert File.read!(Path.join(lane_path, "#{shard_id}.manifest")) == "3\n"
  end

  test "retains only the configured total bytes using cached segment sizes", %{base_dir: base_dir} do
    mission_id = "mission-test"
    lane = :payload
    shard_id = 3

    envelope = envelope(mission_id, lane, shard_id, 1, %{"payload" => String.duplicate("x", 256)})

    encoded_size =
      envelope
      |> :erlang.term_to_binary()
      |> Base.encode64()
      |> byte_size()
      |> Kernel.+(1)

    for sequence <- 1..3 do
      envelope =
        envelope(mission_id, lane, shard_id, sequence, %{
          "payload" => String.duplicate("x", 256),
          "seq" => sequence
        })

      assert {:ok, _meta} =
               LogSink.File.append(
                 shard_id,
                 [envelope],
                 base_dir: base_dir,
                 segment_bytes: 1,
                 max_total_bytes: encoded_size * 2
               )
    end

    lane_path = Path.join([base_dir, mission_id, Atom.to_string(lane)])

    segment_files =
      lane_path
      |> Path.join("#{shard_id}-*.log")
      |> Path.wildcard()
      |> Enum.sort()

    basenames = Enum.map(segment_files, &Path.basename/1)

    assert "3-0.log" not in basenames
    assert List.last(basenames) == "3-2.log"

    retained_bytes =
      Enum.reduce(segment_files, 0, fn path, total ->
        {:ok, stat} = File.stat(path)
        total + stat.size
      end)

    assert retained_bytes <= encoded_size * 2
  end

  defp unique_suffix do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp envelope(mission_id, lane, shard_id, sequence, payload) do
    %LogEnvelope{
      mission_id: mission_id,
      target_id: "TARGET",
      apid: 100,
      lane: lane,
      shard_id: shard_id,
      router_version: 1,
      config_version: 1,
      sequence: sequence,
      ingest_monotonic_ns: sequence,
      source_wall_clock_ms: nil,
      checksum: nil,
      payload: payload,
      meta: %{}
    }
  end
end
