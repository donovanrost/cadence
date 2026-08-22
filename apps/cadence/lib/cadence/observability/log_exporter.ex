defmodule Cadence.Observability.LogExporter do
  @moduledoc """
  Bounded, asynchronous bridge from BEAM Logger events to OTLP/HTTP logs.
  """

  use GenServer

  alias Cadence.Observability.{LoggerHandler, OtlpLogs}

  @default_batch_size 100
  @default_flush_interval_ms 1_000
  @default_handler_id :cadence_otel_logs
  @default_max_queue 5_000
  @default_max_retries 2
  @default_retry_initial_ms 1_000
  @default_timeout_ms 5_000

  @type status :: %{
          queued_count: non_neg_integer(),
          sent_count: non_neg_integer(),
          failed_count: non_neg_integer(),
          dropped_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  @spec ingest(GenServer.server(), map()) :: :ok
  def ingest(server, event) when is_map(event) do
    send(server, {:otel_log, event})
    :ok
  end

  @spec flush(GenServer.server(), timeout()) :: :ok
  def flush(server, timeout \\ 10_000), do: GenServer.call(server, :flush, timeout)

  @spec status(GenServer.server()) :: status()
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(opts) do
    state = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      body_limit: Keyword.get(opts, :body_limit, 16_384),
      dropped_count: 0,
      endpoint: Keyword.fetch!(opts, :endpoint),
      export_fun: Keyword.get(opts, :export_fun),
      failed_count: 0,
      flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
      flush_pending?: false,
      handler_id: Keyword.get(opts, :handler_id, @default_handler_id),
      handler_installed?: false,
      headers: Keyword.get(opts, :headers, []),
      level: Keyword.get(opts, :level, :info),
      logs: [],
      max_queue: Keyword.get(opts, :max_queue, @default_max_queue),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      queued_count: 0,
      retry_initial_ms: Keyword.get(opts, :retry_initial_ms, @default_retry_initial_ms),
      sent_count: 0,
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    }

    with :ok <- validate_state(state),
         {:ok, state} <- maybe_install_handler(state, opts) do
      schedule_periodic_flush(state.flush_interval_ms)
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:otel_log, event}, state) when is_map(event) do
    state =
      if state.queued_count < state.max_queue do
        %{state | logs: [event | state.logs], queued_count: state.queued_count + 1}
      else
        %{state | dropped_count: state.dropped_count + 1}
      end

    if state.queued_count >= state.batch_size and not state.flush_pending? do
      send(self(), :flush)
      {:noreply, %{state | flush_pending?: true}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:flush, state) do
    state =
      state
      |> Map.put(:flush_pending?, false)
      |> flush_one_batch()
      |> maybe_schedule_immediate_flush()

    {:noreply, state}
  end

  def handle_info(:periodic_flush, state) do
    schedule_periodic_flush(state.flush_interval_ms)
    {:noreply, state |> flush_one_batch() |> maybe_schedule_immediate_flush()}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, flush_all(state)}
  end

  def handle_call(:status, _from, state) do
    status = %{
      queued_count: state.queued_count,
      sent_count: state.sent_count,
      failed_count: state.failed_count,
      dropped_count: state.dropped_count
    }

    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.handler_installed? do
      _ = :logger.remove_handler(state.handler_id)
    end

    :ok
  end

  defp validate_state(state) do
    positive_integers = [
      state.batch_size,
      state.flush_interval_ms,
      state.max_queue,
      state.timeout_ms
    ]

    valid? =
      is_binary(state.endpoint) and state.endpoint != "" and
        Enum.all?(positive_integers, &positive_integer?/1) and
        non_negative_integer?(state.max_retries) and
        non_negative_integer?(state.retry_initial_ms)

    if valid?, do: :ok, else: {:error, :invalid_config}
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp maybe_install_handler(state, opts) do
    if Keyword.get(opts, :install_handler?, true) do
      worker = Keyword.get(opts, :name, __MODULE__) || self()

      handler_config = %{
        level: state.level,
        config: %{worker: worker, max_queue: state.max_queue}
      }

      _ = :logger.remove_handler(state.handler_id)

      case :logger.add_handler(state.handler_id, LoggerHandler, handler_config) do
        :ok -> {:ok, %{state | handler_installed?: true}}
        {:error, reason} -> {:error, {:logger_handler, reason}}
      end
    else
      {:ok, state}
    end
  end

  defp flush_all(%{queued_count: 0} = state), do: state

  defp flush_all(state) do
    state
    |> flush_one_batch()
    |> flush_all()
  end

  defp flush_one_batch(%{queued_count: 0} = state), do: state

  defp flush_one_batch(state) do
    {batch, remaining_logs} =
      state.logs
      |> Enum.reverse()
      |> Enum.split(state.batch_size)

    next_state = %{
      state
      | logs: Enum.reverse(remaining_logs),
        queued_count: state.queued_count - length(batch)
    }

    case encode_batch(batch, state.body_limit) do
      {:ok, payload} ->
        case export(payload, state) do
          :ok ->
            %{next_state | sent_count: state.sent_count + length(batch)}

          {:error, _reason} ->
            %{next_state | failed_count: state.failed_count + length(batch)}
        end

      {:error, _reason} ->
        %{next_state | failed_count: state.failed_count + length(batch)}
    end
  end

  defp encode_batch(batch, body_limit) do
    {:ok, OtlpLogs.encode(batch, body_limit: body_limit)}
  rescue
    _exception -> {:error, :encoding_failed}
  catch
    _kind, _reason -> {:error, :encoding_failed}
  end

  defp export(payload, %{export_fun: export_fun}) when is_function(export_fun, 1) do
    export_fun.(payload)
  rescue
    _exception -> {:error, :export_failed}
  catch
    _kind, _reason -> {:error, :export_failed}
  end

  defp export(payload, state) do
    headers = [{"content-type", "application/x-protobuf"} | state.headers]

    case Req.post(state.endpoint,
           body: payload,
           headers: headers,
           receive_timeout: state.timeout_ms,
           retry: :transient,
           max_retries: state.max_retries,
           retry_delay: retry_delay(state.retry_initial_ms),
           retry_log_level: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        OtlpLogs.decode_response(body)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_periodic_flush(interval_ms) do
    Process.send_after(self(), :periodic_flush, interval_ms)
  end

  defp maybe_schedule_immediate_flush(state) do
    if state.queued_count >= state.batch_size and not state.flush_pending? do
      send(self(), :flush)
      %{state | flush_pending?: true}
    else
      state
    end
  end

  defp retry_delay(initial_ms) do
    fn retry_count -> initial_ms * Integer.pow(2, retry_count) end
  end
end
