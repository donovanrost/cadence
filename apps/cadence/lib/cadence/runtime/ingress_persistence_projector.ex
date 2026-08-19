defmodule Cadence.Runtime.IngressPersistenceProjector do
  @moduledoc """
  Path-local async persistence worker for processed ingress batches.

  The live ingress lane can stay focused on ordered resolve/runtime work while
  this projector owns the slower durable writes and archive fan-out.
  """

  use GenServer

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Observability
  alias Cadence.Runtime.Persistence
  alias Cadence.Runtime.ProcessedIngressBatch
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @max_persist_batch_size 2_048
  @default_retry_delay_ms 100
  @event_prefix [:cadence, :runtime, :ingress_persistence_projector]

  @type state :: %{
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          provider_binding_id: binary(),
          organization_id: binary() | nil,
          persistence_module: module(),
          queue: :queue.queue(ProcessedIngressBatch.t()),
          queue_depth: non_neg_integer(),
          processing?: boolean(),
          lifecycle_status: :active | :quiescing | :quiesced,
          quiesce_waiters: [GenServer.from()],
          retry_delay_ms: pos_integer(),
          enqueued_count: non_neg_integer(),
          persisted_count: non_neg_integer(),
          failed_count: non_neg_integer(),
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
      id: {:provider_persistence_projector, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec enqueue(GenServer.server(), ProcessedIngressBatch.t()) :: :ok | {:error, term()}
  def enqueue(projector, %ProcessedIngressBatch{} = batch) do
    with {:ok, pid} <- lookup(projector) do
      GenServer.cast(pid, {:enqueue, batch})
      :ok
    end
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def snapshot(projector) do
    with {:ok, pid} <- lookup(projector) do
      GenServer.call(pid, :snapshot)
    end
  end

  @spec quiesce(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def quiesce(projector) do
    with {:ok, pid} <- lookup(projector) do
      GenServer.call(pid, :quiesce, :infinity)
    end
  end

  @spec notify_when_below(GenServer.server(), non_neg_integer(), pid(), reference()) ::
          :ok | {:error, term()}
  def notify_when_below(projector, threshold, subscriber_pid, ref)
      when is_integer(threshold) and threshold >= 0 and is_pid(subscriber_pid) and
             is_reference(ref) do
    with {:ok, pid} <- lookup(projector) do
      GenServer.call(pid, {:notify_when_below, threshold, subscriber_pid, ref})
    end
  end

  @spec cancel_notify_when_below(GenServer.server(), reference()) :: :ok | {:error, term()}
  def cancel_notify_when_below(projector, ref) when is_reference(ref) do
    with {:ok, pid} <- lookup(projector) do
      GenServer.call(pid, {:cancel_notify_when_below, ref})
    end
  end

  @spec lookup(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def lookup(server)

  def lookup(server) when is_pid(server) do
    if Process.alive?(server) do
      {:ok, server}
    else
      {:error, :ingress_persistence_projector_not_running}
    end
  end

  def lookup(server) do
    case GenServer.whereis(server) do
      nil -> {:error, :ingress_persistence_projector_not_running}
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
       organization_id: Keyword.get(opts, :organization_id),
       persistence_module: Keyword.get(opts, :persistence_module, Persistence),
       queue: :queue.new(),
       queue_depth: 0,
       processing?: false,
       lifecycle_status: :active,
       quiesce_waiters: [],
       retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms),
       enqueued_count: 0,
       persisted_count: 0,
       failed_count: 0,
       last_completed_at: nil,
       last_error: nil,
       capacity_waiters: %{}
     }}
  end

  @impl true
  def handle_call(:quiesce, _from, %{lifecycle_status: :quiesced} = state) do
    {:reply, {:ok, quiescence_settlement(state)}, state}
  end

  def handle_call(:quiesce, from, state) do
    state = %{
      state
      | lifecycle_status: :quiescing,
        quiesce_waiters: [from | state.quiesce_waiters]
    }

    state =
      if state.queue_depth > 0 and not state.processing? do
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
        queue_depth: state.queue_depth,
        processing?: state.processing?,
        enqueued_count: state.enqueued_count,
        persisted_count: state.persisted_count,
        failed_count: state.failed_count,
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
  def handle_cast({:enqueue, %ProcessedIngressBatch{}}, %{lifecycle_status: status} = state)
      when status in [:quiescing, :quiesced] do
    {:noreply, state}
  end

  def handle_cast({:enqueue, %ProcessedIngressBatch{} = batch}, state) do
    case ProcessedIngressBatch.size(batch) do
      0 ->
        {:noreply, state}

      batch_size ->
        next_state = %{
          state
          | queue: :queue.in(batch, state.queue),
            queue_depth: state.queue_depth + batch_size,
            enqueued_count: state.enqueued_count + batch_size
        }

        if state.processing? do
          {:noreply, next_state}
        else
          send(self(), :process_queue)
          {:noreply, %{next_state | processing?: true}}
        end
    end
  end

  @impl true
  def handle_info(:process_queue, %{lifecycle_status: :quiesced} = state),
    do: {:noreply, state}

  def handle_info(:process_queue, state) do
    case dequeue_persist_batch(state) do
      {:ok, %ProcessedIngressBatch{} = batch, rest, batch_size} ->
        handle_dequeued_persist_batch(state, batch, rest, batch_size)

      :empty ->
        state
        |> Map.merge(%{queue_depth: 0, processing?: false})
        |> notify_capacity_waiters()
        |> settle_if_quiescent()
    end
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, remove_capacity_waiter_by_monitor(state, monitor_ref)}
  end

  defp persist_batch(
         %ProcessedIngressBatch{
           processing_results: processing_results
         } = batch,
         organization_id,
         persistence_module
       )
       when is_list(processing_results) and processing_results != [] do
    links = Observability.links(batch.trace_contexts)

    Observability.with_root_span(
      "cadence.telemetry.ingress.persist_batch",
      %{
        kind: :consumer,
        links: links,
        attributes: persistence_span_attributes(batch, links)
      },
      fn ->
        started_at = System.monotonic_time()
        result = do_persist_batch(batch, organization_id, persistence_module)
        emit_persist_result(result, batch, elapsed_us(started_at))
        _ = mark_persistence_result(result, batch)
        result
      end
    )
  end

  defp persist_batch(%ProcessedIngressBatch{}, _organization_id, _persistence_module),
    do: {:error, :empty_batch}

  defp do_persist_batch(
         %ProcessedIngressBatch{
           mission_id: mission_id,
           processing_results: processing_results
         },
         organization_id,
         persistence_module
       ) do
    persistence_started_at = System.monotonic_time()

    result =
      run_persistence(fn ->
        raw_evidence = first_raw_evidence(processing_results)

        persist_processing_results(
          raw_evidence,
          processing_results,
          organization_id,
          persistence_module
        )
      end)

    case result do
      {:ok, :ok} ->
        TelemetryProfiler.record_projected_persistence(
          mission_id,
          length(processing_results),
          elapsed_us(persistence_started_at)
        )

        :ok

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:crash, reason} ->
        {:error, reason}
    end
  end

  defp first_raw_evidence([%{raw_evidence: %RawEvidence{} = raw_evidence} | _rest]),
    do: raw_evidence

  defp first_raw_evidence([]), do: raise(ArgumentError, "processed ingress batch is empty")

  defp handle_dequeued_persist_batch(state, %ProcessedIngressBatch{} = batch, rest, batch_size) do
    case persist_batch(batch, state.organization_id, state.persistence_module) do
      :ok ->
        notify_batch_completed(batch)

        next_state = %{
          state
          | queue: rest,
            queue_depth: max(state.queue_depth - batch_size, 0),
            persisted_count: state.persisted_count + batch_size,
            last_completed_at: DateTime.utc_now(),
            last_error: nil
        }

        next_state
        |> notify_capacity_waiters()
        |> continue_processing_queue()

      {:error, reason} ->
        next_state = %{
          state
          | queue: :queue.in_r(batch, rest),
            failed_count: state.failed_count + 1,
            last_completed_at: DateTime.utc_now(),
            last_error: inspect(reason),
            processing?: true
        }

        Process.send_after(self(), :process_queue, state.retry_delay_ms)
        {:noreply, next_state}
    end
  end

  defp continue_processing_queue(next_state) do
    if next_state.queue_depth > 0 do
      send(self(), :process_queue)
      {:noreply, %{next_state | processing?: true}}
    else
      next_state
      |> Map.put(:processing?, false)
      |> settle_if_quiescent()
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
        released_count: length(ready_waiters)
      })
    end

    %{state | capacity_waiters: Map.new(waiting_waiters)}
  end

  defp notify_capacity_waiter(subscriber_pid, ref, queue_depth) do
    send(subscriber_pid, {:ingress_persistence_capacity_available, self(), ref, queue_depth})
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

  defp persist_processing_results(
         %RawEvidence{} = raw_evidence,
         processing_results,
         organization_id,
         persistence_module
       ) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      persist_processing_results_with_stage(
        processing_results,
        organization_id,
        persistence_module
      )
    end)
  end

  defp persist_processing_results_with_stage(
         processing_results,
         organization_id,
         persistence_module
       ) do
    TelemetryProfiler.with_stage(:persistence, fn ->
      persistence_module.persist_semantic_processing_results(
        processing_results,
        record_current_values?: not CurrentValueStore.hot_path_safe?(),
        organization_id: organization_id
      )
    end)
  end

  defp settle_if_quiescent(
         %{
           lifecycle_status: :quiescing,
           queue_depth: 0,
           processing?: false
         } = state
       ) do
    settlement = quiescence_settlement(state)
    Enum.each(state.quiesce_waiters, &GenServer.reply(&1, {:ok, settlement}))

    {:noreply,
     %{
       state
       | lifecycle_status: :quiesced,
         quiesce_waiters: []
     }}
  end

  defp settle_if_quiescent(state), do: {:noreply, state}

  defp quiescence_settlement(state) do
    %{
      status: :quiesced,
      provider_binding_id: state.provider_binding_id,
      persisted_count: state.persisted_count,
      queue_depth: state.queue_depth
    }
  end

  defp elapsed_us(started_at),
    do: System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)

  defp run_persistence(fun) when is_function(fun, 0) do
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

  defp dequeue_persist_batch(state) do
    case :queue.out(state.queue) do
      {:empty, _queue} ->
        :empty

      {{:value, %ProcessedIngressBatch{} = batch}, rest} ->
        do_dequeue_persist_batch(
          state,
          rest,
          ProcessedIngressBatch.size(batch),
          [batch]
        )
    end
  end

  defp do_dequeue_persist_batch(state, queue, size, batches) do
    case :queue.peek(queue) do
      {:value, %ProcessedIngressBatch{} = batch} ->
        batch_size = ProcessedIngressBatch.size(batch)

        if size + batch_size <= @max_persist_batch_size do
          {{:value, _next_batch}, rest} = :queue.out(queue)

          do_dequeue_persist_batch(
            state,
            rest,
            size + batch_size,
            [batch | batches]
          )
        else
          build_persist_batch(state, queue, size, batches)
        end

      _other ->
        build_persist_batch(state, queue, size, batches)
    end
  end

  defp build_persist_batch(state, queue, size, reversed_batches) do
    batches = Enum.reverse(reversed_batches)

    processing_results =
      Enum.flat_map(batches, & &1.processing_results)

    {:ok,
     ProcessedIngressBatch.new(%{
       mission_id: state.mission_id,
       realized_contact_id: state.realized_contact_id,
       path_id: state.path_id,
       provider_binding_id: state.provider_binding_id,
       processing_results: processing_results,
       trace_contexts: Enum.flat_map(batches, & &1.trace_contexts),
       completions: Enum.flat_map(batches, & &1.completions),
       producer_receipts: Enum.flat_map(batches, & &1.producer_receipts),
       enqueued_at: oldest_enqueued_at(batches)
     }), queue, size}
  end

  defp oldest_enqueued_at(batches) do
    batches
    |> Enum.map(& &1.enqueued_at)
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      enqueued_at_values -> Enum.min(enqueued_at_values)
    end
  end

  defp notify_batch_completed(%ProcessedIngressBatch{} = batch) do
    Enum.each(batch.producer_receipts, fn {producer_pid, count} ->
      send(producer_pid, {:ingress_persistence_completed, self(), count})
    end)

    Enum.each(batch.completions, fn {subscriber_pid, ref} ->
      send(subscriber_pid, {:provider_ingress_persisted, self(), ref})
    end)
  end

  defp persistence_span_attributes(%ProcessedIngressBatch{} = batch, links) do
    %{
      "cadence.contact.id" => batch.realized_contact_id,
      "cadence.ingress.batch.size" => ProcessedIngressBatch.size(batch),
      "cadence.mission.id" => batch.mission_id,
      "cadence.path.id" => batch.path_id,
      "cadence.provider.binding.id" => batch.provider_binding_id,
      "cadence.queue.wait.duration_ms" => ProcessedIngressBatch.queue_wait_ms(batch),
      "cadence.trace.link.count" => length(links)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp emit_persist_result(result, %ProcessedIngressBatch{} = batch, duration_us) do
    metadata =
      case result do
        :ok -> %{outcome: :ok}
        {:error, reason} -> %{outcome: :error, error_type: Observability.error_class(reason)}
      end

    :telemetry.execute(
      @event_prefix ++ [:persist_result],
      %{
        batch_size: ProcessedIngressBatch.size(batch),
        duration_us: duration_us,
        queue_wait_ms: ProcessedIngressBatch.queue_wait_ms(batch)
      },
      metadata
    )
  end

  defp mark_persistence_result(:ok, %ProcessedIngressBatch{} = batch) do
    _ =
      Observability.add_event("cadence.telemetry.ingress.batch_persisted", %{
        "cadence.ingress.batch.size" => ProcessedIngressBatch.size(batch)
      })

    Observability.mark_ok()
  end

  defp mark_persistence_result({:error, reason}, %ProcessedIngressBatch{} = batch) do
    error_class = Observability.error_class(reason)

    _ =
      Observability.add_event("cadence.telemetry.ingress.persistence_failed", %{
        "cadence.error.class" => error_class,
        "cadence.ingress.batch.size" => ProcessedIngressBatch.size(batch)
      })

    _ =
      Observability.log(
        :warning,
        "cadence.telemetry.ingress.persistence_failed",
        "Telemetry ingress persistence failed",
        persistence_log_metadata(batch, error_class)
      )

    Observability.mark_error("telemetry ingress persistence failed")
  end

  defp persistence_log_metadata(%ProcessedIngressBatch{} = batch, error_class) do
    [
      mission_id: batch.mission_id,
      realized_contact_id: batch.realized_contact_id,
      path_id: batch.path_id,
      provider_binding_id: batch.provider_binding_id,
      error_class: error_class
    ]
  end

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
end
