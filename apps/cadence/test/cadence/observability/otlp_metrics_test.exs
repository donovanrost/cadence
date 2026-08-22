defmodule Cadence.Observability.OtlpMetricsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Observability.OtlpMetrics

  @protobuf_module :opentelemetry_exporter_metrics_service_pb

  test "encodes counters, gauges, and explicit-bucket histograms" do
    now = System.system_time(:nanosecond)

    payload =
      OtlpMetrics.encode([
        %{
          name: "cadence.test.counter",
          type: :counter,
          description: "Test counter.",
          unit: "{item}",
          points: [
            %{
              attributes: [{"outcome", "ok"}],
              value: 3,
              start_time_unix_nano: now - 10,
              time_unix_nano: now
            }
          ]
        },
        %{
          name: "cadence.test.gauge",
          type: :gauge,
          description: "Test gauge.",
          unit: "1",
          points: [
            %{
              attributes: [],
              value: 0.5,
              start_time_unix_nano: now,
              time_unix_nano: now
            }
          ]
        },
        %{
          name: "cadence.test.duration",
          type: :histogram,
          description: "Test duration.",
          unit: "s",
          points: [
            %{
              attributes: [],
              count: 2,
              sum: 0.3,
              min: 0.1,
              max: 0.2,
              bucket_counts: [1, 1, 0],
              explicit_bounds: [0.1, 0.5],
              start_time_unix_nano: now - 10,
              time_unix_nano: now
            }
          ]
        }
      ])

    request = @protobuf_module.decode_msg(payload, :export_metrics_service_request)
    [resource_metrics] = request.resource_metrics
    [scope_metrics] = resource_metrics.scope_metrics

    assert Enum.map(scope_metrics.metrics, & &1.name) == [
             "cadence.test.counter",
             "cadence.test.gauge",
             "cadence.test.duration"
           ]

    [counter, gauge, histogram] = scope_metrics.metrics

    assert {:sum, %{aggregation_temporality: :AGGREGATION_TEMPORALITY_CUMULATIVE}} =
             counter.data

    assert {:gauge, %{data_points: [%{value: {:as_double, 0.5}}]}} = gauge.data

    assert {:histogram,
            %{
              aggregation_temporality: :AGGREGATION_TEMPORALITY_CUMULATIVE,
              data_points: [
                %{
                  count: 2,
                  explicit_bounds: [0.1, 0.5],
                  bucket_counts: [1, 1, 0]
                }
              ]
            }} = histogram.data
  end

  test "reports rejected data points from partial success responses" do
    response =
      @protobuf_module.encode_msg(
        %{partial_success: %{rejected_data_points: 2, error_message: "bad points"}},
        :export_metrics_service_response
      )

    assert OtlpMetrics.decode_response(response) == {:error, {:partial_success, 2}}
    assert OtlpMetrics.decode_response(<<>>) == :ok
  end
end
