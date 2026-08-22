defmodule Cadence.Dashboards.SourceCircuitBreaker do
  @moduledoc """
  In-memory circuit breaker for physical dashboard data sources.

  The key includes tenant, mission, logical source, concrete data-source id,
  realm, and dataset so a degraded rehearsal/BYO source does not block unrelated
  flight or managed sources.
  """

  use GenServer

  alias Cadence.Dashboards.{PlannedSourceRequest, ResolvedSourceBinding}

  @type server :: GenServer.server()
  @type source_key :: {
          binary() | nil,
          binary() | nil,
          atom() | nil,
          binary() | nil,
          binary() | atom() | nil,
          binary() | nil
        }
  @type circuit_state :: :closed | :open | :half_open
  @type status :: %{
          state: circuit_state(),
          failure_count: non_neg_integer(),
          opened_at_ms: integer() | nil,
          retry_after_ms: integer() | nil,
          last_failure_reason: term(),
          failure_threshold: pos_integer(),
          backoff_ms: non_neg_integer()
        }

  @default_failure_threshold 3
  @default_backoff_ms 30_000

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, opts)
    else
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec source_key(PlannedSourceRequest.t(), ResolvedSourceBinding.t()) :: source_key()
  def source_key(%PlannedSourceRequest{} = request, %ResolvedSourceBinding{} = binding) do
    {
      request.organization_id,
      request.mission_id,
      request.logical_source,
      binding.data_source && binding.data_source.data_source_id,
      binding.realm,
      binding.dataset
    }
  end

  @spec allow?(source_key(), keyword()) :: {:allow, status()} | {:blocked, status()}
  def allow?(source_key, opts \\ []) do
    allow?(__MODULE__, source_key, configured_opts(opts))
  end

  @spec allow?(server(), source_key(), keyword()) :: {:allow, status()} | {:blocked, status()}
  def allow?(server, source_key, opts)
      when is_tuple(source_key) and is_list(opts) do
    case server_pid(server) do
      nil -> {:allow, closed_status(config(opts))}
      _pid -> GenServer.call(server, {:allow?, source_key, opts})
    end
  end

  @spec record_success(source_key(), keyword()) :: :ok
  def record_success(source_key, opts \\ []) do
    record_success(__MODULE__, source_key, opts)
  end

  @spec record_success(server(), source_key(), keyword()) :: :ok
  def record_success(server, source_key, opts)
      when is_tuple(source_key) and is_list(opts) do
    case server_pid(server) do
      nil -> :ok
      _pid -> GenServer.call(server, {:record_success, source_key})
    end
  end

  @spec record_failure(source_key(), term(), keyword()) :: status()
  def record_failure(source_key, reason, opts \\ []) do
    record_failure(__MODULE__, source_key, reason, configured_opts(opts))
  end

  @spec record_failure(server(), source_key(), term(), keyword()) :: status()
  def record_failure(server, source_key, reason, opts)
      when is_tuple(source_key) and is_list(opts) do
    case server_pid(server) do
      nil -> closed_status(config(opts))
      _pid -> GenServer.call(server, {:record_failure, source_key, reason, opts})
    end
  end

  @spec status(source_key(), keyword()) :: status()
  def status(source_key, opts \\ []) do
    status(__MODULE__, source_key, configured_opts(opts))
  end

  @spec status(server(), source_key(), keyword()) :: status()
  def status(server, source_key, opts)
      when is_tuple(source_key) and is_list(opts) do
    case server_pid(server) do
      nil -> closed_status(config(opts))
      _pid -> GenServer.call(server, {:status, source_key, opts})
    end
  end

  @spec reset(server()) :: :ok
  def reset(server \\ __MODULE__) do
    case server_pid(server) do
      nil -> :ok
      _pid -> GenServer.call(server, :reset)
    end
  end

  @impl true
  def init(opts) do
    default_config =
      if Keyword.get(opts, :runtime_composed?, false) do
        config(opts)
      else
        opts |> configured_opts() |> config()
      end

    {:ok, %{circuits: %{}, default_config: default_config}}
  end

  @impl true
  def handle_call({:allow?, source_key, opts}, _from, state) do
    config = call_config(state, opts)
    now_ms = now_ms(config)

    case Map.get(state.circuits, source_key) do
      nil ->
        {:reply, {:allow, closed_status(config)}, state}

      %{state: :closed} = status ->
        {:reply, {:allow, normalize_status(status, config)}, state}

      %{state: :half_open} = status ->
        {:reply, {:blocked, normalize_status(status, config)}, state}

      %{state: :open, retry_after_ms: retry_after_ms} = status
      when is_integer(retry_after_ms) and now_ms >= retry_after_ms ->
        half_open_status = status |> Map.put(:state, :half_open) |> normalize_status(config)

        {:reply, {:allow, half_open_status},
         %{state | circuits: Map.put(state.circuits, source_key, half_open_status)}}

      status ->
        {:reply, {:blocked, normalize_status(status, config)}, state}
    end
  end

  def handle_call({:record_success, source_key}, _from, state) do
    {:reply, :ok, %{state | circuits: Map.delete(state.circuits, source_key)}}
  end

  def handle_call({:record_failure, source_key, reason, opts}, _from, state) do
    config = call_config(state, opts)
    previous = Map.get(state.circuits, source_key, closed_status(config))
    failure_count = Map.get(previous, :failure_count, 0) + 1

    status =
      if open_after_failure?(previous, failure_count, config) do
        open_status(failure_count, reason, config)
      else
        previous
        |> Map.merge(%{
          state: :closed,
          failure_count: failure_count,
          last_failure_reason: reason,
          opened_at_ms: nil,
          retry_after_ms: nil
        })
        |> normalize_status(config)
      end

    {:reply, status, %{state | circuits: Map.put(state.circuits, source_key, status)}}
  end

  def handle_call({:status, source_key, opts}, _from, state) do
    config = call_config(state, opts)

    status =
      state.circuits
      |> Map.get(source_key, closed_status(config))
      |> normalize_status(config)

    {:reply, status, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | circuits: %{}}}
  end

  defp open_after_failure?(%{state: :half_open}, _failure_count, _config), do: true

  defp open_after_failure?(_previous, failure_count, config) do
    failure_count >= config.failure_threshold
  end

  defp open_status(failure_count, reason, config) do
    opened_at_ms = now_ms(config)

    %{
      state: :open,
      failure_count: failure_count,
      opened_at_ms: opened_at_ms,
      retry_after_ms: opened_at_ms + config.backoff_ms,
      last_failure_reason: reason
    }
    |> normalize_status(config)
  end

  defp closed_status(config) do
    %{
      state: :closed,
      failure_count: 0,
      opened_at_ms: nil,
      retry_after_ms: nil,
      last_failure_reason: nil
    }
    |> normalize_status(config)
  end

  defp normalize_status(status, config) do
    status
    |> Map.put(:failure_threshold, config.failure_threshold)
    |> Map.put(:backoff_ms, config.backoff_ms)
  end

  defp call_config(%{default_config: default_config}, opts) do
    %{
      failure_threshold:
        opts
        |> Keyword.get(:failure_threshold, default_config.failure_threshold)
        |> positive_integer(default_config.failure_threshold),
      backoff_ms:
        opts
        |> Keyword.get(:backoff_ms, default_config.backoff_ms)
        |> non_negative_integer(default_config.backoff_ms),
      now_ms: Keyword.get(opts, :now_ms, default_config.now_ms)
    }
  end

  defp config(opts) do
    %{
      failure_threshold:
        opts
        |> Keyword.get(:failure_threshold, @default_failure_threshold)
        |> positive_integer(@default_failure_threshold),
      backoff_ms:
        opts
        |> Keyword.get(:backoff_ms, @default_backoff_ms)
        |> non_negative_integer(@default_backoff_ms),
      now_ms: Keyword.get(opts, :now_ms)
    }
  end

  defp configured_opts(opts) do
    :cadence
    |> Application.get_env(:dashboard_source_circuit_breaker, [])
    |> Keyword.merge(opts)
  end

  defp now_ms(%{now_ms: now_ms}) when is_integer(now_ms), do: now_ms
  defp now_ms(_config), do: System.monotonic_time(:millisecond)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp server_pid(server) do
    cond do
      is_pid(server) and Process.alive?(server) ->
        server

      is_pid(server) ->
        nil

      true ->
        case GenServer.whereis(server) do
          pid when is_pid(pid) -> pid
          nil -> nil
        end
    end
  end
end
