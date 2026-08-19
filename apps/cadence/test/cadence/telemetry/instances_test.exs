defmodule Cadence.Telemetry.InstancesTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.FileSystem, as: IngressFileSystem
  alias Cadence.Protocol.{PacketRecord, RecordArchive}
  alias Cadence.Protocol.RecordArchive.FileSystem, as: RecordFileSystem
  alias Cadence.Repo
  alias Cadence.Telemetry.{Profiler, RuntimeHealth}

  @ingress_writer_a __MODULE__.IngressWriterA
  @ingress_writer_b __MODULE__.IngressWriterB
  @record_writer_a __MODULE__.RecordWriterA
  @record_writer_b __MODULE__.RecordWriterB
  @profiler_a_id {__MODULE__, :profiler_a}
  @profiler_b_id {__MODULE__, :profiler_b}
  @runtime_health_a_id {__MODULE__, :runtime_health_a}
  @runtime_health_b_id {__MODULE__, :runtime_health_b}

  setup do
    unique = System.unique_integer([:positive])
    test_root = Path.join(System.tmp_dir!(), "cadence_telemetry_instances_#{unique}")

    ingress_policy_a =
      ingress_policy(
        @ingress_writer_a,
        "telemetry-instances-ingress-a-#{unique}",
        Path.join(test_root, "ingress-a")
      )

    ingress_policy_b =
      ingress_policy(
        @ingress_writer_b,
        "telemetry-instances-ingress-b-#{unique}",
        Path.join(test_root, "ingress-b")
      )

    record_policy_a =
      record_policy(
        @record_writer_a,
        "telemetry-instances-record-a-#{unique}",
        Path.join(test_root, "record-a")
      )

    record_policy_b =
      record_policy(
        @record_writer_b,
        "telemetry-instances-record-b-#{unique}",
        Path.join(test_root, "record-b")
      )

    start_supervised!(IngressArchive.child_spec(ingress_policy_a))
    start_supervised!(IngressArchive.child_spec(ingress_policy_b))
    start_supervised!(RecordArchive.child_spec(record_policy_a))
    start_supervised!(RecordArchive.child_spec(record_policy_b))

    profiler_a =
      start_instance!(Profiler, @profiler_a_id,
        name: nil,
        ingress_archive_policy: ingress_policy_a,
        record_archive_policy: record_policy_a
      )

    profiler_b =
      start_instance!(Profiler, @profiler_b_id,
        name: nil,
        ingress_archive_policy: ingress_policy_b,
        record_archive_policy: record_policy_b
      )

    runtime_health_a =
      start_instance!(RuntimeHealth, @runtime_health_a_id,
        name: nil,
        event_route: {__MODULE__, :instance_a}
      )

    runtime_health_b =
      start_instance!(RuntimeHealth, @runtime_health_b_id,
        name: nil,
        event_route: {__MODULE__, :instance_b}
      )

    on_exit(fn -> File.rm_rf!(test_root) end)

    organization_id = "org-telemetry-instances-#{unique}"
    mission_id = "mission-telemetry-instances-#{unique}"
    persist_mission_scope(organization_id, mission_id)

    %{
      ingress_policy_a: ingress_policy_a,
      ingress_policy_b: ingress_policy_b,
      mission_id: mission_id,
      profiler_a: profiler_a,
      profiler_b: profiler_b,
      record_policy_a: record_policy_a,
      record_policy_b: record_policy_b,
      runtime_health_a: runtime_health_a,
      runtime_health_b: runtime_health_b
    }
  end

  test "same-mission profiler and runtime-health instances isolate routing, reset, and stop",
       context do
    %{
      ingress_policy_a: ingress_policy_a,
      ingress_policy_b: ingress_policy_b,
      mission_id: mission_id,
      profiler_a: profiler_a,
      profiler_b: profiler_b,
      record_policy_a: record_policy_a,
      record_policy_b: record_policy_b,
      runtime_health_a: runtime_health_a,
      runtime_health_b: runtime_health_b
    } = context

    profiler_client_a = Profiler.client(profiler_a)
    profiler_client_b = Profiler.client(profiler_b)
    runtime_health_client_a = RuntimeHealth.client(runtime_health_a)
    runtime_health_client_b = RuntimeHealth.client(runtime_health_b)

    assert profiler_client_a.table != profiler_client_b.table
    assert profiler_client_a.ingress_archive_policy == ingress_policy_a
    assert profiler_client_b.ingress_archive_policy == ingress_policy_b
    assert profiler_client_a.record_archive_policy == record_policy_a
    assert profiler_client_b.record_archive_policy == record_policy_b

    raw_a = raw_evidence(mission_id, "shared-evidence-a", <<1>>)
    raw_b = raw_evidence(mission_id, "shared-evidence-b", <<2, 2>>)
    raw_b_second = raw_evidence(mission_id, "shared-evidence-b-second", <<3, 3, 3>>)

    assert :ok =
             Profiler.record_ingress_result(profiler_client_a, raw_a,
               resolve_us: 10,
               end_to_end_us: 100
             )

    assert :ok =
             RuntimeHealth.execute(
               runtime_health_client_a,
               Profiler.ingress_result_event(),
               %{end_to_end_us: 100},
               %{mission_id: mission_id, source_endpoint_id: "endpoint-a"}
             )

    record_repo_query(profiler_client_a, raw_a, :resolve, 110, "SELECT 1")

    assert :ok =
             Profiler.record_ingress_result(profiler_client_b, raw_b,
               runtime_us: 20,
               end_to_end_us: 200
             )

    assert :ok =
             RuntimeHealth.execute(
               runtime_health_client_b,
               Profiler.ingress_result_event(),
               %{end_to_end_us: 200},
               %{mission_id: mission_id, source_endpoint_id: "endpoint-b"}
             )

    assert :ok =
             Profiler.record_ingress_result(profiler_client_b, raw_b_second,
               runtime_us: 30,
               end_to_end_us: 300,
               error?: true
             )

    assert :ok =
             RuntimeHealth.execute(
               runtime_health_client_b,
               Profiler.ingress_result_event(),
               %{end_to_end_us: 300},
               %{mission_id: mission_id, source_endpoint_id: "endpoint-b-second"}
             )

    record_repo_query(profiler_client_b, raw_b, :runtime, 210, "INSERT INTO samples")
    record_repo_query(profiler_client_b, raw_b_second, :persistence, 310, "UPDATE samples")

    assert :ok = IngressArchive.persist_raw_evidences(ingress_policy_a, [raw_a])
    assert :ok = IngressArchive.persist_raw_evidences(ingress_policy_b, [raw_b, raw_b_second])
    assert :ok = IngressArchive.flush(ingress_policy_a, mission_id)
    assert :ok = IngressArchive.flush(ingress_policy_b, mission_id)

    assert :ok =
             RecordArchive.persist_records(
               record_policy_a,
               raw_a,
               [],
               [packet_record(raw_a, "shared-packet-a")]
             )

    assert :ok =
             RecordArchive.persist_records_many(record_policy_b, [
               {raw_b, [], [packet_record(raw_b, "shared-packet-b")]},
               {raw_b_second, [], [packet_record(raw_b_second, "shared-packet-b-second")]}
             ])

    assert :ok = RecordArchive.flush(record_policy_a, mission_id)
    assert :ok = RecordArchive.flush(record_policy_b, mission_id)

    snapshot_a = Profiler.snapshot(profiler_client_a, mission_id)
    snapshot_b = Profiler.snapshot(profiler_client_b, mission_id)

    assert snapshot_a.mission_id == mission_id
    assert snapshot_b.mission_id == mission_id
    assert snapshot_a.ingress_count == 1
    assert snapshot_b.ingress_count == 2
    assert snapshot_a.raw_bytes_total == 1
    assert snapshot_b.raw_bytes_total == 5
    assert snapshot_a.ingress_error_count == 0
    assert snapshot_b.ingress_error_count == 1
    assert snapshot_a.db.query_count == 1
    assert snapshot_b.db.query_count == 2
    assert snapshot_a.db.operations.select_count == 1
    assert snapshot_b.db.operations.insert_count == 1
    assert snapshot_b.db.operations.update_count == 1
    assert snapshot_a.archive.ingress.flushed_count == 1
    assert snapshot_b.archive.ingress.flushed_count == 2
    assert snapshot_a.archive.protocol.flushed_count == 1
    assert snapshot_b.archive.protocol.flushed_count == 2
    assert Profiler.list_missions(profiler_client_a) == [mission_id]
    assert Profiler.list_missions(profiler_client_b) == [mission_id]

    assert RuntimeHealth.snapshot(runtime_health_client_a).total_events == 1
    assert RuntimeHealth.snapshot(runtime_health_client_b).total_events == 2

    survivor_archive = snapshot_b.archive

    assert :ok = Profiler.reset(profiler_client_a, mission_id)
    assert :ok = RuntimeHealth.reset(runtime_health_client_a)

    assert Profiler.snapshot(profiler_client_a, mission_id).ingress_count == 0
    assert IngressArchive.stats(ingress_policy_a, mission_id).flush_count == 0
    assert RecordArchive.stats(record_policy_a, mission_id).flush_count == 0
    assert Profiler.snapshot(profiler_client_b, mission_id).ingress_count == 2
    assert Profiler.snapshot(profiler_client_b, mission_id).archive == survivor_archive
    assert RuntimeHealth.snapshot(runtime_health_client_a).total_events == 0
    assert RuntimeHealth.snapshot(runtime_health_client_b).total_events == 2

    assert :ok = stop_supervised(@profiler_a_id)
    assert :ok = stop_supervised(@runtime_health_a_id)
    refute Process.alive?(profiler_a)
    refute Process.alive?(runtime_health_a)
    assert Process.alive?(profiler_b)
    assert Process.alive?(runtime_health_b)
    assert :ets.info(profiler_client_a.table) == :undefined
    assert :ets.info(profiler_client_b.table) != :undefined

    assert :ok =
             Profiler.record_ingress_result(profiler_client_b, raw_b,
               runtime_us: 40,
               end_to_end_us: 400
             )

    assert :ok =
             RuntimeHealth.execute(
               runtime_health_client_b,
               Profiler.ingress_result_event(),
               %{end_to_end_us: 400},
               %{mission_id: mission_id, source_endpoint_id: "endpoint-b"}
             )

    record_repo_query(profiler_client_b, raw_b, :runtime, 410, "SELECT 2")

    survivor_snapshot = Profiler.snapshot(profiler_client_b, mission_id)
    assert survivor_snapshot.ingress_count == 3
    assert survivor_snapshot.db.query_count == 3
    assert survivor_snapshot.archive == survivor_archive
    assert RuntimeHealth.snapshot(runtime_health_client_b).total_events == 3
  end

  defp start_instance!(module, id, opts) do
    start_supervised!(%{
      id: id,
      start: {module, :start_link, [opts]}
    })
  end

  defp record_repo_query(profiler_client, raw_evidence, stage, total_us, query) do
    Profiler.with_ingress_context(profiler_client, raw_evidence, fn ->
      Profiler.with_stage(stage, fn ->
        :telemetry.execute(
          [:cadence, :repo, :query],
          %{total_time: System.convert_time_unit(total_us, :microsecond, :native)},
          %{
            query: query,
            source: nil,
            result: {:ok, nil},
            repo: Repo,
            type: :ecto_sql_query
          }
        )
      end)
    end)
  end

  defp raw_evidence(mission_id, evidence_id, raw) do
    RawEvidence.new(%{
      evidence_id: evidence_id,
      mission_id: mission_id,
      protocol_family: :tm,
      direction: :downlink,
      raw: raw,
      receipt_time: DateTime.from_unix!(1_701_200_000, :second),
      source_ref: "shared-source"
    })
  end

  defp packet_record(raw_evidence, packet_id) do
    %PacketRecord{
      packet_id: packet_id,
      evidence_id: raw_evidence.evidence_id,
      mission_id: raw_evidence.mission_id,
      protocol_family: :tm,
      packet_kind: :space_packet,
      apid: 42,
      sequence_flags: 3,
      sequence_count: 9,
      secondary_header?: false,
      packet_data: <<0, 7>>,
      receipt_time: raw_evidence.receipt_time,
      provenance: %{}
    }
  end

  defp ingress_policy(name, instance_id, base_path) do
    IngressArchive.policy(
      module: IngressFileSystem,
      name: name,
      instance_id: instance_id,
      base_path: base_path,
      repo: Repo,
      flush_interval_ms: 60_000,
      flush_count: 100
    )
  end

  defp record_policy(name, instance_id, base_path) do
    RecordArchive.policy(
      module: RecordFileSystem,
      name: name,
      instance_id: instance_id,
      base_path: base_path,
      repo: Repo,
      flush_interval_ms: 60_000,
      flush_count: 100
    )
  end
end
