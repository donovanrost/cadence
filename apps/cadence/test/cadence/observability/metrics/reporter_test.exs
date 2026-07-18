defmodule Cadence.Observability.Metrics.ReporterTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Observability.Metrics.{Definition, Reporter}

  @protobuf_module :opentelemetry_exporter_metrics_service_pb
  @event [:cadence, :test, :metric]

  setup do
    handler_id = "metrics-reporter-test-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    %{handler_id: handler_id}
  end

  test "aggregates telemetry events and exports delta metric points", %{handler_id: handler_id} do
    parent = self()

    {:ok, reporter} =
      start_supervised(
        {Reporter,
         endpoint: "http://collector.invalid/v1/metrics",
         definitions: definitions(),
         export_interval_ms: 60_000,
         export_fun: fn payload ->
           send(parent, {:metric_payload, payload})
           :ok
         end,
         handler_id: handler_id,
         name: nil}
      )

    :telemetry.execute(@event, %{count: 2, duration: 0.2}, %{outcome: :ok})
    :telemetry.execute(@event, %{count: 3, duration: 0.8}, %{outcome: :ok})

    assert :ok = Reporter.flush(reporter)
    assert_receive {:metric_payload, payload}

    metrics = decode_metrics(payload)
    counter = Enum.find(metrics, &(&1.name == "cadence.test.item"))
    histogram = Enum.find(metrics, &(&1.name == "cadence.test.duration"))

    assert {:sum, %{data_points: [%{value: {:as_int, 5}}]}} = counter.data

    assert {:histogram,
            %{
              data_points: [
                %{
                  count: 2,
                  sum: 1.0,
                  min: 0.2,
                  max: 0.8,
                  bucket_counts: [1, 1, 0]
                }
              ]
            }} = histogram.data

    assert %{
             series_count: 0,
             exported_data_point_count: 2,
             failed_data_point_count: 0
           } = Reporter.status(reporter)
  end

  test "retains points after export failure and bounds series cardinality", %{
    handler_id: handler_id
  } do
    {:ok, reporter} =
      start_supervised(
        {Reporter,
         endpoint: "http://collector.invalid/v1/metrics",
         definitions: definitions(),
         export_interval_ms: 60_000,
         export_fun: fn _payload -> {:error, :collector_down} end,
         handler_id: handler_id,
         max_series: 1,
         name: nil}
      )

    :telemetry.execute(@event, %{count: 1, duration: 0.2}, %{outcome: :ok})
    :telemetry.execute(@event, %{count: 1, duration: 0.2}, %{outcome: :error})

    assert :ok = Reporter.flush(reporter)

    assert %{
             series_count: 1,
             failed_data_point_count: 1,
             dropped_data_point_count: dropped,
             last_error: :collector_down
           } = Reporter.status(reporter)

    assert dropped >= 2
    assert Process.alive?(reporter)
  end

  test "filters direct-record attributes through the catalog contract", %{
    handler_id: handler_id
  } do
    parent = self()

    {:ok, reporter} =
      start_supervised(
        {Reporter,
         endpoint: "http://collector.invalid/v1/metrics",
         definitions: definitions(),
         export_interval_ms: 60_000,
         export_fun: fn payload ->
           send(parent, {:metric_payload, payload})
           :ok
         end,
         handler_id: handler_id,
         name: nil}
      )

    Reporter.record(reporter, "cadence.test.item", 1, %{
      "outcome" => "ok",
      "cadence.command.id" => "must-not-be-exported"
    })

    assert :ok = Reporter.flush(reporter)
    assert_receive {:metric_payload, payload}

    counter =
      payload
      |> decode_metrics()
      |> Enum.find(&(&1.name == "cadence.test.item"))

    assert {:sum, %{data_points: [point]}} = counter.data
    assert Enum.map(point.attributes, & &1.key) == ["outcome"]
  end

  test "a refused OTLP connection does not crash the reporter", %{handler_id: handler_id} do
    {:ok, reporter} =
      start_supervised(
        {Reporter,
         endpoint: "http://127.0.0.1:1/v1/metrics",
         definitions: definitions(),
         export_interval_ms: 60_000,
         handler_id: handler_id,
         name: nil,
         timeout_ms: 100}
      )

    :telemetry.execute(@event, %{count: 1, duration: 0.2}, %{outcome: :ok})

    assert :ok = Reporter.flush(reporter)

    assert %{
             series_count: 2,
             failed_data_point_count: 2,
             last_error: last_error
           } = Reporter.status(reporter)

    refute is_nil(last_error)
    assert Process.alive?(reporter)
  end

  test "counts events dropped while the reporter mailbox is full", %{handler_id: handler_id} do
    {:ok, reporter} =
      start_supervised(
        {Reporter,
         endpoint: "http://collector.invalid/v1/metrics",
         definitions: definitions(),
         export_interval_ms: 60_000,
         export_fun: fn _payload -> :ok end,
         handler_id: handler_id,
         max_queue: 2,
         name: nil}
      )

    :ok = :sys.suspend(reporter)

    Enum.each(1..5, fn _index ->
      :telemetry.execute(@event, %{count: 1, duration: 0.2}, %{outcome: :ok})
    end)

    :ok = :sys.resume(reporter)

    assert_eventually(fn ->
      Reporter.status(reporter).dropped_data_point_count == 3
    end)
  end

  defp definitions do
    [
      %Definition{
        name: "cadence.test.item",
        type: :counter,
        description: "Test items.",
        unit: "{item}",
        event_name: @event,
        measurement: :count,
        attributes: ["outcome"],
        tag_values: &stringify_outcome/1
      },
      %Definition{
        name: "cadence.test.duration",
        type: :histogram,
        description: "Test duration.",
        unit: "s",
        event_name: @event,
        measurement: :duration,
        attributes: ["outcome"],
        buckets: [0.25, 1.0],
        tag_values: &stringify_outcome/1
      }
    ]
  end

  defp stringify_outcome(metadata), do: %{"outcome" => to_string(metadata.outcome)}

  defp decode_metrics(payload) do
    request = @protobuf_module.decode_msg(payload, :export_metrics_service_request)
    [resource_metrics] = request.resource_metrics
    [scope_metrics] = resource_metrics.scope_metrics
    scope_metrics.metrics
  end

  defp assert_eventually(assertion, attempts \\ 20)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")
end
