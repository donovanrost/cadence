defmodule Cadence.Observability.LogExporterTest do
  use ExUnit.Case, async: false

  alias Cadence.Observability
  alias Cadence.Observability.LogExporter

  @protobuf_module :opentelemetry_exporter_logs_service_pb
  @handler_id :cadence_otel_logs_test

  setup do
    on_exit(fn -> :logger.remove_handler(@handler_id) end)
    :ok
  end

  test "batches events without blocking Logger clients" do
    test_pid = self()

    exporter =
      start_supervised!({
        LogExporter,
        name: nil,
        endpoint: "http://unused.test/v1/logs",
        install_handler?: false,
        batch_size: 2,
        flush_interval_ms: 60_000,
        export_fun: fn payload ->
          send(test_pid, {:payload, payload})
          :ok
        end
      })

    assert :ok = LogExporter.ingest(exporter, log_event("first"))
    assert :ok = LogExporter.ingest(exporter, log_event("second"))
    assert_receive {:payload, payload}, 1_000

    assert log_bodies(payload) == ["first", "second"]

    assert LogExporter.status(exporter) == %{
             queued_count: 0,
             sent_count: 2,
             failed_count: 0,
             dropped_count: 0
           }
  end

  test "counts failed exports and remains alive" do
    exporter =
      start_supervised!({
        LogExporter,
        name: nil,
        endpoint: "http://unused.test/v1/logs",
        install_handler?: false,
        flush_interval_ms: 60_000,
        export_fun: fn _payload -> {:error, :collector_down} end
      })

    LogExporter.ingest(exporter, log_event("not delivered"))
    assert :ok = LogExporter.flush(exporter)

    assert LogExporter.status(exporter) == %{
             queued_count: 0,
             sent_count: 0,
             failed_count: 1,
             dropped_count: 0
           }

    assert Process.alive?(exporter)
  end

  test "Logger handler exports active trace context over OTLP" do
    test_pid = self()

    exporter =
      start_supervised!({
        LogExporter,
        name: nil,
        endpoint: "http://unused.test/v1/logs",
        handler_id: @handler_id,
        level: :warning,
        flush_interval_ms: 60_000,
        export_fun: fn payload ->
          send(test_pid, {:payload, payload})
          :ok
        end
      })

    trace_id =
      Observability.with_root_span("test.logger.network_export", %{}, fn ->
        trace_id =
          Observability.current_span_context()
          |> OpenTelemetry.Span.hex_trace_id()

        Observability.log(
          :warning,
          "cadence.test.network_log",
          "Network log bridge verification",
          mission_id: "mission-network-test"
        )

        trace_id
      end)

    assert :ok = LogExporter.flush(exporter)
    assert_receive {:payload, payload}, 1_000

    record =
      payload
      |> log_records()
      |> Enum.find(fn record ->
        record.body.value == {:string_value, "Network log bridge verification"}
      end)

    assert record
    assert record.trace_id == Base.decode16!(trace_id, case: :mixed)
    assert byte_size(record.span_id) == 8

    attributes = Map.new(record.attributes, &{&1.key, &1.value.value})
    assert attributes["event.name"] == {:string_value, "cadence.test.network_log"}
    assert attributes["cadence.mission.id"] == {:string_value, "mission-network-test"}
  end

  defp log_event(message) do
    %{
      level: :info,
      msg: {:string, message},
      meta: %{time: System.system_time(:microsecond)}
    }
  end

  defp log_bodies(payload) do
    Enum.map(log_records(payload), fn record ->
      {:string_value, body} = record.body.value
      body
    end)
  end

  defp log_records(payload) do
    request = @protobuf_module.decode_msg(payload, :export_logs_service_request)

    for resource_logs <- request.resource_logs,
        scope_logs <- resource_logs.scope_logs,
        record <- scope_logs.log_records do
      record
    end
  end
end
