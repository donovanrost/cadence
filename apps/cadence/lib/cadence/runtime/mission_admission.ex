defmodule Cadence.Runtime.MissionAdmission do
  @moduledoc """
  Mission-local admitted generation, independent of the coordinator's lifetime.

  A staged generation is visible to restarting partition owners but is not an
  application acknowledgement. The desired generation and required partitions
  survive coordinator restart so rollout can resume without retiring healthy
  execution. Losing this process retires its dependent execution tree.
  """

  use GenServer

  alias Cadence.Runtime.{MissionRuntime, MissionRuntimeSpec}

  def start_link(opts) do
    name =
      MissionRuntime.admission_name(
        Keyword.fetch!(opts, :process_namespace),
        Keyword.fetch!(opts, :mission_id)
      )

    GenServer.start_link(__MODULE__, [], name: name)
  end

  def recover(server), do: GenServer.call(server, :recover)

  def stage(server, spec, applied_at, partitions),
    do: GenServer.call(server, {:stage, spec, applied_at, partitions})

  def track(server, key), do: GenServer.call(server, {:track, key})

  def fence(server, key, identity), do: GenServer.call(server, {:fence, key, identity}, :infinity)

  def commit(server, identity), do: GenServer.call(server, {:commit, identity})

  @impl true
  def init([]), do: {:ok, empty()}

  @impl true
  def handle_call(:recover, _from, state), do: {:reply, state, state}

  def handle_call({:stage, %MissionRuntimeSpec{} = spec, applied_at, partitions}, _from, state) do
    pending = %{
      spec: MissionRuntimeSpec.compact(spec),
      applied_at: applied_at,
      partitions: partitions
    }

    {:reply, :ok, %{state | pending: pending}}
  end

  def handle_call(
        {:commit, identity},
        _from,
        %{pending: %{spec: spec, applied_at: applied_at}} = state
      ) do
    if MissionRuntimeSpec.identity(spec) == identity do
      {:reply, :ok, %{state | spec: spec, applied_at: applied_at, pending: nil}}
    else
      {:reply, {:error, :generation_identity_mismatch}, state}
    end
  end

  def handle_call({:commit, _identity}, _from, state),
    do: {:reply, {:error, :no_pending_generation}, state}

  def handle_call({:track, key}, _from, state) do
    {:reply, :ok, %{state | partitions: MapSet.put(state.partitions, key)}}
  end

  def handle_call({:fence, key, identity}, _from, state) do
    {:reply, :ok, %{state | fenced: Map.put(state.fenced, key, identity)}}
  end

  def handle_call({:partition_spec, key}, _from, state) do
    spec = if state.pending, do: state.pending.spec, else: state.spec

    reply =
      cond do
        is_nil(spec) ->
          {:error, :no_active_binding_set}

        Map.get(state.fenced, key) == MissionRuntimeSpec.identity(spec) ->
          {:error, {:partition_fenced, spec.generation}}

        true ->
          MissionRuntimeSpec.partition_input(spec, key)
      end

    {:reply, reply, state}
  end

  defp empty,
    do: %{spec: nil, applied_at: nil, pending: nil, fenced: %{}, partitions: MapSet.new()}
end
