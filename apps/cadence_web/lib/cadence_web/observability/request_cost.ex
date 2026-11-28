defmodule CadenceWeb.Observability.RequestCost do
  @moduledoc """
  Measures the HTTP request up to response headers. Queries issued by a Task
  count towards the first request in its `$callers` chain.
  """

  import Plug.Conn

  require Logger

  @key {__MODULE__, :counters}
  @query_event [:cadence, :repo, :query]

  def setup do
    case :telemetry.attach(
           __MODULE__,
           @query_event,
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defoverridable call: 2

      def call(conn, opts) do
        # Register on the original conn so Phoenix's error renderer sees the callback too.
        unquote(__MODULE__).measure(conn, @request_cost, fn conn -> super(conn, opts) end)
      end
    end
  end

  def measure(conn, mode, dispatch) do
    counters = :atomics.new(2, signed: false)
    previous = Process.put(@key, counters)
    started_at = System.monotonic_time()

    conn =
      register_before_send(conn, fn conn ->
        cost = %{
          queries: :atomics.get(counters, 1),
          db_ms: milliseconds(:atomics.get(counters, 2)),
          wall_ms: milliseconds(System.monotonic_time() - started_at)
        }

        report(conn, cost, mode)
      end)

    try do
      dispatch.(conn)
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  @doc false
  def handle_event(@query_event, measurements, _metadata, _config) do
    counters = Process.get(@key) || caller_counters(Process.get(:"$callers", []))

    if counters do
      db_time =
        (measurements[:query_time] || 0) + (measurements[:decode_time] || 0) +
          (measurements[:queue_time] || 0)

      :atomics.add(counters, 1, 1)
      :atomics.add(counters, 2, db_time)
    end
  end

  defp caller_counters(callers) do
    Enum.find_value(callers, fn caller ->
      case Process.info(caller, {:dictionary, @key}) do
        {{:dictionary, @key}, counters} when is_reference(counters) -> counters
        _ -> nil
      end
    end)
  end

  defp report(conn, cost, :test), do: put_private(conn, :cadence_request_cost, cost)

  defp report(conn, cost, :dev) do
    Logger.info(
      Map.merge(cost, %{method: conn.method, route: route_pattern(conn), status: conn.status}),
      cadence_event: :request_cost
    )

    put_resp_header(
      conn,
      "x-cadence-db",
      "queries=#{cost.queries}; db_ms=#{cost.db_ms}; wall_ms=#{cost.wall_ms}"
    )
  end

  defp route_pattern(conn) do
    case Phoenix.Router.route_info(CadenceWeb.Router, conn.method, conn.path_info, conn.host) do
      %{route: pattern} -> pattern
      :error -> nil
    end
  end

  defp milliseconds(native) do
    System.convert_time_unit(native, :native, :microsecond) / 1_000
  end
end
