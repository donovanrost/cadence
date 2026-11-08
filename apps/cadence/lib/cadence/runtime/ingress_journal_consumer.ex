defmodule Cadence.Runtime.IngressJournalConsumer do
  @moduledoc """
  Replays captured ingress byte ranges into the ordered path executor.

  Only semantic-persistence completion advances the processing cursor. Raw
  archive custody has an independent consumer and acknowledgement. This
  consumer has at most one bounded contiguous range in flight, which makes the
  cursor protocol explicit and bounds replay work after a process restart.
  """

  use GenServer

  require Logger

  alias Cadence.IngressJournal.{Entry, Evidence, FileSystem}
  alias Cadence.Runtime.ProviderIngressExecutor

  @default_poll_interval_ms 10
  @default_max_batch_entries 8
  @default_max_batch_bytes 2 * 1_024 * 1_024

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
      id: {:ingress_journal_consumer, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def snapshot(consumer) do
    with {:ok, pid} <- lookup(consumer) do
      GenServer.call(pid, :snapshot)
    end
  end

  @spec quiesce(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def quiesce(consumer) do
    with {:ok, pid} <- lookup(consumer) do
      GenServer.call(pid, :quiesce, :infinity)
    end
  end

  @spec lookup(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def lookup(server) when is_pid(server) do
    if Process.alive?(server),
      do: {:ok, server},
      else: {:error, :ingress_journal_consumer_not_running}
  end

  def lookup(server) do
    case GenServer.whereis(server) do
      nil -> {:error, :ingress_journal_consumer_not_running}
      pid -> {:ok, pid}
    end
  end

  @impl true
  def init(opts) do
    config =
      opts
      |> Keyword.get_lazy(:policy, &FileSystem.configured_policy/0)
      |> Map.fetch!(:consumer_opts)

    state = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
      path_id: Keyword.fetch!(opts, :path_id),
      provider_binding_id: Keyword.fetch!(opts, :provider_binding_id),
      journal_name: Keyword.fetch!(opts, :journal_name),
      executor_name: Keyword.fetch!(opts, :executor_name),
      poll_interval_ms:
        Keyword.get(
          opts,
          :poll_interval_ms,
          Keyword.get(config, :processing_poll_interval_ms, @default_poll_interval_ms)
        ),
      max_batch_entries:
        positive_option(
          opts,
          config,
          :processing_max_batch_entries,
          @default_max_batch_entries
        ),
      max_batch_bytes:
        positive_option(opts, config, :processing_max_batch_bytes, @default_max_batch_bytes),
      retry_initial_ms: positive_option(opts, config, :retry_initial_ms, 250),
      retry_max_ms: positive_option(opts, config, :retry_max_ms, 30_000),
      retry_ref: nil,
      retry_delay_ms: 0,
      consecutive_failures: 0,
      lifecycle_status: :active,
      quiesce_waiters: [],
      in_flight: nil,
      delivered_batches: 0,
      delivered_entries: 0,
      delivered_bytes: 0,
      acknowledged_batches: 0,
      acknowledged_entries: 0,
      acknowledged_bytes: 0,
      max_delivered_batch_entries: 0,
      max_delivered_batch_bytes: 0,
      failed_count: 0,
      last_completed_at: nil,
      last_error: nil
    }

    send(self(), :consume)
    {:ok, state}
  end

  @impl true
  def handle_call(:quiesce, _from, %{lifecycle_status: :quiesced} = state) do
    {:reply, {:ok, quiescence_settlement(state)}, state}
  end

  def handle_call(:quiesce, from, state) do
    send(self(), :consume)

    {:noreply,
     %{
       state
       | lifecycle_status: :quiescing,
         quiesce_waiters: [from | state.quiesce_waiters]
     }}
  end

  def handle_call(:snapshot, _from, state) do
    in_flight =
      case state.in_flight do
        %{first: first, last: last, entry_count: entry_count, byte_count: byte_count} ->
          %{
            first_sequence: first.sequence,
            last_sequence: last.sequence,
            start_offset: first.start_offset,
            end_offset: last.end_offset,
            entry_count: entry_count,
            byte_count: byte_count
          }

        nil ->
          nil
      end

    {:reply,
     {:ok,
      %{
        provider_binding_id: state.provider_binding_id,
        lifecycle_status: state.lifecycle_status,
        max_batch_entries: state.max_batch_entries,
        max_batch_bytes: state.max_batch_bytes,
        in_flight: in_flight,
        delivered_batches: state.delivered_batches,
        delivered_entries: state.delivered_entries,
        delivered_bytes: state.delivered_bytes,
        acknowledged_batches: state.acknowledged_batches,
        acknowledged_entries: state.acknowledged_entries,
        acknowledged_bytes: state.acknowledged_bytes,
        max_delivered_batch_entries: state.max_delivered_batch_entries,
        max_delivered_batch_bytes: state.max_delivered_batch_bytes,
        failed_count: state.failed_count,
        consecutive_failures: state.consecutive_failures,
        retry_delay_ms: state.retry_delay_ms,
        phase: if(state.in_flight, do: state.in_flight.phase, else: :idle),
        last_completed_at: state.last_completed_at,
        last_error: state.last_error
      }}, state}
  end

  @impl true
  def handle_info(:consume, %{lifecycle_status: :quiesced} = state),
    do: {:noreply, state}

  def handle_info(:consume, %{retry_ref: ref} = state) when not is_nil(ref),
    do: {:noreply, state}

  def handle_info(:consume, %{in_flight: %{phase: :retry, entries: entries}} = state),
    do: consume_entries(state, entries)

  def handle_info(:consume, %{in_flight: %{phase: :acknowledge}} = state),
    do: acknowledge_batch(state)

  def handle_info(:consume, %{in_flight: nil} = state) do
    case FileSystem.next_entries(
           state.journal_name,
           :processing,
           state.max_batch_entries,
           state.max_batch_bytes
         ) do
      {:ok, [%Entry{} | _rest] = entries} ->
        consume_entries(state, compatible_prefix(entries))

      :empty ->
        settle_or_schedule(state)

      {:error, reason} ->
        {:noreply, retry_after_failure(state, reason)}
    end
  end

  def handle_info(:consume, state), do: {:noreply, state}

  def handle_info({:retry, ref}, %{retry_ref: ref} = state) do
    send(self(), :consume)
    {:noreply, %{state | retry_ref: nil}}
  end

  def handle_info({:retry, _stale_ref}, state), do: {:noreply, state}

  def handle_info(
        {:provider_ingress_persisted, _projector_pid, ref},
        %{in_flight: %{ref: ref, phase: :processing} = batch} = state
      ) do
    acknowledge_batch(%{state | in_flight: %{batch | phase: :acknowledge}})
  end

  def handle_info({:provider_ingress_persisted, _projector_pid, _stale_ref}, state),
    do: {:noreply, state}

  def handle_info(
        {:provider_ingress_failed, _executor_pid, ref, reason},
        %{in_flight: %{ref: ref, phase: :processing} = batch} = state
      ) do
    {:noreply, retry_after_failure(%{state | in_flight: %{batch | phase: :retry}}, reason)}
  end

  def handle_info({:provider_ingress_failed, _executor_pid, _stale_ref, _reason}, state),
    do: {:noreply, state}

  defp consume_entries(state, [%Entry{} = first | _rest] = entries) do
    last = List.last(entries)
    entry_count = length(entries)
    byte_count = Enum.sum(Enum.map(entries, & &1.payload_length))

    batch = %{
      first: first,
      last: last,
      entries: entries,
      entry_count: entry_count,
      byte_count: byte_count,
      phase: :retry,
      ref: nil
    }

    state = %{state | in_flight: batch}

    with {:ok, raw_evidence} <- Evidence.from_contiguous_entries(entries),
         ref <- make_ref(),
         :ok <-
           ProviderIngressExecutor.enqueue_telemetry(state.executor_name, raw_evidence,
             completion: {self(), ref}
           ) do
      :telemetry.execute(
        [:cadence, :ingress_journal, :processing_batch],
        %{entries: entry_count, bytes: byte_count},
        %{}
      )

      {:noreply,
       %{
         state
         | in_flight: %{batch | ref: ref, phase: :processing},
           delivered_batches: state.delivered_batches + 1,
           delivered_entries: state.delivered_entries + entry_count,
           delivered_bytes: state.delivered_bytes + byte_count,
           max_delivered_batch_entries: max(state.max_delivered_batch_entries, entry_count),
           max_delivered_batch_bytes: max(state.max_delivered_batch_bytes, byte_count)
       }}
    else
      {:error, reason} ->
        {:noreply, retry_after_failure(state, reason)}
    end
  end

  defp compatible_prefix([%Entry{} = first | rest]) do
    {entries, _last} =
      Enum.reduce_while(rest, {[first], first}, fn entry, {acc, previous} ->
        if Evidence.compatible_entries?(previous, entry) do
          {:cont, {[entry | acc], entry}}
        else
          {:halt, {acc, previous}}
        end
      end)

    Enum.reverse(entries)
  end

  defp positive_option(opts, config, key, default) do
    value = Keyword.get(opts, key, Keyword.get(config, key, default))

    if is_integer(value) and value > 0 do
      value
    else
      raise ArgumentError, "#{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp acknowledge_batch(%{in_flight: batch} = state) do
    case FileSystem.acknowledge(state.journal_name, :processing, batch.last.end_offset) do
      :ok ->
        send(self(), :consume)

        {:noreply,
         %{
           state
           | in_flight: nil,
             acknowledged_batches: state.acknowledged_batches + 1,
             acknowledged_entries: state.acknowledged_entries + batch.entry_count,
             acknowledged_bytes: state.acknowledged_bytes + batch.byte_count,
             last_completed_at: DateTime.utc_now(),
             consecutive_failures: 0,
             retry_delay_ms: 0,
             last_error: nil
         }}

      {:error, reason} ->
        # Processing has completed. Retry custody acknowledgement, not decoding.
        {:noreply, retry_after_failure(state, reason)}
    end
  end

  defp retry_after_failure(state, reason) do
    delay =
      if state.consecutive_failures == 0,
        do: min(state.retry_initial_ms, state.retry_max_ms),
        else: min(state.retry_delay_ms * 2, state.retry_max_ms)

    ref = make_ref()
    Process.send_after(self(), {:retry, ref}, delay)
    phase = if state.in_flight, do: state.in_flight.phase, else: :read

    range =
      if state.in_flight,
        do: {state.in_flight.first.start_offset, state.in_flight.last.end_offset}

    Logger.warning(
      "Ingress journal retry (#{phase}) in #{delay}ms at #{inspect(range)}: " <>
        inspect(reason, limit: 10, printable_limit: 300),
      provider_binding_id: state.provider_binding_id
    )

    :telemetry.execute(
      [:cadence, :ingress_journal, :processing_retry],
      %{count: 1, delay_ms: delay},
      %{phase: phase}
    )

    %{
      state
      | failed_count: state.failed_count + 1,
        consecutive_failures: state.consecutive_failures + 1,
        retry_ref: ref,
        retry_delay_ms: delay,
        last_error: inspect(reason, limit: 10, printable_limit: 300)
    }
  end

  defp settle_or_schedule(%{lifecycle_status: :quiescing} = state) do
    settlement = quiescence_settlement(state)
    Enum.each(state.quiesce_waiters, &GenServer.reply(&1, {:ok, settlement}))

    {:noreply,
     %{
       state
       | lifecycle_status: :quiesced,
         quiesce_waiters: []
     }}
  end

  defp settle_or_schedule(state) do
    schedule_consume(state.poll_interval_ms)
    {:noreply, state}
  end

  defp quiescence_settlement(state) do
    %{
      status: :quiesced,
      provider_binding_id: state.provider_binding_id,
      acknowledged_batches: state.acknowledged_batches,
      acknowledged_entries: state.acknowledged_entries,
      acknowledged_bytes: state.acknowledged_bytes
    }
  end

  defp schedule_consume(interval_ms), do: Process.send_after(self(), :consume, interval_ms)
end
