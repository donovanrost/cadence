defmodule CadenceSimulator.IngressBenchmark.LocalSafetyTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.IngressBenchmark.LocalSafety

  @mountinfo """
  36 25 0:32 / /benchmark/journal rw,nosuid,nodev - tmpfs tmpfs rw,size=64m
  37 25 0:33 / /benchmark/observability rw,nosuid,nodev - tmpfs tmpfs rw,size=32m
  """

  test "accepts a bounded compose schedule whose high-volume paths resolve to capped tmpfs" do
    manifest = manifest()

    assert {:ok, report} =
             LocalSafety.validate(manifest, mountinfo: @mountinfo, component: "harness")

    assert report.qualification == :local_safety_only
    assert report.planned_source_bytes == 2_500_000
    assert report.planned_wall_clock_seconds == 3
    assert report.component == "harness"
    assert report.component_memory_limit_bytes == 256 * 1_048_576

    assert Enum.map(report.tmpfs_mounts, & &1.observed_max_bytes) ==
             Enum.map([64, 32], &(&1 * 1_048_576))
  end

  test "rejects a schedule that can cross its byte or wall-clock fuse" do
    manifest =
      manifest(%{
        "max_source_bytes" => 2_499_999,
        "max_wall_clock_seconds" => 2,
        "max_artifact_bytes" => 1_000_000
      })

    assert {:error, errors} = LocalSafety.validate(manifest, mountinfo: @mountinfo)
    assert "traffic schedule exceeds safety.max_source_bytes" in errors
    assert "traffic schedule exceeds safety.max_wall_clock_seconds" in errors
  end

  test "rejects host-backed and unbounded high-volume paths" do
    mountinfo = """
    36 25 0:32 / /benchmark/journal rw - ext4 /dev/disk1 rw
    37 25 0:33 / /benchmark/observability rw - tmpfs tmpfs rw
    """

    assert {:error, errors} = LocalSafety.validate(manifest(), mountinfo: mountinfo)

    assert "high-volume path /benchmark/journal resolves to ext4, not tmpfs" in errors

    assert "tmpfs path /benchmark/observability does not report an explicit size limit" in errors
  end

  test "rejects a component whose tmpfs and process headroom exceed its memory limit" do
    manifest =
      put_in(
        manifest(),
        ["deployment", "containers", "harness", "memory_limit_bytes"],
        128 * 1_048_576
      )

    assert {:error, errors} =
             LocalSafety.validate(manifest, mountinfo: @mountinfo, component: "harness")

    assert "declared tmpfs mounts plus process headroom exceed the selected container memory limit" in errors
  end

  defp manifest(safety_overrides \\ %{}) do
    safety =
      Map.merge(
        %{
          "max_source_bytes" => 3_000_000,
          "max_wall_clock_seconds" => 4,
          "max_artifact_bytes" => 1_000_000,
          "docker_memory_budget_bytes" => 1_073_741_824,
          "docker_overhead_bytes" => 128 * 1_048_576,
          "process_headroom_bytes" => 128 * 1_048_576
        },
        safety_overrides
      )

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
        "max_bytes" => 96 * 1_048_576,
        "tmpfs_mounts" => [
          %{"path" => "/benchmark/journal", "max_bytes" => 64 * 1_048_576},
          %{"path" => "/benchmark/observability", "max_bytes" => 32 * 1_048_576}
        ]
      },
      "traffic" => %{
        "phases" => [
          %{"name" => "warmup", "duration_seconds" => 2, "target_bps" => 8_000_000},
          %{"name" => "measure", "duration_seconds" => 1, "target_bps" => 4_000_000}
        ]
      },
      "safety" => safety
    }
  end
end
