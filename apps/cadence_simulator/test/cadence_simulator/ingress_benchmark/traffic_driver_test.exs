defmodule CadenceSimulator.IngressBenchmark.TrafficDriverTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.IngressBenchmark.{
    DeterministicPattern,
    LocalSafety,
    Manifest,
    Preflight,
    TrafficDriver,
    ValidatingSink
  }

  @mountinfo """
  36 25 0:32 / /benchmark/corpus rw - tmpfs tmpfs rw,size=16m
  37 25 0:33 / /benchmark/results rw - tmpfs tmpfs rw,size=4m
  38 25 0:34 / /benchmark/scratch rw - tmpfs tmpfs rw,size=16m
  39 25 0:35 / /tmp rw - tmpfs tmpfs rw,size=16m
  """

  test "deterministic source and validating sink agree across arbitrary TCP reads" do
    preflight = preflight!()
    port = unique_tcp_port()

    sink_task =
      Task.async(fn ->
        ValidatingSink.run(preflight, host: "127.0.0.1", port: port, timeout_ms: 2_000)
      end)

    assert {:ok, source_report} =
             TrafficDriver.run(preflight,
               host: "127.0.0.1",
               port: port,
               pace?: false,
               connect_timeout_ms: 2_000
             )

    assert {:ok, sink_report} = Task.await(sink_task, 3_000)

    assert source_report.source_end_offset == 100_000
    assert source_report.transport_accepted_end_offset == 100_000
    assert sink_report.bytes_received == 100_000
    assert sink_report.first_mismatch_offset == nil
    assert source_report.stream_sha256 == sink_report.actual_sha256
    assert sink_report.actual_sha256 == sink_report.expected_sha256
  end

  test "validating sink reports the first corrupt byte" do
    preflight = preflight!()
    port = unique_tcp_port()

    sink_task =
      Task.async(fn ->
        ValidatingSink.run(preflight, host: "127.0.0.1", port: port, timeout_ms: 2_000)
      end)

    {:ok, pattern} = DeterministicPattern.new(381_746, 65_536)
    expected = DeterministicPattern.slice(pattern, 0, 100_000)
    <<first, rest::binary>> = expected
    corrupt = <<Bitwise.bxor(first, 0xFF), rest::binary>>

    {:ok, socket} = connect(port)
    assert :ok = :gen_tcp.send(socket, corrupt)
    :ok = :gen_tcp.close(socket)

    assert {:error, :validation_failed, report} = Task.await(sink_task, 3_000)
    assert report.bytes_received == 100_000
    assert report.first_mismatch_offset == 0
    assert report.actual_sha256 != report.expected_sha256
  end

  test "target rate qualification rejects a complete but late phase" do
    refute TrafficDriver.target_rate_met?(18_750_000_000, 183_900_179, 1_000_000_000, 0.99)
    assert TrafficDriver.target_rate_met?(18_750_000_000, 150_000_081, 1_000_000_000, 0.99)
  end

  defp preflight! do
    manifest = %Manifest{path: "memory", data: manifest_data(), sha256: "manifest-sha256"}

    {:ok, safety} =
      LocalSafety.validate(manifest.data, mountinfo: @mountinfo, component: "harness")

    %Preflight{manifest: manifest, safety: safety}
  end

  defp manifest_data do
    %{
      "schema_version" => 1,
      "deployment" => %{
        "kind" => "compose",
        "containers" => %{
          "harness" => %{"memory_limit_bytes" => 256 * 1_048_576}
        }
      },
      "storage" => %{
        "profile" => "laptop_tmpfs",
        "max_bytes" => 1_073_741_824,
        "tmpfs_mounts" => [
          %{"path" => "/benchmark/corpus", "max_bytes" => 16 * 1_048_576},
          %{"path" => "/benchmark/results", "max_bytes" => 4 * 1_048_576},
          %{"path" => "/benchmark/scratch", "max_bytes" => 16 * 1_048_576},
          %{"path" => "/tmp", "max_bytes" => 16 * 1_048_576}
        ]
      },
      "traffic" => %{
        "seed" => 381_746,
        "pattern_size_bytes" => 65_536,
        "block_size_bytes" => 4_096,
        "phases" => [
          %{"name" => "measure", "duration_seconds" => 1, "target_bps" => 800_000}
        ]
      },
      "safety" => %{
        "max_source_bytes" => 100_000,
        "max_wall_clock_seconds" => 3,
        "max_artifact_bytes" => 1_048_576,
        "docker_memory_budget_bytes" => 2_147_483_648,
        "docker_overhead_bytes" => 268_435_456,
        "process_headroom_bytes" => 134_217_728
      }
    }
  end

  defp connect(port, attempts \\ 20)

  defp connect(port, attempts) when attempts > 0 do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw]) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, :econnrefused} ->
        Process.sleep(10)
        connect(port, attempts - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect(_port, 0), do: {:error, :connect_timeout}

  defp unique_tcp_port do
    45_000 + rem(System.unique_integer([:positive]), 10_000)
  end
end
