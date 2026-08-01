defmodule Cadence.Observability.Metrics.Catalog do
  @moduledoc """
  Metric contracts for Cadence operational observability.

  Metric dimensions are deliberately bounded. Domain object identifiers belong
  in logs and traces; only the small mission-health metric set may carry a
  mission identifier.
  """

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Observability.Metrics.Definition
  alias Cadence.ProviderAdapters.TCPSocket.Instrumentation, as: TCPSocketInstrumentation
  alias Cadence.Telemetry.Profiler

  @forbidden_attributes MapSet.new([
                          "cadence.command.id",
                          "cadence.contact.id",
                          "cadence.job.id",
                          "cadence.path.id",
                          "cadence.provider.binding.id",
                          "cadence.source_endpoint.id",
                          "cadence.spacecraft.id",
                          "db.query.text",
                          "error.message",
                          "http.request.id",
                          "http.route.raw",
                          "trace.id"
                        ])

  @mission_health_metrics MapSet.new([
                            "cadence.contact.expected",
                            "cadence.contact.realization.delay",
                            "cadence.commanding.deadline.result",
                            "cadence.commanding.queue.oldest_eligible.age",
                            "cadence.commanding.queue.pending",
                            "cadence.telemetry.availability.interval",
                            "cadence.telemetry.expected",
                            "cadence.telemetry.freshness"
                          ])

  @duration_buckets [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
  @journal_duration_buckets [
    0.000_01,
    0.000_05,
    0.000_1,
    0.000_25,
    0.000_5,
    0.001,
    0.002_5,
    0.005,
    0.01,
    0.025,
    0.05,
    0.1,
    0.25,
    0.5,
    1.0,
    2.5
  ]
  @receive_size_buckets [
    64,
    256,
    1_024,
    4_096,
    16_384,
    65_536,
    262_144,
    1_048_576,
    2_097_152,
    4_194_304
  ]
  @queue_buckets [0, 1, 2, 4, 8, 10, 100, 500, 1_000, 2_048, 4_096, 8_192]

  @spec definitions() :: [Definition.t()]
  def definitions do
    [
      histogram(
        "http.server.request.duration",
        [:phoenix, :router_dispatch, :stop],
        :duration,
        "s",
        "Duration of HTTP server requests.",
        ["http.request.method", "http.route", "http.response.status_code", "error.type"],
        [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0],
        measurement: &native_time_to_seconds/2,
        tag_values: &http_tags/1
      ),
      histogram(
        "http.server.request.duration",
        [:phoenix, :router_dispatch, :exception],
        :duration,
        "s",
        "Duration of failed HTTP server requests.",
        ["http.request.method", "http.route", "http.response.status_code", "error.type"],
        [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0],
        measurement: &native_time_to_seconds/2,
        tag_values: &http_exception_tags/1
      ),
      up_down_counter(
        "http.server.active_requests",
        [:phoenix, :router_dispatch, :start],
        1,
        "{request}",
        "Number of active HTTP server requests.",
        ["http.request.method", "http.route"],
        tag_values: &http_tags/1
      ),
      up_down_counter(
        "http.server.active_requests",
        [:phoenix, :router_dispatch, :stop],
        -1,
        "{request}",
        "Number of active HTTP server requests.",
        ["http.request.method", "http.route"],
        tag_values: &http_tags/1
      ),
      up_down_counter(
        "http.server.active_requests",
        [:phoenix, :router_dispatch, :exception],
        -1,
        "{request}",
        "Number of active HTTP server requests.",
        ["http.request.method", "http.route"],
        tag_values: &http_exception_tags/1
      ),
      histogram(
        "db.client.operation.duration",
        [:cadence, :repo, :query],
        :total_time,
        "s",
        "Duration of database client operations.",
        ["db.system.name", "error.type"],
        [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0],
        measurement: &native_time_to_seconds/2,
        tag_values: &database_tags/1
      ),
      gauge(
        "beam.memory.usage",
        "By",
        "Memory used by the BEAM runtime.",
        ["memory.type"]
      ),
      gauge("beam.process.count", "{process}", "Number of BEAM processes.", []),
      gauge("beam.process.limit", "{process}", "BEAM process limit.", []),
      gauge("beam.port.count", "{port}", "Number of BEAM ports.", []),
      gauge("beam.port.limit", "{port}", "BEAM port limit.", []),
      gauge(
        "beam.scheduler.run_queue",
        "{process}",
        "Number of runnable BEAM processes and ports.",
        []
      ),
      gauge(
        "beam.scheduler.utilization",
        "1",
        "Fraction of normal BEAM scheduler wall time spent active during the sample interval.",
        []
      ),
      counter(
        "beam.reductions",
        nil,
        nil,
        "{reduction}",
        "BEAM reductions executed during the sample interval.",
        [],
        []
      ),
      counter(
        "beam.gc.collection",
        nil,
        nil,
        "{collection}",
        "BEAM garbage collections completed during the sample interval.",
        [],
        []
      ),
      counter(
        "beam.gc.reclaimed",
        nil,
        nil,
        "{word}",
        "BEAM words reclaimed by garbage collection during the sample interval.",
        [],
        []
      ),
      gauge(
        "otel.sdk.processor.log.queue.size",
        "{record}",
        "Current Cadence OTLP log processor queue size.",
        ["otel.component.name", "otel.component.type"]
      ),
      gauge(
        "otel.sdk.processor.log.queue.capacity",
        "{record}",
        "Configured Cadence OTLP log processor queue capacity.",
        ["otel.component.name", "otel.component.type"]
      ),
      counter(
        "otel.sdk.exporter.log.exported",
        nil,
        nil,
        "{record}",
        "Log records processed by the Cadence OTLP log exporter.",
        ["otel.component.name", "otel.component.type", "error.type"],
        []
      ),
      gauge(
        "otel.sdk.exporter.metric_data_point.inflight",
        "{data_point}",
        "Metric series awaiting export from the Cadence reporter.",
        ["otel.component.name", "otel.component.type"]
      ),
      counter(
        "otel.sdk.exporter.metric_data_point.exported",
        nil,
        nil,
        "{data_point}",
        "Metric data points processed by the Cadence OTLP metrics exporter.",
        ["otel.component.name", "otel.component.type", "error.type"],
        []
      ),
      gauge(
        "cadence.telemetry.expected",
        "{state}",
        "Whether live downlink telemetry is expected for a mission.",
        ["cadence.mission.id"]
      ),
      gauge(
        "cadence.contact.expected",
        "{contact}",
        "Active realized contacts expecting live downlink telemetry.",
        ["cadence.mission.id"]
      ),
      gauge(
        "cadence.telemetry.freshness",
        "s",
        "Age of the newest current telemetry sample.",
        ["cadence.mission.id"]
      ),
      counter(
        "cadence.telemetry.availability.interval",
        nil,
        nil,
        "{interval}",
        "Expected telemetry sampling intervals by availability outcome.",
        ["cadence.mission.id", "outcome"],
        []
      ),
      gauge(
        "cadence.commanding.queue.pending",
        "{command}",
        "Commands currently pending in durable dispatch queues.",
        ["cadence.mission.id"]
      ),
      gauge(
        "cadence.commanding.queue.oldest_eligible.age",
        "s",
        "Age of the oldest command currently eligible for release.",
        ["cadence.mission.id"]
      ),
      counter(
        "cadence.commanding.deadline.result",
        nil,
        nil,
        "{command}",
        "Command queue entries reaching a deadline outcome.",
        ["cadence.mission.id", "outcome"],
        []
      ),
      histogram(
        "cadence.contact.realization.delay",
        nil,
        nil,
        "s",
        "Delay between a scheduled contact start and its realization.",
        ["cadence.mission.id"],
        [0.0, 1.0, 5.0, 15.0, 30.0, 60.0, 120.0, 300.0, 900.0],
        []
      ),
      counter(
        "cadence.telemetry.ingress.evidence",
        Profiler.ingress_result_event(),
        :evidence_count,
        "{evidence}",
        "Evidence items processed by the telemetry ingress runtime.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family", "outcome"],
        tag_values: &ingress_tags/1,
        measurement: fn _measurements, _metadata -> 1 end
      ),
      counter(
        "cadence.telemetry.ingress.packet",
        Profiler.ingress_result_event(),
        :packet_count,
        "{packet}",
        "Packets produced by telemetry ingress processing.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family", "outcome"],
        tag_values: &ingress_tags/1,
        measurement: fn _measurements, metadata -> metadata[:packet_count] end
      ),
      counter(
        "cadence.telemetry.ingress.transfer_frame",
        Profiler.ingress_result_event(),
        :transfer_frame_count,
        "{frame}",
        "Transfer frames produced by telemetry ingress processing.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family", "outcome"],
        tag_values: &ingress_tags/1,
        measurement: fn _measurements, metadata -> metadata[:transfer_frame_count] end
      ),
      counter(
        "cadence.telemetry.ingress.sample",
        Profiler.ingress_result_event(),
        :sample_count,
        "{sample}",
        "Telemetry samples produced by ingress processing.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family", "outcome"],
        tag_values: &ingress_tags/1,
        measurement: fn _measurements, metadata -> metadata[:sample_count] end
      ),
      counter(
        "cadence.telemetry.ingress.anomaly",
        Profiler.ingress_result_event(),
        :anomaly_count,
        "{anomaly}",
        "Protocol anomalies detected during ingress processing.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family"],
        tag_values: &ingress_tags/1,
        measurement: fn _measurements, metadata -> metadata[:anomaly_count] end
      ),
      histogram(
        "cadence.telemetry.ingress.processing.duration",
        Profiler.ingress_result_event(),
        :end_to_end_us,
        "s",
        "End-to-end duration of telemetry ingress processing.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family", "outcome"],
        @duration_buckets,
        tag_values: &ingress_tags/1,
        measurement: &microseconds_to_seconds/2
      ),
      counter(
        "cadence.telemetry.ingress.received",
        TCPSocketInstrumentation.receive_event(),
        :byte_count,
        "By",
        "Bytes returned by successful telemetry transport receive operations.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family"],
        tag_values: &receive_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.receive.operation.duration",
        TCPSocketInstrumentation.receive_event(),
        :duration_us,
        "s",
        "Duration of blocking telemetry transport receive operations that returned bytes.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family"],
        @duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &receive_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.receive.size",
        TCPSocketInstrumentation.receive_event(),
        :byte_count,
        "By",
        "Bytes returned by each successful telemetry transport receive operation.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family"],
        @receive_size_buckets,
        tag_values: &receive_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.journal.appended",
        [:cadence, :ingress_journal, :append],
        :bytes,
        "By",
        "Ingress bytes admitted to a path-local journal.",
        ["durability"],
        tag_values: &journal_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.append.duration",
        [:cadence, :ingress_journal, :append],
        :duration_us,
        "s",
        "Duration of a journal append through its configured durability boundary.",
        ["durability"],
        @journal_duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &journal_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.append.queue_wait.duration",
        [:cadence, :ingress_journal, :append],
        :queue_wait_us,
        "s",
        "Time a journal append waited for the journal process before service began.",
        ["durability"],
        @journal_duration_buckets,
        measurement: &queue_wait_us_to_seconds/2,
        tag_values: &journal_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.record.size",
        [:cadence, :ingress_journal, :record],
        :bytes,
        "By",
        "Payload bytes in each bounded logical ingress journal record.",
        ["durability"],
        @receive_size_buckets,
        tag_values: &journal_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.processing.batch.size",
        [:cadence, :ingress_journal, :processing_batch],
        :bytes,
        "By",
        "Raw bytes grouped into each bounded semantic processing work item.",
        [],
        @receive_size_buckets,
        []
      ),
      histogram(
        "cadence.telemetry.ingress.journal.processing.batch.entry.count",
        [:cadence, :ingress_journal, :processing_batch],
        :entries,
        "{entry}",
        "Journal capture records grouped into each semantic processing work item.",
        [],
        @queue_buckets,
        []
      ),
      counter(
        "cadence.telemetry.ingress.journal.capacity.exhaustion",
        [:cadence, :ingress_journal, :capacity_exhausted],
        nil,
        "{event}",
        "Journal admission attempts rejected because bounded capacity was exhausted.",
        ["durability"],
        measurement: fn _measurements, _metadata -> 1 end,
        tag_values: &journal_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.journal.reclaimed",
        [:cadence, :ingress_journal, :reclaim],
        :bytes,
        "By",
        "Journal segment bytes reclaimed after all durable consumer cursors advanced.",
        ["durability"],
        tag_values: &journal_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.journal.reclaimed.entry",
        [:cadence, :ingress_journal, :reclaim],
        :entries,
        "{entry}",
        "Journal index entries removed with reclaimed segments.",
        ["durability"],
        tag_values: &journal_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.journal.reclaimed.segment",
        [:cadence, :ingress_journal, :reclaim],
        :segments,
        "{segment}",
        "Journal segments reclaimed after all durable consumer cursors advanced.",
        ["durability"],
        tag_values: &journal_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.maintenance.duration",
        [:cadence, :ingress_journal, :maintenance],
        :duration_us,
        "s",
        "Total duration of a journal cursor checkpoint and reclamation cycle.",
        ["durability", "outcome"],
        @journal_duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &journal_maintenance_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.maintenance.queue_wait.duration",
        [:cadence, :ingress_journal, :maintenance],
        :queue_wait_us,
        "s",
        "Delay between a scheduled journal maintenance cycle and its execution.",
        ["durability", "outcome"],
        @journal_duration_buckets,
        measurement: &queue_wait_us_to_seconds/2,
        tag_values: &journal_maintenance_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.checkpoint.duration",
        [:cadence, :ingress_journal, :maintenance],
        :checkpoint_duration_us,
        "s",
        "Duration of the durable journal consumer-cursor checkpoint.",
        ["durability", "outcome"],
        @journal_duration_buckets,
        measurement: &checkpoint_duration_us_to_seconds/2,
        tag_values: &journal_maintenance_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.journal.reclaim.duration",
        [:cadence, :ingress_journal, :maintenance],
        :reclaim_duration_us,
        "s",
        "Duration of journal segment deletion and index-prefix reclamation.",
        ["durability", "outcome"],
        @journal_duration_buckets,
        measurement: &reclaim_duration_us_to_seconds/2,
        tag_values: &journal_maintenance_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.processed",
        Profiler.ingress_result_event(),
        :raw_byte_count,
        "By",
        "Raw bytes successfully handled by semantic telemetry ingress processing.",
        ["cadence.telemetry.direction", "cadence.telemetry.protocol_family"],
        keep: fn _measurements, metadata -> not metadata[:error?] end,
        tag_values: &ingress_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.backpressure.transition",
        [:cadence, :runtime, :provider_ingress_executor, :backpressure_entered],
        :transition_count,
        "{transition}",
        "Transitions into telemetry ingress backpressure.",
        ["downstream", "state"],
        measurement: fn _measurements, _metadata -> 1 end,
        tag_values: fn metadata ->
          %{"downstream" => metadata[:downstream], "state" => "entered"}
        end
      ),
      counter(
        "cadence.telemetry.ingress.backpressure.transition",
        [:cadence, :runtime, :provider_ingress_executor, :backpressure_released],
        :transition_count,
        "{transition}",
        "Transitions out of telemetry ingress backpressure.",
        ["downstream", "state"],
        measurement: fn _measurements, _metadata -> 1 end,
        tag_values: fn metadata ->
          %{"downstream" => metadata[:downstream], "state" => "released"}
        end
      ),
      event_gauge(
        "cadence.telemetry.ingress.backpressure",
        [:cadence, :runtime, :provider_ingress_executor, :backpressure_entered],
        fn _measurements, _metadata -> 1 end,
        "{state}",
        "Current telemetry ingress backpressure state.",
        ["downstream"],
        tag_values: &take_string_keys(&1, ["downstream"])
      ),
      event_gauge(
        "cadence.telemetry.ingress.backpressure",
        [:cadence, :runtime, :provider_ingress_executor, :backpressure_released],
        fn _measurements, _metadata -> 0 end,
        "{state}",
        "Current telemetry ingress backpressure state.",
        ["downstream"],
        tag_values: &take_string_keys(&1, ["downstream"])
      ),
      event_gauge(
        "cadence.telemetry.ingress.queue.depth",
        [:cadence, :runtime, :provider_ingress_executor, :capacity_waiter_registered],
        :queue_depth,
        "{item}",
        "Observed telemetry ingress executor queue depth.",
        ["downstream"],
        tag_values: &take_string_keys(&1, ["downstream"])
      ),
      event_gauge(
        "cadence.telemetry.persistence.queue.depth",
        [:cadence, :runtime, :ingress_persistence_projector, :capacity_waiter_registered],
        :queue_depth,
        "{batch}",
        "Observed ingress persistence projector queue depth.",
        [],
        []
      ),
      gauge(
        "cadence.telemetry.ingress.executor.count",
        "{executor}",
        "Number of running provider ingress executors.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.queue.size",
        "By",
        "Raw telemetry bytes represented by provider ingress executor queues.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.queue.oldest.age",
        "s",
        "Age of the oldest raw telemetry item in provider ingress executor queues.",
        []
      ),
      gauge(
        "cadence.telemetry.persistence.projector.count",
        "{projector}",
        "Number of running ingress persistence projectors.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.capacity_waiter.count",
        "{waiter}",
        "Number of producers waiting for provider ingress capacity.",
        []
      ),
      gauge(
        "cadence.telemetry.persistence.capacity_waiter.count",
        "{waiter}",
        "Number of executors waiting for persistence capacity.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.count",
        "{journal}",
        "Number of running path-local ingress journals.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.entry.count",
        "{entry}",
        "Number of indexed records retained by running ingress journals.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.segment.count",
        "{segment}",
        "Number of filesystem segments retained by running ingress journals.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.mailbox.depth",
        "{message}",
        "Messages waiting in ingress journal process mailboxes.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.checkpoint.inflight",
        "{checkpoint}",
        "Ingress journal cursor checkpoints currently performing filesystem I/O.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.retained",
        "By",
        "Filesystem bytes retained by ingress journals.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.capacity",
        "By",
        "Configured ingress journal byte capacity.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.utilization",
        "1",
        "Largest fraction of configured journal capacity currently retained.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.journal.lag",
        "By",
        "Captured bytes not yet acknowledged by each required journal consumer.",
        ["consumer"]
      ),
      gauge(
        "cadence.telemetry.ingress.archive.consumer.count",
        "{consumer}",
        "Number of running independent raw-archive consumers.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.archive.queue.depth",
        "{evidence}",
        "Evidence items held in raw-archive retry batches.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.archive.queue.size",
        "By",
        "Raw bytes held in raw-archive retry batches.",
        []
      ),
      gauge(
        "cadence.telemetry.ingress.archive.queue.oldest.age",
        "s",
        "Age of the oldest evidence held for raw-archive retry.",
        []
      ),
      counter(
        "cadence.telemetry.ingress.archive.attempt",
        [:cadence, :runtime, :ingress_archive_consumer, :persist_result],
        :attempt_count,
        "{attempt}",
        "Raw-archive batch attempts.",
        ["outcome", "completion", "error.type", "retry"],
        tag_values: &archive_tags/1
      ),
      counter(
        "cadence.telemetry.ingress.archive.archived",
        [:cadence, :runtime, :ingress_archive_consumer, :persist_result],
        :byte_count,
        "By",
        "Journal bytes durably archived or explicitly accepted by the configured policy.",
        ["completion"],
        keep: &successful_archive_result?/2,
        tag_values: &archive_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.archive.duration",
        [:cadence, :runtime, :ingress_archive_consumer, :persist_result],
        :duration_us,
        "s",
        "Duration of raw-archive persistence and cursor acknowledgement attempts.",
        ["outcome", "completion", "error.type", "retry"],
        @duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &archive_tags/1
      ),
      histogram(
        "cadence.telemetry.ingress.archive.batch.size",
        [:cadence, :runtime, :ingress_archive_consumer, :persist_result],
        :batch_size,
        "{evidence}",
        "Evidence items represented by each raw-archive attempt.",
        ["outcome", "retry"],
        @queue_buckets,
        tag_values: &archive_tags/1
      ),
      counter(
        "cadence.telemetry.persistence.evidence",
        [:cadence, :runtime, :ingress_persistence_projector, :persist_result],
        :batch_size,
        "{evidence}",
        "Evidence items handled by ingress persistence.",
        ["outcome", "error.type"],
        tag_values: &persistence_tags/1
      ),
      histogram(
        "cadence.telemetry.persistence.duration",
        [:cadence, :runtime, :ingress_persistence_projector, :persist_result],
        :duration_us,
        "s",
        "Duration of ingress persistence batches.",
        ["outcome", "error.type"],
        @duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &persistence_tags/1
      ),
      histogram(
        "cadence.telemetry.persistence.queue.wait",
        [:cadence, :runtime, :ingress_persistence_projector, :persist_result],
        :queue_wait_ms,
        "s",
        "Time ingress evidence waited before persistence.",
        ["outcome"],
        @duration_buckets,
        measurement: &duration_ms_to_seconds/2,
        tag_values: &persistence_tags/1
      ),
      histogram(
        "cadence.telemetry.persistence.batch.size",
        [:cadence, :runtime, :ingress_persistence_projector, :persist_result],
        :batch_size,
        "{evidence}",
        "Number of evidence items in each persistence batch.",
        ["outcome"],
        @queue_buckets,
        tag_values: &persistence_tags/1
      ),
      counter(
        "cadence.commanding.dispatch",
        [:cadence, :commanding, :lane_dispatcher, :dispatch_result],
        :count,
        "{attempt}",
        "Command lane dispatch results.",
        ["result"],
        tag_values: &take_string_keys(&1, ["result"])
      ),
      histogram(
        "cadence.commanding.dispatch.wait",
        [:cadence, :commanding, :lane_dispatcher, :timer_scheduled],
        :delay_ms,
        "s",
        "Time until the next command lane dispatch attempt.",
        ["reason"],
        [0.0, 0.1, 1.0, 5.0, 30.0, 60.0, 300.0, 900.0, 3_600.0],
        measurement: &delay_ms_to_seconds/2,
        tag_values: &take_string_keys(&1, ["reason"])
      ),
      event_gauge(
        "cadence.commanding.pending_lane.count",
        [:cadence, :commanding, :dispatcher, :reconcile],
        :pending_lane_count,
        "{lane}",
        "Number of command queue lanes with pending work.",
        [],
        []
      ),
      counter(
        "cadence.commanding.verifier.timeout",
        [:cadence, :commanding, :verifier_scheduler, :reconcile],
        :timed_out_verifier_count,
        "{verifier}",
        "Command verifier instances that reached their timeout.",
        ["reason"],
        tag_values: &take_string_keys(&1, ["reason"])
      ),
      counter(
        "cadence.commanding.verifier.timeout",
        [:cadence, :commanding, :verifier_scheduler, :safety_reconcile],
        :timed_out_verifier_count,
        "{verifier}",
        "Command verifier instances that reached their timeout.",
        ["reason"],
        tag_values: &take_string_keys(&1, ["reason"])
      ),
      histogram(
        "cadence.commanding.verifier.reconcile.duration",
        [:cadence, :commanding, :verifier_scheduler, :reconcile],
        :duration_us,
        "s",
        "Duration of command verifier reconciliation.",
        ["reason"],
        @duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &take_string_keys(&1, ["reason"])
      ),
      event_gauge(
        "cadence.commanding.verifier.pending",
        [:cadence, :commanding, :verifier_scheduler, :projection_rebuild],
        :projected_verifier_count,
        "{verifier}",
        "Command verifier instances awaiting a terminal result.",
        [],
        []
      ),
      counter(
        "cadence.contact.scheduler.event",
        [:cadence, :contacts, :scheduler, :stale_timer],
        :count,
        "{event}",
        "Contact scheduler events requiring operator attention.",
        ["event"],
        tag_values: fn _metadata -> %{"event" => "stale_timer"} end
      ),
      histogram(
        "cadence.contact.reconcile.duration",
        [:cadence, :contacts, :scheduler, :reconcile],
        :duration_us,
        "s",
        "Duration of scheduled-contact reconciliation.",
        ["reason", "scheduler.mode"],
        @duration_buckets,
        measurement: &duration_us_to_seconds/2,
        tag_values: &contact_scheduler_tags/1
      ),
      counter(
        "cadence.contact.reconcile.result",
        [:cadence, :contacts, :scheduler, :reconcile],
        :realized_scheduled_contact_count,
        "{contact}",
        "Scheduled contacts transitioned to realized by reconciliation.",
        ["result", "scheduler.mode"],
        measurement: &contact_realized_count/2,
        tag_values: fn metadata ->
          metadata |> contact_scheduler_tags() |> Map.put("result", "realized")
        end
      ),
      counter(
        "cadence.contact.reconcile.result",
        [:cadence, :contacts, :scheduler, :reconcile],
        :expired_scheduled_contact_count,
        "{contact}",
        "Scheduled contacts expired before realization.",
        ["result", "scheduler.mode"],
        measurement: &contact_expired_count/2,
        tag_values: fn metadata ->
          metadata |> contact_scheduler_tags() |> Map.put("result", "expired")
        end
      ),
      counter(
        "cadence.contact.reconcile.result",
        [:cadence, :contacts, :scheduler, :reconcile],
        :error_count,
        "{contact}",
        "Contact reconciliation errors.",
        ["result", "scheduler.mode"],
        tag_values: fn metadata ->
          metadata |> contact_scheduler_tags() |> Map.put("result", "error")
        end
      ),
      event_gauge(
        "cadence.contact.projected",
        [:cadence, :contacts, :scheduler, :projection_rebuild],
        :projected_contact_count,
        "{contact}",
        "Scheduled contacts currently projected by mission schedulers.",
        ["scheduler.mode"],
        tag_values: &contact_scheduler_tags/1
      ),
      counter(
        "cadence.commanding.verifier.event",
        [:cadence, :commanding, :verifier_scheduler, :stale_timer],
        :count,
        "{event}",
        "Command verifier scheduler events requiring operator attention.",
        ["event"],
        tag_values: fn _metadata -> %{"event" => "stale_timer"} end
      ),
      counter(
        "cadence.jobs.worker.start",
        [:cadence, :jobs, :dispatcher, :worker_started],
        :count,
        "{worker}",
        "Background job workers started.",
        ["outcome"],
        tag_values: fn _metadata -> %{"outcome" => "started"} end
      ),
      counter(
        "cadence.jobs.worker.start",
        [:cadence, :jobs, :dispatcher, :worker_start_failed],
        :count,
        "{worker}",
        "Background job workers that failed to start.",
        ["outcome"],
        tag_values: fn _metadata -> %{"outcome" => "failed"} end
      ),
      event_gauge(
        "cadence.jobs.worker.running",
        [:cadence, :jobs, :dispatcher, :worker_started],
        fn _measurements, metadata -> metadata[:running_worker_count] end,
        "{worker}",
        "Background job workers currently running.",
        [],
        []
      ),
      event_gauge(
        "cadence.jobs.worker.running",
        [:cadence, :jobs, :dispatcher, :worker_finished],
        fn _measurements, metadata -> metadata[:running_worker_count] end,
        "{worker}",
        "Background job workers currently running.",
        [],
        []
      ),
      counter(
        "cadence.jobs.worker.finished",
        [:cadence, :jobs, :dispatcher, :worker_finished],
        :count,
        "{worker}",
        "Background job workers reaching a terminal process state.",
        ["outcome"],
        tag_values: &take_string_keys(&1, ["outcome"])
      ),
      counter(
        "cadence.jobs.claimed",
        [:cadence, :jobs, :dispatcher, :jobs_claimed],
        :count,
        "{job}",
        "Background jobs claimed for execution.",
        ["reason"],
        tag_values: &take_string_keys(&1, ["reason"])
      ),
      histogram(
        "cadence.provider.event.poll.duration",
        [:cadence, :provider_event, :poll],
        :duration,
        "s",
        "Duration of provider event polling.",
        ["outcome"],
        @duration_buckets,
        measurement: &native_time_to_seconds/2,
        tag_values: &take_string_keys(&1, ["outcome"])
      ),
      counter(
        "cadence.provider.event.poll",
        [:cadence, :provider_event, :poll],
        :count,
        "{poll}",
        "Provider event poll outcomes.",
        ["outcome"],
        measurement: fn _measurements, _metadata -> 1 end,
        tag_values: &take_string_keys(&1, ["outcome"])
      ),
      histogram(
        "cadence.dashboard.runtime.invalidation.duration",
        RuntimeInvalidation.telemetry_event(),
        :duration,
        "s",
        "Duration of dashboard runtime invalidation.",
        ["boundary"],
        @duration_buckets,
        measurement: &native_time_to_seconds/2,
        tag_values: &take_string_keys(&1, ["boundary"])
      )
    ]
  end

  @spec events() :: [[atom()]]
  def events do
    definitions()
    |> Enum.map(& &1.event_name)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec definitions_by_event() :: %{optional([atom()]) => [Definition.t()]}
  def definitions_by_event do
    definitions()
    |> Enum.reject(&is_nil(&1.event_name))
    |> Enum.group_by(& &1.event_name)
  end

  @spec valid_definition?(Definition.t()) :: boolean()
  def valid_definition?(%Definition{} = definition) do
    definition.type in [:counter, :gauge, :histogram, :up_down_counter] and
      is_binary(definition.name) and definition.name != "" and
      is_binary(definition.description) and definition.description != "" and
      is_binary(definition.unit) and
      Enum.all?(definition.attributes, &valid_attribute?(definition.name, &1)) and
      definition.attributes == Enum.uniq(definition.attributes) and
      valid_buckets?(definition)
  end

  @spec forbidden_attributes() :: MapSet.t(binary())
  def forbidden_attributes, do: @forbidden_attributes

  defp counter(name, event_name, measurement, unit, description, attributes, opts) do
    definition(
      name,
      :counter,
      event_name,
      measurement,
      unit,
      description,
      attributes,
      opts
    )
  end

  defp histogram(
         name,
         event_name,
         measurement,
         unit,
         description,
         attributes,
         buckets,
         opts
       ) do
    definition(
      name,
      :histogram,
      event_name,
      measurement,
      unit,
      description,
      attributes,
      Keyword.put(opts, :buckets, buckets)
    )
  end

  defp gauge(name, unit, description, attributes) do
    definition(name, :gauge, nil, nil, unit, description, attributes, [])
  end

  defp event_gauge(
         name,
         event_name,
         measurement,
         unit,
         description,
         attributes,
         opts
       ) do
    definition(name, :gauge, event_name, measurement, unit, description, attributes, opts)
  end

  defp up_down_counter(
         name,
         event_name,
         increment,
         unit,
         description,
         attributes,
         opts
       ) do
    definition(
      name,
      :up_down_counter,
      event_name,
      fn _measurements, _metadata -> increment end,
      unit,
      description,
      attributes,
      opts
    )
  end

  defp definition(name, type, event_name, measurement, unit, description, attributes, opts) do
    %Definition{
      name: name,
      type: type,
      event_name: event_name,
      measurement: Keyword.get(opts, :measurement, measurement),
      unit: unit,
      description: description,
      attributes: attributes,
      buckets: Keyword.get(opts, :buckets, []),
      keep: Keyword.get(opts, :keep),
      tag_values: Keyword.get(opts, :tag_values)
    }
  end

  defp valid_attribute?(metric_name, "cadence.mission.id") do
    MapSet.member?(@mission_health_metrics, metric_name)
  end

  defp valid_attribute?(_metric_name, attribute) when is_binary(attribute) do
    not MapSet.member?(@forbidden_attributes, attribute)
  end

  defp valid_attribute?(_metric_name, _attribute), do: false

  defp valid_buckets?(%Definition{type: :histogram, buckets: buckets}) do
    buckets != [] and buckets == Enum.sort(Enum.uniq(buckets))
  end

  defp valid_buckets?(%Definition{buckets: []}), do: true
  defp valid_buckets?(%Definition{}), do: false

  defp ingress_tags(metadata) do
    %{
      "cadence.telemetry.direction" => metadata[:direction],
      "cadence.telemetry.protocol_family" => metadata[:protocol_family],
      "outcome" => if(metadata[:error?], do: "error", else: "ok")
    }
  end

  defp receive_tags(metadata) do
    %{
      "cadence.telemetry.direction" => metadata[:direction],
      "cadence.telemetry.protocol_family" => metadata[:protocol_family]
    }
  end

  defp journal_tags(metadata) do
    %{"durability" => metadata[:durability]}
  end

  defp journal_maintenance_tags(metadata) do
    %{
      "durability" => metadata[:durability],
      "outcome" => metadata[:outcome]
    }
  end

  defp persistence_tags(metadata) do
    %{
      "outcome" => metadata[:outcome],
      "error.type" => metadata[:error_type]
    }
  end

  defp archive_tags(metadata) do
    %{
      "outcome" => metadata[:outcome],
      "completion" => metadata[:completion],
      "error.type" => metadata[:error_type],
      "retry" => metadata[:retry]
    }
  end

  defp successful_archive_result?(_measurements, metadata), do: metadata[:outcome] == :ok

  defp http_tags(metadata) do
    conn = Map.get(metadata, :conn, %{})
    status = Map.get(conn, :status)

    %{
      "http.request.method" => Map.get(conn, :method),
      "http.route" => Map.get(metadata, :route),
      "http.response.status_code" => status,
      "error.type" => if(is_integer(status) and status >= 500, do: Integer.to_string(status))
    }
  end

  defp http_exception_tags(metadata) do
    metadata
    |> http_tags()
    |> Map.put("error.type", exception_type(metadata))
  end

  defp exception_type(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp exception_type(_metadata), do: "_OTHER"

  defp database_tags(metadata) do
    %{
      "db.system.name" => "postgresql",
      "error.type" => database_error_type(metadata[:result])
    }
  end

  defp database_error_type({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp database_error_type({:error, %{__struct__: module}}), do: inspect(module)
  defp database_error_type({:error, _reason}), do: "_OTHER"
  defp database_error_type(_result), do: nil

  defp contact_scheduler_tags(metadata) do
    %{
      "reason" => metadata[:reason],
      "scheduler.mode" => metadata[:mode]
    }
  end

  defp contact_realized_count(measurements, _metadata) do
    Map.get(measurements, :realized_scheduled_contact_count)
  end

  defp contact_expired_count(measurements, _metadata) do
    Map.get(measurements, :expired_scheduled_contact_count)
  end

  defp microseconds_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:end_to_end_us)
    |> divide_if_number(1_000_000)
  end

  defp duration_us_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:duration_us)
    |> divide_if_number(1_000_000)
  end

  defp queue_wait_us_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:queue_wait_us)
    |> divide_if_number(1_000_000)
  end

  defp checkpoint_duration_us_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:checkpoint_duration_us)
    |> divide_if_number(1_000_000)
  end

  defp reclaim_duration_us_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:reclaim_duration_us)
    |> divide_if_number(1_000_000)
  end

  defp duration_ms_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:queue_wait_ms)
    |> divide_if_number(1_000)
  end

  defp delay_ms_to_seconds(measurements, _metadata) do
    measurements
    |> Map.get(:delay_ms)
    |> divide_if_number(1_000)
  end

  defp native_time_to_seconds(measurements, _metadata) do
    case Map.get(measurements, :duration) do
      duration when is_integer(duration) ->
        System.convert_time_unit(duration, :native, :nanosecond) / 1_000_000_000

      _missing ->
        nil
    end
  end

  defp divide_if_number(value, divisor) when is_number(value), do: value / divisor
  defp divide_if_number(_value, _divisor), do: nil

  defp take_string_keys(metadata, keys) do
    Map.new(keys, fn key -> {key, Map.get(metadata, String.to_existing_atom(key))} end)
  end
end
