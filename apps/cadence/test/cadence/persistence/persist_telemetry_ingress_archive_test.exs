defmodule Cadence.Persistence.PersistTelemetryIngressArchiveTest do
  use Cadence.ProcessDataCase, async: false

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.FileSystem, as: IngressArchiveFileSystem
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Platform.EventBus
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Protocol.RecordArchive.FileSystem, as: ProtocolRecordArchiveFileSystem
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Runtime.DispatchRecords.DispatchDecisionRow
  alias Cadence.Telemetry.{CurrentValueStore, Storage}

  test "does not persist dispatch decisions when packet and raw evidence rows are archived outside Postgres" do
    ingress_base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_ingress_archive_dispatch_#{System.unique_integer([:positive])}"
      )

    protocol_base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_protocol_archive_dispatch_#{System.unique_integer([:positive])}"
      )

    persistence_policy =
      filesystem_persistence_policy(ingress_base_path, protocol_base_path)

    persist_mission_scope("org-dispatch-archive", "mission-dispatch-archive")

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-dispatch-archive",
        raw: build_space_packet(42, 11, <<0, 7>>)
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-dispatch-archive",
        binding_set_id: "mission-dispatch-archive-default",
        version: 1,
        rules: []
      })

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence, binding_set)

    assert {:ok, ^result} =
             RuntimePersistence.persist_processing_result(persistence_policy, result, [])

    assert result.outputs == []
    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-dispatch-archive") == 0
    assert count_for_mission(PacketRecordRow, :packet_id, "mission-dispatch-archive") == 0
    assert count_dispatch_decisions_for_evidence(raw_evidence.evidence_id) == 0

    [dispatch_decision] = result.dispatch_decisions
    assert dispatch_decision.packet_id
    assert dispatch_decision.evidence_id == raw_evidence.evidence_id
    assert dispatch_decision.status == :unmatched
    assert dispatch_decision.work_items == []
  end

  defp count_for_mission(schema, field, mission_id) do
    schema
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.aggregate(:count, field)
  end

  defp count_dispatch_decisions_for_evidence(evidence_ids) do
    evidence_ids = List.wrap(evidence_ids)

    DispatchDecisionRow
    |> where([row], row.evidence_id in ^evidence_ids)
    |> Repo.aggregate(:count, :dispatch_decision_id)
  end

  defp filesystem_persistence_policy(ingress_base_path, protocol_base_path) do
    ingress_archive_policy =
      IngressArchive.policy(
        module: IngressArchiveFileSystem,
        base_path: ingress_base_path,
        flush_interval_ms: 5_000,
        flush_count: 10
      )

    record_archive_policy =
      RecordArchive.policy(
        module: ProtocolRecordArchiveFileSystem,
        base_path: protocol_base_path,
        flush_interval_ms: 5_000,
        flush_count: 10
      )

    current_value_store_policy =
      CurrentValueStore.policy(module: Cadence.Telemetry.CurrentValueStore.Postgres)

    storage_policy =
      Storage.policy(
        [
          writer: Cadence.Telemetry.Storage.Writers.PostgresReadModel,
          organization_id: "org-test",
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        ],
        current_value_store_policy: current_value_store_policy
      )

    event_bus =
      start_supervised!({EventBus, name: nil, delivery: :sync, before_notify: nil})

    start_supervised!(IngressArchive.child_spec(ingress_archive_policy))
    start_supervised!(RecordArchive.child_spec(record_archive_policy))

    on_exit(fn ->
      File.rm_rf!(ingress_base_path)
      File.rm_rf!(protocol_base_path)
    end)

    RuntimePersistence.policy(
      ingress_archive_policy,
      record_archive_policy,
      storage_policy,
      event_bus: event_bus
    )
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
