defmodule Cadence.Runtime.MissionSupervisionTest do
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.MissionModelFixtures
  alias Cadence.Runtime

  alias Cadence.Runtime.{
    MissionRuntime,
    MissionRuntimeSpec,
    Missions,
    PartitionKey,
    PartitionOwner,
    ProcessNamespace
  }

  @mission "supervision-mission"
  @namespace %ProcessNamespace{
    root_supervisor: __MODULE__.Root,
    registry: __MODULE__.Registry,
    mission_supervisor: __MODULE__.Missions,
    capability_registry: __MODULE__.Capabilities
  }

  setup do
    start_supervised!(
      {Runtime.Supervisor,
       process_namespace: @namespace,
       resource_children: [],
       mission_runtime_opts: [persist_runtime_records?: false],
       profiler: :disabled}
    )

    spec = runtime_spec()
    assert {:ok, _} = Missions.apply(@namespace, spec)
    alpha = PartitionKey.new(%{affinity: :source_endpoint, value: "alpha"})
    beta = PartitionKey.new(%{affinity: :source_endpoint, value: "beta"})
    assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, alpha)
    assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, beta)
    assert {:ok, alpha_owner} = PartitionOwner.lookup(@namespace, @mission, alpha)
    assert {:ok, beta_owner} = PartitionOwner.lookup(@namespace, @mission, beta)
    coordinator = MissionRuntime.coordinator_name(@namespace, @mission)

    %{
      spec: spec,
      alpha: alpha,
      beta: beta,
      alpha_owner: alpha_owner,
      beta_owner: beta_owner,
      coordinator: coordinator
    }
  end

  test "coordinator loss retains admitted generation and execution PIDs", ctx do
    old = GenServer.whereis(ctx.coordinator)
    contact_pool = MissionRuntime.realized_contact_supervisor_name(@namespace, @mission)
    contact_pid = GenServer.whereis(contact_pool)

    assert {:ok, contact} =
             DynamicSupervisor.start_child(
               contact_pool,
               %{id: :contact_fixture, start: {__MODULE__, :start_contact, []}}
             )

    Process.exit(old, :kill)

    await(fn ->
      is_pid(GenServer.whereis(ctx.coordinator)) and GenServer.whereis(ctx.coordinator) != old
    end)

    assert {:ok, _} =
             Missions.confirm_applied(@namespace, @mission, MissionRuntimeSpec.identity(ctx.spec))

    assert {:ok, spec} = Missions.applied_spec(@namespace, @mission)
    assert spec == ctx.spec
    assert Process.alive?(ctx.alpha_owner)
    assert Process.alive?(ctx.beta_owner)
    assert Process.alive?(contact)
    assert GenServer.whereis(contact_pool) == contact_pid
  end

  test "independent contact pool failure preserves partitions", ctx do
    pool = MissionRuntime.realized_contact_supervisor_name(@namespace, @mission)
    old = GenServer.whereis(pool)
    Process.exit(old, :kill)
    await(fn -> is_pid(GenServer.whereis(pool)) and GenServer.whereis(pool) != old end)
    assert Process.alive?(ctx.alpha_owner)
    assert Process.alive?(ctx.beta_owner)
    assert {:ok, %{generation: 1}} = Runtime.partition_snapshot(@namespace, @mission, ctx.alpha)
  end

  test "admission loss invalidates dependent execution instead of retaining untracked owners",
       ctx do
    admission = GenServer.whereis(MissionRuntime.admission_name(@namespace, @mission))
    Process.exit(admission, :kill)
    await(fn -> not Process.alive?(ctx.alpha_owner) and not Process.alive?(ctx.beta_owner) end)
    assert {:ok, %{generation: 1}} = Missions.apply(@namespace, ctx.spec)
    assert {:ok, %{generation: 1}} = Runtime.partition_snapshot(@namespace, @mission, ctx.alpha)
    assert {:ok, replacement} = PartitionOwner.lookup(@namespace, @mission, ctx.alpha)
    assert replacement != ctx.alpha_owner
  end

  test "interrupted rollout resumes without resetting healthy admitted partitions", ctx do
    next = %{ctx.spec | generation: 2, activation_id: "next"}
    :ok = :sys.suspend(ctx.beta_owner)

    try do
      request = :gen_server.send_request(ctx.coordinator, {:apply_spec, next})

      await(fn ->
        MapSet.member?(Missions.rollout_status(@namespace, @mission).ready, ctx.alpha)
      end)

      assert {:ok, %{generation: 2}} = Runtime.partition_snapshot(@namespace, @mission, ctx.alpha)
      before = :sys.get_state(ctx.alpha_owner)
      old = GenServer.whereis(ctx.coordinator)
      Process.exit(old, :kill)
      assert {:error, {:killed, _}} = :gen_server.wait_response(request, 1_000)

      await(fn ->
        is_pid(GenServer.whereis(ctx.coordinator)) and GenServer.whereis(ctx.coordinator) != old
      end)

      await(fn ->
        MapSet.member?(Missions.rollout_status(@namespace, @mission).ready, ctx.alpha)
      end)

      assert :sys.get_state(ctx.alpha_owner) == before
      assert Process.alive?(ctx.beta_owner)
    after
      :sys.resume(ctx.beta_owner)
    end

    await(fn -> Missions.rollout_status(@namespace, @mission).status == :applied end)

    assert {:ok, %{generation: 2}} =
             Missions.confirm_applied(@namespace, @mission, MissionRuntimeSpec.identity(next))
  end

  test "a failed partition neither acknowledges the rollout nor stops its healthy peer", ctx do
    next = %{ctx.spec | generation: 2, activation_id: "next"}
    :ok = :sys.suspend(ctx.beta_owner)
    request = :gen_server.send_request(ctx.coordinator, {:apply_spec, next})

    await(fn ->
      MapSet.member?(Missions.rollout_status(@namespace, @mission).ready, ctx.alpha)
    end)

    Process.exit(ctx.beta_owner, {:shutdown, :failed_partition})

    assert {:reply, {:error, {:generation_incomplete, 2, failed}}} =
             :gen_server.wait_response(request, 1_000)

    assert Map.has_key?(failed, ctx.beta)

    assert {:error, {:generation_incomplete, 2, _}} =
             Missions.confirm_applied(@namespace, @mission, MissionRuntimeSpec.identity(next))

    assert {:ok, %{generation: 2}} = Runtime.partition_snapshot(@namespace, @mission, ctx.alpha)

    await(fn ->
      PartitionOwner.lookup(@namespace, @mission, ctx.beta) == {:error, :partition_not_running}
    end)

    before = :sys.get_state(ctx.alpha_owner)
    assert {:ok, %{generation: 2}} = Missions.apply(@namespace, next)
    assert :sys.get_state(ctx.alpha_owner) == before
    assert {:ok, %{generation: 2}} = Runtime.partition_snapshot(@namespace, @mission, ctx.beta)
  end

  test "incomplete rollout rejects rollback but can converge on a newer generation", ctx do
    next = %{ctx.spec | generation: 2, activation_id: "next"}
    :ok = :sys.suspend(ctx.beta_owner)
    request = :gen_server.send_request(ctx.coordinator, {:apply_spec, next})

    await(fn ->
      MapSet.member?(Missions.rollout_status(@namespace, @mission).ready, ctx.alpha)
    end)

    Process.exit(ctx.beta_owner, {:shutdown, :failed_partition})

    assert {:reply, {:error, {:generation_incomplete, 2, _}}} =
             :gen_server.wait_response(request, 1_000)

    await(fn ->
      PartitionOwner.lookup(@namespace, @mission, ctx.beta) == {:error, :partition_not_running}
    end)

    assert {:error, {:stale_generation, 2}} = Missions.apply(@namespace, ctx.spec)

    assert {:error, {:generation_conflict, 2}} =
             Missions.apply(@namespace, %{next | runtime_basis_sha256: "conflicting-basis"})

    newer = %{next | generation: 3, activation_id: "newer"}
    assert {:ok, %{generation: 3}} = Missions.apply(@namespace, newer)
    assert {:ok, %{generation: 3}} = Runtime.partition_snapshot(@namespace, @mission, ctx.alpha)
    assert {:ok, %{generation: 3}} = Runtime.partition_snapshot(@namespace, @mission, ctx.beta)
  end

  @doc false
  def start_contact(_runtime_opts),
    do:
      Task.start_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

  defp await(fun, attempts \\ 200)
  defp await(_fun, 0), do: flunk("runtime did not converge")

  defp await(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await(fun, attempts - 1)
        )
  end

  defp runtime_spec do
    binding = BindingSet.new(%{mission_id: @mission, binding_set_id: "basis", version: 1})
    {:ok, compilation} = MissionModelFixtures.compile_empty_model(@mission)

    {:ok, spec} =
      MissionRuntimeSpec.new(%{
        activation_id: "initial",
        mission_id: @mission,
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
