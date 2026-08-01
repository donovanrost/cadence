defmodule Cadence.Runtime.IngressJournalConsumer do
  @moduledoc """
  Replays captured ingress byte ranges into the ordered path executor.

  Only semantic-persistence completion advances the processing cursor. Raw
  archive custody has an independent consumer and acknowledgement. This
  consumer has at most one bounded contiguous range in flight, which makes the
  cursor protocol explicit and bounds replay work after a process restart.
  """

  use GenServer

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
    config = Application.get_env(:cadence, :ingress_journal, [])

    state = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
      path_id: Keyword.fetch!(opts, :path_id),
      provider_binding_id: Keyword.fetch!(opts, :provider_binding_id),
      journal_name: Keyword.fetch!(opts, :journal_name),
      executor_name: Keyword.fetch!(opts, :executor_name),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      max_batch_entries:
        positive_option(
          opts,
          config,
          :processing_max_batch_entries,
          @default_max_batch_entries
        ),
      max_batch_bytes:
        positive_option(opts, config, :processing_max_batch_bytes, @default_max_batch_bytes),
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
        last_completed_at: state.last_completed_at,
        last_error: state.last_error
      }}, state}
  end

  @impl true
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
        schedule_consume(state.poll_interval_ms)
        {:noreply, state}

      {:error, reason} ->
        schedule_consume(state.poll_interval_ms)
        {:noreply, record_failure(state, reason)}
    end
  end

  def handle_info(:consume, state), do: {:noreply, state}

  def handle_info(
        {:provider_ingress_persisted, _projector_pid, ref},
        %{
          in_flight: %{
            ref: ref,
            last: last,
            entry_count: entry_count,
            byte_count: byte_count
          }
        } = state
      ) do
    case FileSystem.acknowledge(state.journal_name, :processing, last.end_offset) do
      :ok ->
        send(self(), :consume)

        {:noreply,
         %{
           state
           | in_flight: nil,
             acknowledged_batches: state.acknowledged_batches + 1,
             acknowledged_entries: state.acknowledged_entries + entry_count,
             acknowledged_bytes: state.acknowledged_bytes + byte_count,
             last_completed_at: DateTime.utc_now(),
             last_error: nil
         }}

      {:error, reason} ->
        schedule_consume(state.poll_interval_ms)
        {:noreply, record_failure(%{state | in_flight: nil}, reason)}
    end
  end

  def handle_info({:provider_ingress_persisted, _projector_pid, _stale_ref}, state),
    do: {:noreply, state}

  def handle_info(
        {:provider_ingress_failed, _executor_pid, ref, reason},
        %{in_flight: %{ref: ref}} = state
      ) do
    schedule_consume(state.poll_interval_ms)
    {:noreply, record_failure(%{state | in_flight: nil}, reason)}
  end

  def handle_info({:provider_ingress_failed, _executor_pid, _stale_ref, _reason}, state),
    do: {:noreply, state}

  defp consume_entries(state, [%Entry{} = first | _rest] = entries) do
    last = List.last(entries)
    entry_count = length(entries)
    byte_count = Enum.sum(Enum.map(entries, & &1.payload_length))

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
         | in_flight: %{
             first: first,
             last: last,
             entry_count: entry_count,
             byte_count: byte_count,
             ref: ref
           },
           delivered_batches: state.delivered_batches + 1,
           delivered_entries: state.delivered_entries + entry_count,
           delivered_bytes: state.delivered_bytes + byte_count,
           max_delivered_batch_entries: max(state.max_delivered_batch_entries, entry_count),
           max_delivered_batch_bytes: max(state.max_delivered_batch_bytes, byte_count),
           last_error: nil
       }}
    else
      {:error, reason} ->
        schedule_consume(state.poll_interval_ms)
        {:noreply, record_failure(state, reason)}
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

  defp record_failure(state, reason) do
    %{state | failed_count: state.failed_count + 1, last_error: inspect(reason)}
  end

  defp schedule_consume(interval_ms), do: Process.send_after(self(), :consume, interval_ms)
end
