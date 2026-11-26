defmodule Cadence.Runtime.PacketDefinitionCache do
  @moduledoc """
  Node-wide cache of the mission model's decoded telemetry packet definitions, one ETS entry per
  `{plan_id, packet_definition_id}`.

  A telemetry plan is content-addressed by revision and shared by most of a mission's partitions
  (a catalog can be ~1 MB per revision), so it is decoded once per revision per node, not once per
  partition and not once per packet. A partition `acquire/3`s its plan's revision when it starts or
  reconciles and reads entries straight from the table; the owner deletes a revision's entries when
  the last partition holding it releases it or exits.
  """

  use GenServer

  alias Cadence.Runtime.{MissionModelPlanDecoder, ProcessNamespace}

  @type table :: :ets.table()

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)
    GenServer.start_link(__MODULE__, :ok, name: name(namespace))
  end

  @spec name(ProcessNamespace.t()) :: GenServer.name()
  def name(%ProcessNamespace{} = namespace), do: ProcessNamespace.via(namespace, __MODULE__)

  @doc """
  Holds `plan_id`'s decoded packet definitions for the calling process and releases whatever
  revision it held before. A revision already in the cache costs a small call; `plans` (about 1 MB
  for a real catalog) is only sent to the owner when the revision is not loaded yet.

  The cache is keyed by `plan_id` alone, which is correct only because a plan id is
  content-addressed (`RuntimePlan.new/5` hashes the revision, target, contract and plan content):
  the same id always means the same definitions. A plan without an id is never cached.
  """
  @spec acquire(ProcessNamespace.t(), binary() | nil, map()) ::
          {:ok, table()} | {:error, term()}
  def acquire(%ProcessNamespace{} = namespace, plan_id, plans) when is_binary(plan_id) do
    server = name(namespace)

    case GenServer.call(server, {:hold, self(), plan_id}, :infinity) do
      {:ok, table} -> {:ok, table}
      :miss -> GenServer.call(server, {:load, self(), plan_id, plans}, :infinity)
    end
  end

  def acquire(%ProcessNamespace{} = namespace, _plan_id, plans),
    do: GenServer.call(name(namespace), {:release_without_id, self(), plans}, :infinity)

  @doc "One ETS read of a decoded packet definition."
  @spec fetch(table(), binary(), binary()) :: {:ok, term()} | :error
  def fetch(table, plan_id, packet_definition_id) do
    case :ets.lookup(table, {plan_id, packet_definition_id}) do
      [{_key, definition}] -> {:ok, definition}
      [] -> :error
    end
  end

  @impl true
  def init(:ok) do
    table = :ets.new(__MODULE__, [:set, :protected, read_concurrency: true])
    {:ok, %{table: table, holders: %{}, revisions: %{}}}
  end

  @impl true
  def handle_call({:hold, pid, plan_id}, _from, state) do
    case state.revisions do
      %{^plan_id => _loaded} -> {:reply, {:ok, state.table}, hold(state, pid, plan_id)}
      _unloaded -> {:reply, :miss, state}
    end
  end

  def handle_call({:load, pid, plan_id, plans}, _from, state) do
    # Another caller may have loaded the revision while this one was sending its plans.
    case state.revisions do
      %{^plan_id => _loaded} ->
        {:reply, {:ok, state.table}, hold(state, pid, plan_id)}

      _unloaded ->
        case MissionModelPlanDecoder.telemetry_packet_definitions(plans) do
          {:ok, definitions} ->
            ids = insert(state.table, plan_id, definitions)

            state = %{
              state
              | revisions: Map.put(state.revisions, plan_id, %{holders: 0, ids: ids})
            }

            {:reply, {:ok, state.table}, hold(state, pid, plan_id)}

          {:error, reason} ->
            {:reply, {:error, reason}, release(state, pid)}
        end
    end
  end

  def handle_call({:release_without_id, pid, plans}, _from, state) do
    reason =
      case MissionModelPlanDecoder.telemetry_packet_definitions(plans) do
        {:error, reason} -> reason
        {:ok, _definitions} -> :telemetry_plan_without_id
      end

    {:reply, {:error, reason}, release(state, pid)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, release(state, pid)}

  # Holds the loaded revision for `pid`, releasing what it held before. Holding the same
  # revision again is a no-op.
  defp hold(state, pid, plan_id) do
    case state.holders do
      %{^pid => {_ref, ^plan_id}} ->
        state

      _other ->
        state = release(state, pid)
        revision = Map.fetch!(state.revisions, plan_id)
        holders = Map.put(state.holders, pid, {Process.monitor(pid), plan_id})

        %{
          state
          | holders: holders,
            revisions:
              Map.put(state.revisions, plan_id, %{revision | holders: revision.holders + 1})
        }
    end
  end

  defp insert(table, plan_id, definitions) do
    # The first definition wins when an id repeats.
    definitions
    |> Enum.uniq_by(& &1.packet_definition_id)
    |> Enum.map(fn definition ->
      :ets.insert(table, {{plan_id, definition.packet_definition_id}, definition})
      definition.packet_definition_id
    end)
  end

  defp release(state, pid) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        state

      {{ref, plan_id}, holders} ->
        Process.demonitor(ref, [:flush])
        release_revision(%{state | holders: holders}, plan_id)
    end
  end

  defp release_revision(state, plan_id) do
    case Map.fetch!(state.revisions, plan_id) do
      %{holders: 1, ids: ids} ->
        Enum.each(ids, &:ets.delete(state.table, {plan_id, &1}))
        %{state | revisions: Map.delete(state.revisions, plan_id)}

      %{holders: count} = revision ->
        %{state | revisions: Map.put(state.revisions, plan_id, %{revision | holders: count - 1})}
    end
  end
end
