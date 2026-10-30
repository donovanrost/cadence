# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Runtime.MissionCoordinator do
  @moduledoc """
  Mission-scoped runtime coordinator for exact generation application and
  partition ownership.
  """

  use GenServer

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.Cluster
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionAdmission
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.PartitionOwner
  alias Cadence.Runtime.PartitionRouter
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @type state :: %{
          process_namespace: ProcessNamespace.t(),
          mission_id: binary(),
          profiler: TelemetryProfiler.dependency(),
          runtime_spec: MissionRuntimeSpec.t() | nil,
          applied_at: DateTime.t() | nil,
          partitions: MapSet.t(PartitionKey.t()),
          requests: term(),
          request_counts: map(),
          pending_application: map() | nil,
          max_partition_requests: pos_integer()
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
    coordinator = MissionRuntime.coordinator_name(process_namespace, spec.mission_id)

    # Safety reconciliation usually repeats the active generation. Check its
    # identity before copying a potentially large fleet model across processes.
    case GenServer.call(
           coordinator,
           {:applied_identity, MissionRuntimeSpec.identity(spec)},
           :infinity
         ) do
      {:ok, observation} ->
        {:ok, observation}

      {:error, _reason} = error ->
        case error do
          {:error, {:generation_incomplete, _, _}} ->
            GenServer.call(
              coordinator,
              {:apply_spec, MissionRuntimeSpec.compact(spec)},
              :infinity
            )

          {:error, {:generation_applying, _}} ->
            GenServer.call(
              coordinator,
              {:apply_spec, MissionRuntimeSpec.compact(spec)},
              :infinity
            )

          _ ->
            error
        end

      :apply_required ->
        GenServer.call(coordinator, {:apply_spec, MissionRuntimeSpec.compact(spec)}, :infinity)
    end
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
    partition_call(
      process_namespace,
      mission_id,
      partition_key,
      :binding_set,
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
    partition_call(
      process_namespace,
      mission_id,
      partition_key,
      :snapshot,
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
    partition_call(
      process_namespace,
      mission_id,
      PartitionKey.from_raw_evidence(raw_evidence),
      {:process_raw_evidence, raw_evidence},
      {:process_telemetry_ingress, raw_evidence}
    )
  end

  defp partition_call(namespace, mission, key, request, legacy_request) do
    coordinator = MissionRuntime.coordinator_name(namespace, mission)

    if Cluster.config(namespace) do
      PartitionRouter.call(coordinator, key, request)
    else
      GenServer.call(coordinator, legacy_request, :infinity)
    end
  end

  @impl true
  def code_change(_old_version, %{runtime_spec: %MissionRuntimeSpec{} = spec} = state, _extra) do
    {:ok,
     state
     |> Map.put(:runtime_spec, MissionRuntimeSpec.compact(spec))
     |> with_request_state()}
  end

  def code_change(_old_version, state, _extra), do: {:ok, with_request_state(state)}

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
       partitions: MapSet.new(),
       route_permits: %{},
       requests: :gen_server.reqids_new(),
       request_counts: %{},
       pending_application: nil,
       max_partition_requests: Keyword.get(opts, :max_partition_requests, 32)
     }, {:continue, :recover_admission}}
  end

  @impl true
  def handle_continue(:recover_admission, state) do
    recovered = MissionAdmission.recover(admission(state))
    partitions = MissionRuntime.partition_keys(state.process_namespace, state.mission_id)

    state = %{
      state
      | runtime_spec: recovered.spec,
        applied_at: recovered.applied_at,
        partitions: MapSet.union(MapSet.new(partitions), recovered.partitions)
    }

    case recovered.pending do
      nil ->
        {:noreply, state}

      pending ->
        state = %{state | partitions: MapSet.union(state.partitions, pending.partitions)}
        start_application(state, pending.spec, pending.applied_at, [])
    end
  end

  @impl true
  def handle_call({:applied_identity, identity}, from, %{pending_application: pending} = state)
      when not is_nil(pending), do: await_application(state, identity, from)

  def handle_call({:applied_identity, identity}, _from, state) do
    reply =
      case state.runtime_spec do
        %MissionRuntimeSpec{} = spec ->
          if MissionRuntimeSpec.identity(spec) == identity,
            do: {:ok, GenerationApplied.new(spec, state.applied_at)},
            else: :apply_required

        nil ->
          :apply_required
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:apply_spec, %MissionRuntimeSpec{} = spec},
        from,
        %{pending_application: %{remaining: 0} = pending} = state
      ) do
    case apply_runtime_spec(
           %{state | runtime_spec: pending.spec, applied_at: pending.applied_at},
           spec
         ) do
      {:ok, _, next} -> start_application(state, next.runtime_spec, next.applied_at, [from])
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:apply_spec, %MissionRuntimeSpec{} = spec},
        from,
        %{pending_application: pending} = state
      )
      when not is_nil(pending) do
    await_application(state, MissionRuntimeSpec.identity(spec), from)
  end

  def handle_call({:apply_spec, %MissionRuntimeSpec{} = spec}, from, state) do
    case apply_runtime_spec(state, spec) do
      {:ok, observation, new_state} -> begin_application(state, new_state, observation, from)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:active_spec, _from, state) do
    reply =
      case state.runtime_spec do
        %MissionRuntimeSpec{} = spec -> {:ok, MissionRuntimeSpec.expand(spec)}
        nil -> {:error, :no_active_binding_set}
      end

    {:reply, reply, state}
  end

  def handle_call(:applied_summary, _from, state) do
    reply =
      case state.runtime_spec do
        %MissionRuntimeSpec{} = spec -> {:ok, MissionRuntimeSpec.summary(spec)}
        nil -> {:error, :no_active_binding_set}
      end

    {:reply, reply, state}
  end

  def handle_call(:rollout_status, _from, state) do
    status =
      case state.pending_application do
        nil ->
          %{
            status: :applied,
            generation: state.runtime_spec && state.runtime_spec.generation,
            failed: %{}
          }

        pending ->
          %{
            status: if(pending.remaining > 0, do: :applying, else: :incomplete),
            generation: pending.spec.generation,
            remaining: pending.remaining,
            ready: pending.ready,
            failed: pending.failed
          }
      end

    {:reply, status, state}
  end

  # This is an already admitted immutable generation, never a lookup of mutable
  # governed configuration. A restarted child must not retain its birth generation.
  def handle_call({:partition_spec, %PartitionKey{} = key}, _from, state) do
    spec =
      if state.pending_application, do: state.pending_application.spec, else: state.runtime_spec

    reply =
      if spec,
        do: MissionRuntimeSpec.partition_input(spec, key),
        else: {:error, :no_active_binding_set}

    {:reply, reply, state}
  end

  def handle_call({:partition_route, %PartitionKey{} = key}, {caller, _tag}, state) do
    with :ok <- admit_partition_request(state, key),
         {:ok, pid, state} <- ensure_partition_owner(state, key) do
      permit = Process.monitor(caller)
      counts = Map.update(state.request_counts, key, 1, &(&1 + 1))
      permits = Map.put(state.route_permits, permit, key)
      {:reply, {:ok, pid, permit}, %{state | route_permits: permits, request_counts: counts}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:binding_set_for_partition, %PartitionKey{} = key}, from, state) do
    request_partition(state, key, :binding_set, from)
  end

  def handle_call({:partition_snapshot, %PartitionKey{} = key}, from, state) do
    request_partition(state, key, :snapshot, from)
  end

  def handle_call({:process_telemetry_ingress, %RawEvidence{} = evidence}, from, state) do
    request_partition(
      state,
      PartitionKey.from_raw_evidence(evidence),
      {:process_raw_evidence, evidence},
      from
    )
  end

  @impl true
  def handle_cast({:release_partition_route, permit}, state) do
    {:noreply, release_route(state, permit)}
  end

  @impl true
  def handle_info({:DOWN, permit, :process, _pid, _reason}, %{route_permits: permits} = state)
      when is_map_key(permits, permit) do
    {:noreply, release_route(state, permit)}
  end

  @impl true
  def handle_info(message, state) do
    case :gen_server.check_response(message, state.requests, true) do
      {response, label, requests} ->
        handle_partition_response(response, label, %{state | requests: requests})

      _ ->
        {:noreply, state}
    end
  end

  defp release_route(state, permit) do
    case Map.pop(state.route_permits, permit) do
      {nil, _} ->
        state

      {key, permits} ->
        Process.demonitor(permit, [:flush])
        counts = Map.update!(state.request_counts, key, &(&1 - 1))
        counts = if counts[key] == 0, do: Map.delete(counts, key), else: counts
        %{state | route_permits: permits, request_counts: counts}
    end
  end

  defp await_application(%{pending_application: pending} = state, identity, from) do
    cond do
      identity != MissionRuntimeSpec.identity(pending.spec) ->
        {:reply, {:error, {:generation_applying, pending.spec.generation}}, state}

      pending.remaining == 0 ->
        {:reply, incomplete(pending), state}

      length(pending.waiters) < state.max_partition_requests ->
        {:noreply, %{state | pending_application: %{pending | waiters: [from | pending.waiters]}}}

      true ->
        {:reply, {:error, {:generation_applying, pending.spec.generation}}, state}
    end
  end

  defp request_partition(state, key, request, from) do
    with :ok <- admit_partition_request(state, key),
         {:ok, pid, state} <- ensure_partition_owner(state, key) do
      requests = :gen_server.send_request(pid, request, {:partition, key, from}, state.requests)
      counts = Map.update(state.request_counts, key, 1, &(&1 + 1))
      {:noreply, %{state | requests: requests, request_counts: counts}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp admit_partition_request(%{runtime_spec: nil}, _key), do: {:error, :no_active_binding_set}

  defp admit_partition_request(%{pending_application: pending} = state, key)
       when not is_nil(pending) do
    cond do
      MapSet.member?(pending.ready, key) ->
        check_capacity(state, key)

      Map.has_key?(pending.failed, key) ->
        {:error,
         {:partition_generation_unavailable, pending.spec.generation,
          PartitionKey.identifier(key)}}

      true ->
        {:error, {:generation_applying, pending.spec.generation}}
    end
  end

  defp admit_partition_request(state, key), do: check_capacity(state, key)

  defp check_capacity(state, key) do
    if Map.get(state.request_counts, key, 0) < state.max_partition_requests,
      do: :ok,
      else: {:error, {:partition_busy, PartitionKey.identifier(key)}}
  end

  defp handle_partition_response(response, {:partition, key, from}, state) do
    reply = partition_reply(response)
    GenServer.reply(from, reply)
    counts = Map.update!(state.request_counts, key, &(&1 - 1))
    counts = if counts[key] == 0, do: Map.delete(counts, key), else: counts
    {:noreply, %{state | request_counts: counts}}
  end

  defp handle_partition_response(response, {:reconcile, key}, state) do
    pending = state.pending_application
    pending = %{pending | remaining: pending.remaining - 1}

    pending =
      case partition_reply(response) do
        :ok -> %{pending | ready: MapSet.put(pending.ready, key)}
        error -> %{pending | failed: Map.put(pending.failed, key, error)}
      end

    finish_application(%{state | pending_application: pending})
  end

  defp partition_reply({:reply, reply}), do: reply

  defp partition_reply({:error, {reason, _server}}),
    do: {:error, {:partition_unavailable, reason}}

  defp begin_application(state, new_state, observation, from) do
    if state.runtime_spec &&
         MissionRuntimeSpec.identity(new_state.runtime_spec) ==
           MissionRuntimeSpec.identity(state.runtime_spec) do
      {:reply, {:ok, observation}, state}
    else
      start_application(state, new_state.runtime_spec, new_state.applied_at, [from])
    end
  end

  defp start_application(state, spec, applied_at, waiters) do
    :ok = MissionAdmission.stage(admission(state), spec, applied_at, state.partitions)
    {requests, count, failed} = reconcile_partitions(state, spec)

    pending = %{
      spec: spec,
      applied_at: applied_at,
      observation: GenerationApplied.new(spec, applied_at),
      waiters: waiters,
      remaining: count,
      failed: failed,
      ready: MapSet.new()
    }

    finish_application(%{state | requests: requests, pending_application: pending})
  end

  defp finish_application(
         %{pending_application: %{remaining: 0, failed: failed} = pending} = state
       )
       when map_size(failed) > 0 do
    Enum.each(pending.waiters, &GenServer.reply(&1, incomplete(pending)))
    {:noreply, %{state | pending_application: %{pending | waiters: []}}}
  end

  defp finish_application(%{pending_application: %{remaining: 0} = pending} = state) do
    :ok = MissionAdmission.commit(admission(state), MissionRuntimeSpec.identity(pending.spec))
    Enum.each(pending.waiters, &GenServer.reply(&1, {:ok, pending.observation}))

    {:noreply,
     %{
       state
       | runtime_spec: pending.spec,
         applied_at: pending.applied_at,
         pending_application: nil
     }, :hibernate}
  end

  defp finish_application(state), do: {:noreply, state}

  defp incomplete(pending),
    do: {:error, {:generation_incomplete, pending.spec.generation, pending.failed}}

  defp with_request_state(state) do
    state
    |> Map.put_new(:route_permits, %{})
    |> Map.put_new(:requests, :gen_server.reqids_new())
    |> Map.put_new(:request_counts, %{})
    |> Map.put_new(:pending_application, nil)
    |> Map.put_new(:max_partition_requests, 32)
  end

  defp ensure_partition_owner(
         %{
           runtime_spec: %MissionRuntimeSpec{} = runtime_spec
         } =
           state,
         %PartitionKey{} = partition_key
       ) do
    case start_partition_owner(
           state.process_namespace,
           state.mission_id,
           partition_key,
           runtime_spec,
           state.profiler
         ) do
      {:ok, partition_pid} ->
        unless MapSet.member?(state.partitions, partition_key),
          do: MissionAdmission.track(admission(state), partition_key)

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
         profiler
       ) do
    case PartitionOwner.lookup(process_namespace, mission_id, partition_key) do
      {:ok, partition_pid} ->
        {:ok, partition_pid}

      {:error, :partition_not_running} ->
        start_new_partition_owner(
          process_namespace,
          mission_id,
          partition_key,
          runtime_spec,
          profiler
        )
    end
  end

  defp start_new_partition_owner(
         process_namespace,
         mission_id,
         partition_key,
         runtime_spec,
         profiler
       ) do
    with {:ok, _selected} <- MissionRuntimeSpec.for_partition(runtime_spec, partition_key),
         {:ok, _admitted} <-
           GenServer.call(
             MissionRuntime.admission_name(process_namespace, mission_id),
             {:partition_spec, partition_key},
             :infinity
           ) do
      child_spec =
        {PartitionOwner,
         mission_id: mission_id,
         process_namespace: process_namespace,
         partition_key: partition_key,
         spec_source:
           GenServer.whereis(MissionRuntime.admission_name(process_namespace, mission_id)),
         profiler: profiler,
         defer_init?: true}

      # Failed initialization is returned to waiting callers, without a restart
      # storm. Unexpected owner crashes still restart and recover under supervision.
      child_spec = Supervisor.child_spec(child_spec, restart: :transient)

      result =
        if Cluster.config(process_namespace) do
          %{start: {module, :start_link, [options]}} = child_spec

          child_spec = %{
            child_spec
            | start: {module, :start_link, [Keyword.delete(options, :profiler)]}
          }

          Cluster.start_partition(
            process_namespace,
            {mission_id, partition_key},
            child_spec
          )
        else
          DynamicSupervisor.start_child(
            MissionRuntime.partition_supervisor_name(process_namespace, mission_id),
            child_spec
          )
        end

      case result do
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
  end

  defp reconcile_partitions(state, runtime_spec) do
    Enum.reduce(state.partitions, {state.requests, 0, %{}}, fn key, {requests, count, failed} ->
      with {:ok, spec} <- MissionRuntimeSpec.partition_input(runtime_spec, key),
           {:ok, pid} <-
             start_partition_owner(
               state.process_namespace,
               state.mission_id,
               key,
               runtime_spec,
               state.profiler
             ) do
        requests =
          :gen_server.send_request(
            pid,
            {:reconcile, spec, spec.binding_set},
            {:reconcile, key},
            requests
          )

        {requests, count + 1, failed}
      else
        {:error, reason} -> {requests, count, Map.put(failed, key, {:error, reason})}
      end
    end)
  end

  defp apply_runtime_spec(%{mission_id: mission_id}, %MissionRuntimeSpec{
         mission_id: spec_mission_id
       })
       when mission_id != spec_mission_id do
    {:error, {:mission_runtime_spec_mismatch, :mission_id}}
  end

  defp apply_runtime_spec(%{runtime_spec: nil} = state, %MissionRuntimeSpec{} = spec) do
    applied_at = DateTime.utc_now()

    new_state =
      %{
        state
        | runtime_spec: MissionRuntimeSpec.compact(spec),
          applied_at: applied_at
      }

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

    new_state =
      %{
        state
        | runtime_spec: MissionRuntimeSpec.compact(spec),
          applied_at: applied_at
      }

    {:ok, GenerationApplied.new(spec, applied_at), new_state}
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end

  defp admission(state),
    do: MissionRuntime.admission_name(state.process_namespace, state.mission_id)
end
