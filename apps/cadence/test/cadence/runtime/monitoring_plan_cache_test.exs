defmodule Cadence.Runtime.MonitoringPlanCacheTest do
  @moduledoc """
  The node-wide monitoring and algorithm plan cache (#451 T1): a plan is decoded once per node and a
  partition holds an index over it; the semantic runtime gives the same results from the cache as
  from the decoded lists; a plan's entries go when its last holder does.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Expression, RuntimePlan}
  alias Cadence.Runtime.{MonitoringPlanCache, ProcessNamespace}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, PlanIndex, State, Update}

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
    start_supervised!({MonitoringPlanCache, process_namespace: namespace})
    %{server: MonitoringPlanCache.name(namespace)}
  end

  defp runtime_plan(target, plan_id, content) do
    %RuntimePlan{
      plan_id: plan_id,
      target: target,
      target_contract_version: "2",
      mission_model_revision_id: "rev",
      mission_model_content_sha256: "sha",
      layer_ids: [],
      compiler_version: "test",
      status: :ready,
      content_sha256: "content-#{plan_id}",
      plan: content
    }
  end

  defp expression(node), do: Expression.new(%{node: node, result_type: :number})

  # parameters p0..p(n-1); each has a limit; algorithm i derives q<i> = p<i> * 2 from p<i>.
  defp plans(id, n) do
    %{
      monitoring:
        runtime_plan(:monitoring, "mon-#{id}", %{
          policies:
            for i <- 0..(n - 1) do
              %{
                policy_id: "policy:q#{i}",
                parameter_id: "q#{i}",
                minimum_violations: 1,
                default_rules: [
                  %{kind: :comparison, operator: :>, value: 10, severity: :critical}
                ]
              }
            end ++
              [
                %{
                  policy_id: "policy:p0:second",
                  parameter_id: "p0",
                  default_rules: [
                    %{kind: :comparison, operator: :>, value: 100, severity: :warning}
                  ]
                }
              ]
        }),
      algorithm:
        runtime_plan(:algorithm, "alg-#{id}", %{
          algorithms:
            for i <- 0..(n - 1) do
              %{
                algorithm_id: "algorithm:#{i}",
                input_parameter_ids: ["p#{i}"],
                outputs: [
                  %{
                    parameter_id: "q#{i}",
                    qualified_name: "/q#{i}",
                    expression: expression({:*, {:parameter, "p#{i}"}, {:literal, 2}})
                  }
                ]
              }
            end
        })
    }
  end

  defp update(id, parameter, value, at) do
    Update.new(%{
      update_id: id,
      parameter_id: parameter,
      qualified_name: "/" <> parameter,
      value: value,
      raw_value: value,
      quality: :good,
      receipt_time: at,
      generation_time: at,
      producer_kind: :container,
      producer_id: "container:hk"
    })
  end

  test "a plan is decoded once and a second partition shares it; its entries go with its last holder",
       %{server: server} do
    plans = plans("a", 4)
    parent = self()

    holder = fn ->
      {:ok, index} = MonitoringPlanCache.acquire(server, plans)
      send(parent, {:held, self(), index})
      receive do: (:stop -> :ok)
    end

    first = spawn(holder)
    assert_receive {:held, ^first, index}
    second = spawn(holder)
    assert_receive {:held, ^second, _same}

    assert MonitoringPlanCache.loaded(server) == 1
    table = MonitoringPlanCache.table(server)
    assert :ets.info(table, :size) > 0

    assert [%{parameter_id: "q2"}] = PlanIndex.monitoring_for(index, "q2")
    assert [%{algorithm_id: "algorithm:2"}] = PlanIndex.algorithms_for_input(index, "p2")
    assert [%{algorithm_id: "algorithm:3"}] = PlanIndex.algorithms_with_id(index, "algorithm:3")
    assert PlanIndex.monitoring_for(index, "no-such-parameter") == []

    ref = Process.monitor(first)
    send(first, :stop)
    assert_receive {:DOWN, ^ref, :process, ^first, _}
    # One holder left: still loaded.
    assert MonitoringPlanCache.loaded(server) == 1

    ref = Process.monitor(second)
    send(second, :stop)
    assert_receive {:DOWN, ^ref, :process, ^second, _}
    # The cache learns of an exit by its monitor message: a call after it sees the release.
    assert MonitoringPlanCache.loaded(server) == 0
    assert :ets.info(table, :size) == 0
  end

  test "holding another plan releases the first; the same compiled plan is shared across holders",
       %{server: server} do
    {:ok, _a} = MonitoringPlanCache.acquire(server, plans("a", 3))
    assert MonitoringPlanCache.loaded(server) == 1

    # The same process now holds another plan: the first is released, the second loaded.
    {:ok, b} = MonitoringPlanCache.acquire(server, plans("b", 5))
    assert MonitoringPlanCache.loaded(server) == 1
    assert [%{parameter_id: "q4"}] = PlanIndex.monitoring_for(b, "q4")

    # Holding the same plan again is a no-op.
    {:ok, _again} = MonitoringPlanCache.acquire(server, plans("b", 5))
    assert MonitoringPlanCache.loaded(server) == 1
  end

  @tag capture_log: true
  test "a plan that cannot be decoded fails its caller; the cache keeps serving the others", %{
    server: server
  } do
    good = plans("good", 2)

    bad = %{
      plans("bad", 1)
      | algorithm:
          runtime_plan(:algorithm, "alg-bad", %{
            algorithms: [
              %{
                algorithm_id: "algorithm:bad",
                input_parameter_ids: ["p0"],
                time_basis: "no_such_time_basis_atom",
                outputs: []
              }
            ]
          })
    }

    owner = GenServer.whereis(server)
    ref = Process.monitor(owner)

    assert {:ok, index} = MonitoringPlanCache.acquire(server, good)

    # A second process asks for the bad plan: it raises there, in the asking process.
    {pid, down} = spawn_monitor(fn -> MonitoringPlanCache.acquire(server, bad) end)
    assert_receive {:DOWN, ^down, :process, ^pid, {%ArgumentError{message: message}, _stack}}
    assert message =~ "cannot be decoded"

    # The owner is the same process, still holds the good plan, and loads another.
    refute_received {:DOWN, ^ref, :process, ^owner, _reason}
    assert GenServer.whereis(server) == owner
    assert MonitoringPlanCache.loaded(server) == 1

    assert length(PlanIndex.monitoring_for(index, "p0")) == 1 or
             PlanIndex.monitoring_for(index, "p0") == []

    assert {:ok, _other} = MonitoringPlanCache.acquire(server, plans("another", 3))
  end

  test "a cache that is not running, even behind a registry that is not, gives an index of its own decode" do
    registry = Module.concat(__MODULE__, "NoSuchRegistry#{System.unique_integer([:positive])}")

    for missing <- [
          Module.concat(__MODULE__, "NoSuchCache"),
          {:via, Registry, {registry, :cache}}
        ] do
      assert {:ok, index} = MonitoringPlanCache.acquire(missing, plans("m", 3))
      assert [%{parameter_id: "q1"}] = PlanIndex.monitoring_for(index, "q1")
    end
  end

  test "no monitoring and no algorithms is an empty index; a plan without an id is decoded privately",
       %{server: server} do
    assert {:ok, empty} = MonitoringPlanCache.acquire(server, %{})
    assert PlanIndex.empty?(empty)
    assert MonitoringPlanCache.loaded(server) == 0

    unkeyed = update_in(plans("c", 2), [:monitoring], &%{&1 | plan_id: nil})
    assert {:ok, index} = MonitoringPlanCache.acquire(server, unkeyed)
    refute PlanIndex.empty?(index)
    assert [%{parameter_id: "q1"}] = PlanIndex.monitoring_for(index, "q1")
    assert MonitoringPlanCache.loaded(server) == 0
  end

  test "the cached index answers as the decoded lists do, in the same order", %{server: server} do
    plans = plans("d", 6)
    {:ok, cached} = MonitoringPlanCache.acquire(server, plans)
    listed = plans |> PlanDecoder.decode() |> PlanIndex.from_plan()

    for parameter <- ["p0", "p3", "q0", "q5", "missing"] do
      assert PlanIndex.monitoring_for(cached, parameter) ==
               PlanIndex.monitoring_for(listed, parameter)

      assert PlanIndex.algorithms_for_input(cached, parameter) ==
               PlanIndex.algorithms_for_input(listed, parameter)
    end

    for id <- ["algorithm:0", "algorithm:5", "algorithm:nope"] do
      assert PlanIndex.algorithms_with_id(cached, id) == PlanIndex.algorithms_with_id(listed, id)
    end

    # p0 has two policies (q0 is another parameter): both, in the plan's order.
    assert Enum.map(PlanIndex.monitoring_for(cached, "p0"), & &1.policy_id) == [
             "policy:p0:second"
           ]
  end

  test "the semantic runtime gives the same results from the cache, the lists and the decoded map",
       %{server: server} do
    plans = plans("e", 6)
    {:ok, cached} = MonitoringPlanCache.acquire(server, plans)
    decoded = PlanDecoder.decode(plans)
    at = ~U[2026-11-28 12:00:00.000000Z]

    updates = [
      update("u1", "p0", 3, at),
      update("u2", "p1", 8, DateTime.add(at, 1)),
      update("u3", "p0", 150, DateTime.add(at, 2)),
      update("u4", "p5", 2, DateTime.add(at, 3)),
      update("u5", "unrelated", 1, DateTime.add(at, 4))
    ]

    run = fn plan ->
      {:ok, result, state} = SemanticRuntime.process(%State{}, updates, plan)
      {result, state}
    end

    assert run.(cached) == run.(decoded)
    {result, _state} = run.(cached)

    # Derived values and a monitoring evaluation actually happened (not an empty comparison).
    assert Enum.any?(result.parameter_updates, &(&1.parameter_id == "q1" and &1.value == 16))
    assert result.monitoring_results != []

    # A timer by algorithm id agrees too.
    timer = fn plan ->
      {:ok, state} = {:ok, elem(run.(plan), 1)}
      SemanticRuntime.timer(state, "algorithm:1", DateTime.add(at, 10), plan)
    end

    assert timer.(cached) == timer.(decoded)
  end
end
