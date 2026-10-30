defmodule Cadence.OTPClusterSpike.Runtime do
  @moduledoc false
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Runtime.{MissionRuntime, MissionRuntimeSpec, ProcessNamespace}

  def namespace do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.Root,
      registry: __MODULE__.Registry,
      mission_supervisor: __MODULE__.Missions,
      capability_registry: __MODULE__.Capabilities
    )
  end

  def boot(hosts) do
    {:ok, pid} =
      Cadence.Runtime.Supervisor.start_link(
        process_namespace: namespace(),
        resource_children: [],
        profiler: :disabled,
        mission_runtime_opts: [persist_runtime_records?: false],
        cluster: [
          id: :production_runtime_test,
          scope: __MODULE__.Groups,
          topologies: [
            runtime: [strategy: Cluster.Strategy.Epmd, config: [hosts: hosts, timeout: 100]]
          ]
        ]
      )

    Process.unlink(pid)
    :ok
  end

  def hold_routes(namespace, key) do
    parent = self()

    pid =
      spawn(fn ->
        coordinator =
          MissionRuntime.coordinator_name(namespace, "cluster-mission")

        for _ <- 1..32, do: {:ok, _, _} = GenServer.call(coordinator, {:partition_route, key})
        send(parent, {:held, self()})

        receive do
          :stop -> :ok
        end
      end)

    receive do
      {:held, ^pid} -> pid
    after
      5_000 -> raise "route admission timed out"
    end
  end

  def start_snapshot(namespace, key) do
    {:ok, holder} = Agent.start(fn -> nil end)

    spawn(fn ->
      result = Cadence.Runtime.partition_snapshot(namespace, "cluster-mission", key)
      Agent.update(holder, fn _ -> result end)
    end)

    holder
  end

  def result(holder), do: Agent.get(holder, & &1)

  def spec do
    binding =
      BindingSet.new(%{
        mission_id: "cluster-mission",
        binding_set_id: "basis",
        version: 1
      })

    {:ok, compilation} = Cadence.MissionModelFixtures.compile_empty_model("cluster-mission")

    {:ok, spec} =
      MissionRuntimeSpec.new(%{
        activation_id: "initial",
        mission_id: "cluster-mission",
        generation: 1,
        binding_set_id: binding.binding_set_id,
        binding_set_version: binding.version,
        binding_set: binding,
        mission_model_revision_id: compilation.revision.revision_id,
        mission_model_content_sha256: compilation.revision.content_sha256,
        runtime_plans: compilation.plans,
        activated_at: ~U[2026-10-26 12:00:00Z]
      })

    spec
  end
end
