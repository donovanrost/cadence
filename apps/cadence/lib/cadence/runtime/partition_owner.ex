# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Runtime.PartitionOwner do
  @moduledoc """
  Active owner for one mission execution partition.
  """

  use GenServer

  alias Cadence.ApplicationDispatch.{
    BindingSet,
    CapabilityInstance,
    DispatchDecision,
    Dispatcher,
    WorkItem
  }

  alias Cadence.Capabilities.{Descriptor, ExecutionResult}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, SpacePacketDecoder, TMFrameIngress, TMFramePipeline}
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler
  alias Cadence.Telemetry.Sample

  alias Cadence.Runtime.{
    ActionExecutor,
    CapabilityRegistry,
    Clock,
    MissionModelPlanDecoder,
    MissionRuntime,
    MissionRuntimeSpec,
    PartitionKey,
    Persistence,
    ProcessNamespace,
    TimerService
  }

  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, Result, Scope, State, Store, Update}

  alias Cadence.Runtime.PartitionOwner.{PartitionBuilder, RuntimeRecords}

  @max_async_outputs 20

  @type state :: %{
          process_namespace: ProcessNamespace.t(),
          mission_id: binary(),
          partition_key: PartitionKey.t(),
          active_activation: MissionRuntimeSpec.t(),
          binding_set: BindingSet.t(),
          runtime_binding_set: BindingSet.t(),
          managed_application_states: %{required(binary()) => term()},
          timer_service: TimerService.t(),
          semantic_timers: map(),
          tm_pipeline_state: TMFramePipeline.state(),
          tm_continuity_state: map(),
          tm_frame_remainder: binary(),
          persist_runtime_records?: boolean(),
          persistence_policy: Persistence.policy(),
          pending_runtime_records: map(),
          async_outputs: [term()],
          semantic_state: State.t()
        }

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    partition_key = Keyword.fetch!(opts, :partition_key)
    process_namespace = process_namespace(opts)
    register? = Keyword.get(opts, :register?, true)

    if register? do
      GenServer.start_link(__MODULE__, opts,
        name: MissionRuntime.partition_owner_name(process_namespace, mission_id, partition_key)
      )
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  def start_link(runtime_opts, opts) when is_list(runtime_opts) and is_list(opts) do
    start_link(Keyword.merge(runtime_opts, opts))
  end

  @spec lookup(binary(), PartitionKey.t()) :: {:ok, pid()} | {:error, :partition_not_running}
  def lookup(mission_id, %PartitionKey{} = partition_key) when is_binary(mission_id),
    do: lookup(ProcessNamespace.default(), mission_id, partition_key)

  @spec lookup(ProcessNamespace.t(), binary(), PartitionKey.t()) ::
          {:ok, pid()} | {:error, :partition_not_running}
  def lookup(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        %PartitionKey{} = partition_key
      )
      when is_binary(mission_id) do
    case Registry.lookup(
           process_namespace.registry,
           {:partition_owner, mission_id, PartitionKey.registry_key(partition_key)}
         ) do
      [{partition_pid, _value}] -> {:ok, partition_pid}
      [] -> {:error, :partition_not_running}
    end
  end

  @spec binding_set(pid()) :: {:ok, BindingSet.t()} | {:error, term()}
  def binding_set(partition_owner) do
    GenServer.call(partition_owner, :binding_set)
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(partition_owner) do
    GenServer.call(partition_owner, :snapshot)
  end

  @spec reconcile(pid(), MissionRuntimeSpec.t(), BindingSet.t()) :: :ok
  def reconcile(
        partition_owner,
        %MissionRuntimeSpec{} = activation,
        %BindingSet{} = binding_set
      ) do
    GenServer.call(partition_owner, {:reconcile, activation, binding_set})
  end

  @spec process_raw_evidence(pid(), RawEvidence.t()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def process_raw_evidence(partition_owner, %RawEvidence{} = raw_evidence) do
    GenServer.call(partition_owner, {:process_raw_evidence, raw_evidence})
  end

  @spec drain_runtime_records(pid()) :: {:ok, map()} | {:error, term()}
  def drain_runtime_records(partition_owner) do
    GenServer.call(partition_owner, :drain_runtime_records)
  end

  @spec stop(pid()) :: :ok
  def stop(partition_owner) when is_pid(partition_owner) do
    GenServer.stop(partition_owner)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    process_namespace = process_namespace(opts)
    partition_key = Keyword.fetch!(opts, :partition_key)
    active_activation = Keyword.fetch!(opts, :active_activation)
    binding_set = Keyword.fetch!(opts, :binding_set)
    persist_runtime_records? = Keyword.get(opts, :persist_runtime_records?, true)

    persistence_policy =
      Keyword.get_lazy(opts, :persistence_policy, &Persistence.configured_policy/0)

    clock_mode = Keyword.get(opts, :clock_mode, :live)

    initial_time =
      Keyword.get_lazy(opts, :initial_time, fn ->
        default_initial_time(clock_mode, active_activation)
      end)

    with {:ok, tm_pipeline_state} <- TMFrameIngress.init(),
         {:ok, runtime_binding_set, managed_application_states, timer_service, runtime_records} <-
           build_runtime_partition_state(
             process_namespace,
             binding_set,
             active_activation,
             partition_key,
             clock_mode,
             initial_time
           ),
         {:ok, semantic_state, semantic_timer_cursors, pending_semantic_timers} <-
           recover_semantic_runtime(
             persist_runtime_records?,
             active_activation,
             partition_key
           ),
         :ok <-
           reproject_pending_semantic_timers(
             persist_runtime_records?,
             persistence_policy,
             active_activation,
             partition_key,
             pending_semantic_timers
           ),
         semantic_timers <-
           build_semantic_timers(active_activation, timer_service, semantic_timer_cursors) do
      case maybe_persist_runtime_records(persist_runtime_records?, runtime_records) do
        {:ok, pending_runtime_records} ->
          {:ok,
           %{
             process_namespace: process_namespace,
             mission_id: mission_id,
             partition_key: partition_key,
             active_activation: active_activation,
             binding_set: binding_set,
             runtime_binding_set: runtime_binding_set,
             managed_application_states: managed_application_states,
             timer_service: timer_service,
             semantic_timers: semantic_timers,
             persistence_policy: persistence_policy,
             tm_pipeline_state: tm_pipeline_state,
             tm_continuity_state: %{},
             tm_frame_remainder: <<>>,
             persist_runtime_records?: persist_runtime_records?,
             pending_runtime_records: pending_runtime_records,
             async_outputs: [],
             semantic_state: semantic_state
           }}

        {:error, reason} ->
          _ = TimerService.cancel_all(timer_service)
          cancel_semantic_timers(semantic_timers)
          {:stop, reason}
      end
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:binding_set, _from, state) do
    {:reply, {:ok, state.runtime_binding_set}, state}
  end

  def handle_call(:drain_runtime_records, _from, state) do
    case drain_timer_records(state) do
      {:ok, drained_state} ->
        {:reply, {:ok, drained_state.pending_runtime_records},
         %{drained_state | pending_runtime_records: empty_runtime_records()}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    case snapshot_managed_applications(state) do
      {:ok, managed_applications} ->
        tm_stats = TMFramePipeline.stats(state.tm_pipeline_state)

        snapshot = %{
          mission_id: state.mission_id,
          activation_id: state.active_activation.activation_id,
          generation: state.active_activation.generation,
          binding_set_content_sha256: state.active_activation.binding_set_content_sha256,
          binding_set_id: state.runtime_binding_set.binding_set_id,
          binding_set_version: state.runtime_binding_set.version,
          partition_key: PartitionKey.identifier(state.partition_key),
          partition_affinity: state.partition_key.affinity,
          partition_value: state.partition_key.value,
          rule_count: length(state.runtime_binding_set.rules),
          capability_instance_count: length(state.runtime_binding_set.capability_instances),
          handler_keys: Enum.map(state.runtime_binding_set.capability_instances, & &1.family_key),
          managed_application_count: length(managed_applications),
          managed_applications: managed_applications,
          timer_count: TimerService.count(state.timer_service),
          timers: TimerService.snapshot(state.timer_service),
          semantic_timer_count: map_size(state.semantic_timers),
          semantic_timers: semantic_timer_snapshot(state.semantic_timers),
          tm_frame_remainder_bytes: byte_size(state.tm_frame_remainder),
          tm_packet_buffer_vcid_count: tm_stats.buffered_virtual_channels,
          tm_continuation_vcid_count: tm_stats.continuation_virtual_channels,
          async_output_count: length(state.async_outputs),
          semantic_sequence: state.semantic_state.sequence
        }

        {:reply, {:ok, snapshot}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:reconcile, %MissionRuntimeSpec{} = activation, %BindingSet{} = binding_set},
        _from,
        state
      ) do
    state = refresh_live_clock(state)

    case build_runtime_partition_state(
           state.process_namespace,
           binding_set,
           activation,
           state.partition_key,
           state.timer_service.clock.mode,
           current_runtime_time(state)
         ) do
      {:ok, runtime_binding_set, managed_application_states, timer_service, runtime_records} ->
        previous_timer_events = build_timer_cancellation_records(state)

        with {:ok, semantic_state, semantic_timer_cursors, pending_semantic_timers} <-
               recover_semantic_runtime(
                 state.persist_runtime_records?,
                 activation,
                 state.partition_key
               ),
             :ok <-
               reproject_pending_semantic_timers(
                 state.persist_runtime_records?,
                 state.persistence_policy,
                 activation,
                 state.partition_key,
                 pending_semantic_timers
               ),
             semantic_timers <-
               build_semantic_timers(activation, timer_service, semantic_timer_cursors),
             {:ok, pending_runtime_records} <-
               maybe_persist_runtime_records(
                 state.persist_runtime_records?,
                 merge_runtime_records(runtime_records, %{
                   capability_records: [],
                   action_requests: [],
                   timer_events: previous_timer_events
                 })
               ) do
          _ = TimerService.cancel_all(state.timer_service)
          cancel_semantic_timers(state.semantic_timers)

          {:reply, :ok,
           %{
             state
             | active_activation: activation,
               binding_set: binding_set,
               runtime_binding_set: runtime_binding_set,
               managed_application_states: managed_application_states,
               timer_service: timer_service,
               semantic_timers: semantic_timers,
               pending_runtime_records: pending_runtime_records,
               async_outputs: [],
               semantic_state: semantic_state
           }}
        else
          {:error, reason} ->
            _ = TimerService.cancel_all(timer_service)
            {:stop, reason, {:error, reason}, state}
        end

      {:error, reason} ->
        {:stop, reason, {:error, reason}, state}
    end
  end

  def handle_call({:process_raw_evidence, %RawEvidence{} = raw_evidence}, _from, state) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      TelemetryProfiler.with_stage(:runtime, fn ->
        raw_evidence
        |> process_raw_evidence_reply(state)
        |> handle_processing_reply(state)
      end)
    end)
  end

  defp process_raw_evidence_reply(%RawEvidence{} = raw_evidence, state) do
    with {:ok, prepared_state, pre_runtime_records} <-
           TelemetryProfiler.with_runtime_component(
             raw_evidence.mission_id,
             :partition_prepare,
             fn ->
               with {:ok, prepared_state, pre_runtime_records} <-
                      prepare_for_raw_evidence(state, raw_evidence),
                    :ok <- validate_partition(raw_evidence, prepared_state.partition_key) do
                 {:ok, prepared_state, pre_runtime_records}
               end
             end
           ),
         {:ok, decode_result, next_state, decode_runtime_records} <-
           TelemetryProfiler.with_runtime_component(
             raw_evidence.mission_id,
             :partition_decode,
             fn ->
               decode_packet_records(raw_evidence, prepared_state)
             end
           ),
         {:ok, dispatch_result, next_state, dispatch_runtime_records} <-
           TelemetryProfiler.with_runtime_component(
             raw_evidence.mission_id,
             :partition_dispatch,
             fn ->
               execute_dispatches(decode_result, next_state)
             end
           ),
         all_runtime_records <-
           merge_runtime_records(pre_runtime_records, decode_runtime_records),
         all_runtime_records <-
           merge_runtime_records(all_runtime_records, next_state.pending_runtime_records),
         all_runtime_records <-
           merge_runtime_records(all_runtime_records, dispatch_runtime_records),
         raw_outputs <- Enum.flat_map(dispatch_result.dispatch_results, & &1.outputs),
         {:ok, outputs, semantic_result, next_state} <-
           process_semantic_outputs(raw_outputs, next_state),
         {:ok, pending_runtime_records} <-
           TelemetryProfiler.with_runtime_component(
             raw_evidence.mission_id,
             :runtime_record_persistence,
             fn ->
               maybe_persist_runtime_records(
                 next_state.persist_runtime_records?,
                 all_runtime_records
               )
             end
           ) do
      dispatch_decisions = Enum.map(dispatch_result.dispatch_results, & &1.dispatch_decision)

      {:ok,
       %{
         raw_evidence: raw_evidence,
         packet_records: decode_result.packet_records,
         transfer_frame_records: decode_result.transfer_frame_records,
         protocol_anomalies: decode_result.protocol_anomalies,
         dispatch_decisions: dispatch_decisions,
         outputs: outputs,
         semantic_result: semantic_result,
         runtime_spec: next_state.active_activation,
         runtime_records: all_runtime_records
       }, %{next_state | pending_runtime_records: pending_runtime_records}}
    end
  end

  defp process_semantic_outputs(outputs, %{active_activation: activation} = state) do
    plan = PlanDecoder.decode(activation.runtime_plans)
    annotated_outputs = Enum.map(outputs, &annotate_semantic_basis(&1, activation))

    if plan.algorithms == [] and plan.monitoring == [] do
      {:ok, annotated_outputs, %Result{}, state}
    else
      updates = Enum.flat_map(annotated_outputs, &sample_update/1)

      with {:ok, %Result{} = result, semantic_state} <-
             SemanticRuntime.process(state.semantic_state, updates, plan),
           {:ok, %Result{} = result, semantic_state} <-
             commit_semantic_state(state, updates, result, semantic_state) do
        derived_samples =
          result.parameter_updates
          |> Enum.filter(&(&1.producer_kind == :algorithm))
          |> Enum.map(&derived_sample(&1, activation))

        {:ok, annotated_outputs ++ derived_samples, result,
         %{state | semantic_state: semantic_state}}
      else
        {:error, reason} ->
          {:error, {:semantic_runtime_failed, reason}}
      end
    end
  end

  defp commit_semantic_state(_state, [], result, semantic_state),
    do: {:ok, result, semantic_state}

  defp commit_semantic_state(
         %{persist_runtime_records?: true} = state,
         updates,
         result,
         semantic_state
       ) do
    Store.commit(
      state.active_activation,
      state.partition_key,
      updates,
      result,
      semantic_state
    )
  end

  defp commit_semantic_state(_state, _updates, result, semantic_state),
    do: {:ok, result, semantic_state}

  defp recover_semantic_runtime(false, _activation, _partition_key),
    do: {:ok, SemanticRuntime.new(), %{}, []}

  defp recover_semantic_runtime(true, activation, partition_key) do
    plan = PlanDecoder.decode(activation.runtime_plans)

    if plan.algorithms == [] and plan.monitoring == [] do
      {:ok, SemanticRuntime.new(), %{}, []}
    else
      with {:ok, semantic_state} <- Store.recover(activation, partition_key, plan),
           {:ok, cursors} <- Store.timer_cursors(activation, partition_key),
           {:ok, pending_timers} <- Store.pending_timer_results(activation, partition_key) do
        {:ok, semantic_state, cursors, pending_timers}
      end
    end
  end

  defp reproject_pending_semantic_timers(
         false,
         _persistence_policy,
         _activation,
         _partition_key,
         _pending
       ),
       do: :ok

  defp reproject_pending_semantic_timers(
         true,
         persistence_policy,
         activation,
         partition_key,
         pending
       ) do
    Enum.reduce_while(pending, :ok, fn entry, :ok ->
      derived_samples =
        entry.result.parameter_updates
        |> Enum.filter(&(&1.producer_kind == :algorithm))
        |> Enum.map(&derived_sample(&1, activation))

      with :ok <-
             Persistence.persist_semantic_timer_result(
               persistence_policy,
               activation,
               entry.result,
               derived_samples,
               at: entry.at,
               timer_key: entry.timer_key
             ),
           :ok <-
             Store.mark_timer_projected(
               activation,
               partition_key,
               entry.timer_key,
               entry.at
             ) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp annotate_semantic_basis(%Sample{} = sample, activation) do
    telemetry_plan = Map.get(activation.runtime_plans, :telemetry)

    %Sample{
      sample
      | mission_model_revision_id: activation.mission_model_revision_id,
        runtime_plan_id: telemetry_plan && telemetry_plan.plan_id,
        provenance:
          Map.merge(sample.provenance, %{
            mission_model_revision_id: activation.mission_model_revision_id,
            runtime_plan_id: telemetry_plan && telemetry_plan.plan_id
          })
    }
  end

  defp annotate_semantic_basis(output, _activation), do: output

  defp sample_update(%Sample{semantic_id: semantic_id} = sample) when is_binary(semantic_id) do
    [
      Update.new(%{
        update_id: sample.sample_id,
        parameter_id: semantic_id,
        qualified_name: sample.qualified_name || sample.point_name,
        value: sample.engineering_value,
        raw_value: sample.raw_value,
        quality: sample.quality_state,
        generation_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        producer_kind: sample.producer_kind || :container,
        producer_id: sample.producer_id || sample.packet_definition_id,
        metadata: %{
          mission_id: sample.mission_id,
          spacecraft_id: sample.spacecraft_id,
          packet_id: sample.packet_id,
          evidence_id: sample.evidence_id,
          trigger_sample_id: sample.sample_id
        }
      })
    ]
  end

  defp sample_update(_output), do: []

  defp derived_sample(%Update{} = update, activation) do
    algorithm_plan = Map.get(activation.runtime_plans, :algorithm)

    %Sample{
      sample_id: update.update_id,
      mission_id: metadata_value(update, :mission_id),
      spacecraft_id: metadata_value(update, :spacecraft_id),
      point_id: update.parameter_id,
      point_name: update.qualified_name,
      semantic_id: update.parameter_id,
      qualified_name: update.qualified_name,
      producer_kind: :algorithm,
      producer_id: update.producer_id,
      mission_model_revision_id: activation.mission_model_revision_id,
      runtime_plan_id: algorithm_plan && algorithm_plan.plan_id,
      packet_definition_id: "mission_model_algorithm:" <> update.producer_id,
      packet_definition_version: 1,
      packet_id: metadata_value(update, :packet_id) || update.update_id,
      evidence_id: metadata_value(update, :evidence_id) || update.update_id,
      raw_value: nil,
      engineering_value: update.value,
      quality_state: update.quality,
      generation_time: update.generation_time,
      receipt_time: update.receipt_time,
      provenance: %{
        source_update_ids: update.source_update_ids,
        trigger_sample_id: metadata_value(update, :trigger_sample_id),
        mission_model_revision_id: activation.mission_model_revision_id,
        runtime_plan_id: algorithm_plan && algorithm_plan.plan_id,
        producer_kind: :algorithm,
        producer_id: update.producer_id
      }
    }
  end

  defp metadata_value(update, key),
    do: Map.get(update.metadata, key, Map.get(update.metadata, Atom.to_string(key)))

  @impl true
  def handle_info({:semantic_algorithm_timer, timer_key, timer_id}, state) do
    state = refresh_live_clock(state)

    case Map.get(state.semantic_timers, timer_key) do
      %{timer_id: ^timer_id} = entry ->
        timer_state = %{
          state
          | semantic_timers: Map.delete(state.semantic_timers, timer_key)
        }

        case execute_semantic_timer(entry, timer_state) do
          {:ok, next_state} -> {:noreply, next_state}
          {:error, reason} -> {:stop, reason, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:managed_application_timer, capability_instance_id, timer_key, timer_id},
        state
      ) do
    state = refresh_live_clock(state)

    case TimerService.fire(state.timer_service, capability_instance_id, timer_key, timer_id) do
      {:ok, timer_service, timer_entry} ->
        handle_fired_managed_application_timer(
          capability_instance_id,
          timer_key,
          timer_entry,
          timer_service,
          state
        )

      {:error, :stale_timer} ->
        {:noreply, state}
    end
  end

  defp handle_fired_managed_application_timer(
         capability_instance_id,
         timer_key,
         timer_entry,
         %TimerService{} = timer_service,
         state
       ) do
    case execute_timer(
           capability_instance_id,
           timer_key,
           timer_entry,
           %{state | timer_service: timer_service}
         ) do
      {:ok, next_state, runtime_records} ->
        persist_timer_runtime_records(next_state, runtime_records, state)

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp execute_semantic_timer(entry, state) do
    plan = PlanDecoder.decode(state.active_activation.runtime_plans)

    scopes =
      case Scope.all(state.semantic_state.latest) do
        [{"__mission__", "__mission__"}] -> [Scope.new(state.mission_id, nil)]
        scoped -> scoped
      end

    with {:ok, result, semantic_state} <-
           evaluate_semantic_timer_scopes(scopes, entry, plan, state, %Result{}),
         derived_samples <-
           result.parameter_updates
           |> Enum.filter(&(&1.producer_kind == :algorithm))
           |> Enum.map(&derived_sample(&1, state.active_activation)),
         :ok <- maybe_persist_semantic_timer(state, entry, result, derived_samples) do
      next_entry =
        entry
        |> Map.put(:due_at, DateTime.add(entry.due_at, entry.interval_ms, :millisecond))
        |> schedule_semantic_timer(state.timer_service)

      {:ok,
       state
       |> Map.put(:semantic_state, semantic_state)
       |> Map.put(
         :semantic_timers,
         Map.put(state.semantic_timers, entry.timer_key, next_entry)
       )
       |> store_async_outputs(derived_samples)}
    end
  end

  defp evaluate_semantic_timer_scopes(scopes, entry, plan, state, result) do
    Enum.reduce_while(scopes, {:ok, result, state.semantic_state}, fn scope,
                                                                      {:ok, acc, semantic_state} ->
      with {:ok, scoped_result, next_semantic_state} <-
             SemanticRuntime.timer(
               semantic_state,
               scope,
               entry.algorithm_id,
               entry.due_at,
               plan
             ),
           {:ok, scoped_result, next_semantic_state} <-
             commit_semantic_timer(
               state,
               scope,
               entry,
               scoped_result,
               next_semantic_state
             ) do
        {:cont, {:ok, merge_semantic_results(acc, scoped_result), next_semantic_state}}
      else
        {:error, reason} -> {:halt, {:error, {:semantic_runtime_timer_failed, reason}}}
      end
    end)
  end

  defp commit_semantic_timer(
         %{persist_runtime_records?: true} = state,
         scope,
         entry,
         result,
         semantic_state
       ) do
    Store.commit_timer(
      state.active_activation,
      state.partition_key,
      scope,
      entry.algorithm_id,
      entry.due_at,
      entry.timer_key,
      result,
      semantic_state
    )
  end

  defp commit_semantic_timer(_state, _scope, _entry, result, semantic_state),
    do: {:ok, result, semantic_state}

  defp maybe_persist_semantic_timer(
         %{persist_runtime_records?: true} = state,
         entry,
         result,
         derived_samples
       ) do
    with :ok <-
           Persistence.persist_semantic_timer_result(
             state.persistence_policy,
             state.active_activation,
             result,
             derived_samples,
             at: entry.due_at,
             timer_key: entry.timer_key
           ) do
      Store.mark_timer_projected(
        state.active_activation,
        state.partition_key,
        entry.timer_key,
        entry.due_at
      )
    end
  end

  defp maybe_persist_semantic_timer(_state, _entry, _result, _derived_samples), do: :ok

  defp merge_semantic_results(left, right) do
    %Result{
      parameter_updates: left.parameter_updates ++ right.parameter_updates,
      monitoring_results: left.monitoring_results ++ right.monitoring_results,
      alarm_transitions: left.alarm_transitions ++ right.alarm_transitions,
      diagnostics: left.diagnostics ++ right.diagnostics
    }
  end

  defp handle_processing_reply({:ok, processing_result, next_state}, _state) do
    {:reply, {:ok, processing_result}, next_state}
  end

  defp handle_processing_reply({:error, reason}, state) do
    {:reply, {:error, reason}, state}
  end

  defp persist_timer_runtime_records(next_state, runtime_records, state) do
    all_runtime_records =
      merge_runtime_records(next_state.pending_runtime_records, runtime_records)

    case maybe_persist_runtime_records(next_state.persist_runtime_records?, all_runtime_records) do
      {:ok, pending_runtime_records} ->
        {:noreply, %{next_state | pending_runtime_records: pending_runtime_records}}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp build_runtime_partition_state(
         %ProcessNamespace{} = process_namespace,
         %BindingSet{} = binding_set,
         %MissionRuntimeSpec{} = activation,
         %PartitionKey{} = partition_key,
         clock_mode,
         %DateTime{} = current_time
       ) do
    PartitionBuilder.build(
      binding_set,
      activation,
      partition_key,
      clock_mode,
      current_time,
      process_namespace: process_namespace
    )
  end

  defp decode_packet_records(%RawEvidence{protocol_family: protocol_family} = raw_evidence, state)
       when protocol_family in [:space_packet, :packet, :space_packet_stream] do
    with {:ok, %PacketRecord{} = packet_record} <- SpacePacketDecoder.decode(raw_evidence) do
      {:ok,
       %{
         packet_records: [packet_record],
         transfer_frame_records: [],
         protocol_anomalies: []
       }, state, empty_runtime_records()}
    end
  end

  defp decode_packet_records(%RawEvidence{protocol_family: protocol_family} = raw_evidence, state)
       when protocol_family in [:tm, :tm_transfer_frame] do
    decode_tm_packet_records(protocol_family, raw_evidence, state)
  end

  defp decode_packet_records(%RawEvidence{protocol_family: protocol_family}, _state) do
    {:error, {:unsupported_ingress_protocol_family, protocol_family}}
  end

  defp decode_tm_packet_records(protocol_family, %RawEvidence{} = raw_evidence, state) do
    case TMFrameIngress.process(
           raw_evidence,
           state.tm_pipeline_state,
           state.tm_continuity_state,
           state.tm_frame_remainder
         ) do
      {:ok, decode_result, rest, next_tm_pipeline_state, next_tm_continuity_state} ->
        {:ok, decode_result,
         %{
           state
           | tm_pipeline_state: next_tm_pipeline_state,
             tm_continuity_state: next_tm_continuity_state,
             tm_frame_remainder: rest
         }, empty_runtime_records()}

      {:error, reason, _next_tm_pipeline_state, _next_tm_continuity_state} ->
        {:error, {protocol_family, reason}}
    end
  end

  defp execute_dispatches(
         %{packet_records: []} = decode_result,
         state
       ) do
    {:ok, Map.put(decode_result, :dispatch_results, []), state, empty_runtime_records()}
  end

  defp execute_dispatches(%{packet_records: packet_records} = decode_result, state)
       when is_list(packet_records) do
    Enum.reduce_while(
      packet_records,
      {:ok, [], state, empty_runtime_records()},
      fn %PacketRecord{} = packet_record, {:ok, results, acc_state, runtime_records} ->
        with {:ok, %DispatchDecision{} = dispatch_decision} <-
               Dispatcher.dispatch(packet_record, acc_state.runtime_binding_set),
             {:ok, outputs, next_state, dispatch_runtime_records} <-
               execute_dispatch(packet_record, dispatch_decision, acc_state) do
          {:cont,
           {:ok,
            [
              %{
                packet_record: packet_record,
                dispatch_decision: dispatch_decision,
                outputs: outputs
              }
              | results
            ], next_state, merge_runtime_records(runtime_records, dispatch_runtime_records)}}
        else
          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, dispatch_results_reversed, next_state, runtime_records} ->
        {:ok, Map.put(decode_result, :dispatch_results, Enum.reverse(dispatch_results_reversed)),
         next_state, runtime_records}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_dispatch(
         %PacketRecord{} = packet_record,
         %DispatchDecision{} = dispatch_decision,
         state
       ) do
    Enum.reduce_while(
      dispatch_decision.work_items,
      {:ok, [], state, empty_runtime_records()},
      fn %WorkItem{} = work_item, {:ok, outputs, acc_state, runtime_records} ->
        case execute_work_item(packet_record, work_item, acc_state) do
          {:ok, work_item_outputs, next_state, work_item_runtime_records} ->
            {:cont,
             {:ok, Enum.reverse(work_item_outputs, outputs), next_state,
              merge_runtime_records(runtime_records, work_item_runtime_records)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, outputs_reversed, next_state, runtime_records} ->
        {:ok, Enum.reverse(outputs_reversed), next_state, runtime_records}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_work_item(%PacketRecord{} = packet_record, %WorkItem{} = work_item, state) do
    with {:ok, %Descriptor{} = descriptor} <-
           CapabilityRegistry.fetch_descriptor(
             state.process_namespace.capability_registry,
             work_item.handler_key
           ) do
      case descriptor.kind do
        :semantic_handler ->
          execute_semantic_handler(packet_record, work_item, state)

        :managed_application ->
          execute_managed_application(packet_record, work_item, state)

        kind ->
          {:error, {:unsupported_runtime_execution_kind, kind}}
      end
    end
  end

  defp execute_semantic_handler(%PacketRecord{} = packet_record, %WorkItem{} = work_item, state) do
    with {:ok, handler_module} <-
           CapabilityRegistry.fetch_family(
             state.process_namespace.capability_registry,
             work_item.handler_key
           ),
         {:ok, runtime_configuration} <-
           MissionModelPlanDecoder.resolve_telemetry_configuration(
             state.active_activation.runtime_plans,
             work_item.handler_configuration
           ),
         runtime_work_item <- %WorkItem{
           work_item
           | handler_configuration: runtime_configuration
         },
         {:ok, outputs} <- handler_module.handle(packet_record, runtime_work_item) do
      {:ok, outputs, state, empty_runtime_records()}
    end
  end

  defp execute_managed_application(
         %PacketRecord{} = packet_record,
         %WorkItem{} = work_item,
         state
       ) do
    with {:ok, capability_instance_id} <- fetch_work_item_capability_instance_id(work_item),
         {:ok, %CapabilityInstance{} = capability_instance} <-
           fetch_runtime_capability_instance(state.runtime_binding_set, capability_instance_id),
         {:ok, application_state} <-
           fetch_managed_application_state(state, capability_instance_id),
         execution_context <-
           build_execution_context(
             state.active_activation,
             state.runtime_binding_set,
             state.partition_key,
             capability_instance,
             current_runtime_time(state)
           ),
         {:ok, %ExecutionResult{} = execution_result} <-
           CapabilityRegistry.handle_managed_record(
             state.process_namespace.capability_registry,
             capability_instance.family_key,
             packet_record,
             application_state,
             execution_context
           ),
         {:ok, %{timer_service: timer_service, timer_events: timer_events}} <-
           ActionExecutor.execute_many(
             execution_result.action_requests,
             capability_instance.capability_instance_id,
             state.timer_service
           ),
         {:ok, state_snapshot} <-
           CapabilityRegistry.snapshot_managed_state(
             state.process_namespace.capability_registry,
             capability_instance.family_key,
             execution_result.state,
             execution_context
           ) do
      {:ok, execution_result.records,
       put_managed_application_state(
         state,
         capability_instance.capability_instance_id,
         execution_result.state,
         timer_service
       ),
       managed_execution_runtime_records(
         :record_handled,
         capability_instance,
         execution_context,
         execution_result,
         execution_result.action_requests,
         timer_events,
         packet_record: packet_record,
         state_snapshot: state_snapshot
       )}
    end
  end

  defp execute_timer(capability_instance_id, timer_key, timer_entry, state) do
    with {:ok, %CapabilityInstance{} = capability_instance} <-
           fetch_runtime_capability_instance(state.runtime_binding_set, capability_instance_id),
         {:ok, application_state} <-
           fetch_managed_application_state(state, capability_instance_id),
         execution_context <-
           build_execution_context(
             state.active_activation,
             state.runtime_binding_set,
             state.partition_key,
             capability_instance,
             current_runtime_time(state),
             %{
               timer_key: timer_key,
               timer_due_at: timer_entry.due_at,
               timer_fired_at: current_runtime_time(state),
               timer_metadata: timer_entry.metadata
             }
           ),
         {:ok, %ExecutionResult{} = execution_result} <-
           CapabilityRegistry.handle_managed_timer(
             state.process_namespace.capability_registry,
             capability_instance.family_key,
             timer_key,
             application_state,
             execution_context
           ),
         {:ok, %{timer_service: timer_service, timer_events: timer_events}} <-
           ActionExecutor.execute_many(
             execution_result.action_requests,
             capability_instance.capability_instance_id,
             state.timer_service
           ),
         {:ok, state_snapshot} <-
           CapabilityRegistry.snapshot_managed_state(
             state.process_namespace.capability_registry,
             capability_instance.family_key,
             execution_result.state,
             execution_context
           ) do
      runtime_records =
        managed_execution_runtime_records(
          :timer_handled,
          capability_instance,
          execution_context,
          execution_result,
          execution_result.action_requests,
          [
            %{
              event_kind: :fired,
              timer_key: timer_key,
              due_at: timer_entry.due_at,
              metadata: timer_entry.metadata
            }
            | timer_events
          ],
          timer_key: timer_key,
          state_snapshot: state_snapshot
        )

      {:ok,
       state
       |> put_managed_application_state(
         capability_instance.capability_instance_id,
         execution_result.state,
         timer_service
       )
       |> store_async_outputs(execution_result.records), runtime_records}
    end
  end

  defp snapshot_managed_applications(state),
    do: PartitionBuilder.snapshot_managed_applications(state)

  defp validate_partition(%RawEvidence{} = raw_evidence, %PartitionKey{} = partition_key) do
    if PartitionKey.from_raw_evidence(raw_evidence) == partition_key do
      :ok
    else
      {:error, {:partition_mismatch, PartitionKey.identifier(partition_key)}}
    end
  end

  defp build_execution_context(
         %MissionRuntimeSpec{} = activation,
         %BindingSet{} = runtime_binding_set,
         %PartitionKey{} = partition_key,
         %CapabilityInstance{} = capability_instance,
         %DateTime{} = current_time,
         metadata \\ %{}
       ) do
    PartitionBuilder.execution_context(
      activation,
      runtime_binding_set,
      partition_key,
      capability_instance,
      current_time,
      metadata
    )
  end

  defp fetch_runtime_capability_instance(
         %BindingSet{} = runtime_binding_set,
         capability_instance_id
       ) do
    case BindingSet.fetch_capability_instance(runtime_binding_set, capability_instance_id) do
      {:ok, %CapabilityInstance{} = capability_instance} -> {:ok, capability_instance}
      :error -> {:error, {:unknown_capability_instance, capability_instance_id}}
    end
  end

  defp fetch_work_item_capability_instance_id(%WorkItem{
         capability_instance_id: capability_instance_id
       })
       when is_binary(capability_instance_id),
       do: {:ok, capability_instance_id}

  defp fetch_work_item_capability_instance_id(%WorkItem{}),
    do: {:error, :missing_capability_instance_id}

  defp fetch_managed_application_state(state, capability_instance_id)
       when is_binary(capability_instance_id) do
    case Map.fetch(state.managed_application_states, capability_instance_id) do
      {:ok, application_state} -> {:ok, application_state}
      :error -> {:error, {:managed_application_not_initialized, capability_instance_id}}
    end
  end

  defp put_managed_application_state(
         state,
         capability_instance_id,
         application_state,
         timer_service
       ) do
    %{
      state
      | managed_application_states:
          Map.put(state.managed_application_states, capability_instance_id, application_state),
        timer_service: timer_service
    }
  end

  defp store_async_outputs(state, outputs) when outputs == [], do: state

  defp store_async_outputs(state, outputs) when is_list(outputs) do
    %{state | async_outputs: Enum.take(state.async_outputs ++ outputs, -@max_async_outputs)}
  end

  defp empty_runtime_records, do: RuntimeRecords.empty()

  defp merge_runtime_records(left, right), do: RuntimeRecords.merge(left, right)

  defp managed_execution_runtime_records(
         event_kind,
         capability_instance,
         execution_context,
         execution_result,
         action_requests,
         timer_events,
         opts
       ) do
    RuntimeRecords.for_execution(
      event_kind,
      capability_instance,
      execution_context,
      execution_result,
      action_requests,
      timer_events,
      opts
    )
  end

  defp build_managed_timer_event(
         capability_instance,
         execution_context,
         timer_event,
         packet_record
       ) do
    RuntimeRecords.timer_event(
      capability_instance,
      execution_context,
      timer_event,
      packet_record
    )
  end

  defp persist_runtime_records(%{
         capability_records: capability_records,
         action_requests: action_requests,
         timer_events: timer_events
       })
       when capability_records == [] and action_requests == [] and timer_events == [] do
    :ok
  end

  defp persist_runtime_records(%{
         capability_records: capability_records,
         action_requests: action_requests,
         timer_events: timer_events
       }) do
    Persistence.persist_managed_runtime_records(
      capability_records,
      action_requests,
      timer_events
    )
  end

  defp maybe_persist_runtime_records(true, runtime_records) do
    case persist_runtime_records(runtime_records) do
      :ok -> {:ok, empty_runtime_records()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_persist_runtime_records(false, runtime_records) do
    {:ok, runtime_records}
  end

  defp drain_timer_records(state) do
    case next_timer_entry(state.timer_service) do
      nil ->
        {:ok, state}

      {capability_instance_id, timer_entry} ->
        advanced_state = advance_state_time(state, timer_entry.due_at)

        case execute_timer(
               capability_instance_id,
               timer_entry.timer_key,
               timer_entry,
               %{
                 advanced_state
                 | timer_service: remove_timer_entry(advanced_state.timer_service, timer_entry)
               }
             ) do
          {:ok, next_state, runtime_records} ->
            drain_timer_records(%{
              next_state
              | pending_runtime_records:
                  merge_runtime_records(next_state.pending_runtime_records, runtime_records)
            })

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp next_timer_entry(%TimerService{timers: timers}) do
    timers
    |> Map.values()
    |> Enum.sort_by(&{&1.due_at, &1.capability_instance_id, &1.timer_key})
    |> List.first()
    |> case do
      nil -> nil
      entry -> {entry.capability_instance_id, entry}
    end
  end

  defp remove_timer_entry(%TimerService{} = timer_service, timer_entry) do
    %TimerService{
      timer_service
      | timers:
          Map.delete(
            timer_service.timers,
            {timer_entry.capability_instance_id, timer_entry.timer_key}
          )
    }
  end

  defp build_timer_cancellation_records(state) do
    state.timer_service
    |> TimerService.snapshot()
    |> Enum.reduce([], fn timer_snapshot, acc ->
      case fetch_runtime_capability_instance(
             state.runtime_binding_set,
             timer_snapshot.capability_instance_id
           ) do
        {:ok, %CapabilityInstance{} = capability_instance} ->
          execution_context =
            build_execution_context(
              state.active_activation,
              state.runtime_binding_set,
              state.partition_key,
              capability_instance,
              current_runtime_time(state),
              %{reconciliation: true}
            )

          acc ++
            [
              build_managed_timer_event(
                capability_instance,
                execution_context,
                %{
                  event_kind: :canceled,
                  timer_key: timer_snapshot.timer_key,
                  due_at: timer_snapshot.due_at,
                  metadata: Map.put(timer_snapshot.metadata, :reason, :reconciled)
                },
                nil
              )
            ]

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp default_initial_time(:replay, %MissionRuntimeSpec{} = activation),
    do: activation.activated_at

  defp default_initial_time(_clock_mode, %MissionRuntimeSpec{}), do: DateTime.utc_now()

  defp build_semantic_timers(activation, timer_service, cursors) do
    activation.runtime_plans
    |> PlanDecoder.decode()
    |> Map.fetch!(:algorithms)
    |> Enum.flat_map(fn algorithm ->
      algorithm.triggers
      |> Enum.with_index()
      |> Enum.flat_map(fn {trigger, index} ->
        kind = value(trigger, :kind)
        interval_ms = value(trigger, :interval_ms)

        if kind in [:periodic, "periodic", :timer, "timer"] and
             is_integer(interval_ms) and interval_ms > 0 do
          timer_key =
            "semantic:" <> algorithm.algorithm_id <> ":" <> Integer.to_string(index)

          anchor = Map.get(cursors, timer_key, activation.activated_at)

          [
            %{
              timer_key: timer_key,
              timer_id: nil,
              timer_ref: nil,
              algorithm_id: algorithm.algorithm_id,
              interval_ms: interval_ms,
              due_at: DateTime.add(anchor, interval_ms, :millisecond)
            }
          ]
        else
          []
        end
      end)
    end)
    |> Map.new(fn entry ->
      scheduled = schedule_semantic_timer(entry, timer_service)
      {scheduled.timer_key, scheduled}
    end)
  end

  defp schedule_semantic_timer(entry, timer_service) do
    timer_id = Cadence.Ids.new("semantic_timer")

    timer_ref =
      if TimerService.live?(timer_service) do
        delay_ms =
          entry.due_at
          |> DateTime.diff(TimerService.current_time(timer_service), :millisecond)
          |> max(0)

        Process.send_after(
          self(),
          {:semantic_algorithm_timer, entry.timer_key, timer_id},
          delay_ms
        )
      end

    %{entry | timer_id: timer_id, timer_ref: timer_ref}
  end

  defp cancel_semantic_timers(timers) do
    Enum.each(timers, fn {_key, entry} ->
      if is_reference(entry.timer_ref), do: Process.cancel_timer(entry.timer_ref)
    end)

    :ok
  end

  defp semantic_timer_snapshot(timers) do
    timers
    |> Map.values()
    |> Enum.sort_by(&{&1.due_at, &1.algorithm_id, &1.timer_key})
    |> Enum.map(&Map.drop(&1, [:timer_ref]))
  end

  defp current_runtime_time(state), do: TimerService.current_time(state.timer_service)

  defp refresh_live_clock(%{timer_service: %TimerService{} = timer_service} = state) do
    if TimerService.live?(timer_service) do
      %{state | timer_service: TimerService.set_current_time(timer_service, DateTime.utc_now())}
    else
      state
    end
  end

  defp advance_state_time(
         %{timer_service: %TimerService{} = timer_service} = state,
         %DateTime{} = target_time
       ) do
    %{state | timer_service: TimerService.advance_to(timer_service, target_time)}
  end

  defp prepare_for_raw_evidence(state, %RawEvidence{} = raw_evidence) do
    case state.timer_service.clock do
      %Clock{} = clock when clock.mode == :replay ->
        advance_replay_time(state, raw_evidence_time(raw_evidence))

      %Clock{} ->
        {:ok, refresh_live_clock(state), empty_runtime_records()}
    end
  end

  defp advance_replay_time(state, %DateTime{} = target_time) do
    with {:ok, advanced_state, runtime_records} <-
           fire_due_timers_until(state, target_time, empty_runtime_records()) do
      {:ok, advance_state_time(advanced_state, target_time), runtime_records}
    end
  end

  defp fire_due_timers_until(state, %DateTime{} = target_time, runtime_records) do
    case next_due_runtime_timer(state, target_time) do
      nil ->
        {:ok, state, runtime_records}

      {:managed, capability_instance_id, timer_entry} ->
        timer_state = advance_state_time(state, timer_entry.due_at)

        case execute_timer(
               capability_instance_id,
               timer_entry.timer_key,
               timer_entry,
               %{
                 timer_state
                 | timer_service: remove_timer_entry(timer_state.timer_service, timer_entry)
               }
             ) do
          {:ok, next_state, timer_runtime_records} ->
            fire_due_timers_until(
              next_state,
              target_time,
              merge_runtime_records(runtime_records, timer_runtime_records)
            )

          {:error, reason} ->
            {:error, reason}
        end

      {:semantic, entry} ->
        timer_state =
          state
          |> advance_state_time(entry.due_at)
          |> Map.put(:semantic_timers, Map.delete(state.semantic_timers, entry.timer_key))

        case execute_semantic_timer(entry, timer_state) do
          {:ok, next_state} ->
            fire_due_timers_until(next_state, target_time, runtime_records)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp next_due_runtime_timer(state, target_time) do
    managed =
      case next_due_timer_entry(state.timer_service, target_time) do
        nil ->
          []

        {capability_instance_id, entry} ->
          [{entry.due_at, :managed, capability_instance_id, entry}]
      end

    semantic =
      state.semantic_timers
      |> Map.values()
      |> Enum.filter(&(DateTime.compare(&1.due_at, target_time) != :gt))
      |> Enum.map(&{&1.due_at, :semantic, &1.timer_key, &1})

    (managed ++ semantic)
    |> Enum.sort_by(fn {due_at, kind, key, _entry} -> {due_at, kind, key} end)
    |> List.first()
    |> case do
      nil ->
        nil

      {_due_at, :managed, capability_instance_id, entry} ->
        {:managed, capability_instance_id, entry}

      {_due_at, :semantic, _timer_key, entry} ->
        {:semantic, entry}
    end
  end

  defp next_due_timer_entry(%TimerService{} = timer_service, %DateTime{} = target_time) do
    timer_service.timers
    |> Map.values()
    |> Enum.filter(fn entry ->
      DateTime.compare(entry.due_at, target_time) != :gt
    end)
    |> Enum.sort_by(&{&1.due_at, &1.capability_instance_id, &1.timer_key})
    |> List.first()
    |> case do
      nil -> nil
      entry -> {entry.capability_instance_id, entry}
    end
  end

  defp raw_evidence_time(%RawEvidence{} = raw_evidence) do
    raw_evidence.source_time || raw_evidence.receipt_time
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end
end
