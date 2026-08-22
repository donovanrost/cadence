defmodule Cadence.Persistence.PersistTelemetryIngressRuntimeTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.FileSystem, as: IngressArchiveFileSystem
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.OperationalEvents
  alias Cadence.Platform.EventBus
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Protocol.RecordArchive.FileSystem, as: ProtocolRecordArchiveFileSystem
  alias Cadence.Protocol.RecordArchive.Postgres.{PacketRecordRow, TransferFrameRecordRow}
  alias Cadence.Protocol.RecordArchive.Postgres.ProtocolAnomalyRow
  alias Cadence.Runtime.DispatchRecords.DispatchDecisionRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.{CurrentValueStore, Storage}
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  test "persists protocol anomalies when raw evidence is archived outside Postgres" do
    ingress_base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_ingress_archive_anomaly_#{System.unique_integer([:positive])}"
      )

    protocol_base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_protocol_archive_anomaly_#{System.unique_integer([:positive])}"
      )

    persistence_policy =
      filesystem_persistence_policy(ingress_base_path, protocol_base_path,
        current_value_store: Cadence.TestSupport.LazyCurrentValueStore,
        telemetry_writer: Cadence.Telemetry.Storage.Writers.Noop,
        telemetry_storage_opts: [organization_id: "org-test"]
      )

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-archived-gap",
        mission_id: "mission-alpha",
        display_name: "SC Archived Gap"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-archived-gap",
        mission_id: "mission-alpha",
        spacecraft_id: "sc-archived-gap",
        source_ref: "station-archived-gap"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "ARCHGAP",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-archived-gap",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted_binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               "mission-alpha",
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version
             )

    frame_size = 14

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        protocol_family: :tm,
        source_ref: "station-archived-gap",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: build_tm_single_frame(42, 1, <<0, 31>>, frame_size, 1)
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        protocol_family: :tm,
        source_ref: "station-archived-gap",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: build_tm_single_frame(42, 2, <<0, 32>>, frame_size, 3)
      })

    assert {:ok, first_result} = Cadence.process_telemetry_ingress(raw_evidence_one)

    handler_id = "persistence-empty-multi-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, metadata, test_pid ->
          send(test_pid, {:unexpected_persistence_query, metadata})
        end,
        self()
      )

    on_exit(fn -> _ = :telemetry.detach(handler_id) end)

    assert :ok =
             RuntimePersistence.persist_processing_results(
               persistence_policy,
               [%{first_result | outputs: []}],
               organization_id: "org-test",
               record_current_values?: false
             )

    refute_receive {:unexpected_persistence_query, _metadata}, 100
    :ok = :telemetry.detach(handler_id)

    assert {:ok, second_result} = Cadence.process_telemetry_ingress(raw_evidence_two)

    assert {:ok, ^second_result} =
             RuntimePersistence.persist_processing_result(
               persistence_policy,
               second_result,
               organization_id: "org-test"
             )

    assert Enum.map(second_result.protocol_anomalies, & &1.anomaly_kind) == [
             :master_channel_frame_count_discontinuity,
             :frame_sequence_discontinuity
           ]

    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-alpha") == 0

    latency_events =
      OperationalEvents.list_events("mission-alpha",
        source_record_kind: :operational_observable_snapshot,
        kind: :operational_observable_metric_sampled,
        order: :asc
      )

    assert latency_events == []

    anomaly_rows =
      ProtocolAnomalyRow
      |> where([row], row.mission_id == "mission-alpha")
      |> Repo.all()

    assert Enum.sort(Enum.map(anomaly_rows, & &1.anomaly_kind)) == [
             "frame_sequence_discontinuity",
             "master_channel_frame_count_discontinuity"
           ]

    assert Enum.all?(anomaly_rows, &(&1.evidence_id == raw_evidence_two.evidence_id))
  end

  test "batched persistence retries tolerate already-inserted protocol anomalies" do
    ingress_base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_ingress_archive_retry_#{System.unique_integer([:positive])}"
      )

    protocol_base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_protocol_archive_retry_#{System.unique_integer([:positive])}"
      )

    persistence_policy =
      filesystem_persistence_policy(ingress_base_path, protocol_base_path,
        telemetry_writer: Cadence.Telemetry.Storage.Writers.Noop,
        telemetry_storage_opts: [organization_id: "org-test"]
      )

    organization_id =
      "org-anomaly-retry-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id = "mission-anomaly-retry-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-anomaly-retry",
        mission_id: mission_id,
        display_name: "SC Retry"
      })

    assert {:ok, _persisted_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-anomaly-retry",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "station-anomaly-retry"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_name: "RETRY",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "#{mission_id}-default",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted_binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               organization_id,
               mission_id,
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version,
               activated_by: %{"service_identity_id" => "svc-test"}
             )

    frame_size = 14

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "station-anomaly-retry",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: build_tm_single_frame(42, 1, <<0, 31>>, frame_size, 1)
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "station-anomaly-retry",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: build_tm_single_frame(42, 2, <<0, 32>>, frame_size, 3)
      })

    assert {:ok, first_result} = Cadence.process_telemetry_ingress(raw_evidence_one)
    assert first_result.protocol_anomalies == []

    assert {:ok, second_result} = Cadence.process_telemetry_ingress(raw_evidence_two)
    assert length(second_result.protocol_anomalies) == 2

    assert :ok =
             RuntimePersistence.persist_processing_results(
               persistence_policy,
               [second_result],
               record_current_values?: false
             )

    assert :ok =
             RuntimePersistence.persist_processing_results(
               persistence_policy,
               [second_result],
               record_current_values?: false
             )

    assert count_for_mission(ProtocolAnomalyRow, :anomaly_id, mission_id) == 2
  end

  test "persists TM raw evidence before packet reassembly completes across runtime calls" do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-tm",
        mission_id: "mission-alpha",
        display_name: "SC TM"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-tm",
        mission_id: "mission-alpha",
        spacecraft_id: "sc-tm",
        source_ref: "station-tm"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-tm",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration:
              PacketDefinition.new(%{
                mission_id: "mission-alpha",
                packet_name: "TMHK",
                apid: 42,
                fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
              })
          })
        ]
      })

    assert {:ok, persisted_binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               "mission-alpha",
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version
             )

    frame_size = 10
    [frame_one, frame_two] = build_tm_space_packet_frames(42, 4, <<0, 21>>, frame_size)

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        protocol_family: :tm,
        source_ref: "station-tm",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: frame_one
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        protocol_family: :tm,
        source_ref: "station-tm",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: frame_two
      })

    assert {:ok, first_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence_one)
    assert first_result.packet_records == []
    assert length(first_result.transfer_frame_records) == 1
    assert first_result.protocol_anomalies == []
    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-alpha") == 1
    assert count_for_mission(TransferFrameRecordRow, :frame_record_id, "mission-alpha") == 1
    assert count_for_mission(PacketRecordRow, :packet_id, "mission-alpha") == 0
    assert count_for_mission(ProtocolAnomalyRow, :anomaly_id, "mission-alpha") == 0
    assert count_dispatch_decisions_for_evidence(raw_evidence_one.evidence_id) == 0
    assert count_for_mission(TelemetrySampleRow, :sample_id, "mission-alpha") == 0

    assert {:ok, second_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence_two)
    [packet_record] = second_result.packet_records
    assert length(second_result.transfer_frame_records) == 1
    assert second_result.protocol_anomalies == []
    assert packet_record.protocol_family == :tm
    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-alpha") == 2
    assert count_for_mission(TransferFrameRecordRow, :frame_record_id, "mission-alpha") == 2
    assert count_for_mission(PacketRecordRow, :packet_id, "mission-alpha") == 1
    assert count_for_mission(ProtocolAnomalyRow, :anomaly_id, "mission-alpha") == 0

    assert count_dispatch_decisions_for_evidence([
             raw_evidence_one.evidence_id,
             raw_evidence_two.evidence_id
           ]) == 0

    assert count_for_mission(TelemetrySampleRow, :sample_id, "mission-alpha") == 1

    [first_frame_row, second_frame_row] =
      TransferFrameRecordRow
      |> where([row], row.mission_id == "mission-alpha")
      |> order_by(asc: :inserted_at)
      |> Repo.all()

    assert first_frame_row.protocol_family == "tm"
    assert first_frame_row.vcid == 2
    assert second_frame_row.frame_seq == 1
  end

  test "persists TM sequence discontinuity anomalies alongside valid frame records" do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-gap",
        mission_id: "mission-alpha",
        display_name: "SC GAP"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-gap",
        mission_id: "mission-alpha",
        spacecraft_id: "sc-gap",
        source_ref: "station-gap"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "GAP",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-gap",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted_binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               "mission-alpha",
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version
             )

    frame_size = 14

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        protocol_family: :tm,
        source_ref: "station-gap",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: build_tm_single_frame(42, 1, <<0, 31>>, frame_size, 1)
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        protocol_family: :tm,
        source_ref: "station-gap",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: build_tm_single_frame(42, 2, <<0, 32>>, frame_size, 3)
      })

    assert {:ok, first_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence_one)
    assert first_result.protocol_anomalies == []

    assert {:ok, second_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence_two)
    assert length(second_result.packet_records) == 1

    assert Enum.map(second_result.protocol_anomalies, & &1.anomaly_kind) == [
             :master_channel_frame_count_discontinuity,
             :frame_sequence_discontinuity
           ]

    anomaly_rows =
      ProtocolAnomalyRow
      |> where([row], row.mission_id == "mission-alpha")
      |> Repo.all()

    assert length(anomaly_rows) == 2

    anomaly_row =
      Enum.find(anomaly_rows, &(&1.anomaly_kind == "frame_sequence_discontinuity"))

    assert anomaly_row.anomaly_kind == "frame_sequence_discontinuity"
    assert anomaly_row.protocol_family == "tm"
    assert anomaly_row.vcid == 2
    assert anomaly_row.metadata["expected"] == 2
    assert anomaly_row.metadata["observed"] == 3
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

  defp filesystem_persistence_policy(ingress_base_path, protocol_base_path, opts) do
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
      CurrentValueStore.policy(
        module:
          Keyword.get(
            opts,
            :current_value_store,
            Cadence.Telemetry.CurrentValueStore.Postgres
          )
      )

    storage_config =
      [
        writer:
          Keyword.get(
            opts,
            :telemetry_writer,
            Cadence.Telemetry.Storage.Writers.PostgresReadModel
          ),
        organization_id: "org-test",
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry"
      ]
      |> Keyword.merge(Keyword.get(opts, :telemetry_storage_opts, []))

    storage_policy =
      Storage.policy(storage_config, current_value_store_policy: current_value_store_policy)

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

  defp build_tm_space_packet_frames(apid, sequence_count, packet_data, frame_size) do
    packet = build_space_packet(apid, sequence_count, packet_data)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init([])

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    for <<frame::binary-size(^frame_size) <- encoded_frames>>, do: frame
  end

  defp build_tm_single_frame(apid, sequence_count, packet_data, frame_size, vcfc) do
    packet = build_space_packet(apid, sequence_count, packet_data)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init(vcfc: vcfc)

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    encoded_frames
  end
end
