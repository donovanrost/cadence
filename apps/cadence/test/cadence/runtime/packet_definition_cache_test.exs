defmodule Cadence.Runtime.PacketDefinitionCacheTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.Runtime.PacketDefinitionCache
  alias Cadence.Runtime.PartitionOwner.DispatchCache
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Telemetry.PacketDefinition

  setup do
    base = Module.concat(__MODULE__, "Ns#{System.unique_integer([:positive])}")

    namespace =
      ProcessNamespace.new!(
        root_supervisor: Module.concat(base, Root),
        registry: Module.concat(base, Registry),
        mission_supervisor: Module.concat(base, Missions),
        capability_registry: Module.concat(base, Capabilities)
      )

    start_supervised!({Registry, keys: :unique, name: namespace.registry})
    start_supervised!({PacketDefinitionCache, process_namespace: namespace})
    %{namespace: namespace}
  end

  defp plans(plan_id, packet_ids) do
    %{
      telemetry: %RuntimePlan{
        plan_id: plan_id,
        target: :telemetry,
        target_contract_version: "2",
        mission_model_revision_id: "rev",
        mission_model_content_sha256: "sha",
        layer_ids: [],
        compiler_version: "test",
        status: :ready,
        content_sha256: "content",
        plan: %{
          "runtime_contract" => "mission_model_telemetry_v1",
          "packet_definitions" =>
            for id <- packet_ids do
              %{
                "packet_definition_id" => id,
                "mission_id" => "m",
                "packet_name" => id,
                "apid" => 1,
                "fields" => []
              }
            end
        }
      }
    }
  end

  defp configured(id),
    do:
      PacketDefinition.new(%{
        packet_definition_id: id,
        mission_id: "m",
        packet_name: id,
        apid: 1,
        fields: []
      })

  # Runs `fun` in a process that holds the revision until told to stop, like a partition.
  defp holder(namespace, plans) do
    parent = self()

    pid =
      spawn(fn ->
        cache = DispatchCache.acquire(namespace, plans)
        send(parent, {:held, self(), cache})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:held, ^pid, cache}
    {pid, cache}
  end

  test "resolves packet definitions with one ETS read", %{namespace: namespace} do
    {_pid, cache} = holder(namespace, plans("p1", ["a", "b"]))

    assert {:ok, %PacketDefinition{packet_name: "b"}} =
             DispatchCache.resolve_packet_definition(cache, configured("b"))

    assert {:error, {:mission_model_packet_definition_not_found, "z"}} =
             DispatchCache.resolve_packet_definition(cache, configured("z"))
  end

  test "partitions on one revision share a single decode", %{namespace: namespace} do
    {_a, %{packet_definitions: {:ok, table_a}}} = holder(namespace, plans("p1", ["a", "b"]))
    {_b, %{packet_definitions: {:ok, table_b}}} = holder(namespace, plans("p1", ["a", "b"]))

    assert table_a == table_b
    assert :ets.info(table_a, :size) == 2
  end

  test "a revision is deleted when its last holder exits, and kept while one remains", %{
    namespace: namespace
  } do
    {a, %{packet_definitions: {:ok, table}} = cache} = holder(namespace, plans("p1", ["a"]))
    {b, _} = holder(namespace, plans("p1", ["a"]))

    release(namespace, a)
    assert {:ok, _} = DispatchCache.resolve_packet_definition(cache, configured("a"))

    release(namespace, b)
    assert :ets.info(table, :size) == 0
  end

  test "reacquiring a different revision releases the previous one", %{namespace: namespace} do
    {:ok, table} = PacketDefinitionCache.acquire(namespace, "p1", plans("p1", ["a"]))
    assert {:ok, ^table} = PacketDefinitionCache.acquire(namespace, "p1", plans("p1", ["a"]))
    assert {:ok, ^table} = PacketDefinitionCache.acquire(namespace, "p2", plans("p2", ["c"]))

    assert :error = PacketDefinitionCache.fetch(table, "p1", "a")
    assert {:ok, _} = PacketDefinitionCache.fetch(table, "p2", "c")
  end

  test "a revision already cached is held without its plans being sent", %{namespace: namespace} do
    {_a, %{packet_definitions: {:ok, table}}} = holder(namespace, plans("p1", ["a"]))

    # `%{}` would fail to decode, so a hit that succeeds cannot have used the plans.
    {_b, cache} = holder(namespace, %{telemetry: %{plan_id: "p1"}})

    assert %{packet_definitions: {:ok, ^table}} = cache
    assert {:ok, _} = DispatchCache.resolve_packet_definition(cache, configured("a"))
  end

  test "a plan without an id is never cached, and releases what the caller held", %{
    namespace: namespace
  } do
    first = put_in(plans("ignored", ["a"]), [:telemetry, Access.key(:plan_id)], nil)
    other = put_in(plans("ignored", ["b"]), [:telemetry, Access.key(:plan_id)], nil)

    assert {:error, :telemetry_plan_without_id} =
             PacketDefinitionCache.acquire(namespace, nil, first)

    assert {:error, :telemetry_plan_without_id} =
             PacketDefinitionCache.acquire(namespace, nil, other)

    {:ok, table} = PacketDefinitionCache.acquire(namespace, "p1", plans("p1", ["a"]))

    assert {:error, :telemetry_plan_without_id} =
             PacketDefinitionCache.acquire(namespace, nil, other)

    assert :ets.info(table, :size) == 0
    assert :error = PacketDefinitionCache.fetch(table, nil, "a")
    assert :error = PacketDefinitionCache.fetch(table, nil, "b")
  end

  test "a plan that fails to decode is reported on resolve and caches nothing", %{
    namespace: namespace
  } do
    cache = DispatchCache.acquire(namespace, %{})

    assert {:error, {:mission_model_runtime_plan_required, :telemetry}} =
             DispatchCache.resolve_packet_definition(cache, configured("a"))
  end

  defp release(namespace, pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    # the owner's own DOWN for the pid is already queued; a call after it is handled behind it
    :sys.get_state(GenServer.whereis(PacketDefinitionCache.name(namespace)))
    :ok
  end
end
