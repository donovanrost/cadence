defmodule Cadence.Observability.Metrics.CatalogTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Observability.Metrics.Catalog
  alias Cadence.ProviderAdapters.TCPSocket.Instrumentation, as: TCPSocketInstrumentation
  alias Cadence.Telemetry.Profiler

  test "all metric definitions are valid and dimensionally bounded" do
    definitions = Catalog.definitions()

    assert Enum.all?(definitions, &Catalog.valid_definition?/1)

    refute Enum.any?(definitions, fn definition ->
             Enum.any?(definition.attributes, &MapSet.member?(Catalog.forbidden_attributes(), &1))
           end)
  end

  test "catalog event list is unique and excludes sampler-only metrics" do
    events = Catalog.events()

    assert events == Enum.uniq(events)
    assert Enum.all?(events, &is_list/1)
  end

  test "ingress byte metrics preserve receive-boundary and successful-processing semantics" do
    definitions = Catalog.definitions()

    received = Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.received"))
    processed = Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.processed"))

    assert received.event_name == TCPSocketInstrumentation.receive_event()

    assert received.measurement == :byte_count
    assert received.unit == "By"

    assert processed.event_name == Profiler.ingress_result_event()
    assert processed.measurement == :raw_byte_count
    assert processed.unit == "By"
    assert processed.keep.(%{}, %{error?: false})
    refute processed.keep.(%{}, %{error?: true})
  end

  test "journal metrics separate admission throughput from durability latency" do
    definitions = Catalog.definitions()

    appended =
      Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.journal.appended"))

    append_duration =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.append.duration")
      )

    append_queue_wait =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.append.queue_wait.duration")
      )

    maintenance_duration =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.maintenance.duration")
      )

    checkpoint_duration =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.checkpoint.duration")
      )

    reclaim_duration =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.reclaim.duration")
      )

    record_size =
      Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.journal.record.size"))

    processing_batch_size =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.processing.batch.size")
      )

    processing_batch_entry_count =
      Enum.find(
        definitions,
        &(&1.name == "cadence.telemetry.ingress.journal.processing.batch.entry.count")
      )

    assert appended.event_name == [:cadence, :ingress_journal, :append]
    assert appended.measurement == :bytes
    assert appended.unit == "By"
    assert appended.attributes == ["durability"]

    assert append_duration.event_name == appended.event_name
    assert is_function(append_duration.measurement, 2)
    assert append_duration.measurement.(%{duration_us: 1_000_000}, %{}) == 1.0
    assert append_duration.unit == "s"
    assert append_duration.attributes == ["durability"]
    assert hd(append_duration.buckets) < 0.001

    assert append_queue_wait.event_name == appended.event_name
    assert append_queue_wait.measurement.(%{queue_wait_us: 500}, %{}) == 0.0005
    assert append_queue_wait.attributes == ["durability"]

    assert maintenance_duration.event_name == [:cadence, :ingress_journal, :maintenance]
    assert maintenance_duration.measurement.(%{duration_us: 2_000}, %{}) == 0.002
    assert maintenance_duration.attributes == ["durability", "outcome"]

    assert checkpoint_duration.event_name == maintenance_duration.event_name

    assert checkpoint_duration.measurement.(%{checkpoint_duration_us: 3_000}, %{}) ==
             0.003

    assert reclaim_duration.event_name == maintenance_duration.event_name
    assert reclaim_duration.measurement.(%{reclaim_duration_us: 4_000}, %{}) == 0.004

    assert record_size.event_name == [:cadence, :ingress_journal, :record]
    assert record_size.measurement == :bytes
    assert record_size.unit == "By"
    assert record_size.attributes == ["durability"]

    assert processing_batch_size.event_name ==
             [:cadence, :ingress_journal, :processing_batch]

    assert processing_batch_size.measurement == :bytes
    assert processing_batch_size.unit == "By"
    assert processing_batch_size.attributes == []
    assert processing_batch_entry_count.event_name == processing_batch_size.event_name
    assert processing_batch_entry_count.measurement == :entries
  end

  test "raw archive metrics preserve completion, retry, batch, and latency semantics" do
    definitions = Catalog.definitions()

    archived =
      Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.archive.archived"))

    duration =
      Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.archive.duration"))

    batch_size =
      Enum.find(definitions, &(&1.name == "cadence.telemetry.ingress.archive.batch.size"))

    event_name = [:cadence, :runtime, :ingress_archive_consumer, :persist_result]

    assert archived.event_name == event_name
    assert archived.measurement == :byte_count
    assert archived.unit == "By"
    assert archived.keep.(%{}, %{outcome: :ok})
    refute archived.keep.(%{}, %{outcome: :error})
    assert archived.attributes == ["completion"]

    assert duration.event_name == event_name
    assert duration.measurement.(%{duration_us: 1_000_000}, %{}) == 1.0
    assert duration.attributes == ["outcome", "completion", "error.type", "retry"]

    assert batch_size.event_name == event_name
    assert batch_size.measurement == :batch_size
    assert batch_size.unit == "{evidence}"
  end
end
