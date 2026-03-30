defmodule Cadence.Runtime.IngressPersistenceProjector do
  @moduledoc """
  Path-local async persistence worker for processed ingress batches.

  The live ingress lane can stay focused on ordered resolve/runtime work while
  this projector owns the slower durable writes and archive fan-out.
  """

  use GenServer

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.ProcessedIngressBatch
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @default_retry_delay_ms 100

  @type state :: %{
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          provider_binding_id: binary(),
          queue: :queue.queue(ProcessedIngressBatch.t()),
          queue_depth: non_neg_integer(),
          processing?: boolean(),
          retry_delay_ms: pos_integer(),
          enqueued_count: non_neg_integer(),
          persisted_count: non_neg_integer(),
          failed_count: non_neg_integer(),
          last_completed_at: DateTime.t() | nil,
          last_error: binary() | nil
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
       queue: :queue.new(),
       queue_depth: 0,
       processing?: false,
       retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms),
       enqueued_count: 0,
       persisted_count: 0,
       failed_count: 0,
       last_completed_at: nil,
       last_error: nil
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
        enqueued_count: state.enqueued_count,
        persisted_count: state.persisted_count,
        failed_count: state.failed_count,
        last_completed_at: state.last_completed_at,
        last_error: state.last_error
      }}, state}
  end

  @impl true
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
  def handle_info(:process_queue, state) do
    case :queue.out(state.queue) do
      {{:value, %ProcessedIngressBatch{} = batch}, rest} ->
        case persist_batch(batch) do
          :ok ->
            next_state = %{
              state
              | queue: rest,
                queue_depth: max(state.queue_depth - ProcessedIngressBatch.size(batch), 0),
                persisted_count: state.persisted_count + ProcessedIngressBatch.size(batch),
                last_completed_at: DateTime.utc_now(),
                last_error: nil
            }

            if next_state.queue_depth > 0 do
              send(self(), :process_queue)
              {:noreply, %{next_state | processing?: true}}
            else
              {:noreply, %{next_state | processing?: false}}
            end

          {:error, reason} ->
            Logger.warning(
              "Ingress persistence projector failed for #{state.provider_binding_id}: #{inspect(reason)}"
            )

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

      {:empty, _queue} ->
        {:noreply, %{state | queue_depth: 0, processing?: false}}
    end
  end

  defp persist_batch(%ProcessedIngressBatch{
         mission_id: mission_id,
         processing_results: processing_results
       })
       when is_list(processing_results) and processing_results != [] do
    persistence_started_at = System.monotonic_time()

    result =
      run_persistence(fn ->
        raw_evidence = first_raw_evidence(processing_results)

        TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
          TelemetryProfiler.with_stage(:persistence, fn ->
            Enum.reduce_while(processing_results, :ok, fn processing_result, :ok ->
              case Cadence.Persistence.persist_processing_result(
                     processing_result,
                     record_current_values?:
                       not Cadence.Telemetry.CurrentValueStore.hot_path_safe?()
                   ) do
                {:ok, _persisted_result} -> {:cont, :ok}
                {:error, reason} -> {:halt, {:error, reason}}
              end
            end)
          end)
        end)
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

  defp persist_batch(%ProcessedIngressBatch{}), do: {:error, :empty_batch}

  defp first_raw_evidence([%{raw_evidence: %RawEvidence{} = raw_evidence} | _rest]),
    do: raw_evidence

  defp first_raw_evidence([]), do: raise(ArgumentError, "processed ingress batch is empty")

  defp elapsed_us(started_at),
    do: System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)

  defp run_persistence(fun) when is_function(fun, 0) do
    try do
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
end
