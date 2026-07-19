defmodule Cadence.Telemetry.ProfilerTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.Profiler

  test "captures resolve, runtime, persistence, and query stats for active ingress" do
    mission_id = "mission-profile"
    Profiler.reset(mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-profile",
        mission_id: mission_id,
        display_name: "SC Profile"
      })

    assert {:ok, _spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-profile",
        mission_id: mission_id,
        spacecraft_id: "sc-profile",
        source_ref: "station-profile"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "binding-set-profile",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration:
              PacketDefinition.new(%{
                mission_id: mission_id,
                packet_definition_id: "packet-profile",
                packet_name: "HK",
                apid: 42,
                fields: [
                  %{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint},
                  %{name: "enabled", offset_bits: 16, size_bits: 1, data_type: :bool}
                ]
              })
          })
        ]
      })

    assert {:ok, persisted_binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.Runtime.activate_binding_set(
               mission_id,
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "station-profile",
        raw: build_space_packet(42, 3, <<0, 7, 1::size(1), 0::size(7)>>)
      })

    assert {:ok, processing_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence)
    assert length(processing_result.outputs) == 2

    snapshot = Profiler.snapshot(mission_id)

    assert snapshot.ingress_count == 1
    assert snapshot.ingress_error_count == 0
    assert snapshot.raw_bytes_total == byte_size(raw_evidence.raw)
    assert snapshot.packets.packet_count == 1
    assert snapshot.dispatch.dispatch_count == 1
    assert snapshot.dispatch.work_item_count == 1
    assert snapshot.dispatch.sample_count == 2

    assert snapshot.stages.resolve.count == 1
    assert snapshot.stages.runtime.count == 1
    assert snapshot.stages.persistence.count == 1
    assert snapshot.runtime_components.runtime_boundary.count == 0
    assert snapshot.runtime_components.telemetry_sample_extraction.count == 0
    assert snapshot.runtime_components.current_value_record.count == 0
    assert snapshot.runtime_components.partition_prepare.count == 1
    assert snapshot.runtime_components.partition_decode.count == 1
    assert snapshot.runtime_components.partition_dispatch.count == 1
    assert snapshot.runtime_components.runtime_record_persistence.count == 1

    assert snapshot.db.query_count > 0
    assert snapshot.db.operations.select_count > 0
    assert snapshot.db.operations.insert_count > 0
    assert snapshot.db.by_stage.resolve.query_count > 0
    assert snapshot.db.by_stage.persistence.query_count > 0
    assert snapshot.archive.combined.queue_depth == 0
    assert snapshot.archive.combined.flush_count == 0
    assert snapshot.archive.ingress.queue_depth == 0
    assert snapshot.archive.protocol.queue_depth == 0

    assert :ok = Profiler.reset(mission_id)

    reset_snapshot = Profiler.snapshot(mission_id)
    assert reset_snapshot.ingress_count == 0
    assert reset_snapshot.runtime_components.runtime_boundary.count == 0
    assert reset_snapshot.db.query_count == 0
    assert reset_snapshot.archive.combined.flush_count == 0
  end

  defp build_space_packet(apid, sequence_count, payload) when is_binary(payload) do
    data_length = byte_size(payload) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      data_length::16,
      payload::binary
    >>
  end
end
