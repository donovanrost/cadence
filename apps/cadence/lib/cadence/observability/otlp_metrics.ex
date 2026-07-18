defmodule Cadence.Observability.OtlpMetrics do
  @moduledoc false

  @protobuf_module :opentelemetry_exporter_metrics_service_pb
  @scope_name "cadence.metrics"

  @spec encode([map()]) :: binary()
  def encode(metrics) when is_list(metrics) do
    request = %{
      resource_metrics: [
        %{
          resource: %{attributes: resource_attributes()},
          scope_metrics: [
            %{
              scope: %{
                name: @scope_name,
                version: Application.spec(:cadence, :vsn) |> to_string()
              },
              metrics: Enum.map(metrics, &metric/1)
            }
          ]
        }
      ]
    }

    @protobuf_module.encode_msg(request, :export_metrics_service_request)
  end

  @spec decode_response(binary()) :: :ok | {:error, term()}
  def decode_response(<<>>), do: :ok

  def decode_response(body) when is_binary(body) do
    case @protobuf_module.decode_msg(body, :export_metrics_service_response) do
      %{partial_success: %{rejected_data_points: rejected}} when rejected > 0 ->
        {:error, {:partial_success, rejected}}

      _response ->
        :ok
    end
  rescue
    _exception -> {:error, :invalid_response}
  end

  defp metric(%{type: :counter} = metric) do
    base_metric(metric, {:sum, sum(metric.points)})
  end

  defp metric(%{type: :gauge} = metric) do
    base_metric(metric, {:gauge, %{data_points: Enum.map(metric.points, &number_point/1)}})
  end

  defp metric(%{type: :up_down_counter} = metric) do
    base_metric(metric, {:sum, up_down_sum(metric.points)})
  end

  defp metric(%{type: :histogram} = metric) do
    base_metric(metric, {:histogram, histogram(metric.points)})
  end

  defp base_metric(metric, data) do
    %{
      name: metric.name,
      description: metric.description,
      unit: metric.unit,
      data: data
    }
  end

  defp sum(points) do
    %{
      data_points: Enum.map(points, &number_point/1),
      aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA,
      is_monotonic: true
    }
  end

  defp up_down_sum(points) do
    %{
      data_points: Enum.map(points, &number_point/1),
      aggregation_temporality: :AGGREGATION_TEMPORALITY_CUMULATIVE,
      is_monotonic: false
    }
  end

  defp histogram(points) do
    %{
      data_points: Enum.map(points, &histogram_point/1),
      aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA
    }
  end

  defp number_point(point) do
    %{
      attributes: attributes(point.attributes),
      start_time_unix_nano: point.start_time_unix_nano,
      time_unix_nano: point.time_unix_nano,
      value: number_value(point.value)
    }
  end

  defp histogram_point(point) do
    %{
      attributes: attributes(point.attributes),
      start_time_unix_nano: point.start_time_unix_nano,
      time_unix_nano: point.time_unix_nano,
      count: point.count,
      sum: point.sum,
      bucket_counts: point.bucket_counts,
      explicit_bounds: point.explicit_bounds,
      min: point.min,
      max: point.max
    }
  end

  defp number_value(value) when is_integer(value), do: {:as_int, value}
  defp number_value(value) when is_float(value), do: {:as_double, value}

  defp attributes(attributes) do
    Enum.map(attributes, fn {key, value} ->
      %{key: key, value: any_value(value)}
    end)
  end

  defp resource_attributes do
    :otel_resource_detector.get_resource()
    |> :otel_resource.attributes()
    |> :otel_attributes.map()
    |> Enum.map(fn {key, value} -> %{key: to_string(key), value: any_value(value)} end)
  end

  defp any_value(value) when is_boolean(value), do: %{value: {:bool_value, value}}

  defp any_value(value)
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and
              value <= 9_223_372_036_854_775_807,
       do: %{value: {:int_value, value}}

  defp any_value(value) when is_integer(value),
    do: %{value: {:string_value, Integer.to_string(value)}}

  defp any_value(value) when is_float(value), do: %{value: {:double_value, value}}
  defp any_value(value) when is_binary(value), do: %{value: {:string_value, value}}
  defp any_value(value) when is_atom(value), do: %{value: {:string_value, Atom.to_string(value)}}
  defp any_value(value), do: %{value: {:string_value, inspect(value, limit: 20)}}
end
