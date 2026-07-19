# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Runtime.PartitionOwner do
  @moduledoc """
  Active owner for one mission execution partition.
  """

  use GenServer

  alias Cadence.Activations.BindingSetActivation

  alias Cadence.ApplicationDispatch.{
    BindingSet,
    CapabilityInstance,
    DispatchDecision,
    Dispatcher,
    WorkItem
  }

  alias Cadence.Capabilities.{Descriptor, ExecutionResult}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence
  alias Cadence.Protocol.{PacketRecord, SpacePacketDecoder, TMFrameIngress, TMFramePipeline}
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  alias Cadence.Runtime.{
    ActionExecutor,
    CapabilityRegistry,
    Clock,
    MissionRuntime,
    PartitionKey,
    TimerService
  }

  alias Cadence.Runtime.PartitionOwner.{PartitionBuilder, RuntimeRecords}

  @max_async_outputs 20

  @type state :: %{
          mission_id: binary(),
          partition_key: PartitionKey.t(),
          active_activation: BindingSetActivation.t(),
          binding_set: BindingSet.t(),
          runtime_binding_set: BindingSet.t(),
          managed_application_states: %{required(binary()) => term()},
          timer_service: TimerService.t(),
          tm_pipeline_state: TMFramePipeline.state(),
          tm_continuity_state: map(),
          tm_frame_remainder: binary(),
          persist_runtime_records?: boolean(),
          pending_runtime_records: map(),
          async_outputs: [term()]
        }

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    partition_key = Keyword.fetch!(opts, :partition_key)
    register? = Keyword.get(opts, :register?, true)

    if register? do
      GenServer.start_link(__MODULE__, opts,
        name: MissionRuntime.partition_owner_name(mission_id, partition_key)
      )
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @spec lookup(binary(), PartitionKey.t()) :: {:ok, pid()} | {:error, :partition_not_running}
  def lookup(mission_id, %PartitionKey{} = partition_key) when is_binary(mission_id) do
    case Registry.lookup(
           Cadence.Runtime.Registry,
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

  @spec reconcile(pid(), BindingSetActivation.t(), BindingSet.t()) :: :ok
  def reconcile(
        partition_owner,
        %BindingSetActivation{} = activation,
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
    partition_key = Keyword.fetch!(opts, :partition_key)
    active_activation = Keyword.fetch!(opts, :active_activation)
    binding_set = Keyword.fetch!(opts, :binding_set)
    persist_runtime_records? = Keyword.get(opts, :persist_runtime_records?, true)
    clock_mode = Keyword.get(opts, :clock_mode, :live)

    initial_time =
      Keyword.get_lazy(opts, :initial_time, fn ->
        default_initial_time(clock_mode, active_activation)
      end)

    with {:ok, tm_pipeline_state} <- TMFrameIngress.init(),
         {:ok, runtime_binding_set, managed_application_states, timer_service, runtime_records} <-
           build_runtime_partition_state(
             binding_set,
             active_activation,
             partition_key,
             clock_mode,
             initial_time
           ) do
      case maybe_persist_runtime_records(persist_runtime_records?, runtime_records) do
        {:ok, pending_runtime_records} ->
          {:ok,
           %{
             mission_id: mission_id,
             partition_key: partition_key,
             active_activation: active_activation,
             binding_set: binding_set,
             runtime_binding_set: runtime_binding_set,
             managed_application_states: managed_application_states,
             timer_service: timer_service,
             tm_pipeline_state: tm_pipeline_state,
             tm_continuity_state: %{},
             tm_frame_remainder: <<>>,
             persist_runtime_records?: persist_runtime_records?,
             pending_runtime_records: pending_runtime_records,
             async_outputs: []
           }}

        {:error, reason} ->
          _ = TimerService.cancel_all(timer_service)
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
        snapshot = %{
          mission_id: state.mission_id,
          activation_id: state.active_activation.activation_id,
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
          tm_frame_remainder_bytes: byte_size(state.tm_frame_remainder),
          tm_packet_buffer_vcid_count:
            tm_vcid_count(state.tm_pipeline_state, :packet_buffers_by_vcid),
          tm_continuation_vcid_count:
            tm_vcid_count(state.tm_pipeline_state, :continuation_by_vcid),
          async_output_count: length(state.async_outputs)
        }

        {:reply, {:ok, snapshot}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:reconcile, %BindingSetActivation{} = activation, %BindingSet{} = binding_set},
        _from,
        state
      ) do
    state = refresh_live_clock(state)

    case build_runtime_partition_state(
           binding_set,
           activation,
           state.partition_key,
           state.timer_service.clock.mode,
           current_runtime_time(state)
         ) do
      {:ok, runtime_binding_set, managed_application_states, timer_service, runtime_records} ->
        previous_timer_events = build_timer_cancellation_records(state)

        case maybe_persist_runtime_records(
               state.persist_runtime_records?,
               merge_runtime_records(runtime_records, %{
                 capability_records: [],
                 action_requests: [],
                 timer_events: previous_timer_events
               })
             ) do
          {:ok, pending_runtime_records} ->
            _ = TimerService.cancel_all(state.timer_service)

            {:reply, :ok,
             %{
               state
               | active_activation: activation,
                 binding_set: binding_set,
                 runtime_binding_set: runtime_binding_set,
                 managed_application_states: managed_application_states,
                 timer_service: timer_service,
                 pending_runtime_records: pending_runtime_records,
                 async_outputs: []
             }}

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
      outputs = Enum.flat_map(dispatch_result.dispatch_results, & &1.outputs)
      dispatch_decisions = Enum.map(dispatch_result.dispatch_results, & &1.dispatch_decision)

      {:ok,
       %{
         raw_evidence: raw_evidence,
         packet_records: decode_result.packet_records,
         transfer_frame_records: decode_result.transfer_frame_records,
         protocol_anomalies: decode_result.protocol_anomalies,
         dispatch_decisions: dispatch_decisions,
         outputs: outputs,
         runtime_records: all_runtime_records
       }, %{next_state | pending_runtime_records: pending_runtime_records}}
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
         %BindingSet{} = binding_set,
         %BindingSetActivation{} = activation,
         %PartitionKey{} = partition_key,
         clock_mode,
         %DateTime{} = current_time
       ) do
    PartitionBuilder.build(binding_set, activation, partition_key, clock_mode, current_time)
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
           CapabilityRegistry.fetch_descriptor(work_item.handler_key) do
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
    with {:ok, handler_module} <- CapabilityRegistry.fetch_family(work_item.handler_key),
         {:ok, outputs} <- handler_module.handle(packet_record, work_item) do
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
         packet_record
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
          nil,
          timer_key
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
         %BindingSetActivation{} = activation,
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
         packet_record,
         timer_key \\ nil
       ) do
    RuntimeRecords.for_execution(
      event_kind,
      capability_instance,
      execution_context,
      execution_result,
      action_requests,
      timer_events,
      packet_record,
      timer_key
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

  defp tm_vcid_count(state, key) when is_map(state) and is_atom(key) do
    state
    |> Map.get(key, %{})
    |> map_size()
  end

  defp tm_vcid_count(_state, _key), do: 0

  defp default_initial_time(:replay, %BindingSetActivation{} = activation),
    do: activation.activated_at

  defp default_initial_time(_clock_mode, %BindingSetActivation{}), do: DateTime.utc_now()

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
    case next_due_timer_entry(state.timer_service, target_time) do
      nil ->
        {:ok, state, runtime_records}

      {capability_instance_id, timer_entry} ->
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
end
