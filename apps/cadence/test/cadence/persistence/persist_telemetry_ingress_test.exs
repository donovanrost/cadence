defmodule Cadence.Persistence.PersistTelemetryIngressTest do
  use Cadence.DataCase, async: true

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Platform.EventBus
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Runtime.DispatchRecords.DispatchDecisionRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.CurrentValueStore.Postgres.TelemetryLatestValueRow
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow
  alias Cadence.TestSupport.TelemetryPersistencePolicies

  setup do
    event_bus =
      start_supervised!({EventBus, name: nil, delivery: :sync, before_notify: nil})

    policies = TelemetryPersistencePolicies.postgres()

    persistence_policy =
      RuntimePersistence.policy(
        policies.ingress_archive,
        policies.record_archive,
        policies.telemetry_storage,
        event_bus: event_bus
      )

    %{persistence_policy: persistence_policy}
  end

  test "persists raw evidence, packet records, and canonical telemetry samples without live dispatch rows",
       %{persistence_policy: persistence_policy} do
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

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence, binding_set)

    assert {:ok, ^result} =
             RuntimePersistence.persist_processing_result(
               persistence_policy,
               result,
               []
             )

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

  test "loads persisted little-endian packet definitions and decodes samples correctly", %{
    persistence_policy: persistence_policy
  } do
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
             Cadence.process_telemetry_ingress(
               raw_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, ^result} =
             RuntimePersistence.persist_processing_result(
               persistence_policy,
               result,
               []
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

  test "persists multiple processing results in one batch with Postgres archive backends", %{
    persistence_policy: persistence_policy
  } do
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
             RuntimePersistence.persist_processing_results(
               persistence_policy,
               [first_result, second_result],
               record_current_values?: false
             )

    assert count_for_mission(RawEvidenceRow, :evidence_id, "mission-alpha") == 2
    assert count_for_mission(PacketRecordRow, :packet_id, "mission-alpha") == 2
    assert count_for_mission(TelemetrySampleRow, :sample_id, "mission-alpha") == 2

    sample_values =
      TelemetrySampleRow
      |> where([row], row.mission_id == "mission-alpha")
      |> Repo.all()
      |> Enum.map(fn row -> row.raw_value["value"] end)
      |> Enum.sort()

    assert sample_values == [7, 8]
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
end
