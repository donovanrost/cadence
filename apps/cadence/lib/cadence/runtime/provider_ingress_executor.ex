defmodule Cadence.Runtime.ProviderIngressExecutor do
  @moduledoc """
  Path-local ordered ingress executor for provider-delivered downlink messages.

  Providers should adapt external transport I/O into canonical ingress message
  units, then enqueue them here. This process owns the heavier mission-facing
  work such as telemetry processing and path transport-event handling.
  """

  use GenServer

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime, as: RuntimeBoundary
  alias Cadence.Runtime.{IngressPersistenceProjector, ProcessedIngressBatch}
  alias Cadence.SourceEndpoints
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @max_drain_batch 512
  @projector_high_watermark 8_192
  @projector_low_watermark 2_048
  @projector_capacity_retry_ms 1_000
  @event_prefix [:cadence, :runtime, :provider_ingress_executor]

  @type executor_item ::
          {:telemetry, RawEvidence.t()}
          | {:transport_event, binary(), term(), keyword()}

  @type state :: %{
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          provider_binding_id: binary(),
          persistence_projector_name: GenServer.server(),
          persistence_projector_pid: pid() | nil,
          persistence_projector_monitor_ref: reference() | nil,
          projector_backpressured?: boolean(),
          projector_capacity_wait_ref: reference() | nil,
          pending_persistence_batches: [ProcessedIngressBatch.t()],
          queue: :queue.queue(executor_item()),
          queue_depth: non_neg_integer(),
          processing?: boolean(),
          enqueued_count: non_neg_integer(),
          processed_count: non_neg_integer(),
          failed_count: non_neg_integer(),
          telemetry_count: non_neg_integer(),
          transport_event_count: non_neg_integer(),
          last_completed_at: DateTime.t() | nil,
          last_error: binary() | nil,
          capacity_waiters: %{optional(reference()) => map()}
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: {:provider_ingress_executor, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec enqueue_telemetry(GenServer.server(), RawEvidence.t()) :: :ok | {:error, term()}
  def enqueue_telemetry(executor, %RawEvidence{} = raw_evidence) do
    enqueue(executor, {:telemetry, raw_evidence})
  end

  @spec enqueue_many_telemetry(GenServer.server(), [RawEvidence.t()]) :: :ok | {:error, term()}
  def enqueue_many_telemetry(executor, raw_evidences) when is_list(raw_evidences) do
    items = Enum.map(raw_evidences, &{:telemetry, &1})
    enqueue_many(executor, items)
  end

  @spec enqueue_transport_event(GenServer.server(), binary(), term(), keyword()) ::
          :ok | {:error, term()}
  def enqueue_transport_event(executor, transport_binding_id, event, opts \\ [])
      when is_binary(transport_binding_id) and is_list(opts) do
    enqueue(executor, {:transport_event, transport_binding_id, event, opts})
  end

  @spec enqueue_many_transport_events(GenServer.server(), binary(), [term()], keyword()) ::
          :ok | {:error, term()}
  def enqueue_many_transport_events(executor, transport_binding_id, events, opts \\ [])
      when is_binary(transport_binding_id) and is_list(events) and is_list(opts) do
    items = Enum.map(events, &{:transport_event, transport_binding_id, &1, opts})
    enqueue_many(executor, items)
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def snapshot(executor) do
    call_if_running(executor, :snapshot)
  end

  @spec notify_when_below(GenServer.server(), non_neg_integer(), pid(), reference()) ::
          :ok | {:error, term()}
  def notify_when_below(executor, threshold, subscriber_pid, ref)
      when is_integer(threshold) and threshold >= 0 and is_pid(subscriber_pid) and
             is_reference(ref) do
    call_if_running(executor, {:notify_when_below, threshold, subscriber_pid, ref})
  end

  @spec cancel_notify_when_below(GenServer.server(), reference()) :: :ok | {:error, term()}
  def cancel_notify_when_below(executor, ref) when is_reference(ref) do
    call_if_running(executor, {:cancel_notify_when_below, ref})
  end

  @spec lookup(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def lookup(server)

  def lookup(server) when is_pid(server) do
    if Process.alive?(server) do
      {:ok, server}
    else
      {:error, :provider_ingress_executor_not_running}
    end
  end

  def lookup(server) do
    case GenServer.whereis(server) do
      nil -> {:error, :provider_ingress_executor_not_running}
      pid when is_pid(pid) -> {:ok, pid}
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       mission_id: Keyword.fetch!(opts, :mission_id),
       realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
       path_id: Keyword.fetch!(opts, :path_id),
       provider_binding_id: Keyword.fetch!(opts, :provider_binding_id),
       persistence_projector_name: Keyword.fetch!(opts, :persistence_projector_name),
       persistence_projector_pid: nil,
       persistence_projector_monitor_ref: nil,
       projector_backpressured?: false,
       projector_capacity_wait_ref: nil,
       pending_persistence_batches: [],
       queue: :queue.new(),
       queue_depth: 0,
       processing?: false,
       enqueued_count: 0,
       processed_count: 0,
       failed_count: 0,
       telemetry_count: 0,
       transport_event_count: 0,
       last_completed_at: nil,
       last_error: nil,
       capacity_waiters: %{}
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply,
     {:ok,
      %{
        provider_binding_id: state.provider_binding_id,
        queue_depth: state.queue_depth,
        processing?: state.processing?,
        backpressured?: state.projector_backpressured?,
        projector_backpressured?: state.projector_backpressured?,
        projector_capacity_waiting?: is_reference(state.projector_capacity_wait_ref),
        pending_persistence_batch_count: length(state.pending_persistence_batches),
        enqueued_count: state.enqueued_count,
        processed_count: state.processed_count,
        failed_count: state.failed_count,
        telemetry_count: state.telemetry_count,
        transport_event_count: state.transport_event_count,
        capacity_waiter_count: map_size(state.capacity_waiters),
        last_completed_at: state.last_completed_at,
        last_error: state.last_error
      }}, state}
  end

  def handle_call({:notify_when_below, threshold, subscriber_pid, ref}, _from, state) do
    state =
      if state.queue_depth < threshold do
        state = remove_capacity_waiter(state, ref)
        notify_capacity_waiter(subscriber_pid, ref, state.queue_depth)
        state
      else
        put_capacity_waiter(state, threshold, subscriber_pid, ref)
      end

    {:reply, :ok, state}
  end

  def handle_call({:cancel_notify_when_below, ref}, _from, state) do
    {:reply, :ok, remove_capacity_waiter(state, ref)}
  end

  @impl true
  def handle_cast({:enqueue, item}, state) do
    next_state = enqueue_items(state, [item])

    if state.processing? do
      {:noreply, next_state}
    else
      send(self(), :process_queue)
      {:noreply, %{next_state | processing?: true}}
    end
  end

  def handle_cast({:enqueue_many, items}, state) do
    case items do
      [] ->
        {:noreply, state}

      _non_empty ->
        next_state = enqueue_items(state, items)

        if state.processing? do
          {:noreply, next_state}
        else
          send(self(), :process_queue)
          {:noreply, %{next_state | processing?: true}}
        end
    end
  end

  @impl true
  def handle_info(:process_queue, state) do
    case flush_pending_persistence_batches(state) do
      {:ok, ready_state} ->
        case maybe_gate_on_projector_pressure(ready_state) do
          {:ok, schedulable_state} ->
            process_schedulable_queue_state(schedulable_state)

          {:blocked, blocked_state} ->
            {:noreply, %{blocked_state | processing?: true}}
        end

      {:error, retry_state} ->
        {:noreply, %{retry_state | processing?: true}}
    end
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, projector_pid, reason},
        %{
          persistence_projector_monitor_ref: monitor_ref,
          persistence_projector_pid: projector_pid
        } = state
      ) do
    Logger.warning(
      "Provider ingress persistence projector exited for #{state.provider_binding_id}: #{inspect(reason)}"
    )

    {:noreply,
     %{
       state
       | persistence_projector_pid: nil,
         persistence_projector_monitor_ref: nil,
         projector_capacity_wait_ref: nil
     }}
  end

  def handle_info(
        {:ingress_persistence_capacity_available, projector_pid, ref, queue_depth},
        %{persistence_projector_pid: projector_pid, projector_capacity_wait_ref: ref} = state
      ) do
    emit(:capacity_waiter_released, state, %{queue_depth: state.queue_depth}, %{
      downstream: :ingress_persistence_projector,
      downstream_queue_depth: queue_depth
    })

    send(self(), :process_queue)
    {:noreply, %{state | projector_capacity_wait_ref: nil, processing?: true}}
  end

  def handle_info(
        {:ingress_persistence_capacity_available, _projector_pid, _stale_ref, _queue_depth},
        state
      ) do
    {:noreply, state}
  end

  def handle_info({:projector_capacity_check, ref}, %{projector_capacity_wait_ref: ref} = state) do
    state = cancel_projector_capacity_waiter(state, ref)
    send(self(), :process_queue)
    {:noreply, %{state | projector_capacity_wait_ref: nil, processing?: true}}
  end

  def handle_info({:projector_capacity_check, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, remove_capacity_waiter_by_monitor(state, monitor_ref)}
  end

  defp enqueue(executor, item) do
    with {:ok, pid} <- lookup(executor) do
      GenServer.cast(pid, {:enqueue, item})
      :ok
    end
  end

  defp enqueue_many(executor, items) do
    with {:ok, pid} <- lookup(executor) do
      GenServer.cast(pid, {:enqueue_many, items})
      :ok
    end
  end

  defp call_if_running(server, request) do
    with {:ok, pid} <- lookup(server) do
      GenServer.call(pid, request)
    end
  end

  defp enqueue_items(state, items) do
    {queue, count} =
      Enum.reduce(items, {state.queue, 0}, fn item, {queue, count} ->
        {:queue.in(item, queue), count + 1}
      end)

    %{
      state
      | queue: queue,
        queue_depth: state.queue_depth + count,
        enqueued_count: state.enqueued_count + count
    }
  end

  defp drain_batch(state, 0, current_batch, batches) do
    {state, Enum.reverse(finalize_persistence_batches(state, current_batch, batches))}
  end

  defp drain_batch(state, remaining, current_batch, batches) do
    case :queue.out(state.queue) do
      {{:value, {:transport_event, _, _, _}}, _rest} when current_batch != [] ->
        {state, Enum.reverse(finalize_persistence_batches(state, current_batch, batches))}

      {{:value, item}, rest} ->
        base_state =
          state
          |> Map.put(:queue, rest)
          |> Map.put(:queue_depth, state.queue_depth - 1)

        case execute_item(item) do
          {:ok, {:telemetry, processing_result}} ->
            next_state = apply_execution_result(base_state, {:ok, :telemetry})
            drain_batch(next_state, remaining - 1, [processing_result | current_batch], batches)

          {:ok, :transport_event} ->
            next_state = apply_execution_result(base_state, {:ok, :transport_event})

            drain_batch(
              next_state,
              remaining - 1,
              [],
              finalize_persistence_batches(next_state, current_batch, batches)
            )

          {:error, kind, reason} ->
            next_state = apply_execution_result(base_state, {:error, kind, reason})
            drain_batch(next_state, remaining - 1, current_batch, batches)
        end

      {:empty, _queue} ->
        {%{state | queue_depth: 0},
         Enum.reverse(finalize_persistence_batches(state, current_batch, batches))}
    end
  end

  defp execute_item({:telemetry, %RawEvidence{} = raw_evidence}) do
    case run_ingress(fn -> process_telemetry_item(raw_evidence) end) do
      {:ok, {:ok, processing_result}} -> {:ok, {:telemetry, processing_result}}
      {:ok, {:error, reason}} -> {:error, :telemetry, inspect(reason)}
      {:crash, reason} -> {:error, :telemetry, reason}
    end
  end

  defp execute_item({:transport_event, transport_binding_id, event, opts}) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    path_id = Keyword.fetch!(opts, :path_id)
    call_opts = Keyword.drop(opts, [:mission_id, :realized_contact_id, :path_id])

    case run_ingress(fn ->
           Cadence.handle_path_transport_event(
             mission_id,
             realized_contact_id,
             path_id,
             transport_binding_id,
             event,
             call_opts
           )
         end) do
      {:ok, {:ok, _outputs}} -> {:ok, :transport_event}
      {:ok, {:error, reason}} -> {:error, :transport_event, inspect(reason)}
      {:crash, reason} -> {:error, :transport_event, reason}
    end
  end

  defp apply_execution_result(state, {:ok, :telemetry}) do
    %{
      state
      | processed_count: state.processed_count + 1,
        telemetry_count: state.telemetry_count + 1,
        last_completed_at: DateTime.utc_now(),
        last_error: nil
    }
  end

  defp apply_execution_result(state, {:ok, :transport_event}) do
    %{
      state
      | processed_count: state.processed_count + 1,
        transport_event_count: state.transport_event_count + 1,
        last_completed_at: DateTime.utc_now(),
        last_error: nil
    }
  end

  defp apply_execution_result(state, {:error, kind, reason}) do
    Logger.warning(
      "Provider ingress executor failed for #{state.provider_binding_id} (#{kind}): #{reason}"
    )

    %{
      state
      | failed_count: state.failed_count + 1,
        last_completed_at: DateTime.utc_now(),
        last_error: reason
    }
  end

  defp process_telemetry_item(%RawEvidence{} = raw_evidence) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      ingress_started_at = System.monotonic_time()

      resolve_result =
        TelemetryProfiler.with_stage(:resolve, fn ->
          SourceEndpoints.resolve_raw_evidence(raw_evidence)
        end)

      resolve_us = elapsed_us(ingress_started_at)

      case resolve_result do
        {:ok, %RawEvidence{} = resolved_raw_evidence} ->
          handle_resolved_telemetry_item(
            resolved_raw_evidence,
            ingress_started_at,
            resolve_us
          )

        {:error, reason} ->
          TelemetryProfiler.record_ingress_result(
            raw_evidence,
            resolve_us: resolve_us,
            end_to_end_us: elapsed_us(ingress_started_at),
            error?: true
          )

          {:error, reason}
      end
    end)
  end

  defp process_schedulable_queue_state(schedulable_state) do
    {next_state, persistence_batches} = drain_batch(schedulable_state, @max_drain_batch, [], [])
    next_state = notify_capacity_waiters(next_state)

    case enqueue_persistence_batches(next_state, persistence_batches) do
      {:ok, persisted_state} ->
        continue_processing_queue(persisted_state)

      {:error, retry_state} ->
        {:noreply, %{retry_state | processing?: true}}
    end
  end

  defp continue_processing_queue(persisted_state) do
    if persisted_state.queue_depth > 0 do
      send(self(), :process_queue)
      {:noreply, %{persisted_state | processing?: true}}
    else
      {:noreply, %{persisted_state | processing?: false}}
    end
  end

  defp put_capacity_waiter(state, threshold, subscriber_pid, ref) do
    case Map.get(state.capacity_waiters, ref) do
      %{monitor_ref: monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])

      _other ->
        :ok
    end

    waiter = %{
      threshold: threshold,
      subscriber_pid: subscriber_pid,
      monitor_ref: Process.monitor(subscriber_pid)
    }

    emit(:capacity_waiter_registered, state, %{queue_depth: state.queue_depth}, %{
      downstream: :provider_ingress_executor,
      threshold: threshold
    })

    put_in(state.capacity_waiters[ref], waiter)
  end

  defp notify_capacity_waiters(%{capacity_waiters: waiters} = state) when map_size(waiters) == 0,
    do: state

  defp notify_capacity_waiters(state) do
    {ready_waiters, waiting_waiters} =
      Enum.split_with(state.capacity_waiters, fn {_ref, %{threshold: threshold}} ->
        state.queue_depth < threshold
      end)

    Enum.each(ready_waiters, fn {ref, %{subscriber_pid: subscriber_pid, monitor_ref: monitor_ref}} ->
      Process.demonitor(monitor_ref, [:flush])
      notify_capacity_waiter(subscriber_pid, ref, state.queue_depth)
    end)

    if ready_waiters != [] do
      emit(:capacity_waiter_released, state, %{queue_depth: state.queue_depth}, %{
        downstream: :provider_ingress_executor,
        released_count: length(ready_waiters)
      })
    end

    %{state | capacity_waiters: Map.new(waiting_waiters)}
  end

  defp notify_capacity_waiter(subscriber_pid, ref, queue_depth) do
    send(subscriber_pid, {:provider_ingress_capacity_available, self(), ref, queue_depth})
  end

  defp remove_capacity_waiter_by_monitor(state, monitor_ref) do
    capacity_waiters =
      state.capacity_waiters
      |> Enum.reject(fn {_ref, waiter} -> waiter.monitor_ref == monitor_ref end)
      |> Map.new()

    %{state | capacity_waiters: capacity_waiters}
  end

  defp remove_capacity_waiter(state, ref) do
    case Map.pop(state.capacity_waiters, ref) do
      {%{monitor_ref: monitor_ref}, capacity_waiters} ->
        Process.demonitor(monitor_ref, [:flush])
        %{state | capacity_waiters: capacity_waiters}

      {nil, _capacity_waiters} ->
        state
    end
  end

  defp handle_resolved_telemetry_item(
         %RawEvidence{} = resolved_raw_evidence,
         ingress_started_at,
         resolve_us
       ) do
    runtime_started_at = System.monotonic_time()
    runtime_result = process_telemetry_runtime(resolved_raw_evidence)
    runtime_us = elapsed_us(runtime_started_at)

    case runtime_result do
      {:ok, processing_result} ->
        finalize_processed_telemetry_item(
          resolved_raw_evidence,
          processing_result,
          ingress_started_at,
          resolve_us,
          runtime_us
        )

      {:error, reason} ->
        TelemetryProfiler.record_ingress_result(
          resolved_raw_evidence,
          resolve_us: resolve_us,
          runtime_us: runtime_us,
          end_to_end_us: elapsed_us(ingress_started_at),
          error?: true
        )

        {:error, reason}
    end
  end

  defp process_telemetry_runtime(%RawEvidence{} = resolved_raw_evidence) do
    TelemetryProfiler.with_runtime_component(
      resolved_raw_evidence.mission_id,
      :runtime_boundary,
      fn ->
        TelemetryProfiler.with_stage(:runtime, fn ->
          RuntimeBoundary.process_telemetry_ingress(resolved_raw_evidence)
        end)
      end
    )
  end

  defp finalize_processed_telemetry_item(
         %RawEvidence{} = resolved_raw_evidence,
         processing_result,
         ingress_started_at,
         resolve_us,
         runtime_us
       ) do
    with {:ok, telemetry_samples} <-
           extract_telemetry_samples(resolved_raw_evidence.mission_id, processing_result),
         :ok <-
           maybe_record_current_values(
             resolved_raw_evidence.mission_id,
             telemetry_samples
           ) do
      TelemetryProfiler.record_ingress_result(
        resolved_raw_evidence,
        resolve_us: resolve_us,
        runtime_us: runtime_us,
        end_to_end_us: elapsed_us(ingress_started_at),
        error?: false,
        processing_result: processing_result
      )

      {:ok, processing_result}
    else
      {:error, reason} ->
        TelemetryProfiler.record_ingress_result(
          resolved_raw_evidence,
          resolve_us: resolve_us,
          runtime_us: runtime_us,
          end_to_end_us: elapsed_us(ingress_started_at),
          error?: true,
          processing_result: processing_result
        )

        {:error, reason}
    end
  end

  defp extract_telemetry_samples(mission_id, processing_result) do
    TelemetryProfiler.with_runtime_component(
      mission_id,
      :telemetry_sample_extraction,
      fn ->
        Cadence.Persistence.telemetry_samples(processing_result.outputs)
      end
    )
  end

  defp maybe_record_current_values(_mission_id, telemetry_samples) when telemetry_samples == [],
    do: :ok

  defp maybe_record_current_values(mission_id, telemetry_samples) do
    if CurrentValueStore.hot_path_safe?() do
      TelemetryProfiler.with_runtime_component(mission_id, :current_value_record, fn ->
        CurrentValueStore.record_samples(telemetry_samples)
      end)
    else
      :ok
    end
  end

  defp elapsed_us(started_at) do
    System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)
  end

  defp finalize_persistence_batches(_state, [], batches), do: batches

  defp finalize_persistence_batches(state, current_batch, batches) do
    [build_persistence_batch(state, current_batch) | batches]
  end

  defp build_persistence_batch(state, current_batch) do
    ProcessedIngressBatch.new(%{
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      path_id: state.path_id,
      provider_binding_id: state.provider_binding_id,
      processing_results: Enum.reverse(current_batch)
    })
  end

  defp enqueue_persistence_batch(state, %ProcessedIngressBatch{} = batch) do
    with {:ok, next_state} <- ensure_persistence_projector(state),
         :ok <- IngressPersistenceProjector.enqueue(next_state.persistence_projector_pid, batch) do
      {:ok, next_state}
    end
  end

  defp flush_pending_persistence_batches(%{pending_persistence_batches: []} = state),
    do: {:ok, state}

  defp flush_pending_persistence_batches(state) do
    state
    |> Map.put(:pending_persistence_batches, [])
    |> enqueue_persistence_batches(state.pending_persistence_batches)
  end

  defp enqueue_persistence_batches(state, []), do: {:ok, state}

  defp enqueue_persistence_batches(state, [%ProcessedIngressBatch{} = batch | rest]) do
    case enqueue_persistence_batch(state, batch) do
      {:ok, next_state} ->
        enqueue_persistence_batches(next_state, rest)

      {:error, reason} ->
        retry_state =
          state
          |> Map.put(:pending_persistence_batches, [batch | rest])
          |> apply_execution_result({:error, :telemetry_persistence_enqueue, inspect(reason)})

        Process.send_after(self(), :process_queue, 50)
        {:error, retry_state}
    end
  end

  defp ensure_persistence_projector(%{persistence_projector_pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      {:ok, state}
    else
      resolve_persistence_projector(%{
        state
        | persistence_projector_pid: nil,
          persistence_projector_monitor_ref: nil
      })
    end
  end

  defp ensure_persistence_projector(state), do: resolve_persistence_projector(state)

  defp maybe_gate_on_projector_pressure(state) do
    with {:ok, next_state} <- ensure_persistence_projector(state),
         {:ok, snapshot} <-
           IngressPersistenceProjector.snapshot(next_state.persistence_projector_pid) do
      queue_depth = Map.get(snapshot, :queue_depth, 0)

      threshold =
        if next_state.projector_backpressured? do
          @projector_low_watermark
        else
          @projector_high_watermark
        end

      if queue_depth >= threshold do
        state =
          next_state
          |> maybe_emit_projector_backpressure_entered(queue_depth)
          |> register_projector_capacity_waiter()
          |> Map.put(:projector_backpressured?, true)

        {:blocked, state}
      else
        state =
          next_state
          |> maybe_emit_projector_backpressure_released(queue_depth)
          |> Map.put(:projector_backpressured?, false)

        {:ok, state}
      end
    end
  end

  defp register_projector_capacity_waiter(%{projector_capacity_wait_ref: ref} = state)
       when is_reference(ref) do
    state
  end

  defp register_projector_capacity_waiter(state) do
    ref = make_ref()

    _ =
      IngressPersistenceProjector.notify_when_below(
        state.persistence_projector_pid,
        @projector_low_watermark,
        self(),
        ref
      )

    Process.send_after(self(), {:projector_capacity_check, ref}, @projector_capacity_retry_ms)

    emit(:capacity_waiter_registered, state, %{queue_depth: state.queue_depth}, %{
      downstream: :ingress_persistence_projector,
      downstream_low_watermark: @projector_low_watermark
    })

    %{state | projector_capacity_wait_ref: ref}
  end

  defp cancel_projector_capacity_waiter(%{persistence_projector_pid: pid} = state, ref)
       when is_pid(pid) and is_reference(ref) do
    _ = IngressPersistenceProjector.cancel_notify_when_below(pid, ref)
    state
  end

  defp cancel_projector_capacity_waiter(state, _ref), do: state

  defp maybe_emit_projector_backpressure_entered(
         %{projector_backpressured?: false} = state,
         downstream_queue_depth
       ) do
    emit(:backpressure_entered, state, %{queue_depth: state.queue_depth}, %{
      downstream: :ingress_persistence_projector,
      downstream_queue_depth: downstream_queue_depth,
      downstream_high_watermark: @projector_high_watermark,
      downstream_low_watermark: @projector_low_watermark
    })

    state
  end

  defp maybe_emit_projector_backpressure_entered(state, _downstream_queue_depth), do: state

  defp maybe_emit_projector_backpressure_released(
         %{projector_backpressured?: true} = state,
         downstream_queue_depth
       ) do
    emit(:backpressure_released, state, %{queue_depth: state.queue_depth}, %{
      downstream: :ingress_persistence_projector,
      downstream_queue_depth: downstream_queue_depth
    })

    state
  end

  defp maybe_emit_projector_backpressure_released(state, _downstream_queue_depth), do: state

  defp resolve_persistence_projector(state) do
    with {:ok, pid} <- IngressPersistenceProjector.lookup(state.persistence_projector_name) do
      next_state =
        state
        |> maybe_demonitor_persistence_projector()
        |> Map.put(:persistence_projector_pid, pid)
        |> Map.put(:persistence_projector_monitor_ref, Process.monitor(pid))

      {:ok, next_state}
    end
  end

  defp maybe_demonitor_persistence_projector(
         %{
           persistence_projector_monitor_ref: monitor_ref
         } = state
       )
       when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    %{state | persistence_projector_monitor_ref: nil}
  end

  defp maybe_demonitor_persistence_projector(state), do: state

  defp emit(event, state, measurements, metadata) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      Map.merge(
        %{
          mission_id: state.mission_id,
          realized_contact_id: state.realized_contact_id,
          path_id: state.path_id,
          provider_binding_id: state.provider_binding_id
        },
        metadata
      )
    )
  end

  defp run_ingress(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    exception ->
      stacktrace = __STACKTRACE__

      Logger.error(Exception.format(:error, exception, stacktrace))

      {:crash, Exception.format_banner(:error, exception)}
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__

      Logger.error(Exception.format(kind, reason, stacktrace))

      {:crash, Exception.format_banner(kind, reason)}
  end
end
