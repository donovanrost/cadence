defmodule Cadence.Runtime.MissionCoordinator do
  @moduledoc """
  Mission-scoped runtime coordinator for active basis resolution and partition
  ownership.
  """

  use GenServer

  alias Cadence.Activations
  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Governance
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.PartitionOwner
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @type state :: %{
          mission_id: binary(),
          active_activation: BindingSetActivation.t() | nil,
          binding_set: BindingSet.t() | nil,
          partitions: MapSet.t(PartitionKey.t())
        }

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, opts, name: MissionRuntime.coordinator_name(mission_id))
  end

  @spec refresh_active_basis(binary()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def refresh_active_basis(mission_id) when is_binary(mission_id) do
    GenServer.call(MissionRuntime.coordinator_name(mission_id), :refresh_active_basis)
  end

  @spec binding_set_for_partition(binary(), PartitionKey.t()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def binding_set_for_partition(mission_id, %PartitionKey{} = partition_key)
      when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.coordinator_name(mission_id),
      {:binding_set_for_partition, partition_key}
    )
  end

  @spec partition_snapshot(binary(), PartitionKey.t()) :: {:ok, map()} | {:error, term()}
  def partition_snapshot(mission_id, %PartitionKey{} = partition_key)
      when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.coordinator_name(mission_id),
      {:partition_snapshot, partition_key}
    )
  end

  @spec active_activation(binary()) :: {:ok, BindingSetActivation.t()} | {:error, term()}
  def active_activation(mission_id) when is_binary(mission_id) do
    GenServer.call(MissionRuntime.coordinator_name(mission_id), :active_activation)
  end

  @spec process_telemetry_ingress(binary(), RawEvidence.t()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def process_telemetry_ingress(mission_id, %RawEvidence{} = raw_evidence)
      when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.coordinator_name(mission_id),
      {:process_telemetry_ingress, raw_evidence}
    )
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)

    {:ok,
     %{
       mission_id: mission_id,
       active_activation: nil,
       binding_set: nil,
       partitions: MapSet.new()
     }}
  end

  @impl true
  def handle_call(:refresh_active_basis, _from, state) do
    new_state = refresh_state(state)

    reply =
      case new_state.active_activation do
        %BindingSetActivation{} = activation -> {:ok, activation}
        nil -> {:error, :no_active_binding_set}
      end

    {:reply, reply, new_state}
  end

  def handle_call(:active_activation, _from, state) do
    reply =
      case state.active_activation do
        %BindingSetActivation{} = activation -> {:ok, activation}
        nil -> {:error, :no_active_binding_set}
      end

    {:reply, reply, state}
  end

  def handle_call({:binding_set_for_partition, %PartitionKey{} = partition_key}, _from, state) do
    with {:ok, state} <- ensure_active_state(state),
         {:ok, partition_pid, state} <- ensure_partition_owner(state, partition_key),
         {:ok, runtime_binding_set} <- PartitionOwner.binding_set(partition_pid) do
      {:reply, {:ok, runtime_binding_set}, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:partition_snapshot, %PartitionKey{} = partition_key}, _from, state) do
    with {:ok, state} <- ensure_active_state(state),
         {:ok, partition_pid, state} <- ensure_partition_owner(state, partition_key),
         {:ok, snapshot} <- PartitionOwner.snapshot(partition_pid) do
      {:reply, {:ok, snapshot}, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:process_telemetry_ingress, %RawEvidence{} = raw_evidence}, _from, state) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      TelemetryProfiler.with_stage(:runtime, fn ->
        partition_key = PartitionKey.from_raw_evidence(raw_evidence)

        with {:ok, state} <- ensure_active_state(state),
             {:ok, partition_pid, state} <- ensure_partition_owner(state, partition_key) do
          {:reply, PartitionOwner.process_raw_evidence(partition_pid, raw_evidence), state}
        else
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end)
    end)
  end

  defp ensure_active_state(
         %{active_activation: %BindingSetActivation{}, binding_set: %BindingSet{}} = state
       ),
       do: {:ok, state}

  defp ensure_active_state(state) do
    refreshed_state = refresh_state(state)

    case refreshed_state.active_activation do
      %BindingSetActivation{} -> {:ok, refreshed_state}
      nil -> {:error, :no_active_binding_set}
    end
  end

  defp refresh_state(state) do
    case fetch_active_basis(state.mission_id) do
      {:ok, activation, binding_set} ->
        state
        |> Map.put(:active_activation, activation)
        |> Map.put(:binding_set, binding_set)
        |> reconcile_partitions()

      {:error, :no_active_binding_set} ->
        %{state | active_activation: nil, binding_set: nil}

      {:error, _reason} ->
        %{state | active_activation: nil, binding_set: nil}
    end
  end

  defp fetch_active_basis(mission_id) do
    with {:ok, %BindingSetActivation{} = activation} <-
           Activations.fetch_active_activation(mission_id),
         {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(
             mission_id,
             activation.binding_set_id,
             activation.binding_set_version
           ) do
      {:ok, activation, binding_set}
    end
  end

  defp ensure_partition_owner(
         %{
           active_activation: %BindingSetActivation{} = activation,
           binding_set: %BindingSet{} = binding_set
         } =
           state,
         %PartitionKey{} = partition_key
       ) do
    case start_partition_owner(state.mission_id, partition_key, activation, binding_set) do
      {:ok, partition_pid} ->
        {:ok, partition_pid, %{state | partitions: MapSet.put(state.partitions, partition_key)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_partition_owner(_state, %PartitionKey{}), do: {:error, :no_active_binding_set}

  defp start_partition_owner(mission_id, %PartitionKey{} = partition_key, activation, binding_set) do
    child_spec =
      {PartitionOwner,
       mission_id: mission_id,
       partition_key: partition_key,
       active_activation: activation,
       binding_set: binding_set}

    case DynamicSupervisor.start_child(
           MissionRuntime.partition_supervisor_name(mission_id),
           child_spec
         ) do
      {:ok, partition_pid} ->
        {:ok, partition_pid}

      {:error, {:already_started, partition_pid}} ->
        {:ok, partition_pid}

      {:error, {:already_present, _child_spec}} ->
        PartitionOwner.lookup(mission_id, partition_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reconcile_partitions(
         %{
           active_activation: %BindingSetActivation{} = activation,
           binding_set: %BindingSet{} = binding_set
         } =
           state
       ) do
    Enum.each(state.partitions, fn %PartitionKey{} = partition_key ->
      case PartitionOwner.lookup(state.mission_id, partition_key) do
        {:ok, partition_pid} ->
          :ok = PartitionOwner.reconcile(partition_pid, activation, binding_set)

        {:error, :partition_not_running} ->
          :ok
      end
    end)

    state
  end

  defp reconcile_partitions(state), do: state
end
