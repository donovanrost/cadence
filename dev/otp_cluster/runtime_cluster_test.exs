defmodule Cadence.RuntimeClusterTest do
  use ExUnit.Case, async: false
  alias Cadence.Ingress.RawEvidence
  alias Cadence.OTPClusterSpike.Cluster
  alias Cadence.OTPClusterSpike.Runtime, as: Fixture

  alias Cadence.Runtime.{
    MissionAdmission,
    MissionRuntime,
    MissionRuntimeSpec,
    Missions,
    PartitionKey,
    PartitionOwner,
    ProcessNamespace
  }

  @moduletag timeout: 60_000

  setup do
    peers = Cluster.start()
    on_exit(fn -> Cluster.stop(peers) end)

    Enum.each(peers, fn peer ->
      Cluster.call(peer, Code, :require_file, [Path.join(__DIR__, "runtime.ex")])
      assert :ok = Cluster.call(peer, Fixture, :boot, [Enum.map(peers, & &1.node)])
    end)

    namespace = Fixture.namespace()
    group = {Cadence.Runtime.Cluster, :production_runtime_test, namespace.registry}

    Cluster.await(fn ->
      Enum.all?(
        peers,
        &(length(Cluster.call(&1, :pg, :get_members, [Fixture.Groups, group])) == 3)
      )
    end)

    spec = Fixture.spec()
    [a | _] = peers
    assert {:ok, _} = Cluster.call(a, Missions, :apply, [namespace, spec])
    %{peers: peers, namespace: namespace, spec: spec}
  end

  test "production partitions execute remotely and generations converge without replacing healthy owners",
       %{peers: [a, b, c], namespace: ns, spec: spec} do
    key = key_on(b, [a, b, c])

    assert {:ok, %{generation: 1}} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    assert {:ok, owner} = Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key])
    assert node(owner) == b.node
    assert {:ok, ^owner} = Cluster.call(c, PartitionOwner, :lookup, [ns, spec.mission_id, key])

    next = %{spec | generation: 2, activation_id: "next"}
    assert {:ok, %{generation: 2}} = Cluster.call(c, Missions, :apply, [ns, next])

    assert {:ok, %{generation: 2}} =
             Cluster.call(a, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    evidence =
      RawEvidence.new(%{
        mission_id: spec.mission_id,
        source_endpoint_ref: key.value,
        raw: <<0::3, 0::1, 0::1, 42::11, 3::2, 1::14, 1::16, 0, 7>>
      })

    assert {:ok, processed} =
             Cluster.call(c, Cadence.Runtime, :process_telemetry_ingress, [ns, evidence])

    assert processed.observation_context.generation == 2
    assert processed.raw_evidence.evidence_id == evidence.evidence_id

    assert {:ok, ^owner} = Cluster.call(c, PartitionOwner, :lookup, [ns, spec.mission_id, key])

    coordinator_name = Cluster.call(a, MissionRuntime, :coordinator_name, [ns, spec.mission_id])
    old = Cluster.call(a, GenServer, :whereis, [coordinator_name])
    Cluster.call(a, Process, :exit, [old, :kill])

    Cluster.await(fn ->
      pid = Cluster.call(c, GenServer, :whereis, [coordinator_name])
      is_pid(pid) and pid != old
    end)

    assert Cluster.call(b, Process, :alive?, [owner])

    assert {:ok, %{generation: 2}} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    groups = Cluster.call(b, Process, :whereis, [Fixture.Groups])
    Cluster.call(b, Process, :exit, [groups, :kill])

    Cluster.await(fn ->
      pid = Cluster.call(b, Process, :whereis, [Fixture.Groups])
      is_pid(pid) and pid != groups
    end)

    assert Cluster.call(b, Process, :alive?, [owner])
    discovery_name = ProcessNamespace.via(ns, :discovery)
    discovery = Cluster.call(b, GenServer, :whereis, [discovery_name])
    Cluster.call(b, Process, :exit, [discovery, :kill])

    Cluster.await(fn ->
      pid = Cluster.call(b, GenServer, :whereis, [discovery_name])
      is_pid(pid) and pid != discovery
    end)

    assert Cluster.call(b, Process, :alive?, [owner])
    assert :ok = Cluster.call(c, Cadence.Runtime, :stop_mission, [ns, spec.mission_id])
    Cluster.await(fn -> not Cluster.call(b, Process, :alive?, [owner]) end)
  end

  test "node loss rebuilds the partition on a surviving execution agent", %{
    peers: [a, b, c],
    namespace: ns,
    spec: spec
  } do
    key = key_on(b, [a, b, c])

    assert {:ok, _} =
             Cluster.call(a, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    assert {:ok, old} = Cluster.call(c, PartitionOwner, :lookup, [ns, spec.mission_id, key])
    assert node(old) == b.node
    Cluster.stop([b])

    Cluster.await(fn ->
      Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key]) ==
        {:error, :partition_not_running}
    end)

    assert {:ok, %{generation: 1}} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    assert {:ok, replacement} =
             Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key])

    assert node(replacement) in [a.node, c.node]
  end

  test "routing enforces admission and reports uncertain owner loss without replay", %{
    peers: [a, b, c],
    namespace: ns,
    spec: spec
  } do
    key = key_on(b, [a, b, c])

    assert {:ok, _} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    holder = Cluster.call(c, Fixture, :hold_routes, [ns, key])

    assert {:error, {:partition_busy, _}} =
             Cluster.call(a, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    Cluster.call(c, Process, :exit, [holder, :kill])
    coordinator = Cluster.call(a, MissionRuntime, :coordinator_name, [ns, spec.mission_id])

    Cluster.await(fn ->
      Cluster.call(a, :sys, :get_state, [coordinator]).request_counts == %{}
    end)

    assert {:ok, owner} = Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key])
    :ok = Cluster.call(b, :sys, :suspend, [owner])
    result = Cluster.call(c, Fixture, :start_snapshot, [ns, key])

    Cluster.await(fn ->
      case Cluster.call(b, Process, :info, [owner, :message_queue_len]) do
        {:message_queue_len, count} -> count > 0
        _ -> false
      end
    end)

    Cluster.call(b, Process, :exit, [owner, :kill])
    Cluster.await(fn -> not is_nil(Cluster.call(c, Fixture, :result, [result])) end)
    assert {:error, {:partition_outcome_unknown, _}} = Cluster.call(c, Fixture, :result, [result])
  end

  test "withdrawing execution eligibility preserves owners and refuses new placement", %{
    peers: peers,
    namespace: ns,
    spec: spec
  } do
    [a, b, c] = peers
    key = key_on(b, peers)

    assert {:ok, _} =
             Cluster.call(a, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    Enum.each(peers, &Cluster.call(&1, Cadence.Runtime.ExecutionAgent, :withdraw, [ns]))
    group = {Cadence.Runtime.Cluster, :production_runtime_test, ns.registry}
    Cluster.await(fn -> Cluster.call(a, :pg, :get_members, [Fixture.Groups, group]) == [] end)

    assert {:ok, _} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    other = PartitionKey.new(%{affinity: :source_endpoint, value: "unplaced"})

    assert {:error, :no_execution_nodes} =
             Cluster.call(a, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, other])
  end

  test "admission loss retires remote execution and stale restart sources do not loop", %{
    peers: [a, b, c],
    namespace: ns,
    spec: spec
  } do
    key = key_on(b, [a, b, c])

    assert {:ok, _} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    assert {:ok, owner} = Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key])
    admission_name = Cluster.call(a, MissionRuntime, :admission_name, [ns, spec.mission_id])
    old_admission = Cluster.call(a, GenServer, :whereis, [admission_name])
    Cluster.call(a, Process, :exit, [old_admission, :kill])
    Cluster.await(fn -> not Cluster.call(b, Process, :alive?, [owner]) end)

    child =
      Supervisor.child_spec(
        {PartitionOwner,
         mission_id: spec.mission_id,
         process_namespace: ns,
         partition_key: key,
         spec_source: old_admission,
         defer_init?: true},
        restart: :transient
      )

    pool = ProcessNamespace.via(ns, :execution_pool)
    original_pool = Cluster.call(b, GenServer, :whereis, [pool])
    assert {:ok, orphan} = Cluster.call(b, DynamicSupervisor, :start_child, [pool, child])
    Cluster.await(fn -> not Cluster.call(b, Process, :alive?, [orphan]) end)
    assert Cluster.call(b, GenServer, :whereis, [pool]) == original_pool
    assert %{active: 0} = Cluster.call(b, DynamicSupervisor, :count_children, [pool])

    Cluster.await(fn ->
      pid = Cluster.call(a, GenServer, :whereis, [admission_name])
      is_pid(pid) and pid != old_admission
    end)

    assert {:ok, _} = Cluster.call(c, Missions, :apply, [ns, spec])

    assert {:ok, %{generation: 1}} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])
  end

  test "a fencing rejection survives controller restart and only a new admission permits recovery",
       %{peers: [a, b, c], namespace: ns, spec: spec} do
    key = key_on(b, [a, b, c])

    assert {:ok, _} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    assert {:ok, owner} = Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key])
    admission = Cluster.call(a, MissionRuntime, :admission_name, [ns, spec.mission_id])

    assert :ok =
             Cluster.call(a, MissionAdmission, :fence, [
               admission,
               key,
               MissionRuntimeSpec.identity(spec)
             ])

    assert :ok = Cluster.call(b, GenServer, :stop, [owner])

    assert {:error, {:partition_fenced, 1}} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    coordinator = Cluster.call(a, MissionRuntime, :coordinator_name, [ns, spec.mission_id])
    old = Cluster.call(a, GenServer, :whereis, [coordinator])
    Cluster.call(a, Process, :exit, [old, :kill])

    Cluster.await(fn ->
      pid = Cluster.call(c, GenServer, :whereis, [coordinator])
      is_pid(pid) and pid != old
    end)

    assert {:error, {:partition_fenced, 1}} =
             Cluster.call(c, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])

    assert {:error, :partition_not_running} =
             Cluster.call(a, PartitionOwner, :lookup, [ns, spec.mission_id, key])

    next = %{spec | generation: 2, activation_id: "readmitted"}
    assert {:ok, %{generation: 2}} = Cluster.call(c, Missions, :apply, [ns, next])

    assert {:ok, %{generation: 2}} =
             Cluster.call(a, Cadence.Runtime, :partition_snapshot, [ns, spec.mission_id, key])
  end

  test "concurrent mission starts wait for the globally named control unit to be ready", %{
    peers: peers,
    namespace: ns,
    spec: spec
  } do
    [a | _] = peers
    assert :ok = Cluster.call(a, Cadence.Runtime, :stop_mission, [ns, spec.mission_id])

    results =
      Task.async_stream(
        peers,
        fn peer ->
          Cluster.call(peer, Missions, :apply, [ns, spec])
        end,
        timeout: 15_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, %{generation: 1}}}, &1))
    name = Cluster.call(a, MissionRuntime, :runtime_name, [ns, spec.mission_id])
    roots = Enum.map(peers, &Cluster.call(&1, GenServer, :whereis, [name]))
    assert [root] = Enum.uniq(roots)
    assert is_pid(root)
    assert length(Cluster.call(a, Supervisor, :which_children, [root])) == 3
  end

  defp key_on(target, peers) do
    Enum.find_value(1..100, fn index ->
      key = PartitionKey.new(%{affinity: :source_endpoint, value: "source-#{index}"})
      selected = Enum.max_by(peers, &:erlang.phash2({{"cluster-mission", key}, &1.node}))
      if selected == target, do: key
    end)
  end
end
