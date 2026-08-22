# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Runtime.MissionCoordinator do
  @moduledoc """
  Mission-scoped runtime coordinator for exact generation application and
  partition ownership.
  """

  use GenServer

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.PartitionOwner
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @type state :: %{
          process_namespace: ProcessNamespace.t(),
          mission_id: binary(),
          profiler: TelemetryProfiler.dependency(),
          runtime_spec: MissionRuntimeSpec.t() | nil,
          applied_at: DateTime.t() | nil,
          partitions: MapSet.t(PartitionKey.t())
        }

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    process_namespace = process_namespace(opts)

    GenServer.start_link(__MODULE__, opts,
      name: MissionRuntime.coordinator_name(process_namespace, mission_id)
    )
  end

  @spec apply_spec(MissionRuntimeSpec.t()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def apply_spec(%MissionRuntimeSpec{} = spec) do
    apply_spec(ProcessNamespace.default(), spec)
  end

  @spec apply_spec(ProcessNamespace.t(), MissionRuntimeSpec.t()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def apply_spec(%ProcessNamespace{} = process_namespace, %MissionRuntimeSpec{} = spec) do
    GenServer.call(
      MissionRuntime.coordinator_name(process_namespace, spec.mission_id),
      {:apply_spec, spec}
    )
  end

  @spec binding_set_for_partition(binary(), PartitionKey.t()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def binding_set_for_partition(mission_id, %PartitionKey{} = partition_key)
      when is_binary(mission_id) do
    binding_set_for_partition(ProcessNamespace.default(), mission_id, partition_key)
  end

  @spec binding_set_for_partition(ProcessNamespace.t(), binary(), PartitionKey.t()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def binding_set_for_partition(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        %PartitionKey{} = partition_key
      )
      when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.coordinator_name(process_namespace, mission_id),
      {:binding_set_for_partition, partition_key}
    )
  end

  @spec partition_snapshot(binary(), PartitionKey.t()) :: {:ok, map()} | {:error, term()}
  def partition_snapshot(mission_id, %PartitionKey{} = partition_key)
      when is_binary(mission_id) do
    partition_snapshot(ProcessNamespace.default(), mission_id, partition_key)
  end

  @spec partition_snapshot(ProcessNamespace.t(), binary(), PartitionKey.t()) ::
          {:ok, map()} | {:error, term()}
  def partition_snapshot(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        %PartitionKey{} = partition_key
      )
      when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.coordinator_name(process_namespace, mission_id),
      {:partition_snapshot, partition_key}
    )
  end

  @spec active_spec(binary()) :: {:ok, MissionRuntimeSpec.t()} | {:error, term()}
  def active_spec(mission_id) when is_binary(mission_id),
    do: active_spec(ProcessNamespace.default(), mission_id)

  @spec active_spec(ProcessNamespace.t(), binary()) ::
          {:ok, MissionRuntimeSpec.t()} | {:error, term()}
  def active_spec(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    GenServer.call(MissionRuntime.coordinator_name(process_namespace, mission_id), :active_spec)
  end

  @doc false
  def active_activation(mission_id), do: active_spec(mission_id)

  @doc false
  def active_activation(%ProcessNamespace{} = process_namespace, mission_id),
    do: active_spec(process_namespace, mission_id)

  @spec process_telemetry_ingress(binary(), RawEvidence.t()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def process_telemetry_ingress(mission_id, %RawEvidence{} = raw_evidence)
      when is_binary(mission_id) do
    process_telemetry_ingress(ProcessNamespace.default(), mission_id, raw_evidence)
  end

  @spec process_telemetry_ingress(ProcessNamespace.t(), binary(), RawEvidence.t()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def process_telemetry_ingress(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        %RawEvidence{} = raw_evidence
      )
      when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.coordinator_name(process_namespace, mission_id),
      {:process_telemetry_ingress, raw_evidence}
    )
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)

    {:ok,
     %{
       process_namespace: process_namespace(opts),
       mission_id: mission_id,
       profiler: Keyword.get(opts, :profiler, TelemetryProfiler),
       runtime_spec: nil,
       applied_at: nil,
       partitions: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:apply_spec, %MissionRuntimeSpec{} = spec}, _from, state) do
    case apply_runtime_spec(state, spec) do
      {:ok, observation, new_state} -> {:reply, {:ok, observation}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:active_spec, _from, state) do
    reply =
      case state.runtime_spec do
        %MissionRuntimeSpec{} = spec -> {:ok, spec}
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
    TelemetryProfiler.with_ingress_context(state.profiler, raw_evidence, fn ->
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

  defp ensure_active_state(%{runtime_spec: %MissionRuntimeSpec{}} = state),
    do: {:ok, state}

  defp ensure_active_state(_state), do: {:error, :no_active_binding_set}

  defp ensure_partition_owner(
         %{
           runtime_spec:
             %MissionRuntimeSpec{binding_set: %BindingSet{} = binding_set} = runtime_spec
         } =
           state,
         %PartitionKey{} = partition_key
       ) do
    case start_partition_owner(
           state.process_namespace,
           state.mission_id,
           partition_key,
           runtime_spec,
           binding_set,
           state.profiler
         ) do
      {:ok, partition_pid} ->
        {:ok, partition_pid, %{state | partitions: MapSet.put(state.partitions, partition_key)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_partition_owner(
         process_namespace,
         mission_id,
         %PartitionKey{} = partition_key,
         runtime_spec,
         binding_set,
         profiler
       ) do
    child_spec =
      {PartitionOwner,
       mission_id: mission_id,
       process_namespace: process_namespace,
       partition_key: partition_key,
       active_activation: runtime_spec,
       binding_set: binding_set,
       profiler: profiler}

    case DynamicSupervisor.start_child(
           MissionRuntime.partition_supervisor_name(process_namespace, mission_id),
           child_spec
         ) do
      {:ok, partition_pid} ->
        {:ok, partition_pid}

      {:error, {:already_started, partition_pid}} ->
        {:ok, partition_pid}

      {:error, {:already_present, _child_spec}} ->
        PartitionOwner.lookup(process_namespace, mission_id, partition_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reconcile_partitions(
         %{
           runtime_spec:
             %MissionRuntimeSpec{binding_set: %BindingSet{} = binding_set} = runtime_spec
         } =
           state
       ) do
    Enum.each(state.partitions, fn %PartitionKey{} = partition_key ->
      case PartitionOwner.lookup(state.process_namespace, state.mission_id, partition_key) do
        {:ok, partition_pid} ->
          :ok = PartitionOwner.reconcile(partition_pid, runtime_spec, binding_set)

        {:error, :partition_not_running} ->
          :ok
      end
    end)

    state
  end

  defp apply_runtime_spec(%{mission_id: mission_id}, %MissionRuntimeSpec{
         mission_id: spec_mission_id
       })
       when mission_id != spec_mission_id do
    {:error, {:mission_runtime_spec_mismatch, :mission_id}}
  end

  defp apply_runtime_spec(%{runtime_spec: nil} = state, %MissionRuntimeSpec{} = spec) do
    applied_at = DateTime.utc_now()
    new_state = %{state | runtime_spec: spec, applied_at: applied_at} |> reconcile_partitions()
    {:ok, GenerationApplied.new(spec, applied_at), new_state}
  end

  defp apply_runtime_spec(
         %{runtime_spec: %MissionRuntimeSpec{generation: current_generation}},
         %MissionRuntimeSpec{generation: generation}
       )
       when generation < current_generation do
    {:error, {:stale_generation, current_generation}}
  end

  defp apply_runtime_spec(
         %{
           runtime_spec: %MissionRuntimeSpec{generation: generation} = current_spec,
           applied_at: %DateTime{} = applied_at
         } = state,
         %MissionRuntimeSpec{generation: generation} = spec
       ) do
    if MissionRuntimeSpec.identity(current_spec) == MissionRuntimeSpec.identity(spec) do
      {:ok, GenerationApplied.new(current_spec, applied_at), state}
    else
      {:error, {:generation_conflict, generation}}
    end
  end

  defp apply_runtime_spec(state, %MissionRuntimeSpec{} = spec) do
    applied_at = DateTime.utc_now()
    new_state = %{state | runtime_spec: spec, applied_at: applied_at} |> reconcile_partitions()
    {:ok, GenerationApplied.new(spec, applied_at), new_state}
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end
end
