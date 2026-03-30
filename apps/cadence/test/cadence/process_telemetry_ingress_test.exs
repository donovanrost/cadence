defmodule Cadence.ProcessTelemetryIngressTest do
  use Cadence.DataCase, async: true

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Spacecraft
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.PacketDefinition

  test "processes raw evidence into canonical telemetry samples through governed dispatch" do
    source_time = DateTime.from_unix!(1_700_000_000, :second)
    receipt_time = DateTime.from_unix!(1_700_000_005, :second)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        spacecraft_id: "sc-alpha",
        source_time: source_time,
        receipt_time: receipt_time,
        source_ref: "station-a",
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

    [packet_record] = result.packet_records
    [dispatch_decision] = result.dispatch_decisions

    assert packet_record.evidence_id == raw_evidence.evidence_id
    assert packet_record.apid == 42
    assert dispatch_decision.status == :matched
    assert length(result.outputs) == 2

    sample_names = Enum.map(result.outputs, & &1.point_name)
    assert sample_names == ["HK.temperature_raw", "HK.heater_enabled"]

    [temperature_sample, heater_sample] = result.outputs
    assert temperature_sample.raw_value == 500
    assert temperature_sample.generation_time == source_time
    assert temperature_sample.receipt_time == receipt_time
    assert heater_sample.raw_value == true
    assert heater_sample.provenance.evidence_id == raw_evidence.evidence_id
  end

  test "records an unmatched dispatch decision when no binding rule matches" do
    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(99, 3, <<0, 10>>)
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        rules: [
          %{handler_key: :definition_bound_telemetry, apid: 42, packet_kind: :space_packet}
        ]
      })

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence, binding_set)
    [dispatch_decision] = result.dispatch_decisions
    assert dispatch_decision.status == :unmatched
    assert dispatch_decision.anomalies == [:no_matching_binding_rules]
    assert result.outputs == []
  end

  test "marks dispatch as ambiguous when multiple exclusive rules match the same packet" do
    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(42, 1, <<0, 1>>)
      })

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
        rules: [
          %{
            handler_key: :definition_bound_telemetry,
            apid: 42,
            packet_kind: :space_packet,
            priority: 10,
            handler_configuration: packet_definition
          },
          %{
            handler_key: :definition_bound_telemetry,
            apid: 42,
            packet_kind: :space_packet,
            priority: 20,
            handler_configuration: packet_definition
          }
        ]
      })

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence, binding_set)
    [dispatch_decision] = result.dispatch_decisions
    assert dispatch_decision.status == :ambiguous
    assert dispatch_decision.anomalies == [:ambiguous_binding_rules]
    assert result.outputs == []
  end

  test "extracts float fields through the definition-bound telemetry runtime" do
    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(42, 11, <<12.5::float-32>>)
      })

    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_name: "THERM",
        apid: 42,
        fields: [%{name: "temperature_c", offset_bits: 0, size_bits: 32, data_type: :float}]
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

    assert [%{point_name: "THERM.temperature_c", raw_value: 12.5, engineering_value: 12.5}] =
             result.outputs
  end

  test "rejects a binding set from a different mission" do
    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(42, 1, <<0, 1>>)
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-bravo",
        rules: [
          %{handler_key: :definition_bound_telemetry, apid: 42, packet_kind: :space_packet}
        ]
      })

    assert {:error, {:binding_set_mission_mismatch, "mission-alpha", "mission-bravo"}} =
             Cadence.process_telemetry_ingress(raw_evidence, binding_set)
  end

  test "prefers a source-endpoint-scoped rule over a mission-default rule for the same packet" do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-alpha",
        mission_id: "mission-alpha",
        display_name: "SC Alpha"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-alpha",
        mission_id: "mission-alpha",
        spacecraft_id: "sc-alpha",
        source_ref: "station-a"
      })

    assert {:ok, _persisted_source_endpoint} = Cadence.persist_source_endpoint(source_endpoint)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        source_ref: "station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    mission_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "mission-packet",
        packet_name: "MISSION",
        apid: 42,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    endpoint_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "endpoint-packet",
        packet_name: "ENDPOINT",
        apid: 42,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "mission-default-rule",
            handler_key: :definition_bound_telemetry,
            selector: %{
              scope: %{target_scope: :mission},
              match: %{packet_kind: :space_packet, apid: 42}
            },
            priority: 100,
            handler_configuration: mission_definition
          }),
          BindingRule.new(%{
            binding_rule_id: "endpoint-specific-rule",
            handler_key: :definition_bound_telemetry,
            selector: %{
              scope: %{target_scope: :source_endpoint, source_endpoint_ref: "endpoint-sc-alpha"},
              match: %{packet_kind: :space_packet, apid: 42}
            },
            priority: 100,
            handler_configuration: endpoint_definition
          })
        ]
      })

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence, binding_set)
    [packet_record] = result.packet_records
    [dispatch_decision] = result.dispatch_decisions

    assert dispatch_decision.status == :matched
    assert dispatch_decision.matched_rule_ids == ["endpoint-specific-rule"]
    assert Enum.map(result.outputs, & &1.point_name) == ["ENDPOINT.counter"]
    assert packet_record.source_endpoint_ref == "endpoint-sc-alpha"
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
