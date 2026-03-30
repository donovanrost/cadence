defmodule Cadence.Reads.TelemetryTest do
  use Cadence.DataCase, async: true

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition

  setup do
    organization_id = "org-telemetry-reads"
    mission_id = "mission-alpha"

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "reads telemetry history and keeps the latest-value projection on the newest sample", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    binding_set = persist_binding_set_fixture(organization_id, mission_id)

    newer_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        receipt_time: DateTime.from_unix!(1_700_000_100, :second),
        raw: build_space_packet(42, 2, <<0, 20>>)
      })

    older_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        receipt_time: DateTime.from_unix!(1_700_000_050, :second),
        raw: build_space_packet(42, 1, <<0, 10>>)
      })

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               newer_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               older_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    latest_sample = Cadence.latest_telemetry_value(organization_id, mission_id, "HK.counter", [])
    assert latest_sample.raw_value == 20
    assert DateTime.compare(latest_sample.receipt_time, newer_evidence.receipt_time) == :eq

    history =
      Cadence.telemetry_history(organization_id, mission_id, "HK.counter", order: :asc, limit: 10)

    assert Enum.map(history, & &1.raw_value) == [10, 20]

    latest_values = Cadence.latest_telemetry_values(organization_id, mission_id, [])
    assert Enum.map(latest_values, & &1.point_name) == ["HK.counter"]
    assert hd(latest_values).raw_value == 20
  end

  defp persist_binding_set_fixture(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: mission_id <> "-read-model",
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
             Cadence.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id
    persisted_binding_set
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
