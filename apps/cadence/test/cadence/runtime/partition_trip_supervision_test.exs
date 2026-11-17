defmodule Cadence.Runtime.PartitionTripSupervisionTest do
  @moduledoc """
  DECISIONS #99 landing condition (lead and director, 11-17): a partition tripped by a replay-id
  conflict must not take anything else down. A mission's partitions share one DynamicSupervisor
  (3 restarts in 5 s); an abnormal exit per tripped partition let four partitions tripping together
  exhaust it and kill every partition of the mission. A trip now stops its owner with a shutdown
  (not restarted, not counted) and the coordinator backs the partition off, then starts it again
  on the next request. A non-trip crash is restarted and counted as before.

  Real runtime: an isolated namespace's mission runtime, coordinator, partition pool and owners;
  the owners' writes go through `Cadence.Test.TrippingRuntimeWriter`, which trips a chosen write
  through the real `ReplayId.check_replay/4`.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Catalog.MissionModel.Expression
  alias Cadence.Ingress.RawEvidence
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

  alias Cadence.Test.TrippingRuntimeWriter

  @mission "trip-supervision-mission"
  @org "trip-supervision-org"
  @apid 42
  @namespace %ProcessNamespace{
    root_supervisor: __MODULE__.Root,
    registry: __MODULE__.Registry,
    mission_supervisor: __MODULE__.Missions,
    capability_registry: __MODULE__.Capabilities
  }

  setup tags do
    sandbox = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)
    on_exit(fn -> Cadence.DataCase.stop_sandbox_owner(sandbox) end)
    Cadence.DataCase.persist_mission_scope(@org, @mission)
    TrippingRuntimeWriter.configure(@mission, trip: [], notify: self())
    on_exit(fn -> TrippingRuntimeWriter.reset(@mission) end)

    start_supervised!(
      {Runtime.Supervisor,
       process_namespace: @namespace,
       resource_children: [],
       mission_runtime_opts: [runtime_writer: TrippingRuntimeWriter],
       profiler: :disabled}
    )

    assert {:ok, _} = Missions.apply(@namespace, runtime_spec(tags[:periodic_ms]))
    beta = key("beta")
    assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, beta)
    assert {:ok, beta_owner} = PartitionOwner.lookup(@namespace, @mission, beta)

    %{
      beta: beta,
      beta_owner: beta_owner,
      pool: GenServer.whereis(MissionRuntime.partition_supervisor_name(@namespace, @mission)),
      coordinator: MissionRuntime.coordinator_name(@namespace, @mission)
    }
  end

  test "a managed-application timer trip stops with a shutdown, backs off, comes back and clears",
       ctx do
    alpha = key("alpha")
    assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, alpha)
    {:ok, owner} = PartitionOwner.lookup(@namespace, @mission, alpha)
    ref = Process.monitor(owner)
    TrippingRuntimeWriter.configure(@mission, trip: [:timer_handled], notify: self())

    log =
      capture_log([level: :error], fn ->
        # The packet arms the packet counter's flush timer; its firing is the tripped write.
        assert {:ok, _} = ingest(alpha, 1)
        assert_receive {:tripped, :timer_handled, @mission}, 2_000

        assert_receive {:DOWN, ^ref, :process, ^owner,
                        {:shutdown, {:replay_id_tripped, {:replay_id_conflict, _, _}}}},
                       2_000
      end)

    # The trip still says so, at error level, once per trip.
    assert [_one] = Regex.scan(~r/\[error\].*MM_REPLAY_ID_CONFLICT managed_action_request/, log)

    # Not restarted by the pool (a shutdown), backed off by the coordinator instead.
    await(fn ->
      PartitionOwner.lookup(@namespace, @mission, alpha) == {:error, :partition_not_running}
    end)

    assert {:error, {:partition_initialization_backoff, {:replay_id_conflict, _, _}, retry_ms}} =
             Runtime.partition_snapshot(@namespace, @mission, alpha)

    assert retry_ms <= 250

    # It comes back through the backoff (director (1)), and a start that answers clears the
    # backoff, so its next failure starts at 250 ms again, not doubled (lead (2)).
    TrippingRuntimeWriter.configure(@mission, trip: [], notify: self())
    Process.sleep(retry_ms + 20)
    assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, alpha)
    assert {:ok, back} = PartitionOwner.lookup(@namespace, @mission, alpha)
    assert back != owner
    refute Map.has_key?(:sys.get_state(ctx.coordinator).partition_backoff, alpha)

    assert_untouched(ctx)
  end

  @tag periodic_ms: 150
  test "a semantic timer trip backs off, and its re-trips in initialization stay bounded", ctx do
    gamma = key("gamma")
    beta_ref = Process.monitor(ctx.beta_owner)
    TrippingRuntimeWriter.configure(@mission, trip: [:semantic_timer], notify: self())
    starts = count_recoveries(gamma)

    capture_log(fn ->
      assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, gamma)
      {:ok, owner} = PartitionOwner.lookup(@namespace, @mission, gamma)
      ref = Process.monitor(owner)
      assert_receive {:tripped, :semantic_timer, @mission}, 2_000

      assert_receive {:DOWN, ^ref, :process, ^owner,
                      {:shutdown, {:replay_id_tripped, {:replay_id_conflict, _, _}}}},
                     2_000

      # The tick was committed before its projection tripped, so every start re-projects it in
      # initialization and trips again. Ask for the partition every 20 ms for 1.6 s: only the
      # backoff decides how often it starts (250, 500, 1000 ms), never the request rate.
      replies = for _ <- 1..80, do: ask(gamma)

      assert Enum.count(replies, &match?({:error, {:partition_initialization_backoff, _, _}}, &1)) >=
               75

      refute Enum.any?(replies, &match?({:ok, _}, &1))
    end)

    assert :counters.get(starts, 1) in 2..4

    # The algorithm runs in every partition, so beta's tick trips too (the systemic case): it
    # stops with a shutdown like gamma, the pool restarts neither, and the pool itself is untouched.
    assert_receive {:DOWN, ^beta_ref, :process, _, {:shutdown, {:replay_id_tripped, _}}}, 2_000

    assert PartitionOwner.lookup(@namespace, @mission, ctx.beta) ==
             {:error, :partition_not_running}

    assert GenServer.whereis(pool_name()) == ctx.pool
    assert Process.alive?(ctx.pool)
  end

  test "a trip in initialization exits with a shutdown and is backed off, never restarted", ctx do
    delta = key("delta")
    TrippingRuntimeWriter.configure(@mission, trip: [:initialized], notify: self())
    starts = count_recoveries(delta)

    capture_log(fn ->
      assert {:error, {:partition_unavailable, _}} =
               Runtime.partition_snapshot(@namespace, @mission, delta)

      assert_receive {:tripped, :initialized, @mission}, 2_000

      assert {:error, {:partition_initialization_backoff, {:replay_id_conflict, _, _}, _}} =
               Runtime.partition_snapshot(@namespace, @mission, delta)
    end)

    Process.sleep(100)
    assert :counters.get(starts, 1) == 1
    assert PartitionOwner.lookup(@namespace, @mission, delta) == {:error, :partition_not_running}
    assert_untouched(ctx)
  end

  test "four partitions tripping together leave the pool and a healthy sibling alive", ctx do
    keys = for name <- ~w(p1 p2 p3 p4), do: key(name)

    owners =
      for k <- keys do
        assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, k)
        {:ok, owner} = PartitionOwner.lookup(@namespace, @mission, k)
        {owner, Process.monitor(owner)}
      end

    TrippingRuntimeWriter.configure(@mission, trip: [:timer_handled], notify: self())

    capture_log(fn ->
      Enum.each(keys, &({:ok, _} = ingest(&1, 1)))

      for {owner, ref} <- owners do
        assert_receive {:DOWN, ^ref, :process, ^owner, _reason}, 3_000
      end

      # Room for the pool to restart them (before the fix it did, and gave up at the fourth).
      Process.sleep(300)
    end)

    assert_untouched(ctx)
  end

  test "a non-trip crash is still restarted by the pool and counted as before", ctx do
    alpha = key("alpha")
    assert {:ok, _} = Runtime.partition_snapshot(@namespace, @mission, alpha)
    {:ok, owner} = PartitionOwner.lookup(@namespace, @mission, alpha)

    capture_log(fn ->
      Process.exit(owner, :boom)

      # Restarted by its supervisor, with no request asking for it.
      await(fn ->
        match?({:ok, pid} when pid != owner, PartitionOwner.lookup(@namespace, @mission, alpha))
      end)

      # Counted: three more crashes inside 5 s exhaust the pool's intensity, as they always have.
      for _ <- 1..3 do
        {:ok, pid} = PartitionOwner.lookup(@namespace, @mission, alpha)
        ref = Process.monitor(pid)
        Process.exit(pid, :boom)
        assert_receive {:DOWN, ^ref, :process, ^pid, :boom}, 1_000
        await(fn -> GenServer.whereis(pool_name()) != ctx.pool or restarted?(alpha, pid) end)
      end

      await(fn -> GenServer.whereis(pool_name()) not in [nil, ctx.pool] end)
    end)

    refute Process.alive?(ctx.pool)
  end

  defp assert_untouched(ctx) do
    assert GenServer.whereis(pool_name()) == ctx.pool
    assert Process.alive?(ctx.pool)
    assert Process.alive?(ctx.beta_owner)
    assert PartitionOwner.lookup(@namespace, @mission, ctx.beta) == {:ok, ctx.beta_owner}
  end

  defp restarted?(key, old) do
    match?({:ok, pid} when pid != old, PartitionOwner.lookup(@namespace, @mission, key))
  end

  defp pool_name, do: MissionRuntime.partition_supervisor_name(@namespace, @mission)

  defp ask(key) do
    reply = Runtime.partition_snapshot(@namespace, @mission, key)
    Process.sleep(20)
    reply
  end

  defp ingest(%PartitionKey{value: endpoint}, sequence) do
    Runtime.process_telemetry_ingress(
      @namespace,
      RawEvidence.new(%{
        mission_id: @mission,
        source_ref: "provider/" <> endpoint,
        source_endpoint_ref: endpoint,
        raw: space_packet(@apid, sequence, <<0, 7>>)
      })
    )
  end

  defp count_recoveries(%PartitionKey{} = key) do
    counter = :counters.new(1, [])
    id = PartitionKey.identifier(key)
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :runtime, :partition, :recovery, :start],
        fn _event, _measurements, metadata, _config ->
          if metadata.mission_id == @mission and metadata.partition_id == id,
            do: :counters.add(counter, 1, 1)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    counter
  end

  defp key(endpoint), do: PartitionKey.new(%{affinity: :source_endpoint, value: endpoint})

  defp runtime_spec(periodic_ms) do
    binding =
      BindingSet.new(%{
        mission_id: @mission,
        binding_set_id: "trip-basis",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: "trip-packet-counter",
            family_key: :packet_counter,
            runtime_configuration: %{"metric_name" => "trip", "flush_interval_ms" => 25}
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: "trip-packet-counter-rule",
            capability_instance_id: "trip-packet-counter",
            selector: %{match: %{packet_kind: :space_packet, apid: @apid}},
            priority: 10,
            fanout_mode: :multi
          })
        ]
      })

    {:ok, compilation} = MissionModelFixtures.compile_empty_model(@mission)

    {:ok, spec} =
      MissionRuntimeSpec.new(%{
        activation_id: "trip-initial",
        mission_id: @mission,
        generation: 1,
        binding_set_id: binding.binding_set_id,
        binding_set_version: binding.version,
        binding_set: binding,
        mission_model_revision_id: compilation.revision.revision_id,
        mission_model_content_sha256: compilation.revision.content_sha256,
        runtime_plans: with_periodic_algorithm(compilation.plans, periodic_ms),
        activated_at: DateTime.utc_now()
      })

    spec
  end

  defp with_periodic_algorithm(plans, nil), do: plans

  defp with_periodic_algorithm(plans, interval_ms) do
    Map.update!(plans, :algorithm, fn plan ->
      %{
        plan
        | plan: %{
            "algorithms" => [
              %{
                algorithm_id: "algorithm:trip-heartbeat",
                input_parameter_ids: [],
                triggers: [%{kind: :periodic, interval_ms: interval_ms}],
                outputs: [
                  %{
                    parameter_id: "parameter:trip-heartbeat",
                    qualified_name: "/parameters/trip-heartbeat",
                    expression: Expression.new(%{node: {:literal, 1}, result_type: :number})
                  }
                ]
              }
            ]
          }
      }
    end)
  end

  defp space_packet(apid, sequence_count, data) do
    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, byte_size(data) - 1::16,
      data::binary>>
  end

  defp await(fun, attempts \\ 100) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition not reached")
      true -> Process.sleep(20) && await(fun, attempts - 1)
    end
  end
end
