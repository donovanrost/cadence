defmodule Cadence.Observability.Metrics.RuntimeSamplerTest do
  use Cadence.UnitCase, async: false

  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Observability.Metrics.RuntimeSampler
  alias Cadence.Runtime.MissionRuntime

  test "samples interval BEAM saturation measurements" do
    test_pid = self()
    reporter = spawn(fn -> reporter_loop(test_pid) end)
    on_exit(fn -> send(reporter, :stop) end)

    sampler_name = :"runtime_sampler_test_#{System.unique_integer([:positive])}"

    sampler =
      start_supervised!(
        {RuntimeSampler,
         name: sampler_name,
         interval_ms: 60_000,
         metrics_reporter: reporter,
         log_exporter: :missing_log_exporter}
      )

    first_sample = collect_sample()

    assert first_sample["beam.reductions"] > 0
    assert first_sample["beam.gc.collection"] > 0
    assert first_sample["beam.gc.reclaimed"] > 0
    refute Map.has_key?(first_sample, "beam.scheduler.utilization")

    Process.sleep(5)
    send(sampler, :sample)

    second_sample = collect_sample()
    utilization = Map.fetch!(second_sample, "beam.scheduler.utilization")

    assert utilization >= 0.0
    assert utilization <= 1.0
    assert second_sample["beam.reductions"] > 0
  end

  @tag :tmp_dir
  test "samples journal capacity and independent consumer lag", %{tmp_dir: tmp_dir} do
    test_pid = self()
    reporter = spawn(fn -> reporter_loop(test_pid) end)
    on_exit(fn -> send(reporter, :stop) end)

    journal_name =
      MissionRuntime.provider_ingress_journal_name(
        "mission-sampler",
        "contact-sampler",
        "path-sampler",
        "provider-sampler"
      )

    start_supervised!(
      {IngressJournal,
       name: journal_name,
       mission_id: "mission-sampler",
       realized_contact_id: "contact-sampler",
       path_id: "path-sampler",
       provider_binding_id: "provider-sampler",
       base_path: tmp_dir,
       max_bytes: 4_096,
       segment_bytes: 1_024,
       durability: :page_cache,
       checkpoint_interval_ms: 60_000}
    )

    assert {:ok, _entry} =
             IngressJournal.append(journal_name, :binary.copy(<<7>>, 64), DateTime.utc_now())

    archive_consumer =
      spawn(fn ->
        Registry.register(
          Cadence.Runtime.Registry,
          {:provider_ingress_archive_consumer, "mission-sampler", "contact-sampler",
           "path-sampler", "provider-sampler"},
          nil
        )

        send(test_pid, :archive_consumer_registered)
        archive_consumer_loop()
      end)

    assert_receive :archive_consumer_registered
    on_exit(fn -> Process.exit(archive_consumer, :kill) end)

    start_supervised!(
      {RuntimeSampler,
       name: :"runtime_sampler_journal_test_#{System.unique_integer([:positive])}",
       interval_ms: 60_000,
       metrics_reporter: reporter,
       log_exporter: :missing_log_exporter}
    )

    metrics = collect_sample_points()

    assert metric_value(metrics, "cadence.telemetry.ingress.journal.count") == 1
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.entry.count") == 1
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.segment.count") == 1
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.mailbox.depth") >= 0
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.checkpoint.inflight") == 0
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.capacity") == 4_096
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.retained") > 64
    assert metric_value(metrics, "cadence.telemetry.ingress.journal.utilization") > 0.0

    assert metric_value(metrics, "cadence.telemetry.ingress.journal.lag", %{
             "consumer" => :processing
           }) == 64

    assert metric_value(metrics, "cadence.telemetry.ingress.journal.lag", %{
             "consumer" => :archive
           }) == 64

    assert metric_value(metrics, "cadence.telemetry.ingress.archive.consumer.count") == 1
    assert metric_value(metrics, "cadence.telemetry.ingress.archive.queue.depth") == 2
    assert metric_value(metrics, "cadence.telemetry.ingress.archive.queue.size") == 48
    assert metric_value(metrics, "cadence.telemetry.ingress.archive.queue.oldest.age") == 0.25
  end

  defp archive_consumer_loop do
    receive do
      {:"$gen_call", from, :snapshot} ->
        GenServer.reply(from, %{
          pending_entries: 2,
          pending_bytes: 48,
          oldest_pending_age_ms: 250
        })

        archive_consumer_loop()
    end
  end

  defp reporter_loop(test_pid) do
    receive do
      {:otel_metric_record, name, value, attributes, _observed_at} ->
        send(test_pid, {:sampled_metric, name, value, attributes})
        reporter_loop(test_pid)

      {:"$gen_call", from, :status} ->
        GenServer.reply(from, %{
          series_count: 0,
          exported_data_point_count: 0,
          failed_data_point_count: 0,
          dropped_data_point_count: 0
        })

        send(test_pid, :metric_reporter_status_requested)
        reporter_loop(test_pid)

      :stop ->
        :ok
    end
  end

  defp collect_sample(metrics \\ %{}) do
    receive do
      {:sampled_metric, name, value, _attributes} ->
        collect_sample(Map.put(metrics, name, value))

      :metric_reporter_status_requested ->
        metrics
    after
      1_000 ->
        flunk("runtime sampler did not finish a measurement pass")
    end
  end

  defp collect_sample_points(metrics \\ []) do
    receive do
      {:sampled_metric, name, value, attributes} ->
        collect_sample_points([{name, value, attributes} | metrics])

      :metric_reporter_status_requested ->
        metrics
    after
      1_000 ->
        flunk("runtime sampler did not finish a measurement pass")
    end
  end

  defp metric_value(metrics, name, attributes \\ %{}) do
    case Enum.find(metrics, fn {metric_name, _value, metric_attributes} ->
           metric_name == name and Map.merge(metric_attributes, attributes) == metric_attributes
         end) do
      {^name, value, _attributes} -> value
      nil -> flunk("missing sampled metric #{name} with #{inspect(attributes)}")
    end
  end
end
