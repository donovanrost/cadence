defmodule Cadence.Runtime.ProviderIngressExecutor do
  @moduledoc """
  Path-local ordered ingress executor for provider-delivered downlink messages.

  Providers should adapt external transport I/O into canonical ingress message
  units, then enqueue them here. This process owns the heavier mission-facing
  work such as telemetry processing and path transport-event handling.
  """

  use GenServer

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Observability
  alias Cadence.Observability.AsyncContext
  alias Cadence.Runtime, as: RuntimeBoundary
  alias Cadence.Runtime.{IngressEvidence, IngressPersistenceProjector, ProcessedIngressBatch}
  alias Cadence.Runtime.ProviderIngressExecutor.Instrumentation
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  @max_drain_batch 512
  @projector_high_watermark 8_192
  @projector_low_watermark 2_048
  @type executor_item ::
          {:telemetry, RawEvidence.t(), AsyncContext.t(), {pid(), reference()} | nil}
          | {:transport_event, binary(), term(), keyword()}

  @type state :: %{
          organization_id: binary() | nil,
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          provider_binding_id: binary(),
          persistence_projector_name: GenServer.server(),
          persistence_projector_pid: pid() | nil,
          persistence_projector_monitor_ref: reference() | nil,
          projector_backpressured?: boolean(),
          projector_capacity_wait_ref: reference() | nil,
          projector_in_flight_count: non_neg_integer(),
          pending_persistence_batches: [ProcessedIngressBatch.t()],
          queue: :queue.queue(executor_item()),
          queue_depth: non_neg_integer(),
          telemetry_queue_bytes: non_neg_integer(),
          telemetry_enqueued_at_queue: :queue.queue(integer()),
          processing?: boolean(),
          lifecycle_status: :active | :quiescing | :quiesced | :quiescence_failed,
          quiesce_waiters: [GenServer.from()],
          quiescence_error: term() | nil,
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

  @spec enqueue_telemetry(GenServer.server(), RawEvidence.t(), keyword()) ::
          :ok | {:error, term()}
  def enqueue_telemetry(executor, %RawEvidence{} = raw_evidence, opts \\ [])
      when is_list(opts) do
    completion = Keyword.get(opts, :completion)

    Instrumentation.trace_enqueue([raw_evidence], fn async_context ->
      enqueue(executor, {:telemetry, raw_evidence, async_context, completion})
    end)
  end

  @spec enqueue_many_telemetry(GenServer.server(), [RawEvidence.t()]) ::
          :ok | {:error, term()}
  def enqueue_many_telemetry(_executor, []), do: :ok

  def enqueue_many_telemetry(executor, raw_evidences) when is_list(raw_evidences) do
    Instrumentation.trace_enqueue(raw_evidences, fn async_context ->
      items = Enum.map(raw_evidences, &{:telemetry, &1, async_context, nil})
      enqueue_many(executor, items)
    end)
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

  @spec quiesce(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def quiesce(executor) do
    call_if_running(executor, :quiesce, :infinity)
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
       organization_id: Keyword.get(opts, :organization_id),
       mission_id: Keyword.fetch!(opts, :mission_id),
       realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
       path_id: Keyword.fetch!(opts, :path_id),
       provider_binding_id: Keyword.fetch!(opts, :provider_binding_id),
       persistence_projector_name: Keyword.fetch!(opts, :persistence_projector_name),
       persistence_projector_pid: nil,
       persistence_projector_monitor_ref: nil,
       projector_backpressured?: false,
       projector_capacity_wait_ref: nil,
       projector_in_flight_count: 0,
       pending_persistence_batches: [],
       queue: :queue.new(),
       queue_depth: 0,
       telemetry_queue_bytes: 0,
       telemetry_enqueued_at_queue: :queue.new(),
       processing?: false,
       lifecycle_status: :active,
       quiesce_waiters: [],
       quiescence_error: nil,
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
  def handle_call(:quiesce, _from, %{lifecycle_status: :quiesced} = state) do
    {:reply, {:ok, quiescence_settlement(state)}, state}
  end

  def handle_call(:quiesce, _from, %{lifecycle_status: :quiescence_failed} = state) do
    {:reply, {:error, state.quiescence_error}, state}
  end

  def handle_call(:quiesce, from, state) do
    state = %{
      state
      | lifecycle_status: :quiescing,
        quiesce_waiters: [from | state.quiesce_waiters]
    }

    state =
      if work_pending?(state) and not state.processing? do
        send(self(), :process_queue)
        %{state | processing?: true}
      else
        state
      end

    settle_if_quiescent(state)
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     {:ok,
      %{
        provider_binding_id: state.provider_binding_id,
        lifecycle_status: state.lifecycle_status,
        quiescence_error: state.quiescence_error,
        queue_depth: state.queue_depth,
        queue_bytes: state.telemetry_queue_bytes,
        oldest_queued_age_ms: oldest_queued_age_ms(state.telemetry_enqueued_at_queue),
        processing?: state.processing?,
        backpressured?: state.projector_backpressured?,
        projector_backpressured?: state.projector_backpressured?,
        projector_capacity_waiting?: is_reference(state.projector_capacity_wait_ref),
        projector_in_flight_count: state.projector_in_flight_count,
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
  def handle_cast({:enqueue, _item}, %{lifecycle_status: status} = state)
      when status in [:quiescing, :quiesced, :quiescence_failed] do
    {:noreply, state}
  end

  def handle_cast({:enqueue, item}, state) do
    next_state = enqueue_items(state, [item])

    if state.processing? do
      {:noreply, next_state}
    else
      send(self(), :process_queue)
      {:noreply, %{next_state | processing?: true}}
    end
  end

  def handle_cast({:enqueue_many, _items}, %{lifecycle_status: status} = state)
      when status in [:quiescing, :quiesced, :quiescence_failed] do
    {:noreply, state}
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
  def handle_info(:process_queue, %{lifecycle_status: status} = state)
      when status in [:quiesced, :quiescence_failed],
      do: {:noreply, state}

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
    Instrumentation.log_projector_exit(state.provider_binding_id, reason)

    next_state = %{
      state
      | persistence_projector_pid: nil,
        persistence_projector_monitor_ref: nil,
        projector_capacity_wait_ref: nil,
        projector_in_flight_count: 0,
        projector_backpressured?: false
    }

    case state.lifecycle_status do
      :quiescing ->
        fail_quiescence(next_state, {:persistence_projector_exited, reason})

      _other ->
        {:noreply, next_state}
    end
  end

  def handle_info(
        {:ingress_persistence_completed, projector_pid, completed_count},
        %{persistence_projector_pid: projector_pid} = state
      )
      when is_integer(completed_count) and completed_count > 0 do
    in_flight_count = max(state.projector_in_flight_count - completed_count, 0)

    next_state =
      state
      |> Map.put(:projector_in_flight_count, in_flight_count)
      |> maybe_release_local_projector_backpressure()

    settle_if_quiescent(next_state)
  end

  def handle_info(
        {:ingress_persistence_completed, _projector_pid, _completed_count},
        state
      ) do
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

  defp call_if_running(server, request, timeout \\ 5_000) do
    with {:ok, pid} <- lookup(server) do
      GenServer.call(pid, request, timeout)
    end
  end

  defp enqueue_items(state, items) do
    {queue, enqueued_at_queue, byte_count, count} =
      Enum.reduce(
        items,
        {state.queue, state.telemetry_enqueued_at_queue, 0, 0},
        fn item, {queue, enqueued_at_queue, byte_count, count} ->
          {
            :queue.in(item, queue),
            enqueue_timestamp(enqueued_at_queue, item),
            byte_count + item_raw_byte_count(item),
            count + 1
          }
        end
      )

    %{
      state
      | queue: queue,
        queue_depth: state.queue_depth + count,
        telemetry_queue_bytes: state.telemetry_queue_bytes + byte_count,
        telemetry_enqueued_at_queue: enqueued_at_queue,
        enqueued_count: state.enqueued_count + count
    }
  end

  defp enqueue_timestamp(
         queue,
         {:telemetry, _raw_evidence, %AsyncContext{} = async_context, _completion}
       ) do
    :queue.in(async_context.enqueued_at, queue)
  end

  defp enqueue_timestamp(queue, _item), do: queue

  defp item_raw_byte_count(
         {:telemetry, %RawEvidence{} = raw_evidence, _async_context, _completion}
       ) do
    byte_size(raw_evidence.raw || <<>>)
  end

  defp item_raw_byte_count(_item), do: 0

  defp dequeue_item_metrics(
         state,
         {:telemetry, %RawEvidence{} = raw_evidence, _async_context, _completion}
       ) do
    enqueued_at_queue =
      case :queue.out(state.telemetry_enqueued_at_queue) do
        {{:value, _enqueued_at}, rest} -> rest
        {:empty, queue} -> queue
      end

    %{
      state
      | telemetry_queue_bytes:
          max(state.telemetry_queue_bytes - byte_size(raw_evidence.raw || <<>>), 0),
        telemetry_enqueued_at_queue: enqueued_at_queue
    }
  end

  defp dequeue_item_metrics(state, _item), do: state

  defp oldest_queued_age_ms(queue) do
    case :queue.peek(queue) do
      {:value, enqueued_at} ->
        AsyncContext.queue_wait_ms(%AsyncContext{enqueued_at: enqueued_at})

      :empty ->
        0.0
    end
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
          |> dequeue_item_metrics(item)
          |> Map.put(:queue, rest)
          |> Map.put(:queue_depth, state.queue_depth - 1)

        case execute_item(item, base_state) do
          {:ok, {:telemetry, processing_result, span_context, completion}} ->
            next_state = apply_execution_result(base_state, {:ok, :telemetry})

            drain_batch(
              next_state,
              remaining - 1,
              [{processing_result, span_context, completion} | current_batch],
              batches
            )

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
        {%{
           state
           | queue_depth: 0,
             telemetry_queue_bytes: 0,
             telemetry_enqueued_at_queue: :queue.new()
         }, Enum.reverse(finalize_persistence_batches(state, current_batch, batches))}
    end
  end

  defp execute_item(
         {:telemetry, %RawEvidence{} = raw_evidence, %AsyncContext{} = async_context, completion},
         state
       ) do
    attributes =
      raw_evidence
      |> Instrumentation.ingress_attributes()
      |> Map.merge(Instrumentation.executor_attributes(state))
      |> Map.put("cadence.queue.wait.duration_ms", AsyncContext.queue_wait_ms(async_context))

    result =
      Observability.with_span(
        async_context.parent_context,
        "cadence.telemetry.ingress.process",
        %{kind: :consumer, attributes: attributes},
        fn -> process_telemetry_in_span(raw_evidence, state.organization_id) end
      )

    case result do
      {:ok, {:telemetry, processing_result, span_context}} ->
        {:ok, {:telemetry, processing_result, span_context, completion}}

      {:error, _kind, reason} = error ->
        notify_completion_failed(completion, reason)
        error
    end
  end

  defp execute_item({:transport_event, transport_binding_id, event, opts}, _state) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    path_id = Keyword.fetch!(opts, :path_id)
    call_opts = Keyword.drop(opts, [:mission_id, :realized_contact_id, :path_id])

    case Instrumentation.run_ingress(fn ->
           RuntimeBoundary.handle_path_transport_event(
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

  defp process_telemetry_in_span(%RawEvidence{} = raw_evidence, organization_id) do
    case Instrumentation.run_ingress(fn ->
           process_telemetry_item(raw_evidence, organization_id)
         end) do
      {:ok, {:ok, processing_result}} ->
        result_attributes = Instrumentation.processing_result_attributes(processing_result)
        _ = Observability.set_attributes(result_attributes)
        _ = Observability.add_event("cadence.telemetry.ingress.processed", result_attributes)
        _ = Instrumentation.maybe_record_anomaly_event(result_attributes)
        _ = Observability.mark_ok()

        {:ok, {:telemetry, processing_result, Observability.current_span_context()}}

      {:ok, {:error, reason}} ->
        _ = Instrumentation.record_processing_failure(raw_evidence, reason, "processing_failed")
        _ = Observability.mark_error("telemetry ingress processing failed")
        {:error, :telemetry, inspect(reason)}

      {:crash, reason} ->
        _ = Instrumentation.record_processing_failure(raw_evidence, reason, "processing_crashed")
        _ = Observability.mark_error("telemetry ingress processing crashed")
        {:error, :telemetry, reason}
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

  defp apply_execution_result(state, {:error, :telemetry, reason}) do
    %{
      state
      | failed_count: state.failed_count + 1,
        last_completed_at: DateTime.utc_now(),
        last_error: reason
    }
  end

  defp apply_execution_result(state, {:error, kind, reason}) do
    Instrumentation.log_processing_failure(state.provider_binding_id, kind, reason)

    %{
      state
      | failed_count: state.failed_count + 1,
        last_completed_at: DateTime.utc_now(),
        last_error: reason
    }
  end

  defp process_telemetry_item(%RawEvidence{} = raw_evidence, organization_id) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      ingress_started_at = System.monotonic_time()

      resolve_result =
        TelemetryProfiler.with_stage(:resolve, fn ->
          resolve_raw_evidence_in_span(raw_evidence)
        end)

      resolve_us = elapsed_us(ingress_started_at)

      case resolve_result do
        {:ok, %RawEvidence{} = resolved_raw_evidence} ->
          handle_resolved_telemetry_item(
            resolved_raw_evidence,
            organization_id,
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

  defp resolve_raw_evidence_in_span(%RawEvidence{} = raw_evidence) do
    Instrumentation.trace_stage(
      "cadence.telemetry.ingress.resolve",
      fn -> IngressEvidence.validate(raw_evidence) end
    )
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
      persisted_state
      |> Map.put(:processing?, false)
      |> settle_if_quiescent()
    end
  end

  defp settle_if_quiescent(
         %{
           lifecycle_status: :quiescing,
           queue_depth: 0,
           processing?: false,
           pending_persistence_batches: [],
           projector_in_flight_count: 0
         } = state
       ) do
    settlement = quiescence_settlement(state)
    Enum.each(state.quiesce_waiters, &GenServer.reply(&1, {:ok, settlement}))

    {:noreply,
     %{
       state
       | lifecycle_status: :quiesced,
         quiesce_waiters: [],
         quiescence_error: nil
     }}
  end

  defp settle_if_quiescent(state), do: {:noreply, state}

  defp fail_quiescence(state, reason) do
    Enum.each(state.quiesce_waiters, &GenServer.reply(&1, {:error, reason}))

    {:noreply,
     %{
       state
       | lifecycle_status: :quiescence_failed,
         quiesce_waiters: [],
         quiescence_error: reason
     }}
  end

  defp work_pending?(state) do
    state.queue_depth > 0 or state.pending_persistence_batches != []
  end

  defp quiescence_settlement(state) do
    %{
      status: :quiesced,
      provider_binding_id: state.provider_binding_id,
      processed_count: state.processed_count,
      failed_count: state.failed_count,
      queue_depth: state.queue_depth,
      projector_in_flight_count: state.projector_in_flight_count
    }
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

    Instrumentation.emit(:capacity_waiter_registered, state, %{queue_depth: state.queue_depth}, %{
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
      Instrumentation.emit(:capacity_waiter_released, state, %{queue_depth: state.queue_depth}, %{
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
         organization_id,
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
          organization_id,
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
          process_telemetry_runtime_in_span(resolved_raw_evidence)
        end)
      end
    )
  end

  defp process_telemetry_runtime_in_span(%RawEvidence{} = resolved_raw_evidence) do
    Instrumentation.trace_stage(
      "cadence.telemetry.ingress.runtime",
      fn -> RuntimeBoundary.process_telemetry_ingress(resolved_raw_evidence) end
    )
  end

  defp finalize_processed_telemetry_item(
         %RawEvidence{} = resolved_raw_evidence,
         processing_result,
         organization_id,
         ingress_started_at,
         resolve_us,
         runtime_us
       ) do
    with {:ok, telemetry_samples} <-
           extract_telemetry_samples(resolved_raw_evidence.mission_id, processing_result),
         :ok <-
           maybe_record_current_values(
             resolved_raw_evidence,
             telemetry_samples,
             organization_id
           ) do
      _ =
        Observability.set_attributes(%{
          "cadence.telemetry.sample.count" => length(telemetry_samples)
        })

      end_to_end_us = elapsed_us(ingress_started_at)

      TelemetryProfiler.record_ingress_result(
        resolved_raw_evidence,
        resolve_us: resolve_us,
        runtime_us: runtime_us,
        end_to_end_us: end_to_end_us,
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
        Instrumentation.trace_stage(
          "cadence.telemetry.ingress.extract_samples",
          fn -> RuntimePersistence.telemetry_samples(processing_result.outputs) end
        )
      end
    )
  end

  defp maybe_record_current_values(%RawEvidence{}, telemetry_samples, _organization_id)
       when telemetry_samples == [],
       do: :ok

  defp maybe_record_current_values(
         %RawEvidence{} = resolved_raw_evidence,
         telemetry_samples,
         organization_id
       ) do
    if CurrentValueStore.hot_path_safe?() do
      record_hot_path_current_values(resolved_raw_evidence, telemetry_samples, organization_id)
    else
      :ok
    end
  end

  defp record_hot_path_current_values(
         %RawEvidence{} = resolved_raw_evidence,
         telemetry_samples,
         organization_id
       ) do
    TelemetryProfiler.with_runtime_component(
      resolved_raw_evidence.mission_id,
      :current_value_record,
      fn ->
        Instrumentation.trace_stage("cadence.telemetry.ingress.record_current_values", fn ->
          resolved_raw_evidence
          |> enriched_current_samples(telemetry_samples, organization_id)
          |> record_enriched_current_values()
        end)
      end
    )
  end

  defp enriched_current_samples(
         %RawEvidence{} = resolved_raw_evidence,
         telemetry_samples,
         organization_id
       ) do
    TelemetryStorage.enrich_samples(
      telemetry_samples,
      current_value_storage_opts(resolved_raw_evidence, organization_id)
    )
  end

  defp record_enriched_current_values({:ok, enriched_samples}) do
    CurrentValueStore.record_samples(enriched_samples)
  end

  defp record_enriched_current_values({:error, reason}), do: {:error, reason}

  defp current_value_storage_opts(%RawEvidence{} = resolved_raw_evidence, organization_id) do
    [
      organization_id: organization_id,
      source_endpoint_id:
        resolved_raw_evidence.source_endpoint_ref || resolved_raw_evidence.source_ref,
      recorded_at: resolved_raw_evidence.receipt_time
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp elapsed_us(started_at) do
    System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)
  end

  defp finalize_persistence_batches(_state, [], batches), do: batches

  defp finalize_persistence_batches(state, current_batch, batches) do
    [build_persistence_batch(state, current_batch) | batches]
  end

  defp build_persistence_batch(state, current_batch) do
    entries = Enum.reverse(current_batch)

    ProcessedIngressBatch.new(%{
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      path_id: state.path_id,
      provider_binding_id: state.provider_binding_id,
      enqueued_at: System.monotonic_time(),
      processing_results: Enum.map(entries, &elem(&1, 0)),
      trace_contexts: Enum.map(entries, &elem(&1, 1)),
      completions: entries |> Enum.map(&elem(&1, 2)) |> Enum.reject(&is_nil/1),
      producer_receipts: [{self(), length(entries)}]
    })
  end

  defp enqueue_persistence_batch(state, %ProcessedIngressBatch{} = batch) do
    with {:ok, next_state} <- ensure_persistence_projector(state),
         :ok <- IngressPersistenceProjector.enqueue(next_state.persistence_projector_pid, batch) do
      {:ok,
       %{
         next_state
         | projector_in_flight_count:
             next_state.projector_in_flight_count + ProcessedIngressBatch.size(batch)
       }}
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
    threshold =
      if state.projector_backpressured?,
        do: @projector_low_watermark,
        else: @projector_high_watermark

    if state.projector_in_flight_count >= threshold do
      next_state =
        state
        |> maybe_emit_projector_backpressure_entered(state.projector_in_flight_count)
        |> Map.put(:projector_backpressured?, true)

      {:blocked, next_state}
    else
      next_state =
        state
        |> maybe_emit_projector_backpressure_released(state.projector_in_flight_count)
        |> Map.put(:projector_backpressured?, false)

      {:ok, next_state}
    end
  end

  defp maybe_emit_projector_backpressure_entered(
         %{projector_backpressured?: false} = state,
         downstream_queue_depth
       ) do
    Instrumentation.emit(:backpressure_entered, state, %{queue_depth: state.queue_depth}, %{
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
    Instrumentation.emit(:backpressure_released, state, %{queue_depth: state.queue_depth}, %{
      downstream: :ingress_persistence_projector,
      downstream_queue_depth: downstream_queue_depth
    })

    state
  end

  defp maybe_emit_projector_backpressure_released(state, _downstream_queue_depth), do: state

  defp maybe_release_local_projector_backpressure(
         %{projector_backpressured?: true, projector_in_flight_count: in_flight_count} = state
       )
       when in_flight_count < @projector_low_watermark do
    next_state =
      state
      |> maybe_emit_projector_backpressure_released(in_flight_count)
      |> Map.put(:projector_backpressured?, false)

    send(self(), :process_queue)
    %{next_state | processing?: true}
  end

  defp maybe_release_local_projector_backpressure(state), do: state

  defp notify_completion_failed({pid, ref}, reason) when is_pid(pid) and is_reference(ref) do
    send(pid, {:provider_ingress_failed, self(), ref, reason})
    :ok
  end

  defp notify_completion_failed(_completion, _reason), do: :ok

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
end
