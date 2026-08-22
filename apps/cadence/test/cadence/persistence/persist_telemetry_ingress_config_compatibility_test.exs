defmodule Cadence.Persistence.PersistTelemetryIngressConfigCompatibilityTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Governance.BindingSetRow
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow

  test "configured compatibility arity loads a persisted binding set by id and version" do
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

  defp count_for_mission(schema, field, mission_id) do
    schema
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.aggregate(:count, field)
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
