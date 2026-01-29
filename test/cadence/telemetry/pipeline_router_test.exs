defmodule Cadence.Telemetry.PipelineRouterTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{PacketEnvelope, PacketLogRecord, PipelineRouter, ResolvedUnit}

  defp resolved_unit(attrs) do
    defaults = %ResolvedUnit{
      packet_id: "packet-1",
      mission_id: "mission-1",
      envelope: PacketEnvelope.new("mission-1", <<1>>, config_version_seen: 1),
      parsed_unit:
        {:space_packet,
         %Cadence.Telemetry.SpacePacket{
           primary: %{apid: 1},
           sec_header: nil,
           user_data: <<>>,
           raw_ref: nil
         }},
      format: :space_packet,
      identity: {:ok, "target-1"},
      schema: {:ok, %{name: "PKT"}},
      decision_trace: %{},
      config_version_used: 1
    }

    struct!(ResolvedUnit, Map.merge(Map.from_struct(defaults), attrs))
  end

  test "decom gating only for eligible packets" do
    resolved = resolved_unit(%{})
    assert {:decom, ^resolved} = PipelineRouter.route_resolved(resolved)

    unresolved = resolved_unit(%{identity: {:unresolved, :no_identity_evidence, nil}})
    assert {:sink, :unidentified, _} = PipelineRouter.route_resolved(unresolved)

    unknown_schema = resolved_unit(%{schema: {:unknown_apid, "target-1", "def", 100}})
    assert {:sink, :unknown_schema, _} = PipelineRouter.route_resolved(unknown_schema)

    unsupported =
      resolved_unit(%{format: :encap_packet, schema: {:unsupported_format, :encap_packet}})

    assert {:sink, :unsupported_format, _} = PipelineRouter.route_resolved(unsupported)
  end

  test "persistence records include required fields" do
    envelope =
      PacketEnvelope.new("mission-1", <<0xAA>>, config_version_seen: 2, router_version: 5)
      |> Map.put(:provenance, %{transport_id: "transport-1"})

    record = PacketLogRecord.envelope_record(envelope, :payload, 0)
    assert record.record_type == :envelope
    assert record.payload.raw == <<0xAA>>
    assert record.payload.provenance == %{transport_id: "transport-1"}
    assert record.payload.config_version_seen == 2

    resolved = resolved_unit(%{envelope: envelope})
    classification = PacketLogRecord.classification_record(resolved, :payload, 0)

    assert classification.record_type == :classification
    assert classification.packet_id == resolved.packet_id
    assert classification.payload.identity_result == resolved.identity
    assert classification.payload.schema_result == resolved.schema
  end
end
