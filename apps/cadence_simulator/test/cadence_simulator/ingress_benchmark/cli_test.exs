defmodule CadenceSimulator.IngressBenchmark.CLITest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.IngressBenchmark.CLI

  @mountinfo """
  36 25 0:32 / /benchmark/corpus rw - tmpfs tmpfs rw,size=16m
  37 25 0:33 / /benchmark/results rw - tmpfs tmpfs rw,size=4m
  38 25 0:34 / /benchmark/scratch rw - tmpfs tmpfs rw,size=16m
  39 25 0:35 / /tmp rw - tmpfs tmpfs rw,size=16m
  """

  test "preflight command emits a machine-readable passing report" do
    manifest_path = write_manifest!()

    assert {:ok, output} =
             CLI.run(
               :preflight,
               ["--manifest", manifest_path, "--component", "harness"],
               mountinfo: @mountinfo
             )

    result = Jason.decode!(output)

    assert result["status"] == "passed"
    assert result["qualification"] == "local_safety_only"
    assert result["safety"]["planned_source_bytes"] == 100_000
    assert result["safety"]["component"] == "harness"
  end

  test "source and sink command options require bounded endpoints" do
    assert {:error, source_error} = CLI.parse_args(:source, ["--manifest", "run.yaml"])
    assert source_error == "--tcp is required"

    assert {:error, sink_error} =
             CLI.parse_args(:sink, ["--manifest", "run.yaml", "--listen", "localhost:nope"])

    assert sink_error == "--listen must be HOST:PORT"
  end

  test "source accepts an explicit bounded send timeout" do
    assert {:ok, opts} =
             CLI.parse_args(:source, [
               "--manifest",
               "run.yaml",
               "--tcp",
               "cadence:4601",
               "--send-timeout-ms",
               "5000"
             ])

    assert opts[:send_timeout_ms] == 5_000
  end

  defp write_manifest! do
    path =
      Path.join(
        System.tmp_dir!(),
        "cadence_ingress_manifest_#{System.unique_integer([:positive])}.yaml"
      )

    File.write!(path, manifest_yaml())
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp manifest_yaml do
    """
    schema_version: 1
    deployment:
      kind: compose
      containers:
        harness:
          memory_limit_bytes: 268435456
    storage:
      profile: laptop_tmpfs
      max_bytes: 1073741824
      tmpfs_mounts:
        - {path: /benchmark/corpus, max_bytes: 16777216}
        - {path: /benchmark/results, max_bytes: 4194304}
        - {path: /benchmark/scratch, max_bytes: 16777216}
        - {path: /tmp, max_bytes: 16777216}
    traffic:
      seed: 381746
      pattern_size_bytes: 65536
      block_size_bytes: 4096
      phases:
        - {name: measure, duration_seconds: 1, target_bps: 800000}
    safety:
      max_source_bytes: 100000
      max_wall_clock_seconds: 3
      max_artifact_bytes: 1048576
      docker_memory_budget_bytes: 2147483648
      docker_overhead_bytes: 268435456
      process_headroom_bytes: 134217728
    """
  end
end
