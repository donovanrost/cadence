defmodule Cadence.Persistence.PersistTelemetryIngressTest do
  use Cadence.ConfigCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Governance.BindingSetRow
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.FileSystem, as: IngressArchiveFileSystem
  alias Cadence.OperationalEvents
  alias Cadence.Protocol.RecordArchive.FileSystem, as: ProtocolRecordArchiveFileSystem

  alias Cadence.Persistence.Schemas.{
    DispatchDecisionRow,
    PacketRecordRow,
    ProtocolAnomalyRow,
    RawEvidenceRow,
    TelemetryLatestValueRow,
    TelemetrySampleRow,
    TransferFrameRecordRow
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  test "persists raw evidence, packet records, and canonical telemetry samples without live dispatch rows" do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-alpha",
        mission_id: "mission-alpha",
        display_name: "SC Alpha"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-alpha",
        mission_id: "mission-alpha",
        spacecraft_id: "sc-alpha",
        source_ref: "station-a"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    source_time = DateTime.from_unix!(1_700_000_000, :second)
    receipt_time = DateTime.from_unix!(1_700_000_005, :second)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        spacecraft_id: "sc-alpha",
        source_time: source_time,
        receipt_time: receipt_time,
        source_ref: "station-a",
        metadata: %{vcid: 7},
        raw: build_space_packet(42, 7, <<1, 244, 1::size(1), 0::size(7)>>)
      })

    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{name: "temperature_raw", offset_bits: 0, size_bits: 16, data_type: :uint},
          %{name: "heater_enabled", offset_bits: 16, size_bits: 1, data_type: :bool}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
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

    assert {:ok, result} =
             Cadence.process_and_persist_telemetry_ingress(raw_evidence, binding_set)

    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-alpha") == 1
    assert count_for_mission(PacketRecordRow, :packet_id, "mission-alpha") == 1
    assert count_dispatch_decisions_for_evidence(raw_evidence.evidence_id) == 0
    assert count_for_mission(TelemetrySampleRow, :sample_id, "mission-alpha") == 2
    assert count_for_mission(TelemetryLatestValueRow, :id, "mission-alpha") == 2

    evidence_row = Repo.get!(RawEvidenceRow, raw_evidence.evidence_id)
    assert evidence_row.mission_id == "mission-alpha"
    assert evidence_row.source_endpoint_ref == "endpoint-sc-alpha"
    assert evidence_row.protocol_family == "space_packet"
    assert evidence_row.direction == "downlink"
    assert evidence_row.metadata == %{"vcid" => 7}
    assert evidence_row.raw == raw_evidence.raw

    [packet_record] = result.packet_records
    [dispatch_decision] = result.dispatch_decisions

    packet_row = Repo.get!(PacketRecordRow, packet_record.packet_id)
    assert packet_row.evidence_id == raw_evidence.evidence_id
    assert packet_row.source_endpoint_ref == "endpoint-sc-alpha"
    assert packet_row.packet_kind == "space_packet"
    assert packet_row.apid == 42
    refute packet_row.secondary_header
    assert packet_row.provenance["source_endpoint_ref"] == "endpoint-sc-alpha"
    assert packet_row.provenance["source_ref"] == "station-a"
    assert dispatch_decision.packet_id == packet_record.packet_id
    assert dispatch_decision.status == :matched
    assert length(dispatch_decision.work_items) == 1

    telemetry_samples =
      TelemetrySampleRow
      |> where([row], row.mission_id == "mission-alpha")
      |> order_by(asc: :point_name)
      |> Repo.all()

    assert Enum.map(telemetry_samples, & &1.point_name) == [
             "HK.heater_enabled",
             "HK.temperature_raw"
           ]

    [heater_row, temperature_row] = telemetry_samples
    assert heater_row.raw_value == %{"value" => true}
    assert heater_row.engineering_value == %{"value" => true}
    assert heater_row.quality_state == "good"
    assert temperature_row.raw_value == %{"value" => 500}
    assert temperature_row.evidence_id == raw_evidence.evidence_id
    assert temperature_row.packet_id == packet_record.packet_id
  end

  test "loads a persisted binding set by id and version during ingest" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-default",
        version: 3,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, _binding_set} = Cadence.Governance.persist_binding_set(binding_set)
    assert count_for_mission(BindingSetRow, :id, "mission-alpha") == 1

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(42, 9, <<0, 7>>)
      })

    assert {:ok, result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    [dispatch_decision] = result.dispatch_decisions
    assert dispatch_decision.status == :matched
    assert Enum.map(result.outputs, & &1.raw_value) == [7]
    assert count_for_mission(TelemetrySampleRow, :sample_id, "mission-alpha") == 1
  end

  test "loads persisted little-endian packet definitions and decodes samples correctly" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "THERM",
        apid: 42,
        fields: [
          %{
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint,
            byte_order: :little_endian
          },
          %{
            name: "temperature_c",
            offset_bits: 16,
            size_bits: 32,
            data_type: :float,
            byte_order: :little_endian
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-little-endian",
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

    assert {:ok, _binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw:
          build_space_packet(
            42,
            13,
            <<500::little-unsigned-integer-size(16), 12.5::little-float-32>>
          )
      })

    assert {:ok, result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert Enum.map(result.outputs, &{&1.point_name, &1.raw_value}) == [
             {"THERM.counter", 500},
             {"THERM.temperature_c", 12.5}
           ]

    telemetry_samples =
      TelemetrySampleRow
      |> where([row], row.mission_id == "mission-alpha")
      |> order_by(asc: :point_name)
      |> Repo.all()

    assert Enum.map(telemetry_samples, &{&1.point_name, &1.raw_value}) == [
             {"THERM.counter", %{"value" => 500}},
             {"THERM.temperature_c", %{"value" => 12.5}}
           ]
  end

  test "does not persist dispatch decisions when packet and raw evidence rows are archived outside Postgres" do
    previous_ingress_archive = Application.get_env(:cadence, :ingress_archive, [])
    previous_protocol_archive = Application.get_env(:cadence, :protocol_record_archive, [])

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

    Application.put_env(:cadence, :ingress_archive,
      module: IngressArchiveFileSystem,
      base_path: ingress_base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    Application.put_env(:cadence, :protocol_record_archive,
      module: ProtocolRecordArchiveFileSystem,
      base_path: protocol_base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    start_supervised!(
      {Cadence.IngressArchive.FileSystem.Writer, Application.get_env(:cadence, :ingress_archive)}
    )

    start_supervised!(
      {Cadence.Protocol.RecordArchive.FileSystem.Writer,
       Application.get_env(:cadence, :protocol_record_archive)}
    )

    on_exit(fn ->
      Application.put_env(:cadence, :ingress_archive, previous_ingress_archive)
      Application.put_env(:cadence, :protocol_record_archive, previous_protocol_archive)
      File.rm_rf!(ingress_base_path)
      File.rm_rf!(protocol_base_path)
    end)

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

    assert {:ok, result} =
             Cadence.process_and_persist_telemetry_ingress(raw_evidence, binding_set)

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

  test "persists protocol anomalies when raw evidence is archived outside Postgres" do
    previous_ingress_archive = Application.get_env(:cadence, :ingress_archive, [])
    previous_protocol_archive = Application.get_env(:cadence, :protocol_record_archive, [])

    previous_current_value_store =
      Application.get_env(:cadence, :telemetry_current_value_store, [])

    previous_telemetry_storage = Application.get_env(:cadence, :telemetry_storage, [])

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

    Application.put_env(:cadence, :ingress_archive,
      module: IngressArchiveFileSystem,
      base_path: ingress_base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    Application.put_env(:cadence, :protocol_record_archive,
      module: ProtocolRecordArchiveFileSystem,
      base_path: protocol_base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    Application.put_env(:cadence, :telemetry_current_value_store,
      module: Cadence.TestSupport.LazyCurrentValueStore
    )

    Application.put_env(:cadence, :telemetry_storage,
      writer: Cadence.Telemetry.Storage.Writers.Noop,
      organization_id: "org-test"
    )

    start_supervised!(
      {Cadence.IngressArchive.FileSystem.Writer, Application.get_env(:cadence, :ingress_archive)}
    )

    start_supervised!(
      {Cadence.Protocol.RecordArchive.FileSystem.Writer,
       Application.get_env(:cadence, :protocol_record_archive)}
    )

    on_exit(fn ->
      Application.put_env(:cadence, :ingress_archive, previous_ingress_archive)
      Application.put_env(:cadence, :protocol_record_archive, previous_protocol_archive)
      Application.put_env(:cadence, :telemetry_current_value_store, previous_current_value_store)
      Application.put_env(:cadence, :telemetry_storage, previous_telemetry_storage)
      File.rm_rf!(ingress_base_path)
      File.rm_rf!(protocol_base_path)
    end)

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
             Cadence.Runtime.activate_binding_set(
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

    assert {:ok, _first_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence_one)
    assert {:ok, second_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence_two)

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

    assert length(latency_events) == 2

    assert Enum.all?(
             latency_events,
             &(Map.get(&1.payload, "observable_id") == "ingress.processing_latency_ms")
           )

    assert Enum.all?(latency_events, &(Map.get(&1.payload, "scope_kind") == "source_endpoint"))

    assert Enum.all?(
             latency_events,
             &(Map.get(&1.payload, "source_endpoint_id") == "endpoint-archived-gap")
           )

    assert Enum.all?(
             latency_events,
             &(Map.get(&1.payload, "spacecraft_id") == "sc-archived-gap")
           )

    assert Enum.all?(latency_events, &(Map.get(&1.payload, "unit") == "ms"))
    assert Enum.all?(latency_events, &is_number(Map.get(&1.payload, "value")))
    assert Enum.all?(latency_events, &(Map.get(&1.payload, "value") > 0))

    assert Enum.map(latency_events, &Map.get(&1.metadata, "evidence_id")) == [
             raw_evidence_one.evidence_id,
             raw_evidence_two.evidence_id
           ]

    assert Enum.all?(latency_events, &(Map.get(&1.metadata, "end_to_end_us") > 0))

    latency_samples =
      Cadence.OperationalEvents.operational_observable_metric_samples("mission-alpha",
        observable_id: "ingress.processing_latency_ms",
        source_endpoint_id: "endpoint-archived-gap",
        order: :asc
      )

    assert length(latency_samples) == 2
    assert Enum.all?(latency_samples, &(&1.source_endpoint_id == "endpoint-archived-gap"))
    assert Enum.all?(latency_samples, &(&1.spacecraft_id == "sc-archived-gap"))
    assert Enum.all?(latency_samples, &(&1.unit == "ms"))
    assert Enum.all?(latency_samples, &(&1.value > 0))

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
    previous_ingress_archive = Application.get_env(:cadence, :ingress_archive, [])
    previous_protocol_archive = Application.get_env(:cadence, :protocol_record_archive, [])
    previous_telemetry_storage = Application.get_env(:cadence, :telemetry_storage, [])

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

    Application.put_env(:cadence, :ingress_archive,
      module: IngressArchiveFileSystem,
      base_path: ingress_base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    Application.put_env(:cadence, :protocol_record_archive,
      module: ProtocolRecordArchiveFileSystem,
      base_path: protocol_base_path,
      flush_interval_ms: 5_000,
      flush_count: 10
    )

    Application.put_env(:cadence, :telemetry_storage,
      writer: Cadence.Telemetry.Storage.Writers.Noop,
      organization_id: "org-test"
    )

    start_supervised!(
      {Cadence.IngressArchive.FileSystem.Writer, Application.get_env(:cadence, :ingress_archive)}
    )

    start_supervised!(
      {Cadence.Protocol.RecordArchive.FileSystem.Writer,
       Application.get_env(:cadence, :protocol_record_archive)}
    )

    on_exit(fn ->
      Application.put_env(:cadence, :ingress_archive, previous_ingress_archive)
      Application.put_env(:cadence, :protocol_record_archive, previous_protocol_archive)
      Application.put_env(:cadence, :telemetry_storage, previous_telemetry_storage)
      File.rm_rf!(ingress_base_path)
      File.rm_rf!(protocol_base_path)
    end)

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
             Cadence.Activations.activate_binding_set(
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
             Cadence.Persistence.persist_processing_results(
               [second_result],
               record_current_values?: false
             )

    assert :ok =
             Cadence.Persistence.persist_processing_results(
               [second_result],
               record_current_values?: false
             )

    assert count_for_mission(ProtocolAnomalyRow, :anomaly_id, mission_id) == 2
  end

  test "persists multiple processing results in one batch with Postgres archive backends" do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-batch",
        mission_id: "mission-alpha",
        display_name: "SC Batch"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-batch",
        mission_id: "mission-alpha",
        spacecraft_id: "sc-batch",
        source_ref: "station-batch"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "BATCH",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-batch",
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

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        source_ref: "station-batch",
        raw: build_space_packet(42, 21, <<0, 7>>)
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        source_ref: "station-batch",
        raw: build_space_packet(42, 22, <<0, 8>>)
      })

    assert {:ok, first_result} = Cadence.process_telemetry_ingress(raw_evidence_one, binding_set)
    assert {:ok, second_result} = Cadence.process_telemetry_ingress(raw_evidence_two, binding_set)

    assert :ok =
             Cadence.Persistence.persist_processing_results(
               [first_result, second_result],
               record_current_values?: false
             )

    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-alpha") == 2
    assert count_for_mission(PacketRecordRow, :packet_id, "mission-alpha") == 2
    assert count_for_mission(TelemetrySampleRow, :sample_id, "mission-alpha") == 2

    sample_values =
      TelemetrySampleRow
      |> where([row], row.mission_id == "mission-alpha")
      |> order_by(asc: :receipt_time, asc: :sample_id)
      |> Repo.all()
      |> Enum.map(fn row -> row.raw_value["value"] end)

    assert sample_values == [7, 8]
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
             Cadence.Runtime.activate_binding_set(
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
             Cadence.Runtime.activate_binding_set(
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
