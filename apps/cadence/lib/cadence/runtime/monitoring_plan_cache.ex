defmodule Cadence.Runtime.MonitoringPlanCache do
  @moduledoc """
  Node-wide cache of the mission model's decoded monitoring and algorithm plans, one ETS entry per
  `{plan, :monitoring, parameter_id}`, `{plan, :algorithms_for, parameter_id}` and
  `{plan, :algorithm, algorithm_id}` (#451 T1), the counterpart of `PacketDefinitionCache` for the
  semantic side.

  Before, every partition decoded the whole plan for every batch (`PlanDecoder.decode/1` maps
  `MonitoringPlan.new/1` over each policy) and the runtime then scanned every monitoring plan and
  every algorithm for each update: O(catalog) per batch and per update, in every partition. A
  catalog of 5,000 parameters is 0.5 to 1 MB of plans. Now a plan is decoded once per node, and a
  partition holds only an index over the table (`SemanticRuntime.PlanIndex`): a per-update lookup
  is one ETS read that copies the plans of that parameter.

  **Same protocol as `PacketDefinitionCache`.** A partition `acquire/2`s its activation's plans when
  it starts or reconciles (releasing what it held before); the owner deletes a plan's entries when
  its last holder releases it or exits, so a retired revision's entries go by key without a sweep.
  A plan already loaded costs a small call; the plans (up to ~1 MB) are only sent to the owner when
  the plan is not loaded yet.

  **The key** is the pair of content-addressed plan ids (`RuntimePlan.plan_id` of the monitoring
  and the algorithm plan), plus a hash of the registered-implementation registry the plans were
  bound against (an algorithm's `implementation` carries the registry's authorization), so the same
  compiled plan on two revisions is one set of entries, and a registry change is a different key. A
  plan with no id (not content-addressed) is not cached: the caller gets an index over its own
  decode, as before. The registry is read when a plan is acquired, not per batch: a registry
  change takes effect at the next activation or reconcile, not mid-activation.
  """

  use GenServer

  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.SemanticRuntime.{PlanDecoder, PlanIndex, RegisteredRegistry}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @doc """
  Starts a cache. With a `:process_namespace` it is that namespace's cache (registered; what the
  runtime's partition owners find by default). Without one it is unregistered, for a host that owns
  its own tree and passes the pid to its partition owners (an isolated replay session).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :process_namespace) do
      {:ok, namespace} -> GenServer.start_link(__MODULE__, :ok, name: name(namespace))
      :error -> GenServer.start_link(__MODULE__, :ok)
    end
  end

  @spec name(ProcessNamespace.t()) :: GenServer.name()
  def name(%ProcessNamespace{} = namespace), do: ProcessNamespace.via(namespace, __MODULE__)

  @doc """
  Holds the plans' decoded entries for the calling process (releasing what it held before) and
  returns the index to run them with. Plans with no monitoring and no algorithms are an empty
  index; plans that cannot be keyed are decoded into an index of their own.
  """
  @spec acquire(GenServer.server(), map()) :: {:ok, PlanIndex.t()}
  def acquire(server, runtime_plans) when is_map(runtime_plans) do
    registry = RegisteredRegistry.configured()

    case running?(server) && plan_key(runtime_plans, registry) do
      # No cache process (a host that does not start one): an index over its own decode.
      false ->
        {:ok, runtime_plans |> PlanDecoder.decode(registry) |> PlanIndex.from_plan()}

      :empty ->
        GenServer.call(server, {:release, self()}, :infinity)
        {:ok, PlanIndex.from_plan(%{})}

      :unkeyed ->
        GenServer.call(server, {:release, self()}, :infinity)
        {:ok, runtime_plans |> PlanDecoder.decode(registry) |> PlanIndex.from_plan()}

      key ->
        {:ok, table, empty?} =
          case GenServer.call(server, {:hold, self(), key}, :infinity) do
            {:ok, table, empty?} -> {:ok, table, empty?}
            :miss -> load(server, key, runtime_plans, registry)
          end

        {:ok, PlanIndex.from_cache(table, key, empty?)}
    end
  end

  # The load runs in the cache's process; a plan it cannot decode fails the caller (a partition
  # that cannot run it), and the cache keeps serving the rest.
  defp load(server, key, runtime_plans, registry) do
    case GenServer.call(server, {:load, self(), key, runtime_plans, registry}, :infinity) do
      {:ok, table, empty?} ->
        {:ok, table, empty?}

      {:error, reason} ->
        raise ArgumentError, "the monitoring plan cannot be decoded: #{reason}"
    end
  end

  # A named cache that is not started (a host without one, a `--no-start` test), or a `:via` name
  # whose registry is not running either.
  defp running?(server) do
    GenServer.whereis(server) != nil
  rescue
    ArgumentError -> false
  end

  @doc "How many plans the cache holds right now (a diagnostic, and for tests)."
  @spec loaded(GenServer.server()) :: non_neg_integer()
  def loaded(server), do: GenServer.call(server, :loaded)

  @doc "The table, for a test that reads entries directly."
  @spec table(GenServer.server()) :: :ets.table()
  def table(server), do: GenServer.call(server, :table)

  @impl true
  def init(:ok) do
    table = :ets.new(__MODULE__, [:set, :protected, read_concurrency: true])
    {:ok, %{table: table, holders: %{}, plans: %{}}}
  end

  @impl true
  def handle_call({:hold, pid, key}, _from, state) do
    case state.plans do
      %{^key => %{empty?: empty?}} -> {:reply, {:ok, state.table, empty?}, hold(state, pid, key)}
      _unloaded -> {:reply, :miss, state}
    end
  end

  def handle_call({:load, pid, key, runtime_plans, registry}, _from, state) do
    # Another caller may have loaded the plan while this one was sending it.
    case state.plans do
      %{^key => %{empty?: empty?}} ->
        {:reply, {:ok, state.table, empty?}, hold(state, pid, key)}

      _unloaded ->
        # A plan that cannot be decoded (a value outside the plan vocabulary) is the asking
        # partition's failure, never the owner's: raising here would drop every plan the node holds.
        case decode(runtime_plans, registry) do
          {:ok, decoded} ->
            entries = PlanIndex.entries(key, decoded.algorithms, decoded.monitoring)
            Enum.each(entries, &:ets.insert(state.table, &1))
            empty? = decoded.algorithms == [] and decoded.monitoring == []
            keys = Enum.map(entries, &elem(&1, 0))
            plans = Map.put(state.plans, key, %{holders: 0, keys: keys, empty?: empty?})
            state = %{state | plans: plans}
            {:reply, {:ok, state.table, empty?}, hold(state, pid, key)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:release, pid}, _from, state), do: {:reply, :ok, release(state, pid)}
  def handle_call(:loaded, _from, state), do: {:reply, map_size(state.plans), state}
  def handle_call(:table, _from, state), do: {:reply, state.table, state}

  defp decode(runtime_plans, registry) do
    {:ok, PlanDecoder.decode(runtime_plans, registry)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, release(state, pid)}

  # Holds the loaded plan for `pid`, releasing what it held before. Holding the same plan again is
  # a no-op.
  defp hold(state, pid, key) do
    case state.holders do
      %{^pid => {_ref, ^key}} ->
        state

      _other ->
        state = release(state, pid)
        plan = Map.fetch!(state.plans, key)
        holders = Map.put(state.holders, pid, {Process.monitor(pid), key})

        %{
          state
          | holders: holders,
            plans: Map.put(state.plans, key, %{plan | holders: plan.holders + 1})
        }
    end
  end

  defp release(state, pid) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        state

      {{ref, key}, holders} ->
        Process.demonitor(ref, [:flush])
        release_plan(%{state | holders: holders}, key)
    end
  end

  defp release_plan(state, key) do
    case Map.fetch!(state.plans, key) do
      %{holders: 1, keys: keys} ->
        Enum.each(keys, &:ets.delete(state.table, &1))
        %{state | plans: Map.delete(state.plans, key)}

      %{holders: count} = plan ->
        %{state | plans: Map.put(state.plans, key, %{plan | holders: count - 1})}
    end
  end

  # The pair of content-addressed plan ids and the registry's hash; `:empty` when there is nothing
  # to run, `:unkeyed` when a present plan has no id.
  defp plan_key(runtime_plans, registry) do
    monitoring = Map.get(runtime_plans, :monitoring)
    algorithm = Map.get(runtime_plans, :algorithm)

    cond do
      is_nil(monitoring) and is_nil(algorithm) -> :empty
      not keyed?(monitoring) or not keyed?(algorithm) -> :unkeyed
      true -> {plan_id(monitoring), plan_id(algorithm), :erlang.phash2(registry)}
    end
  end

  defp keyed?(nil), do: true
  defp keyed?(%{plan_id: id}), do: is_binary(id)
  defp plan_id(nil), do: nil
  defp plan_id(%{plan_id: id}), do: id
end
