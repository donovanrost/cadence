defmodule CadenceSimulator.IngressBenchmark.LaptopComposeProfileTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.IngressBenchmark.{Manifest, Preflight}

  @root Path.expand("../../../../..", __DIR__)
  @compose_path Path.join(@root, "dev/ingress-benchmark/compose.laptop-tmpfs.yaml")
  @manifest_path Path.join(@root, "dev/ingress-benchmark/laptop-tmpfs-manifest.yaml")
  @full_flow_compose_path Path.join(
                            @root,
                            "dev/ingress-benchmark/compose.full-flow-tmpfs.yaml"
                          )
  @full_flow_manifest_path Path.join(
                             @root,
                             "dev/ingress-benchmark/full-flow-500mbps-manifest.yaml"
                           )
  @full_flow_1gbps_manifest_path Path.join(
                                   @root,
                                   "dev/ingress-benchmark/full-flow-1gbps-manifest.yaml"
                                 )
  @full_flow_1gbps_env_path Path.join(
                              @root,
                              "dev/ingress-benchmark/full-flow-1gbps.env"
                            )
  @dockerfile_path Path.join(@root, "dev/ingress-benchmark/Dockerfile")

  @mountinfo """
  36 25 0:32 / /benchmark/corpus rw - tmpfs tmpfs rw,size=16m
  37 25 0:33 / /benchmark/results rw - tmpfs tmpfs rw,size=4m
  38 25 0:34 / /benchmark/scratch rw - tmpfs tmpfs rw,size=16m
  39 25 0:35 / /benchmark/journal rw - tmpfs tmpfs rw,size=1g
  40 25 0:36 / /tmp rw - tmpfs tmpfs rw,size=16m
  """

  test "checked-in laptop manifest passes the runtime safety contract" do
    assert {:ok, manifest} = Manifest.load(@manifest_path)

    assert {:ok, preflight} =
             Preflight.evaluate(manifest, mountinfo: @mountinfo, component: "preflight")

    assert preflight.safety.planned_source_bytes == 2_500_000
    assert preflight.safety.planned_wall_clock_seconds == 3
    assert preflight.safety.component_memory_limit_bytes == 256 * 1_048_576
  end

  test "compose overlay replaces mutable service data with capped tmpfs" do
    {:ok, compose} = YamlElixir.read_from_file(@compose_path)
    services = Map.fetch!(compose, "services")

    Enum.each(
      %{
        "questdb" => "/var/lib/questdb",
        "questdb_customer" => "/var/lib/questdb",
        "greptimedb" => "/greptimedb_data",
        "tempo" => "/var/tempo",
        "loki" => "/loki",
        "grafana" => "/var/lib/grafana"
      },
      fn {service_name, data_path} ->
        service = Map.fetch!(services, service_name)
        assert service["read_only"] == true
        assert is_binary(service["mem_limit"])
        assert get_in(service, ["logging", "options", "max-size"]) == "1m"

        data_mount = Enum.find(service["volumes"], &(&1["target"] == data_path))
        assert data_mount["type"] == "tmpfs"
        assert get_in(data_mount, ["tmpfs", "size"]) > 0
      end
    )

    refute File.read!(@compose_path) =~ "./var"
  end

  test "harness image context is narrow and produces an escript" do
    dockerignore = File.read!(Path.join(@root, ".dockerignore"))
    dockerfile = File.read!(@dockerfile_path)
    mix_project = File.read!(Path.join(@root, "apps/cadence_simulator/mix.exs"))

    assert String.starts_with?(dockerignore, "*\n")
    assert dockerignore =~ "!apps/cadence_simulator/lib/**"
    assert dockerfile =~ "ARG ELIXIR_IMAGE=elixir:1.20.2-otp-28-slim"
    assert dockerfile =~ "RUN mix escript.build"
    assert dockerfile =~ "AS cadence-full-flow"
    assert dockerfile =~ ~s(CMD ["mix", "run", "--no-start")
    assert mix_project =~ "escript: [main_module: CadenceSimulator.CLI, app: nil]"
  end

  test "full-flow profile is the exact bounded 500 Mb/s scenario" do
    assert {:ok, manifest} = Manifest.load(@full_flow_manifest_path)

    assert {:ok, preflight} =
             Preflight.evaluate(manifest, mountinfo: @mountinfo, component: "cadence")

    assert Manifest.get(manifest, [:traffic, :corpus_id]) == "ccsds-tm-frame-v1"
    assert Manifest.get(manifest, [:traffic, :pattern_size_bytes]) == 62_500
    assert Manifest.get(manifest, [:traffic, :block_size_bytes]) == 62_500
    assert Manifest.get(manifest, [:traffic, :minimum_rate_ratio]) == 0.99

    assert Manifest.get(manifest, [:processing, :ingress_journal]) ==
             "capture_first_page_cache_tmpfs"

    assert Manifest.get(manifest, [:traffic, :phases]) == [
             %{
               "name" => "measure",
               "duration_seconds" => 150,
               "target_bps" => 500_000_000
             }
           ]

    assert preflight.safety.planned_source_bytes == 9_375_000_000
    assert preflight.safety.planned_wall_clock_seconds == 150
    assert preflight.safety.max_wall_clock_seconds == 210
    assert preflight.safety.container_memory_total_bytes == 6_979_321_856
    assert preflight.safety.docker_memory_budget_bytes == 8_394_457_088

    assert {:ok, source_preflight} =
             Preflight.evaluate(manifest, mountinfo: @mountinfo, component: "traffic_source")

    refute Enum.any?(source_preflight.safety.tmpfs_mounts, &(&1.path == "/benchmark/journal"))
  end

  test "full-flow compose keeps every mutable path bounded and isolated" do
    {:ok, compose} = YamlElixir.read_from_file(@full_flow_compose_path)
    services = Map.fetch!(compose, "services")

    assert get_in(services, ["cadence", "build", "target"]) == "cadence-full-flow"
    assert get_in(services, ["traffic_source", "build", "target"]) == "runtime"
    assert services["grafana"]["ports"] == ["3300:3000"]

    assert Enum.chunk_every(services["preflight"]["command"], 2, 1, :discard)
           |> Enum.any?(&(&1 == ["--component", "cadence"]))

    Enum.each(services, fn {_name, service} ->
      assert is_binary(service["mem_limit"])
      assert get_in(service, ["logging", "options", "max-size"]) == "2m"
      assert get_in(service, ["logging", "options", "max-file"]) == "1"
      assert get_in(service, ["logging", "options", "compress"]) == "false"

      Enum.each(Map.get(service, "volumes", []), fn mount ->
        if mount["type"] == "bind", do: assert(mount["read_only"] == true)
      end)
    end)

    assert Enum.any?(
             services["postgres"]["tmpfs"],
             &String.starts_with?(&1, "/var/lib/postgresql/data:size=")
           )

    assert Enum.any?(
             services["greptimedb"]["tmpfs"],
             &String.starts_with?(&1, "/greptimedb_data:size=")
           )

    grafana_data_mount =
      Enum.find(services["grafana"]["volumes"], &(&1["target"] == "/var/lib/grafana"))

    assert grafana_data_mount["type"] == "tmpfs"
    assert get_in(grafana_data_mount, ["tmpfs", "size"]) == 67_108_864

    journal_mount =
      Enum.find(services["cadence"]["volumes"], &(&1["target"] == "/benchmark/journal"))

    assert journal_mount["type"] == "tmpfs"
    assert get_in(journal_mount, ["tmpfs", "size"]) == 1_073_741_824

    refute Enum.any?(
             services["traffic_source"]["volumes"],
             &(&1["target"] == "/benchmark/journal")
           )

    refute File.read!(@full_flow_compose_path) =~ "./var"
  end

  test "1 Gb/s profile doubles traffic within a smaller bounded container budget" do
    assert {:ok, manifest} = Manifest.load(@full_flow_1gbps_manifest_path)

    assert {:ok, preflight} =
             Preflight.evaluate(manifest, mountinfo: @mountinfo, component: "cadence")

    assert Manifest.get(manifest, [:traffic, :phases]) == [
             %{
               "name" => "measure",
               "duration_seconds" => 150,
               "target_bps" => 1_000_000_000
             }
           ]

    assert Manifest.get(manifest, [:processing, :ingress_journal]) ==
             "capture_first_page_cache_tmpfs"

    assert preflight.safety.planned_source_bytes == 18_750_000_000
    assert preflight.safety.component_memory_limit_bytes == 1_342_177_280
    assert preflight.safety.container_memory_total_bytes == 6_174_015_488
    assert preflight.safety.docker_memory_budget_bytes == 8_394_457_088

    environment = File.read!(@full_flow_1gbps_env_path)
    assert environment =~ "CADENCE_INGRESS_BENCHMARK_PROJECT=cadence-ingress-1000"
    assert environment =~ "CADENCE_INGRESS_BENCHMARK_MANIFEST=./full-flow-1gbps-manifest.yaml"
    assert environment =~ "CADENCE_INGRESS_CADENCE_MEM_LIMIT=1280m"
    assert environment =~ "CADENCE_INGRESS_POSTGRES_MEM_LIMIT=3072m"
    assert environment =~ "CADENCE_INGRESS_POSTGRES_TMPFS_BYTES=2684354560"
  end
end
