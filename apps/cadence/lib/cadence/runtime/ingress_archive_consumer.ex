defmodule Cadence.Runtime.IngressArchiveConsumer do
  @moduledoc """
  Independently replicates captured journal ranges to the raw archive.

  The archive cursor advances only after a batch receipt satisfies the
  configured completion policy. Failed effects retain the same deterministic
  batch for ordered, idempotent retry.
  """

  use GenServer

  require Logger

  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.{Batch, Receipt}
  alias Cadence.IngressJournal.{Entry, Evidence, FileSystem}

  @default_poll_interval_ms 10
  @default_max_batch_entries 128
  @default_max_batch_bytes 8 * 1_024 * 1_024
  @default_max_dwell_ms 25
  @default_retry_initial_ms 50
  @default_retry_max_ms 5_000
  @event_name [:cadence, :runtime, :ingress_archive_consumer, :persist_result]

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
      id: {:ingress_archive_consumer, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 10_000
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
      else: {:error, :ingress_archive_consumer_not_running}
  end

  def lookup(server) do
    case GenServer.whereis(server) do
      nil -> {:error, :ingress_archive_consumer_not_running}
      pid -> {:ok, pid}
    end
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:cadence, :ingress_archive_consumer, [])

    state = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
      path_id: Keyword.fetch!(opts, :path_id),
      provider_binding_id: Keyword.fetch!(opts, :provider_binding_id),
      journal_name: Keyword.fetch!(opts, :journal_name),
      archive_module: Keyword.get(opts, :archive_module, IngressArchive),
      required_completion:
        Keyword.get(
          opts,
          :required_completion,
          Keyword.get(config, :required_completion, :durable)
        ),
      poll_interval_ms:
        Keyword.get(
          opts,
          :poll_interval_ms,
          Keyword.get(config, :poll_interval_ms, @default_poll_interval_ms)
        ),
      max_batch_entries:
        Keyword.get(
          opts,
          :max_batch_entries,
          Keyword.get(config, :max_batch_entries, @default_max_batch_entries)
        ),
      max_batch_bytes:
        Keyword.get(
          opts,
          :max_batch_bytes,
          Keyword.get(config, :max_batch_bytes, @default_max_batch_bytes)
        ),
      max_dwell_ms:
        Keyword.get(
          opts,
          :max_dwell_ms,
          Keyword.get(config, :max_dwell_ms, @default_max_dwell_ms)
        ),
      retry_initial_ms:
        Keyword.get(
          opts,
          :retry_initial_ms,
          Keyword.get(config, :retry_initial_ms, @default_retry_initial_ms)
        ),
      retry_max_ms:
        Keyword.get(
          opts,
          :retry_max_ms,
          Keyword.get(config, :retry_max_ms, @default_retry_max_ms)
        ),
      retry_delay_ms:
        Keyword.get(
          opts,
          :retry_initial_ms,
          Keyword.get(config, :retry_initial_ms, @default_retry_initial_ms)
        ),
      pending: nil,
      dwell_started_at_ms: nil,
      attempt_count: 0,
      batch_count: 0,
      archived_entries: 0,
      archived_bytes: 0,
      failed_count: 0,
      retry_count: 0,
      last_completed_at: nil,
      last_failure_at: nil,
      last_recovered_at: nil,
      last_error: nil
    }

    with :ok <- validate_state(state) do
      send(self(), :consume)
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply,
     {:ok,
      %{
        provider_binding_id: state.provider_binding_id,
        required_completion: state.required_completion,
        pending_batch: pending_snapshot(state.pending),
        pending_entries: pending_value(state.pending, :item_count),
        pending_bytes: pending_value(state.pending, :byte_count),
        oldest_pending_age_ms: pending_age_ms(state.pending),
        dwell_age_ms: dwell_age_ms(state.dwell_started_at_ms),
        attempt_count: state.attempt_count,
        batch_count: state.batch_count,
        archived_entries: state.archived_entries,
        archived_bytes: state.archived_bytes,
        failed_count: state.failed_count,
        retry_count: state.retry_count,
        retry_delay_ms: state.retry_delay_ms,
        last_completed_at: state.last_completed_at,
        last_failure_at: state.last_failure_at,
        last_recovered_at: state.last_recovered_at,
        last_error: state.last_error
      }}, state}
  end

  @impl true
  def handle_info(:consume, %{pending: nil, dwell_started_at_ms: nil} = state) do
    case FileSystem.next_entries(
           state.journal_name,
           :archive,
           state.max_batch_entries,
           state.max_batch_bytes
         ) do
      {:ok, entries} ->
        if batch_threshold_reached?(state, entries) do
          build_and_persist(state, entries)
        else
          schedule(:flush, state.max_dwell_ms)
          {:noreply, %{state | dwell_started_at_ms: System.monotonic_time(:millisecond)}}
        end

      :empty ->
        schedule(:consume, state.poll_interval_ms)
        {:noreply, state}

      {:error, reason} ->
        fail_without_batch(state, reason)
    end
  end

  def handle_info(:consume, state), do: {:noreply, state}

  def handle_info(:flush, %{pending: nil} = state) do
    case FileSystem.next_entries(
           state.journal_name,
           :archive,
           state.max_batch_entries,
           state.max_batch_bytes
         ) do
      {:ok, entries} -> build_and_persist(state, entries)
      :empty -> resume_consuming(state)
      {:error, reason} -> fail_without_batch(state, reason)
    end
  end

  def handle_info(:flush, state), do: {:noreply, state}

  def handle_info(:retry, %{pending: %{batch: %Batch{} = batch}} = state) do
    persist_and_ack(state, batch, true)
  end

  def handle_info(:retry, state), do: {:noreply, state}

  defp build_and_persist(state, [%Entry{} | _rest] = entries) do
    first_entry = List.first(entries)
    last_entry = List.last(entries)

    case Evidence.from_entries(entries) do
      {:ok, raw_evidences} ->
        batch =
          Batch.new(
            first_entry.stream_id,
            first_entry.start_offset,
            last_entry.end_offset,
            raw_evidences
          )

        pending = %{
          batch: batch,
          item_count: batch.item_count,
          byte_count: batch.byte_count,
          oldest_receipt_time: first_entry.receipt_time
        }

        persist_and_ack(%{state | pending: pending, dwell_started_at_ms: nil}, batch, false)

      {:error, reason} ->
        fail_without_batch(state, reason)
    end
  end

  defp persist_and_ack(state, %Batch{} = batch, retry?) do
    started_at = System.monotonic_time()

    result =
      with {:ok, %Receipt{} = receipt} <- safe_persist(state.archive_module, batch),
           true <- Receipt.satisfies?(receipt, state.required_completion),
           :ok <- FileSystem.acknowledge(state.journal_name, :archive, batch.end_offset) do
        {:ok, receipt}
      else
        false ->
          {:error, {:archive_completion_below_required, state.required_completion}}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_archive_batch_result, other}}
      end

    duration_us = elapsed_us(started_at)
    emit_result(result, batch, duration_us, retry?)

    case result do
      {:ok, %Receipt{}} ->
        recovered_at = if state.last_error, do: DateTime.utc_now(), else: state.last_recovered_at
        send(self(), :consume)

        {:noreply,
         %{
           state
           | pending: nil,
             dwell_started_at_ms: nil,
             attempt_count: state.attempt_count + 1,
             batch_count: state.batch_count + 1,
             archived_entries: state.archived_entries + batch.item_count,
             archived_bytes: state.archived_bytes + batch.byte_count,
             retry_delay_ms: state.retry_initial_ms,
             last_completed_at: DateTime.utc_now(),
             last_recovered_at: recovered_at,
             last_error: nil
         }}

      {:error, reason} ->
        record_batch_failure(state, reason)
    end
  end

  defp record_batch_failure(state, reason) do
    Logger.warning(
      "Ingress archive batch failed for #{state.provider_binding_id}: #{inspect(reason)}"
    )

    schedule(:retry, state.retry_delay_ms)

    {:noreply,
     %{
       state
       | attempt_count: state.attempt_count + 1,
         failed_count: state.failed_count + 1,
         retry_count: state.retry_count + 1,
         retry_delay_ms: min(state.retry_delay_ms * 2, state.retry_max_ms),
         last_failure_at: DateTime.utc_now(),
         last_error: inspect(reason)
     }}
  end

  defp fail_without_batch(state, reason) do
    Logger.warning(
      "Ingress archive consumer failed for #{state.provider_binding_id}: #{inspect(reason)}"
    )

    schedule(:consume, state.retry_delay_ms)

    {:noreply,
     %{
       state
       | dwell_started_at_ms: nil,
         failed_count: state.failed_count + 1,
         retry_count: state.retry_count + 1,
         retry_delay_ms: min(state.retry_delay_ms * 2, state.retry_max_ms),
         last_failure_at: DateTime.utc_now(),
         last_error: inspect(reason)
     }}
  end

  defp safe_persist(archive_module, %Batch{} = batch) do
    archive_module.persist_batch(batch)
  rescue
    exception -> {:error, {:archive_sink_crash, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:archive_sink_crash, kind, reason}}
  end

  defp emit_result(result, %Batch{} = batch, duration_us, retry?) do
    metadata =
      case result do
        {:ok, %Receipt{} = receipt} ->
          %{outcome: :ok, completion: receipt.completion, error_type: nil, retry: retry?}

        {:error, reason} ->
          %{outcome: :error, completion: nil, error_type: error_type(reason), retry: retry?}
      end

    :telemetry.execute(
      @event_name,
      %{
        attempt_count: 1,
        batch_size: batch.item_count,
        byte_count: batch.byte_count,
        duration_us: duration_us
      },
      metadata
    )
  end

  defp validate_state(state) do
    valid? =
      state.required_completion in [:durable, :accepted] and
        positive_integer?(state.poll_interval_ms) and positive_integer?(state.max_batch_entries) and
        positive_integer?(state.max_batch_bytes) and positive_integer?(state.max_dwell_ms) and
        positive_integer?(state.retry_initial_ms) and positive_integer?(state.retry_max_ms) and
        state.retry_initial_ms <= state.retry_max_ms

    if valid?, do: :ok, else: {:stop, :invalid_ingress_archive_consumer_config}
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp pending_snapshot(nil), do: nil

  defp pending_snapshot(%{batch: %Batch{} = batch}) do
    %{
      batch_id: batch.batch_id,
      stream_id: batch.stream_id,
      start_offset: batch.start_offset,
      end_offset: batch.end_offset,
      item_count: batch.item_count,
      byte_count: batch.byte_count
    }
  end

  defp pending_value(nil, _key), do: 0
  defp pending_value(pending, key), do: Map.fetch!(pending, key)

  defp pending_age_ms(nil), do: 0

  defp pending_age_ms(%{oldest_receipt_time: %DateTime{} = receipt_time}) do
    max(DateTime.diff(DateTime.utc_now(), receipt_time, :millisecond), 0)
  end

  defp dwell_age_ms(nil), do: 0

  defp dwell_age_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp batch_threshold_reached?(state, entries) do
    length(entries) >= state.max_batch_entries or
      Enum.reduce(entries, 0, &(&1.payload_length + &2)) >= state.max_batch_bytes
  end

  defp resume_consuming(state) do
    schedule(:consume, state.poll_interval_ms)
    {:noreply, %{state | dwell_started_at_ms: nil}}
  end

  defp error_type(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_type({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_type({reason, _detail, _more}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_type(_reason), do: "archive_error"

  defp elapsed_us(started_at) do
    System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)
  end

  defp schedule(message, interval_ms), do: Process.send_after(self(), message, interval_ms)
end
