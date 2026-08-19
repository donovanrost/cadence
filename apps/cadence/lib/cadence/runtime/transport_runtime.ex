# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Runtime.TransportRuntime do
  @moduledoc """
  Clock-aware runtime for one transport-local extension instance.
  """

  use GenServer

  alias Cadence.ActionRequests.{CancelTimer, ProviderRequest, ScheduleTimer, UplinkRequest}
  alias Cadence.Capabilities.{Descriptor, ExecutionContext, ExecutionResult}
  alias Cadence.Contacts.{CombinedDownlinkRecord, DownlinkDiagnostic, DownlinkObservation}
  alias Cadence.Ids
  alias Cadence.Runtime.Persistence

  alias Cadence.Runtime.{
    ActionExecutor,
    Clock,
    MissionRuntime,
    PartitionKey,
    TimerService,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  alias Cadence.ProviderAdapters

  alias Cadence.Runtime.CapabilityRegistry
  alias Cadence.Telemetry.Sample

  @type state :: %{
          mission_id: binary(),
          realized_contact_id: binary() | nil,
          path_id: binary() | nil,
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          capability_instance_id: binary(),
          family_key: atom(),
          configuration: term(),
          scope_ref: binary(),
          partition_key: PartitionKey.t(),
          timer_service: TimerService.t(),
          extension_state: term(),
          persist_runtime_records?: boolean(),
          lifecycle_status: :active | :quiesced,
          outputs: [term()]
        }

  @max_outputs 20

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    case runtime_name(opts) do
      nil -> GenServer.start_link(__MODULE__, opts)
      runtime_name -> GenServer.start_link(__MODULE__, opts, name: runtime_name)
    end
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(transport_runtime) do
    GenServer.call(transport_runtime, :snapshot)
  end

  @spec quiesce(pid()) :: {:ok, map()} | {:error, :noproc}
  def quiesce(transport_runtime) when is_pid(transport_runtime) do
    GenServer.call(transport_runtime, :quiesce, :infinity)
  catch
    :exit, {:noproc, _details} -> {:error, :noproc}
    :exit, {:normal, _details} -> {:error, :noproc}
  end

  @spec handle_transport_event(pid(), term(), keyword()) :: {:ok, [term()]} | {:error, term()}
  def handle_transport_event(transport_runtime, event, opts \\ []) when is_list(opts) do
    GenServer.call(
      transport_runtime,
      {:handle_transport_event, event, opts},
      Keyword.get(opts, :call_timeout, 5_000)
    )
  end

  @spec handle_control_input(pid(), term(), keyword()) :: {:ok, [term()]} | {:error, term()}
  def handle_control_input(transport_runtime, control_input, opts \\ []) when is_list(opts) do
    GenServer.call(transport_runtime, {:handle_control_input, control_input, opts})
  end

  @spec advance_time(pid(), DateTime.t()) :: :ok | {:error, term()}
  def advance_time(transport_runtime, %DateTime{} = target_time) do
    GenServer.call(transport_runtime, {:advance_time, target_time})
  end

  @spec stop(pid()) :: :ok
  def stop(transport_runtime) when is_pid(transport_runtime),
    do: GenServer.stop(transport_runtime)

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.get(opts, :realized_contact_id)
    path_id = Keyword.get(opts, :path_id)
    activation_id = Keyword.fetch!(opts, :activation_id)
    binding_set_id = Keyword.fetch!(opts, :binding_set_id)
    binding_set_version = Keyword.fetch!(opts, :binding_set_version)
    capability_instance_id = Keyword.fetch!(opts, :capability_instance_id)
    family_key = Keyword.fetch!(opts, :family_key)
    configuration = Keyword.fetch!(opts, :configuration)
    scope_ref = Keyword.fetch!(opts, :scope_ref)
    partition_key = Keyword.fetch!(opts, :partition_key)
    clock_mode = Keyword.get(opts, :clock_mode, :live)
    initial_time = Keyword.get(opts, :initial_time, DateTime.utc_now())

    persist_runtime_records? =
      Keyword.get_lazy(opts, :persist_runtime_records?, fn ->
        is_binary(realized_contact_id) and is_binary(path_id)
      end)

    timer_service = TimerService.new(mode: clock_mode, current_time: initial_time)

    with {:ok, %Descriptor{kind: :transport_extension}} <-
           CapabilityRegistry.fetch_descriptor(family_key),
         execution_context <-
           build_execution_context(%{
             mission_id: mission_id,
             activation_id: activation_id,
             binding_set_id: binding_set_id,
             binding_set_version: binding_set_version,
             capability_instance_id: capability_instance_id,
             scope_ref: scope_ref,
             partition_key: partition_key,
             current_time: TimerService.current_time(timer_service)
           }),
         {:ok, %ExecutionResult{} = execution_result} <-
           CapabilityRegistry.init_transport_extension(
             family_key,
             configuration,
             execution_context
           ),
         {:ok, %{timer_service: timer_service, timer_events: timer_events}} <-
           ActionExecutor.execute_many(
             execution_result.action_requests,
             capability_instance_id,
             timer_service
           ) do
      state = %{
        mission_id: mission_id,
        realized_contact_id: realized_contact_id,
        path_id: path_id,
        activation_id: activation_id,
        binding_set_id: binding_set_id,
        binding_set_version: binding_set_version,
        capability_instance_id: capability_instance_id,
        family_key: family_key,
        configuration: configuration,
        scope_ref: scope_ref,
        partition_key: partition_key,
        timer_service: timer_service,
        extension_state: execution_result.state,
        persist_runtime_records?: persist_runtime_records?,
        lifecycle_status: :active,
        outputs: execution_result.records
      }

      case persist_runtime_records(
             state,
             :initialized,
             execution_result,
             timer_events,
             %{interaction: :init}
           ) do
        :ok ->
          {:ok, state}

        {:error, reason} ->
          {:stop, reason}
      end
    else
      {:ok, %Descriptor{} = descriptor} ->
        {:stop, {:invalid_transport_extension_descriptor, descriptor.kind}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:quiesce, _from, state) do
    canceled_timer_count = TimerService.count(state.timer_service)

    state = %{
      state
      | lifecycle_status: :quiesced,
        timer_service: TimerService.cancel_all(state.timer_service)
    }

    {:reply,
     {:ok,
      %{
        status: :quiesced,
        capability_instance_id: state.capability_instance_id,
        canceled_timer_count: canceled_timer_count
      }}, state}
  end

  def handle_call(:snapshot, _from, state) do
    reply =
      with {:ok, snapshot_state} <-
             CapabilityRegistry.snapshot_transport_state(
               state.family_key,
               state.extension_state,
               execution_context(state)
             ) do
        {:ok,
         %{
           mission_id: state.mission_id,
           realized_contact_id: state.realized_contact_id,
           path_id: state.path_id,
           activation_id: state.activation_id,
           binding_set_id: state.binding_set_id,
           binding_set_version: state.binding_set_version,
           capability_instance_id: state.capability_instance_id,
           family_key: state.family_key,
           lifecycle_status: state.lifecycle_status,
           scope_ref: state.scope_ref,
           partition_key: PartitionKey.identifier(state.partition_key),
           clock_mode: state.timer_service.clock.mode,
           current_time: current_time(state),
           timer_count: TimerService.count(state.timer_service),
           timers: TimerService.snapshot(state.timer_service),
           state: snapshot_state,
           output_count: length(state.outputs),
           outputs: state.outputs
         }}
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_transport_event, _event, _opts},
        _from,
        %{lifecycle_status: :quiesced} = state
      ) do
    {:reply, {:error, :transport_runtime_quiesced}, state}
  end

  def handle_call({:handle_transport_event, event, opts}, _from, state) do
    reply =
      with {:ok, state} <- prepare_for_interaction(state, opts),
           {:ok, %ExecutionResult{} = execution_result} <-
             CapabilityRegistry.handle_transport_event(
               state.family_key,
               event,
               state.extension_state,
               execution_context(state)
             ),
           {:ok, state} <-
             apply_execution_result(
               state,
               :transport_event_handled,
               execution_result,
               %{interaction: :transport_event}
             ) do
        {:ok, execution_result.records, state}
      end

    case reply do
      {:ok, outputs, next_state} -> {:reply, {:ok, outputs}, next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:handle_control_input, _control_input, _opts},
        _from,
        %{lifecycle_status: :quiesced} = state
      ) do
    {:reply, {:error, :transport_runtime_quiesced}, state}
  end

  def handle_call({:handle_control_input, control_input, opts}, _from, state) do
    reply =
      with {:ok, state} <- prepare_for_interaction(state, opts),
           {:ok, %ExecutionResult{} = execution_result} <-
             CapabilityRegistry.handle_transport_control_input(
               state.family_key,
               control_input,
               state.extension_state,
               execution_context(state)
             ),
           {:ok, state} <-
             apply_execution_result(
               state,
               :control_input_handled,
               execution_result,
               %{interaction: :control_input}
             ) do
        {:ok, execution_result.records, state}
      end

    case reply do
      {:ok, outputs, next_state} -> {:reply, {:ok, outputs}, next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:advance_time, %DateTime{}},
        _from,
        %{lifecycle_status: :quiesced} = state
      ) do
    {:reply, {:error, :transport_runtime_quiesced}, state}
  end

  def handle_call({:advance_time, %DateTime{} = target_time}, _from, state) do
    case advance_to(state, target_time) do
      {:ok, next_state} -> {:reply, :ok, next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(
        {:managed_application_timer, _capability_instance_id, _timer_key, _timer_id},
        %{lifecycle_status: :quiesced} = state
      ) do
    {:noreply, state}
  end

  def handle_info(
        {:managed_application_timer, capability_instance_id, timer_key, timer_id},
        state
      ) do
    state = refresh_live_clock(state)

    case TimerService.fire(state.timer_service, capability_instance_id, timer_key, timer_id) do
      {:ok, timer_service, timer_entry} ->
        case execute_timer(%{state | timer_service: timer_service}, timer_key, timer_entry) do
          {:ok, next_state} -> {:noreply, next_state}
          {:error, reason} -> {:stop, reason, state}
        end

      {:error, :stale_timer} ->
        {:noreply, state}
    end
  end

  defp prepare_for_interaction(state, opts) do
    case state.timer_service.clock do
      %Clock{mode: :replay} ->
        target_time = Keyword.get(opts, :occurred_at, current_time(state))
        advance_to(state, target_time)

      %Clock{} ->
        {:ok, refresh_live_clock(state)}
    end
  end

  defp advance_to(state, %DateTime{} = target_time) do
    with {:ok, state} <- fire_due_timers_until(state, target_time) do
      {:ok, put_timer_service(state, TimerService.advance_to(state.timer_service, target_time))}
    end
  end

  defp fire_due_timers_until(state, %DateTime{} = target_time) do
    case next_due_timer_entry(state.timer_service, target_time) do
      nil ->
        {:ok, state}

      timer_entry ->
        advanced_timer_service =
          state.timer_service
          |> TimerService.advance_to(timer_entry.due_at)
          |> remove_timer_entry(timer_entry)

        state = put_timer_service(state, advanced_timer_service)

        case execute_timer(state, timer_entry.timer_key, timer_entry) do
          {:ok, next_state} -> fire_due_timers_until(next_state, target_time)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp execute_timer(state, timer_key, timer_entry) do
    with {:ok, %ExecutionResult{} = execution_result} <-
           CapabilityRegistry.handle_transport_timer(
             state.family_key,
             timer_key,
             state.extension_state,
             execution_context(
               state,
               %{
                 timer_key: timer_key,
                 timer_due_at: timer_entry.due_at,
                 timer_fired_at: current_time(state),
                 timer_metadata: timer_entry.metadata
               }
             )
           ) do
      apply_execution_result(
        state,
        :timer_handled,
        execution_result,
        %{
          interaction: :timer,
          timer_key: timer_key,
          timer_due_at: timer_entry.due_at
        }
        |> Map.merge(timer_entry.metadata),
        [
          %{
            event_kind: :fired,
            timer_key: timer_key,
            due_at: timer_entry.due_at,
            metadata: timer_entry.metadata
          }
        ]
      )
    end
  end

  defp apply_execution_result(
         state,
         event_kind,
         %ExecutionResult{} = execution_result,
         metadata,
         timer_event_prefix \\ []
       ) do
    case ActionExecutor.execute_many(
           execution_result.action_requests,
           state.capability_instance_id,
           state.timer_service
         ) do
      {:ok, %{timer_service: timer_service, timer_events: timer_events}} ->
        with {:ok, provider_delivery_metadata} <-
               deliver_provider_requests(state, execution_result.action_requests) do
          next_state = %{
            state
            | extension_state: execution_result.state,
              timer_service: timer_service,
              outputs: append_outputs(state.outputs, execution_result.records)
          }

          all_timer_events = timer_event_prefix ++ timer_events

          merged_metadata =
            metadata
            |> Map.new()
            |> Map.merge(Map.new(execution_result.metadata || %{}))
            |> Map.merge(provider_delivery_metadata)

          case persist_runtime_records(
                 next_state,
                 event_kind,
                 execution_result,
                 all_timer_events,
                 merged_metadata
               ) do
            :ok -> {:ok, next_state}
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deliver_provider_requests(state, action_requests) do
    action_requests
    |> Enum.filter(&match?(%ProviderRequest{}, &1))
    |> Enum.reduce_while({:ok, []}, fn %ProviderRequest{} = provider_request, {:ok, acc} ->
      case ProviderAdapters.deliver_uplink(
             state.mission_id,
             state.realized_contact_id,
             state.path_id,
             provider_request
           ) do
        {:ok, delivery_metadata} ->
          {:cont, {:ok, acc ++ [delivery_metadata]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, []} ->
        {:ok, %{}}

      {:ok, delivery_results} ->
        {:ok, %{provider_delivery_results: delivery_results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execution_context(state, metadata \\ %{}) do
    build_execution_context(
      %{
        mission_id: state.mission_id,
        activation_id: state.activation_id,
        binding_set_id: state.binding_set_id,
        binding_set_version: state.binding_set_version,
        capability_instance_id: state.capability_instance_id,
        scope_ref: state.scope_ref,
        partition_key: state.partition_key,
        current_time: current_time(state)
      },
      metadata
    )
  end

  defp build_execution_context(
         %{
           mission_id: mission_id,
           activation_id: activation_id,
           binding_set_id: binding_set_id,
           binding_set_version: binding_set_version,
           capability_instance_id: capability_instance_id,
           scope_ref: scope_ref,
           partition_key: partition_key,
           current_time: current_time
         },
         metadata \\ %{}
       ) do
    ExecutionContext.new(%{
      mission_id: mission_id,
      activation_id: activation_id,
      binding_set_id: binding_set_id,
      binding_set_version: binding_set_version,
      current_time: current_time,
      partition_key: partition_key,
      capability_instance_id: capability_instance_id,
      scope_ref: scope_ref,
      metadata: metadata
    })
  end

  defp persist_runtime_records(
         %{persist_runtime_records?: false},
         _event_kind,
         %ExecutionResult{},
         _timer_events,
         _metadata
       ),
       do: :ok

  defp persist_runtime_records(
         %{
           realized_contact_id: realized_contact_id,
           path_id: path_id
         } = state,
         event_kind,
         %ExecutionResult{} = execution_result,
         timer_events,
         metadata
       )
       when is_binary(realized_contact_id) and is_binary(path_id) do
    capability_record =
      %TransportCapabilityRecord{
        transport_record_id: Ids.new("transport_record"),
        mission_id: state.mission_id,
        realized_contact_id: realized_contact_id,
        path_id: path_id,
        capability_instance_id: state.capability_instance_id,
        family_key: state.family_key,
        activation_id: state.activation_id,
        binding_set_id: state.binding_set_id,
        binding_set_version: state.binding_set_version,
        partition_affinity: state.partition_key.affinity,
        partition_value: state.partition_key.value,
        event_kind: event_kind,
        timer_key: Map.get(metadata, :timer_key),
        emitted_record_kinds: Enum.map(execution_result.records, &record_kind/1),
        emitted_record_count: length(execution_result.records),
        action_request_count: length(execution_result.action_requests),
        state_snapshot: execution_result.state,
        recorded_at: current_time(state),
        metadata: metadata
      }

    action_requests =
      Enum.map(execution_result.action_requests, fn action_request ->
        %TransportActionRequest{
          action_request_id: Ids.new("transport_action_request"),
          mission_id: state.mission_id,
          realized_contact_id: realized_contact_id,
          path_id: path_id,
          capability_instance_id: state.capability_instance_id,
          family_key: state.family_key,
          activation_id: state.activation_id,
          binding_set_id: state.binding_set_id,
          binding_set_version: state.binding_set_version,
          partition_affinity: state.partition_key.affinity,
          partition_value: state.partition_key.value,
          command_release_attempt_id: command_release_attempt_id(action_request),
          command_request_id: command_request_id(action_request),
          source_endpoint_ref: source_endpoint_ref(action_request),
          command_name: command_name(action_request),
          signal_phase: signal_phase(action_request),
          action_kind: action_kind(action_request),
          request_document: action_request_document(action_request),
          requested_at: current_time(state),
          metadata: metadata
        }
      end)

    timer_events =
      Enum.map(timer_events, fn timer_event ->
        %TransportTimerEvent{
          timer_event_id: Ids.new("transport_timer_event"),
          mission_id: state.mission_id,
          realized_contact_id: realized_contact_id,
          path_id: path_id,
          capability_instance_id: state.capability_instance_id,
          family_key: state.family_key,
          activation_id: state.activation_id,
          binding_set_id: state.binding_set_id,
          binding_set_version: state.binding_set_version,
          partition_affinity: state.partition_key.affinity,
          partition_value: state.partition_key.value,
          timer_key: timer_event.timer_key,
          event_kind: timer_event.event_kind,
          due_at: timer_event.due_at,
          occurred_at: current_time(state),
          metadata: timer_event.metadata
        }
      end)

    Persistence.persist_transport_runtime_records(
      [capability_record],
      action_requests,
      timer_events
    )
  end

  defp current_time(state), do: TimerService.current_time(state.timer_service)

  defp record_kind(%Sample{}), do: :telemetry_sample
  defp record_kind(%DownlinkObservation{}), do: :downlink_observation
  defp record_kind(%CombinedDownlinkRecord{}), do: :combined_downlink_record
  defp record_kind(%DownlinkDiagnostic{}), do: :downlink_diagnostic
  defp record_kind(_output), do: :unknown

  defp action_kind(%ScheduleTimer{}), do: :schedule_timer
  defp action_kind(%CancelTimer{}), do: :cancel_timer
  defp action_kind(%UplinkRequest{}), do: :uplink_request
  defp action_kind(%ProviderRequest{}), do: :provider_request
  defp action_kind(_action_request), do: :unknown

  defp command_release_attempt_id(%UplinkRequest{} = action_request),
    do: action_request.command_release_attempt_id

  defp command_release_attempt_id(%ProviderRequest{} = action_request),
    do: action_request.command_release_attempt_id

  defp command_release_attempt_id(_action_request), do: nil

  defp command_request_id(%UplinkRequest{} = action_request),
    do: action_request.command_request_id

  defp command_request_id(%ProviderRequest{} = action_request),
    do: action_request.command_request_id

  defp command_request_id(_action_request), do: nil

  defp source_endpoint_ref(%UplinkRequest{} = action_request),
    do: action_request.source_endpoint_ref

  defp source_endpoint_ref(%ProviderRequest{} = action_request),
    do: action_request.source_endpoint_ref

  defp source_endpoint_ref(_action_request), do: nil

  defp command_name(%UplinkRequest{} = action_request), do: action_request.command_name
  defp command_name(%ProviderRequest{} = action_request), do: action_request.command_name
  defp command_name(_action_request), do: nil

  defp signal_phase(%UplinkRequest{}), do: :acceptance
  defp signal_phase(_action_request), do: nil

  defp action_request_document(%ScheduleTimer{} = action_request) do
    %{
      timer_key: action_request.timer_key,
      delay_ms: action_request.delay_ms,
      metadata: action_request.metadata
    }
  end

  defp action_request_document(%CancelTimer{} = action_request) do
    %{timer_key: action_request.timer_key}
  end

  defp action_request_document(%UplinkRequest{} = action_request) do
    %{
      command_release_attempt_id: action_request.command_release_attempt_id,
      command_queue_entry_id: action_request.command_queue_entry_id,
      command_request_id: action_request.command_request_id,
      source_endpoint_ref: action_request.source_endpoint_ref,
      mission_model_revision_id: action_request.mission_model_revision_id,
      command_id: action_request.command_id,
      command_name: action_request.command_name,
      layout_kind:
        case action_request.layout_kind do
          nil -> nil
          layout_kind -> Atom.to_string(layout_kind)
        end,
      preferred_uplink_service: action_request.preferred_uplink_service,
      apid: action_request.apid,
      service_type: action_request.service_type,
      service_subtype: action_request.service_subtype,
      opcode: action_request.opcode,
      encoded_binary_base64: action_request.encoded_binary_base64,
      encoded_size_bytes: action_request.encoded_size_bytes,
      transport_profile:
        case action_request.transport_profile do
          nil -> nil
          transport_profile -> Atom.to_string(transport_profile)
        end,
      transfer_frames_base64: action_request.transfer_frames_base64,
      transfer_frame_count: action_request.transfer_frame_count,
      transfer_frame_size_bytes: action_request.transfer_frame_size_bytes,
      first_frame_seq: action_request.first_frame_seq,
      last_frame_seq: action_request.last_frame_seq,
      scid: action_request.scid,
      vcid: action_request.vcid,
      bypass_flag: action_request.bypass_flag,
      control_command_flag: action_request.control_command_flag,
      segment_header_flag: action_request.segment_header_flag,
      metadata: action_request.metadata
    }
  end

  defp action_request_document(%ProviderRequest{} = action_request) do
    %{
      provider_binding_id: action_request.provider_binding_id,
      provider_adapter_key: Atom.to_string(action_request.provider_adapter_key),
      command_release_attempt_id: action_request.command_release_attempt_id,
      command_queue_entry_id: action_request.command_queue_entry_id,
      command_request_id: action_request.command_request_id,
      source_endpoint_ref: action_request.source_endpoint_ref,
      mission_model_revision_id: action_request.mission_model_revision_id,
      command_id: action_request.command_id,
      command_name: action_request.command_name,
      transport_profile:
        case action_request.transport_profile do
          nil -> nil
          transport_profile -> Atom.to_string(transport_profile)
        end,
      payloads_base64: action_request.payloads_base64,
      payload_count: action_request.payload_count,
      payload_size_bytes: action_request.payload_size_bytes,
      metadata: action_request.metadata
    }
  end

  defp action_request_document(action_request) do
    %{request: inspect(action_request)}
  end

  defp append_outputs(outputs, []), do: outputs
  defp append_outputs(outputs, new_outputs), do: Enum.take(outputs ++ new_outputs, -@max_outputs)

  defp refresh_live_clock(state) do
    if TimerService.live?(state.timer_service) do
      put_timer_service(
        state,
        TimerService.set_current_time(state.timer_service, DateTime.utc_now())
      )
    else
      state
    end
  end

  defp put_timer_service(state, %TimerService{} = timer_service) do
    %{state | timer_service: timer_service}
  end

  defp next_due_timer_entry(%TimerService{} = timer_service, %DateTime{} = target_time) do
    timer_service.timers
    |> Map.values()
    |> Enum.filter(fn entry ->
      DateTime.compare(entry.due_at, target_time) != :gt
    end)
    |> Enum.sort_by(&{&1.due_at, &1.capability_instance_id, &1.timer_key})
    |> List.first()
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

  defp runtime_name(opts) do
    with mission_id when is_binary(mission_id) <- Keyword.get(opts, :mission_id),
         realized_contact_id when is_binary(realized_contact_id) <-
           Keyword.get(opts, :realized_contact_id),
         path_id when is_binary(path_id) <- Keyword.get(opts, :path_id),
         capability_instance_id when is_binary(capability_instance_id) <-
           Keyword.get(opts, :capability_instance_id) do
      MissionRuntime.transport_runtime_name(
        mission_id,
        realized_contact_id,
        path_id,
        capability_instance_id
      )
    else
      _missing_context -> nil
    end
  end
end
