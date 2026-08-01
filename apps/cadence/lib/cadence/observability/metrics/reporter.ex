defmodule Cadence.Observability.Metrics.Reporter do
  @moduledoc """
  Bounded asynchronous reporter from Cadence `:telemetry` events to OTLP metrics.
  """

  use GenServer

  alias Cadence.Observability.Metrics.{Catalog, Definition, Handler}
  alias Cadence.Observability.OtlpMetrics

  @default_export_interval_ms 10_000
  @default_max_queue 10_000
  @default_max_series 5_000
  @default_timeout_ms 5_000

  @type status :: %{
          series_count: non_neg_integer(),
          exported_data_point_count: non_neg_integer(),
          failed_data_point_count: non_neg_integer(),
          dropped_data_point_count: non_neg_integer(),
          last_export_at: DateTime.t() | nil,
          last_error: term() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  @spec record(GenServer.server(), binary(), number(), map()) :: :ok
  def record(server \\ __MODULE__, name, value, attributes \\ %{})
      when is_binary(name) and is_number(value) and is_map(attributes) do
    send(server, {:otel_metric_record, name, value, attributes, System.system_time(:nanosecond)})
    :ok
  end

  @spec flush(GenServer.server(), timeout()) :: :ok
  def flush(server \\ __MODULE__, timeout \\ 10_000), do: GenServer.call(server, :flush, timeout)

  @spec status(GenServer.server()) :: status()
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @impl true
  def init(opts) do
    definitions = Keyword.get(opts, :definitions, Catalog.definitions())
    definitions_by_event = Enum.group_by(definitions, & &1.event_name)
    drop_counter = :atomics.new(1, signed: false)

    state = %{
      definitions: Map.new(definitions, &{&1.name, &1}),
      definitions_by_event: Map.delete(definitions_by_event, nil),
      drop_counter: drop_counter,
      endpoint: Keyword.fetch!(opts, :endpoint),
      export_fun: Keyword.get(opts, :export_fun),
      export_interval_ms: Keyword.get(opts, :export_interval_ms, @default_export_interval_ms),
      exported_data_point_count: 0,
      failed_data_point_count: 0,
      dropped_data_point_count: 0,
      handler_id: Keyword.get(opts, :handler_id, default_handler_id()),
      headers: Keyword.get(opts, :headers, []),
      last_error: nil,
      last_export_at: nil,
      max_queue: Keyword.get(opts, :max_queue, @default_max_queue),
      max_series: Keyword.get(opts, :max_series, @default_max_series),
      series: %{},
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    }

    with :ok <- validate_state(state),
         :ok <- attach_handler(state, Keyword.get(opts, :name, __MODULE__) || self()) do
      schedule_export(state.export_interval_ms)
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:otel_metric_event, event_name, measurements, metadata, observed_at}, state) do
    state =
      state.definitions_by_event
      |> Map.get(event_name, [])
      |> Enum.reduce(state, fn definition, acc ->
        record_definition(acc, definition, measurements, metadata, observed_at)
      end)

    {:noreply, state}
  end

  def handle_info({:otel_metric_record, name, value, attributes, observed_at}, state) do
    state =
      case Map.get(state.definitions, name) do
        %Definition{} = definition ->
          record_value(
            state,
            definition,
            value,
            direct_record_attributes(definition, attributes),
            observed_at
          )

        nil ->
          %{state | dropped_data_point_count: state.dropped_data_point_count + 1}
      end

    {:noreply, state}
  end

  def handle_info(:export, state) do
    schedule_export(state.export_interval_ms)
    {:noreply, export(state)}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, export(state)}
  end

  def handle_call(:status, _from, state) do
    status = %{
      series_count: map_size(state.series),
      exported_data_point_count: state.exported_data_point_count,
      failed_data_point_count: state.failed_data_point_count,
      dropped_data_point_count:
        state.dropped_data_point_count + :atomics.get(state.drop_counter, 1),
      last_export_at: state.last_export_at,
      last_error: state.last_error
    }

    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  defp validate_state(state) do
    valid_definitions? =
      state.definitions
      |> Map.values()
      |> Enum.all?(&Catalog.valid_definition?/1)

    valid? =
      is_binary(state.endpoint) and state.endpoint != "" and
        positive_integer?(state.export_interval_ms) and
        positive_integer?(state.max_queue) and
        positive_integer?(state.max_series) and
        positive_integer?(state.timeout_ms) and
        valid_definitions?

    if valid?, do: :ok, else: {:error, :invalid_config}
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp attach_handler(state, worker) do
    _ = :telemetry.detach(state.handler_id)

    :telemetry.attach_many(
      state.handler_id,
      Map.keys(state.definitions_by_event),
      &Handler.handle_event/4,
      %{worker: worker, max_queue: state.max_queue, drop_counter: state.drop_counter}
    )
  end

  defp default_handler_id do
    "#{__MODULE__}.#{System.unique_integer([:positive])}"
  end

  defp record_definition(state, definition, measurements, metadata, observed_at) do
    if keep?(definition, measurements, metadata) do
      value = measurement(definition, measurements, metadata)
      attributes = attributes(definition, metadata)

      if is_number(value) do
        record_value(state, definition, value, attributes, observed_at)
      else
        state
      end
    else
      state
    end
  rescue
    _exception ->
      %{state | dropped_data_point_count: state.dropped_data_point_count + 1}
  end

  defp keep?(%Definition{keep: nil}, _measurements, _metadata), do: true
  defp keep?(%Definition{keep: keep}, measurements, metadata), do: keep.(measurements, metadata)

  defp measurement(%Definition{measurement: measurement}, measurements, metadata)
       when is_function(measurement, 2) do
    measurement.(measurements, metadata)
  end

  defp measurement(%Definition{measurement: measurement}, measurements, _metadata) do
    Map.get(measurements, measurement)
  end

  defp attributes(%Definition{attributes: allowed, tag_values: nil}, metadata) do
    metadata
    |> stringify_keys()
    |> Map.take(allowed)
    |> compact_attributes()
  end

  defp attributes(%Definition{attributes: allowed, tag_values: tag_values}, metadata) do
    metadata
    |> tag_values.()
    |> stringify_keys()
    |> Map.take(allowed)
    |> compact_attributes()
  end

  defp direct_record_attributes(%Definition{attributes: allowed}, attributes) do
    attributes
    |> stringify_keys()
    |> Map.take(allowed)
    |> compact_attributes()
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp compact_attributes(attributes) do
    attributes
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {key, value} -> {key, normalize_attribute(value)} end)
    |> Enum.sort()
  end

  defp normalize_attribute(value) when is_boolean(value), do: value
  defp normalize_attribute(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_attribute(value) when is_binary(value), do: value
  defp normalize_attribute(value) when is_number(value), do: value
  defp normalize_attribute(value), do: inspect(value, limit: 20)

  defp record_value(state, definition, value, attributes, observed_at) do
    key = {definition.name, attributes}

    cond do
      Map.has_key?(state.series, key) ->
        update_series(state, key, definition, value, observed_at)

      map_size(state.series) < state.max_series ->
        put_series(state, key, definition, value, observed_at)

      true ->
        %{state | dropped_data_point_count: state.dropped_data_point_count + 1}
    end
  end

  defp put_series(state, key, definition, value, observed_at) do
    series = initial_series(definition, value, observed_at)
    %{state | series: Map.put(state.series, key, series)}
  end

  defp update_series(state, key, definition, value, observed_at) do
    series = Map.fetch!(state.series, key)
    updated = update_series_value(series, definition, value, observed_at)
    %{state | series: Map.put(state.series, key, updated)}
  end

  defp initial_series(%Definition{type: :counter}, value, observed_at) do
    %{value: value, start_time_unix_nano: observed_at, time_unix_nano: observed_at}
  end

  defp initial_series(%Definition{type: type}, value, observed_at)
       when type in [:gauge, :up_down_counter] do
    %{value: value, start_time_unix_nano: observed_at, time_unix_nano: observed_at}
  end

  defp initial_series(%Definition{type: :histogram, buckets: buckets}, value, observed_at) do
    %{
      count: 1,
      sum: value,
      min: value,
      max: value,
      bucket_counts: increment_bucket(List.duplicate(0, length(buckets) + 1), buckets, value),
      explicit_bounds: buckets,
      start_time_unix_nano: observed_at,
      time_unix_nano: observed_at
    }
  end

  defp update_series_value(series, %Definition{type: :counter}, value, observed_at) do
    %{series | value: series.value + value, time_unix_nano: observed_at}
  end

  defp update_series_value(series, %Definition{type: :gauge}, value, observed_at) do
    %{series | value: value, time_unix_nano: observed_at}
  end

  defp update_series_value(series, %Definition{type: :up_down_counter}, value, observed_at) do
    %{series | value: series.value + value, time_unix_nano: observed_at}
  end

  defp update_series_value(
         series,
         %Definition{type: :histogram, buckets: buckets},
         value,
         observed_at
       ) do
    %{
      series
      | count: series.count + 1,
        sum: series.sum + value,
        min: min(series.min, value),
        max: max(series.max, value),
        bucket_counts: increment_bucket(series.bucket_counts, buckets, value),
        time_unix_nano: observed_at
    }
  end

  defp increment_bucket(counts, bounds, value) do
    index = Enum.find_index(bounds, &(value <= &1)) || length(bounds)
    List.update_at(counts, index, &(&1 + 1))
  end

  defp export(%{series: series} = state) when map_size(series) == 0, do: state

  defp export(state) do
    metrics = export_metrics(state)
    data_point_count = Enum.reduce(metrics, 0, &(length(&1.points) + &2))

    with {:ok, payload} <- encode(metrics),
         :ok <- send_payload(payload, state) do
      %{
        state
        | exported_data_point_count: state.exported_data_point_count + data_point_count,
          last_export_at: DateTime.utc_now(),
          last_error: nil
      }
    else
      {:error, reason} ->
        %{
          state
          | failed_data_point_count: state.failed_data_point_count + data_point_count,
            last_error: reason
        }
    end
  end

  defp export_metrics(state) do
    state.series
    |> Enum.group_by(fn {{name, _attributes}, _series} -> name end)
    |> Enum.map(fn {name, entries} ->
      definition = Map.fetch!(state.definitions, name)

      %{
        name: name,
        type: definition.type,
        description: definition.description,
        unit: definition.unit,
        points:
          Enum.map(entries, fn {{_name, attributes}, series} ->
            Map.put(series, :attributes, attributes)
          end)
      }
    end)
  end

  defp encode(metrics) do
    {:ok, OtlpMetrics.encode(metrics)}
  rescue
    _exception -> {:error, :encoding_failed}
  catch
    _kind, _reason -> {:error, :encoding_failed}
  end

  defp send_payload(payload, %{export_fun: export_fun}) when is_function(export_fun, 1) do
    export_fun.(payload)
  rescue
    _exception -> {:error, :export_failed}
  catch
    _kind, _reason -> {:error, :export_failed}
  end

  defp send_payload(payload, state) do
    headers = [{"content-type", "application/x-protobuf"} | state.headers]

    case Req.post(state.endpoint,
           body: payload,
           headers: headers,
           receive_timeout: state.timeout_ms,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        OtlpMetrics.decode_response(body)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_export(interval_ms) do
    Process.send_after(self(), :export, interval_ms)
  end
end
