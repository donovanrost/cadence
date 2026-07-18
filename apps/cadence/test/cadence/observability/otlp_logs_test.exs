defmodule Cadence.Observability.OtlpLogsTest do
  use ExUnit.Case, async: true

  alias Cadence.Observability.OtlpLogs

  @protobuf_module :opentelemetry_exporter_logs_service_pb

  test "encodes Logger events as correlated OTLP log records" do
    trace_id = "0123456789abcdef0123456789abcdef"
    span_id = "0123456789abcdef"

    payload =
      OtlpLogs.encode([
        %{
          level: :warning,
          msg: {:string, "Telemetry ingress processing failed"},
          meta: %{
            time: 1_700_000_000_000_000,
            cadence_event: "cadence.telemetry.ingress.failed",
            error_class: "timeout",
            file: ~c"lib/cadence/runtime/provider_ingress_executor.ex",
            mission_id: "mission-test",
            mfa: {Cadence.Runtime.ProviderIngressExecutor, :handle_info, 2},
            otel_span_id: span_id,
            otel_trace_flags: "01",
            otel_trace_id: trace_id
          }
        }
      ])

    request = @protobuf_module.decode_msg(payload, :export_logs_service_request)
    [resource_logs] = request.resource_logs
    [scope_logs] = resource_logs.scope_logs
    [record] = scope_logs.log_records

    assert scope_logs.scope.name == "cadence.logger"
    assert record.body.value == {:string_value, "Telemetry ingress processing failed"}
    assert record.severity_number == :SEVERITY_NUMBER_WARN
    assert record.severity_text == "WARNING"
    assert record.time_unix_nano == 1_700_000_000_000_000_000
    assert record.trace_id == Base.decode16!(trace_id, case: :mixed)
    assert record.span_id == Base.decode16!(span_id, case: :mixed)
    assert record.flags == 1

    attributes = attributes_map(record.attributes)

    assert attributes["event.name"] == {:string_value, "cadence.telemetry.ingress.failed"}
    assert attributes["error.type"] == {:string_value, "timeout"}
    assert attributes["cadence.mission.id"] == {:string_value, "mission-test"}

    assert attributes["code.namespace"] ==
             {:string_value, "Cadence.Runtime.ProviderIngressExecutor"}

    assert attributes["code.function.name"] == {:string_value, "handle_info/2"}

    assert attributes["code.file.path"] ==
             {:string_value, "lib/cadence/runtime/provider_ingress_executor.ex"}

    resource_attributes = attributes_map(resource_logs.resource.attributes)
    assert {:string_value, _service_name} = resource_attributes["service.name"]
    assert {:string_value, _instance_id} = resource_attributes["service.instance.id"]
  end

  test "omits invalid trace context and arbitrary Logger metadata" do
    payload =
      OtlpLogs.encode([
        %{
          level: :info,
          msg: {:string, "bounded"},
          meta: %{
            time: 1_700_000_000_000_000,
            arbitrary_provider_metadata: %{secret: "not exported"},
            otel_span_id: "bad",
            otel_trace_id: "bad"
          }
        }
      ])

    request = @protobuf_module.decode_msg(payload, :export_logs_service_request)
    [resource_logs] = request.resource_logs
    [scope_logs] = resource_logs.scope_logs
    [record] = scope_logs.log_records

    assert record.trace_id == ""
    assert record.span_id == ""
    assert record.attributes == []
  end

  test "detects partially rejected OTLP responses" do
    response =
      @protobuf_module.encode_msg(
        %{partial_success: %{rejected_log_records: 2, error_message: "bad records"}},
        :export_logs_service_response
      )

    assert OtlpLogs.decode_response(<<>>) == :ok
    assert OtlpLogs.decode_response(response) == {:error, {:partial_success, 2}}
    assert OtlpLogs.decode_response("not protobuf") == {:error, :invalid_response}
  end

  defp attributes_map(attributes) do
    Map.new(attributes, fn attribute -> {attribute.key, attribute.value.value} end)
  end
end
